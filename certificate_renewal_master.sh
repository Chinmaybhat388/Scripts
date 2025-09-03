#!/bin/bash
LOGFILE="/postgres_log/certificate_lifecycle/cert_renewal.log"
DB_update_fail_log="/tmp/dbUpdate_fail.log"
scp_fail_log="/tmp/scp_failed_hosts.log"
download_fail_log="/tmp/download_failed_certs.log"
FROM_ADDR="postgres@lowes.com"
MAILADDR="chinmay.kr@lowes.com"
PGPORT=50001

> $DB_update_fail_log
> $scp_fail_log
> $download_fail_log
> /tmp/cert_expiry.txt

log() {
  echo "[$(date +'%F %T')] $1" | tee -a $LOGFILE
}

#Get all the certificates that are expiring in the next 391 days
/usr/bin/psql -t -d msb -p 50001 -c "select distinct current_certificate_id from hci_certificate_inventory WHERE (TO_TIMESTAMP(current_expiry_date, 'Mon DD HH24:MI:SS YYYY') AT TIME ZONE 'GMT' - NOW()) < INTERVAL '391 days'" | awk NF > /tmp/cert_expiry.txt

#Proceed if the file is not empty.
if [[ -s /tmp/cert_expiry.txt ]];
then
	#Log
	log "Expiring certificate IDs : `/usr/bin/psql -t -d msb -p 50001 -c \"select distinct current_certificate_id from hci_certificate_inventory WHERE (TO_TIMESTAMP(current_expiry_date, 'Mon DD HH24:MI:SS YYYY') AT TIME ZONE 'GMT' - NOW()) < INTERVAL '391 days'\"|xargs`"
	
	#Obtain the API token
	access_token=$(curl -s --location -k --request POST 'https://auth.sso.sectigo.com/auth/realms/apiclients/protocol/openid-connect/token' \
	-H "Content-Type: application/x-www-form-urlencoded" \
	-d "grant_type=client_credentials" \
	-d "client_id=3f3bf203-aa91-44f0-a204-1ae280addbe8" \
	-d "client_secret=hfNhai6=aNfMhgS92jYYZk]ipgwKrLc7" | jq -r '."access_token"')

	if [[ -n $access_token ]];
	then
		log "Successfully obtained access token : ${access_token:0:15}"
	else
		log "Unable to fetch API token"
		mailx -s "Unable to fetch API token for certificate renewal, please check." -r $FROM_ADDR $MAILADDR
		exit 1
	fi

	for id in $(cat /tmp/cert_expiry.txt);
	do
		#Renew the certificate
		response=$(curl -s -X POST "https://admin.enterprise.sectigo.com/api/ssl/v1/renewById/${id}" -H "Content-Type: application/json" -H "Authorization: Bearer ${access_token}" -H "customerUri: lowes-prod" -H "Accept: application/json" -H "login: eaprodpers")

		sleep 20 

		# Extract new cert ID
		new_cert_id=$(echo "$response" | jq -r '.sslId')
		local_cert_dir="/home/postgres/cert_renewal/${new_cert_id}"

		log "$id has been renewed to : $new_cert_id"

		#Get the status of the new certificate : 
		cert_status=`curl -s "https://cert-manager.com/private/api/ssl/v1/${new_cert_id}" -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/{/,/}/p' | jq '.status' | sed 's/"//g'`

		log "Status of $new_cert_id : $cert_status"

		if [[ $cert_status == "Issued" ]];
		then
			log "Downloading the certificates for $new_cert_id"
			mkdir -p "$local_cert_dir"
			#Download the root
			curl -s "https://cert-manager.com/private/api/ssl/v1/collect/${new_cert_id}?format=x509IO" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' >> ${local_cert_dir}/root.crt
			#Download server certificate 
			curl -s "https://cert-manager.com/private/api/ssl/v1/collect/${new_cert_id}?format=x509CO" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' >> ${local_cert_dir}/server.crt
			#Download the p12 key file
			curl -s -k `curl -s "https://cert-manager.com/private/api/ssl/v1/keystore/${new_cert_id}/p12aes" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/Transfer-Encoding: chunked/,$p' | sed '1d' | jq -r '.link'` --output ${local_cert_dir}/keyfile.p12
			#Convert the p12 to server.key
			openssl pkcs12 -in ${local_cert_dir}/keyfile.p12 -out ${local_cert_dir}/server.key -nocerts -nodes -nodes -passin pass:"Lowes@1234567"
			#Permissions
			chmod 600 ${local_cert_dir}/root.crt
			chmod 600 ${local_cert_dir}/server.crt
			chmod 600 ${local_cert_dir}/server.key

			#Validate if the certs got created : 
			if [[ ! -s ${local_cert_dir}/server.crt || ! -s ${local_cert_dir}/server.key || ! -s ${local_cert_dir}/root.crt ]];
			then
				log "Missing one or more cert files for $new_cert_id"
				echo "$new_cert_id" >> $download_fail_log
  				continue  
			fi

			#Obtain the creation and expiry date
			creation_date=$(openssl x509 -in ${local_cert_dir}/server.crt -startdate -noout | cut -d= -f2)
			expiry_date=$(openssl x509 -in ${local_cert_dir}/server.crt -enddate -noout | cut -d= -f2)

			#Copying the files over to the target servers 
			renew_hosts=$(/usr/bin/psql -t -d msb -p 50001 -c "select server_name from hci_certificate_inventory WHERE current_certificate_id='$id'"|awk NF)
			for host in $renew_hosts;
			do
				log "Copying cert $new_cert_id to $host"
				ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no $host "mkdir -p /home/postgres/certs/${new_cert_id}"
				scp -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -r "/home/postgres/cert_renewal/${new_cert_id}" $host:/home/postgres/certs

				if [[ $? -eq 0 ]];
				then
					log "SCP of $new_cert_id to $host succeeded."
					#If SCP is successful, update the table with the necessary details from the new cert.
					/usr/bin/psql -d msb -p 50001 -c "UPDATE hci_certificate_inventory SET current_certificate_id='$new_cert_id', current_creation_date='$creation_date', current_expiry_date='$expiry_date' WHERE server_name='$host';"
					
					sleep 5

					#Verify
					DB_update=$(/usr/bin/psql -t -d msb -p 50001 -c "select current_certificate_id from hci_certificate_inventory WHERE server_name='$host';"|awk NF|xargs)

					if [[ $DB_update == $new_cert_id ]];
					then
						log "Database updated with $new_cert_id for $host."
					else
						log "Database update for $host with new certificate ID $new_cert_id failed."
						echo "Database update for $host with new certificate ID $new_cert_id failed.Please check." >> $DB_update_fail_log
					fi

				else
					log "SCP of $new_cert_id to $host failed. Skipping DB update for this host."
					echo "$host,$new_cert_id" >> $scp_fail_log
				fi 
			done

			if [[ -s $DB_update_fail_log ]];
			then
				mailx -s "Failed to update the database record with the new certificate details.Please check." -a $DB_update_fail_log -r $FROM_ADDR $MAILADDR
			fi

			if [[ -s $scp_fail_log ]];
			then
				mailx -s "Failed to copy the new certificates.Please check." -a $scp_fail_log -r $FROM_ADDR $MAILADDR
			fi
		fi
	done

	if [[ -s $download_fail_log ]];
	then
		mailx -s "Failed to download the new certificates.Please check." -a $download_fail_log -r $FROM_ADDR $MAILADDR
	fi
else
	log "Nothing to renew. Exiting."
fi
