#Generates TLS certificates for HCI Patroni cluster nodes.

#!/bin/bash

#email="DL-DIST-Carbon-Postgres@xxxxx.com"
email="chinmay.kr@xxxxx.com"
logfile="cert_generation.log"

> "$logfile"

# Redirecting all output to the logfile
exec > >(tee -a "$logfile") 2>&1

read -p "How many nodes in the cluster? " num_nodes

nodes=()

count=1
while [[ $count -lt $num_nodes+1 ]];
do
 read -p "Node $count name : " NODE_NAME
 nodes+=("$NODE_NAME")
 count=$((count+1))
done

read -p "Enter the cluster name / scope name : " CLUSTER_NAME

printf "\n\n"
subjAltNames=$(IFS=,; echo "${nodes[*]},$(for node in "${nodes[@]}"; do echo "$node.lowes.com"; done | paste -sd, -)")
echo "DNS names : $subjAltNames"
echo "Common name : $CLUSTER_NAME"
printf "\n\n"

mkdir -p ${CLUSTER_NAME}_certs

#Get the access token :
access_token=$(curl -s --location -k --request POST 'https://auth.sso.xxxxxxx.com/auth/realms/apiclients/protocol/openid-connect/token' \
-H "Content-Type: application/x-www-form-urlencoded" \
-d "grant_type=client_credentials" \
-d "client_id=3f3bf203-xxxx-xxxx-xxxx-1ae280addbe8" \
-d "client_secret=xxxxxxx=xxxxxxxxxxxxxxx" | jq -r '."access_token"')


