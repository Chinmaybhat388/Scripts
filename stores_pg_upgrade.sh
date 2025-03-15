##To upgrade 1700+ stores from PG12 to PG14##

#!/bin/bash

backup_dir="/var/lib/postgresql/cluster_dumps/pgdump"
pg14_fs="/var/lib/postgresql/14/main"
pg12_fs="/var/lib/postgresql/12/main"
logfile="/var/lib/postgresql/pg_upgrade.log"

> "$logfile"

# Redirecting all output to the logfile
exec > >(tee -a "$logfile") 2>&1

echo -e "Running prechecks."
echo -e "Verifying the latest backup."
echo -e "================================================================="
latest_backup=$(find /var/lib/postgresql/cluster_dumps/pgdump -type f -name '*.gz' -mtime -1 -exec ls -lrt {} + | tail -n 1|awk '{print $9}')

if [[ -n "$latest_backup" ]];
then
	latest_backup_time=$(stat $latest_backup|grep -i birth|awk '{print $2,$3}')
echo -e "Latest backup :"
echo "$latest_backup taken at $latest_backup_time"
else
echo -e "Latest backup is not present."
exit 1
fi

printf "\n\n"


echo -e "Verifying the Postgresql data file systems."
echo -e "================================================================="


pg12_data_dir=`ls -ld /var/lib/postgresql/12/main 2>/dev/null`

if [[ -n $pg12_data_dir ]];
then
echo -e "PG-12 data directory : $pg12_fs : `df -h $pg12_fs|awk '{print $2}'|tail -1`"
else
echo -e "PG12 data directory not found."
exit 1
fi

pg14_data_dir=`ls -ld /var/lib/postgresql/14/main 2>/dev/null`

if [[ -n $pg14_data_dir ]];
then
echo -e "PG-14 data directory : $pg14_fs : `df -h $pg14_fs|awk '{print $2}'|tail -1`"
else
echo -e "PG14 data directory not found."
exit 1
fi

printf "\n\n"

echo -e "Installed extensions."
echo -e "================================================================="
dbs=`psql -P pager=off -t -c "\l"|awk '{print $1}'|grep -v "|"|head -n -1`
for db in ${dbs[@]};
do
if [[ $db != 'template0' ]];
then
echo "$db :";
psql -d $db -t -P pager=off -c "\dx"|awk '{print $1}';
else
continue
fi
done

printf "\n\n"

echo -e "Check and stop 14 cluster if running."
ps -ef|grep /var/lib/postgresql/14/main|grep -v grep
if [[ $? == 0 ]];
then
printf "\n"
echo "Stopping 14 main cluster."
pg_ctlcluster 14 main stop
else
echo "14 main is not running."
fi
printf "\n"
echo -e "Running preupgrade step."
/usr/lib/postgresql/14/bin/pg_upgrade --old-bindir /usr/lib/postgresql/12/bin --new-bindir /usr/lib/postgresql/14/bin --old-datadir /var/lib/postgresql/12/main --new-datadir /var/lib/postgresql/14/main/ -o "-c config_file=/etc/postgresql/12/main/postgresql.conf" -O "-c config_file=/etc/postgresql/14/main/postgresql.conf" -p 5432 -p 5433 --check

printf "\n\n"

echo -e "Starting the upgrade"
pg_ctlcluster 12 main stop
/usr/lib/postgresql/14/bin/pg_upgrade --old-bindir /usr/lib/postgresql/12/bin --new-bindir /usr/lib/postgresql/14/bin --old-datadir /var/lib/postgresql/12/main --new-datadir /var/lib/postgresql/14/main/ -o "-c config_file=/etc/postgresql/12/main/postgresql.conf" -O "-c config_file=/etc/postgresql/14/main/postgresql.conf" -p 5432 -p 5433


if [[ $? -eq 0 ]]; then
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
    echo "Copied config and pg_hba.conf files."
else
    echo "Upgrade failed."
    exit 1
fi

printf "\n\n"

echo -e "Starting 14 main cluster."
pg_ctlcluster 14 main start

sleep 5
printf "\n"
pg_isready

printf "\n\n"
echo -e "Collecting optimizer statistics."
/usr/lib/postgresql/14/bin/vacuumdb --all --analyze-in-stages

printf "\n\n"
echo "Upgrade completed."
