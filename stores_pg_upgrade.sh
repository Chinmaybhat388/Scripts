##To upgrade 1700+ stores from PG12 to PG14##

#!/bin/bash

backup_dir="/var/lib/postgresql/cluster_dumps/pgdump"
pg14_fs="/var/lib/postgresql/14/main"
pg12_fs="/var/lib/postgresql/12/main"
logfile="/var/lib/postgresql/pg_upgrade.log"
touch $logfile
> "$logfile"

# Redirecting all output to the logfile
#exec > >(tee -a "$logfile") 2>&1

echo "Running prechecks." | tee -a $logfile
echo "Verifying the latest backup." | tee -a $logfile
echo "=================================================================" | tee -a $logfile
latest_backup=$(find /var/lib/postgresql/cluster_dumps/pgdump -type f -name '*.gz' -mtime -1 -exec ls -lrt {} + | tail -n 1|awk '{print $9}')

if [[ -n "$latest_backup" ]];
then
 latest_backup_time=$(stat $latest_backup|grep -i birth|awk '{print $2,$3}')
echo "Latest backup :" | tee -a $logfile
echo "$latest_backup taken at $latest_backup_time" | tee -a $logfile
else
echo "Latest backup is not present." | tee -a $logfile
exit 1
fi

printf "\n\n" | tee -a $logfile


echo "Verifying the Postgresql data file systems." | tee -a $logfile
echo "=================================================================" | tee -a $logfile


pg12_data_dir=`ls -ld /var/lib/postgresql/12/main 2>/dev/null`

if [[ -n $pg12_data_dir ]];
then
echo "PG-12 data directory : $pg12_fs : `df -h $pg12_fs|awk '{print $2}'|tail -1`" | tee -a $logfile
else
echo "PG12 data directory not found." | tee -a $logfile
exit 1
fi

pg14_data_dir=`ls -ld /var/lib/postgresql/14/main 2>/dev/null`

if [[ -n $pg14_data_dir ]];
then
echo "PG-14 data directory : $pg14_fs : `df -h $pg14_fs|awk '{print $2}'|tail -1`" | tee -a $logfile
else
echo "PG14 data directory not found." | tee -a $logfile
exit 1
fi

printf "\n\n" | tee -a $logfile

echo "Verifying the data_checksums on 12 and 14 clusters." | tee -a $logfile
echo "=================================================================" | tee -a $logfile

pg12_data_checksum=`psql -p 5432 -t -c "show data_checksums"`
pg14_data_checksum=`psql -p 5433 -t -c "show data_checksums"`

echo "On 12 cluster : $pg12_data_checksum"
echo "On 14 cluster : $pg14_data_checksum"

if [[ "$pg12_data_checksum" != "$pg14_data_checksum" ]];
then
echo "Data checksums do not match between 12 and 14 clusters." | tee -a $logfile
exit 1
fi


echo "Installed extensions." | tee -a $logfile
echo "=================================================================" | tee -a $logfile
dbs=`psql -P pager=off -t -c "\l"|awk '{print $1}'|grep -v "|"|head -n -1`
for db in ${dbs[@]};
do
if [[ $db != 'template0' ]];
then
echo "$db :" | tee -a $logfile
psql -d $db -t -P pager=off -c "\dx"|awk '{print $1}' | tee -a $logfile
else
continue
fi
done

printf "\n\n" | tee -a $logfile

echo "Check and stop 14 cluster if running." | tee -a $logfile
ps -ef|grep /var/lib/postgresql/14/main|grep -v grep
if [[ $? == 0 ]];
then
printf "\n"
echo "Stopping 14 main cluster." | tee -a $logfile
pg_ctlcluster 14 main stop
else
echo "14 main is not running." | tee -a $logfile
fi
printf "\n" | tee -a $logfile
echo "Running preupgrade step." | tee -a $logfile
/usr/lib/postgresql/14/bin/pg_upgrade --old-bindir /usr/lib/postgresql/12/bin --new-bindir /usr/lib/postgresql/14/bin --old-datadir /var/lib/postgresql/12/main --new-datadir /var/lib/postgresql/14/main/ -o "-c config_file=/etc/postgresql/12/main/postgresql.conf" -O "-c config_file=/etc/postgresql/14/main/postgresql.conf" -p 5432 -p 5433 --check | tee -a $logfile

