#!/bin/bash

HOST=`hostname`
LOGPATH="/home/postgres/logs/"
LOGFILE="/home/postgres/logs/cert_lifecycle.log"
FROM_ADDR="postgres@lowes.com"
MAILADDR="chinmay.kr@lowes.com"

log() {
  echo "[$(date +'%F %T')] $1" | tee -a $LOGFILE
}

#Get the data directory where the certs are placed.
PGDATA=`ps -ef | grep bin/postgres | grep -- -D | grep -v grep| grep -v pg_basebackup| grep -v pg_dump | awk '{print $10}'|head -1`

if [[ -z $PGDATA ]]; 
then
    PGDATA=`psql -c "show data_directory" -t`
fi

if [[ -z $PGDATA ]]; 
then
    log "Unable to get the data directory"
    mailx -s "Failed to get the data directory for certificate renewal." -r $FROM_ADDR $MAILADDR
    exit 1
fi

#Get PGpath
PGPATH="$(dirname `ps -ef | grep bin/postgres | grep -- -D | grep -v grep | awk '{print $8}'|head -1`)"

if [[ -z $PGPATH ]]; 
then
    PGPATH="$(dirname `ps -ef | grep bin/postgres  |  grep -v grep |  awk '{print $8}'|head -1`)"
fi

log "Data directory : $PGDATA"
log "Postgres path : $PGPATH"

#In case of multiple directories, scan all directories to get the latest certificate directory
latest_epoch=0
latest_dir=""

for dir in /home/postgres/certs/*; 
do
    cert_path="$dir/server.crt"
    log "Evaluating $cert_path"

    if [[ -f "$cert_path" ]]; 
    then
        # Validate format
        if openssl x509 -in "$cert_path" -noout > /dev/null 2>&1; 
        then
            expiry_date=$(openssl x509 -in "$cert_path" -enddate -noout | cut -d= -f2)
            expiry_epoch=$(date -d "$expiry_date" +%s)
            log "Expiry date is $expiry_date"

            if (( $expiry_epoch > $latest_epoch )); 
            then
                latest_epoch=$expiry_epoch
                latest_dir="$dir"
                log "Directory with latest certificates : $latest_dir"
            fi
        fi
    fi
done

#Compare expiry with the current certificates.
cur_cert="$PGDATA/server.crt"
cur_expiry=$(openssl x509 -in "$cur_cert" -enddate -noout | cut -d= -f2)
cur_epoch=$(date -d "$cur_expiry" +%s)
log "Current certificate $cur_cert"
log "Current expiry $cur_expiry"

if (( $latest_epoch > $cur_epoch )); 
then
    log "New cert is newer — deploying $latest_dir"
    # backup old certs
    cp "$PGDATA/server.crt" "$PGDATA/server.crt.bak.$(date +%F_%T)"
    cp "$PGDATA/server.key" "$PGDATA/server.key.bak.$(date +%F_%T)"

    # copy from $latest_dir
    cp "$latest_dir/server.crt" "$PGDATA/server.crt"
    cp "$latest_dir/server.key" "$PGDATA/server.key"
    chown postgres:postgres "$PGDATA/server.crt" "$PGDATA/server.key"
    chmod 600 "$PGDATA/server.key"
    chmod 600 "$PGDATA/server.crt"
    # reload
    $PGPATH/pg_ctl -D $PGDATA reload

    if [[ $? -eq 0 ]];
    then
        log "Successfully deployed and reloaded the database."
        mailx -s "Successfully deployed new certificates and reloaded the database on $HOST." -r $FROM_ADDR $MAILADDR
    fi

else
    log "No newer cert found. Skipping."
fi