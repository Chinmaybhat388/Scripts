#!/bin/bash
LOGFILE="/postgres_log/certificate_lifecycle/cert_revocation.log"
revoke_fail_log="/tmp/revocation_failed_hosts.log"
FROM_ADDR="postgres@lowes.com"
MAILADDR="chinmay.kr@lowes.com"

> $revoke_fail_log
> /tmp/cert_revocation.txt

log() {
  echo "[$(date +'%F %T')] $1" | tee -a $LOGFILE
}

#Get all the certificates that were renewed more than 40 days ago.
/usr/bin/psql -t -d msb -p 50001 -c "select distinct old_certificate_id from hci_old_certificate_inventory WHERE revoked='no' AND insertion_date < NOW() - INTERVAL '40 days'" | awk NF > /tmp/cert_revocation.txt

#Proceed if the file is not empty.
if [[ -s /tmp/cert_revocation.txt ]];
then
    #Log
    log "Certificate IDs that can be revoked : `/usr/bin/psql -t -d msb -p 50001 -c \"select distinct old_certificate_id from hci_old_certificate_inventory WHERE revoked='no' AND insertion_date < NOW() - INTERVAL '40 days'\"|xargs`"

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
		mailx -s "Unable to fetch API token for old certificate revocation, please check." -r $FROM_ADDR $MAILADDR
        exit 1
	fi

	for id in $(cat /tmp/cert_revocation.txt);
	do
        log "Revoking certificate $id."
	    #Revoke the certificate.
        curl -s -X POST "https://admin.enterprise.sectigo.com/api/ssl/v1/revoke/${id}" -H 'Content-Type: application/json' -H "Authorization: Bearer ${access_token}" -H 'customerUri: lowes-prod' -H 'Accept: application/json' -H 'login: eaprodpers' -d '{"reasonCode":4,"reason":"Rotation"}'
        #Check if it was successfully revoked.
        cert_status=`curl -s -X GET "https://cert-manager.com/private/api/ssl/v1/${id}" -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/{/,/}/p' | jq '.status' | sed 's/"//g'`
        
        log "Status of certificate $id : $cert_status"

        if [[ $cert_status == "Revoked" ]];
        then
            log "Successfully revoked $id"
            log "Updating the database."
            /usr/bin/psql -d msb -p 50001 -c "UPDATE hci_old_certificate_inventory SET revoked='yes', revocation_reason='rotation' WHERE old_certificate_id ='$id'"
            if [[ $? -eq 0 ]];
            then
                log "Updated the table hci_old_certificate_inventory successfully for $id."
            fi
        else
            log "Failed to revoke $id"
            echo "$id" >> $revoke_fail_log
        fi
    done 

    if [[ -s $revoke_fail_log ]]; 
    then
        mailx -s "Failed to revoke certificates. Please check." -a $revoke_fail_log -r $FROM_ADDR $MAILADDR
    fi
else
    log "Nothing to revoke. Exiting."
fi