precheck_exit=${PIPESTATUS[0]}

if [[ $precheck_exit -ne 0 ]]; then
    echo "Pre-upgrade check failed. Aborting upgrade." | tee -a "$logfile"
    exit 1
fi

printf "\n\n" | tee -a $logfile

echo "Starting the upgrade" | tee -a $logfile
pg_ctlcluster 12 main stop
/usr/lib/postgresql/14/bin/pg_upgrade --old-bindir /usr/lib/postgresql/12/bin --new-bindir /usr/lib/postgresql/14/bin --old-datadir /var/lib/postgresql/12/main --new-datadir /var/lib/postgresql/14/main/ -o "-c config_file=/etc/postgresql/12/main/postgresql.conf" -O "-c config_file=/etc/postgresql/14/main/postgresql.conf" -p 5432 -p 5433 | tee -a $logfile

upgrade_exit=${PIPESTATUS[0]}

if [[ $upgrade_exit -ne 0 ]]; then
    echo "Upgrade failed. Check log for details." | tee -a "$logfile"
    exit 1
fi

echo "Upgrade successful. Copying configuration files..." | tee -a "$logfile"

set -e
mv /etc/postgresql/14/main/pg_hba.conf /etc/postgresql/14/main/pg_hba.conf_orig
mv /etc/postgresql/14/main/postgresql.conf /etc/postgresql/14/main/postgresql.conf_orig
cp /etc/postgresql/12/main/pg_hba.conf /etc/postgresql/14/main/
cp /etc/postgresql/12/main/postgresql.conf /etc/postgresql/14/main/
#Modify the copied postgresql.conf to point to 14/main directories.
sed -i "s#data_directory = '/var/lib/postgresql/12/main'#data_directory = '/var/lib/postgresql/14/main'#g" /etc/postgresql/14/main/postgresql.conf
sed -i "s#hba_file = '/etc/postgresql/12/main/pg_hba.conf'#hba_file = '/etc/postgresql/14/main/pg_hba.conf'#g" /etc/postgresql/14/main/postgresql.conf
sed -i "s#ident_file = '/etc/postgresql/12/main/pg_ident.conf'#ident_file = '/etc/postgresql/14/main/pg_ident.conf'#g" /etc/postgresql/14/main/postgresql.conf
sed -i "s#external_pid_file = '/var/run/postgresql/12-main.pid'#external_pid_file = '/var/run/postgresql/14-main.pid'#g" /etc/postgresql/14/main/postgresql.conf
sed -i "s#stats_temp_directory = '/var/run/postgresql/12-main.pg_stat_tmp'#stats_temp_directory = '/var/run/postgresql/14-main.pg_stat_tmp'#g" /etc/postgresql/14/main/postgresql.conf
sed -i '$s/auto/manual/' /etc/postgresql/12/main/start.conf
printf "\n\n" | tee -a $logfile
echo "Copied config and pg_hba.conf files." | tee -a $logfile


printf "\n\n" | tee -a $logfile

echo "Starting 14 main cluster." | tee -a $logfile
pg_ctlcluster 14 main start

sleep 5
printf "\n" | tee -a $logfile
pg_isready | tee -a $logfile

printf "\n\n" | tee -a $logfile
echo "Collecting optimizer statistics." | tee -a $logfile
printf "\n\n" | tee -a $logfile
echo "Running analyze on the new cluster." | tee -a $logfile
/usr/lib/postgresql/14/bin/vacuumdb --all --analyze-in-stages | tee -a $logfile

printf "\n\n" | tee -a $logfile
echo "Upgrade completed." | tee -a $logfile
