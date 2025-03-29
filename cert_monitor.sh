#This script is to monitor if any client connections are still using older versions of TLS certificates to connect to postgres database.
#hba entry needed "hostssl    postgres   postgres      <host_ip>/32    trust clientcert=verify-ca"


#!/bin/bash

OS=`uname`
HOST=`hostname`
DT=`date +%d-%b-%Y-%H-%M-%S-%p`
LOGPATH="/home/postgres/logs/certs"
LOGFILE=${LOGPATH}/${HOST}_PG_${DT}cert_monitor.log
MAILADDR="email@domain.com"
PGDATA=`ps -ef | grep bin/postgres | grep -- -D | grep -v grep| grep -v pg_basebackup| grep -v pg_dump | awk '{print $10}'|head -1`
PGPATH="$(dirname `ps -ef | grep bin/postgres | grep -- -D | grep -v grep | awk '{print $8}'|head -1`)"

mkdir -p $LOGPATH

PGPATH=$PGPATH/
PATH=$PATH:$PGPATH
echo "PGPATH is : " $PGPATH  | tee -a "$LOGFILE"
echo "PGDATA is : " $PGDATA  | tee -a "$LOGFILE"

if [ -e "$PGDATA/postgresql.conf" ]; then
  DBPORT=`cat $PGDATA/postgresql.conf | grep -w "^port" | awk '{print $3}'| tr -d \'\"`
else
  PSQLCONF=`ps -ef | grep postgres | grep -- -D | grep -v grep | awk '{print $11}' | sed 's:^[^/]*::;s/ .*//'`
  if [ -e "$PSQLCONF" ]; then
    DBPORT=`cat $PSQLCONF | grep -w "^port" | awk '{print $3}'`
  fi
fi
if [ -z "$DBPORT" ]; then
  DBPORT=50001
fi

echo "Database port is : " $DBPORT  | tee -a "$LOGFILE"

#Check if the certificates are present

ssl_ca_file=$(ls -lrt $PGDATA/root.crt|awk '{print $9}')
ssl_cert_file=$(ls -lrt $PGDATA/server.crt|awk '{print $9}')
ssl_key_file=$(ls -lrt $PGDATA/server.key|awk '{print $9}')

if ([[ -n $ssl_ca_file ]] && [[ -n $ssl_cert_file ]] && [[ -n $ssl_key_file ]])
then
  echo "All 3 certificates are present."
  client_serial=$($PGPATH/psql "sslmode=verify-ca sslrootcert=$ssl_ca_file sslcert=$ssl_cert_file sslkey=$ssl_key_file host=$HOST port=$DBPORT user=postgres dbname=postgres" -c "select client_serial from pg_stat_ssl where pid=(select pg_backend_pid())" -t)
  echo "Client serial is $client_serial"
  old_cert_count=$($PGPATH/psql -c "select count(*) from pg_stat_ssl where client_serial != $client_serial" -t)
  if [[ old_cert_count -gt 0 ]]
  then
    sessions_with_old_cert=$($PGPATH/psql -c "select pid,datname,usename,application_name,client_addr,client_port,backend_start from pg_stat_activity where pid in (select pid from pg_stat_ssl where client_serial != $client_serial)")
    echo "$sessions_with_old_cert" | mailx -s "Postgresql sessions using old certificates" $MAILADDR
  fi
elif [[ -z $ssl_ca_file ]] || [[ -z $ssl_cert_file ]] || [[ -n $ssl_key_file ]]
then
  echo "Certificates are missing, please check."
fi