#Check if the certificate exists :
cert_id=$(curl -s "https://cert-manager.com/private/api/ssl/v1?commonName=${CLUSTER_NAME}" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/{/,/}/p' | jq '.[].sslId'| head -1)

if [[ -n $cert_id ]];
then
  echo "Certificate ID : $cert_id"
  cert_details=$(curl -s "https://cert-manager.com/private/api/ssl/v1/${cert_id}" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/{/,/}/p' | jq '.issued,.expires,.status')

  printf '\n'
  echo "The certificate was generated on `echo $cert_details|awk '{print $1}'`"
  echo "The certificate expires on `echo $cert_details|awk '{print $2}'`"
  echo "The certificate status is `echo $cert_details|awk '{print $3}'`"
  printf '\n'

  read -p "Certificate for ${CLUSTER_NAME} already exists. Download existing certificates? [y/n]: " download_existing

  if [[ $download_existing == 'y' ]]
  then
    curl -s "https://cert-manager.com/private/api/ssl/v1/collect/${cert_id}?format=x509IO" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' >> ${CLUSTER_NAME}_certs/root.crt
    echo "root.crt downloaded."
    curl -s "https://cert-manager.com/private/api/ssl/v1/collect/${cert_id}?format=x509CO" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' >> ${CLUSTER_NAME}_certs/server.crt
    echo "server.crt downloaded"
    curl -s -k `curl -s "https://cert-manager.com/private/api/ssl/v1/keystore/${cert_id}/p12aes" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/Transfer-Encoding: chunked/,$p' | sed '1d' | jq -r '.link'` --output ${CLUSTER_NAME}_certs/${CLUSTER_NAME}.p12
    echo "${CLUSTER_NAME}.p12 file downloaded."
    openssl pkcs12 -in ${CLUSTER_NAME}_certs/${CLUSTER_NAME}.p12 -out ${CLUSTER_NAME}_certs/server.key -nocerts -nodes -passin pass:"xxxxx@1234567"
    echo "Converted ${CLUSTER_NAME}.p12 file to server.key"
    chmod 600 ${CLUSTER_NAME}_certs/*
    echo "Downloaded the certificates."

    printf "\n\n"
    echo "Validity : "
    openssl x509 -in ${CLUSTER_NAME}_certs/server.crt -noout -dates

    mkdir -p ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs
    cp ${CLUSTER_NAME}_certs/*.crt ${CLUSTER_NAME}_certs/*.key ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs
    zip -r ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs.zip ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs
    mailx -s "Certificates for ${CLUSTER_NAME}" -a ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs.zip $email < /dev/null

  elif [[ $download_existing == 'n' ]]
  then
    read -p "Create a new certificate? [y/n] :" create_new

    if [[ $create_new == 'y' ]]
    then
      echo "Creating a new certificate."
      printf "\n"

      curl -s -k 'https://admin.enterprise.xxxxxxx.com/api/ssl/v1/enroll-keygen' -i -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer ${access_token}" -H 'customerUri: lowes-prod' -H 'Accept: application/json'  -H 'login: eaprodpers'  -d  '{"orgId":12345,"subjAltNames":"'"${subjAltNames}"'","certType":12345,"term":390,"comments":"Certificate for Postgres cluster","externalRequester":"DL-DIST-Carbon-Postgres@xxxxx.com","customFields":[{"name":"CMDB App ID","value":"12345"}], "commonName":"'"${CLUSTER_NAME}"'","passPhrase":"xxxxxxxxxxx","keySize":xxxx,"keyParam":"2048","algorithm":"RSA"}'| sed -n '/{/,/}/p'

      generated_cert_id=$(curl -s "https://cert-manager.com/private/api/ssl/v1?commonName=${CLUSTER_NAME}" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/{/,/}/p' | jq '.[].sslId' | head -1)

      echo "Certificates generated : $generated_cert_id"
      printf "\n"
      sleep 60
      curl -s "https://cert-manager.com/private/api/ssl/v1/collect/${generated_cert_id}?format=x509IO" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' >> ${CLUSTER_NAME}_certs/root.crt
      echo "root.crt downloaded."
      curl -s "https://cert-manager.com/private/api/ssl/v1/collect/${generated_cert_id}?format=x509CO" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' >> ${CLUSTER_NAME}_certs/server.crt
      echo "server.crt downloaded."
      curl -s -k `curl -s "https://cert-manager.com/private/api/ssl/v1/keystore/${generated_cert_id}/p12aes" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/Transfer-Encoding: chunked/,$p' | sed '1d' | jq -r '.link'` --output ${CLUSTER_NAME}_certs/${CLUSTER_NAME}.p12
      echo "${CLUSTER_NAME}.p12 file downloaded."
      openssl pkcs12 -in ${CLUSTER_NAME}_certs/${CLUSTER_NAME}.p12 -out ${CLUSTER_NAME}_certs/server.key -nocerts -nodes -passin pass:"xxxxx@1234567"
      echo "Converted ${CLUSTER_NAME}.p12 file to server.key"
      chmod 600 ${CLUSTER_NAME}_certs/*
      echo "Downloaded the certificates."

      printf "\n\n"
      echo "Validity : "
      openssl x509 -in ${CLUSTER_NAME}_certs/server.crt -noout -dates

      mkdir -p ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs
      cp ${CLUSTER_NAME}_certs/*.crt ${CLUSTER_NAME}_certs/*.key ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs
      zip -r ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs.zip ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs
      mailx -s "Certificates for ${CLUSTER_NAME}" -a ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs.zip $email < /dev/null
    fi
    echo "Exiting."
    
  else
    echo "Enter either y or n."
    exit
  fi


else
  echo "Certificate does not exist."

  read -p "Generate new certificates [y/n] : " new_gen
  if [[ $new_gen == 'y' ]]
  then
    echo "Creating a new certificate."

    curl -s -k 'https://admin.enterprise.sectigo.com/api/ssl/v1/enroll-keygen' -i -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer ${access_token}" -H 'customerUri: lowes-prod' -H 'Accept: application/json'  -H 'login: eaprodpers'  -d  '{"orgId":40584,"subjAltNames":"'"${subjAltNames}"'","certType":12345,"term":390,"comments":"Certificate for Postgres cluster","externalRequester":"DL-DIST-Carbon-Postgres@xxxxx.com","customFields":[{"name":"CMDB App ID","value":"12345"}], "commonName":"'"${CLUSTER_NAME}"'","passPhrase":"xxxxxxxxxxx","keySize":xxxx,"keyParam":"xxxx","algorithm":"RSA"}'| sed -n '/{/,/}/p'

    generated_cert_id=$(curl -s "https://cert-manager.com/private/api/ssl/v1?commonName=${CLUSTER_NAME}" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/{/,/}/p' | jq '.[].sslId')
    echo "Certificates generated : $generated_cert_id"
    sleep 60
    curl -s "https://cert-manager.com/private/api/ssl/v1/collect/${generated_cert_id}?format=x509IO" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' >> ${CLUSTER_NAME}_certs/root.crt
    echo "root.crt downloaded."
    curl -s "https://cert-manager.com/private/api/ssl/v1/collect/${generated_cert_id}?format=x509CO" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' >> ${CLUSTER_NAME}_certs/server.crt
    echo "server.crt downloaded."
    curl -s -k `curl -s "https://cert-manager.com/private/api/ssl/v1/keystore/${generated_cert_id}/p12aes" -i -X GET -H 'Accept: application/json' -H 'customerUri: lowes-prod' -H "Authorization: Bearer ${access_token}" | sed -n '/Transfer-Encoding: chunked/,$p' | sed '1d' | jq -r '.link'` --output ${CLUSTER_NAME}_certs/${CLUSTER_NAME}.p12
    echo "${CLUSTER_NAME}.p12 file downloaded."
    openssl pkcs12 -in ${CLUSTER_NAME}_certs/${CLUSTER_NAME}.p12 -out ${CLUSTER_NAME}_certs/server.key -nocerts -nodes -passin pass:"xxxxxxxxxxx"
    echo "Converted ${CLUSTER_NAME}.p12 file to server.key"
    chmod 600 ${CLUSTER_NAME}_certs/*
    echo "Downloaded the certificates."

    printf "\n\n"
    echo "Validity : "
    openssl x509 -in ${CLUSTER_NAME}_certs/server.crt -noout -dates

    mkdir -p ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs
    cp ${CLUSTER_NAME}_certs/*.crt ${CLUSTER_NAME}_certs/*.key ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs
    zip -r ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs.zip ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs
    mailx -s "Certificates for ${CLUSTER_NAME}" -a ${CLUSTER_NAME}_certs/${CLUSTER_NAME}_certs.zip $email < /dev/null

  elif [[ $new_gen == 'n' ]]
  then
    echo "Exiting."
    exit

  else
    echo "Enter either y or n"
  fi
fi

mv cert_generation.log ${CLUSTER_NAME}_certs/
