#!/bin/bash

##########################################################################################################################################################################################
#Script to install postgres
#The RPMs need to be moved to the target server from  lxcrbutilprdw01:/cicd/ansible/postgres/rpms/rpms or lxpgscarbdevs05:/postgres_dump/rpms
#The rpms need to be placed in /tmp/rpms directory on the target server.
#For patroni builds, we need to install postgres as well as the packages in lxcrbutilprdw01:/cicd/ansible/postgres/rpms/rpms/patroni3/el9 or lxpgscarbdevs05:/postgres_dump/rpms/patroni3/el9  
##########################################################################################################################################################################################

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

standalone(){

echo -e "${GREEN} Installing postgres packages. ${RESET}"
yum install -y /tmp/rpms/15_2/el9/postgresql15-libs-15.2-1PGDG.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi
yum install -y /tmp/rpms/15_2/el9/postgresql15-15.2-1PGDG.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi
yum install -y /tmp/rpms/15_2/el9/postgresql15-server-15.2-1PGDG.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi
yum install -y /tmp/rpms/15_2/el9/postgresql15-contrib-15.2-1PGDG.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi
yum install -y /tmp/rpms/15_2/el9/pgbackrest-2.45-1.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi
yum install -y /tmp/rpms/15_2/el9/pg_partman_15-4.7.3-1.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

echo -e "${GREEN} **** Successfully installed Postgres libraries, Client, Server, Contrib, PGbackrest and partman RPMs ${RESET}"
echo "================================================================================================================"

echo -e "${GREEN} Changing the ownership of postgres directories ${RESET}"
chown -R postgres:postgres /postgres_data
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi
chown -R postgres:postgres /postgres_dump
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi
chown -R postgres:postgres /postgres_log
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

echo -e "${GREEN} **** Successfully changed Postgres directory ownership ****${RESET}"
echo "================================================================================================================"

echo -e "${GREEN} Creating Postgres systemd service file ${RESET}"
touch /etc/systemd/system/postgresql.service
chown postgres /etc/systemd/system/postgresql.service

cat << EOL > /etc/systemd/system/postgresql.service
[Unit]
Description=postgres start script
After=syslog.target network.target
 
[Service]
Type=forking
User=postgres
ExecStart=/usr/pgsql-15/bin/pg_ctl -D /postgres_data/15/main start -l /postgres_log/startlog.log
ExecStop=/usr/pgsql-15/bin/pg_ctl -D /postgres_data/15/main stop -l /postgres_log/stoplog.log
ExecReload=/usr/pgsql-15/bin/pg_ctl -D /postgres_data/15/main reload -l /postgres_log/service.log
KillMode=mixed
KillSignal=SIGINT
TimeoutSec=0
 
[Install]
WantedBy=multi-user.target
EOL

systemctl enable postgresql.service

echo -e "${GREEN}**** Successfully enabled postgres service. **** ${RESET}"
echo "================================================================================================================"

echo -e "${GREEN} **** Run the pre build job from jenkins : http://lxapsdbasdevs01:8080/view/Install/job/hci_prebuild/ ${RESET}"
echo -e "Initialize the DB and follow the remaing steps : https://tools.lowes.com/confluence/display/EA/HCI+Postgres+Standalone+Server+Build"

}



patroni(){

echo -e "${GREEN} Installing postgres packages. ${RESET}"
yum install -y /tmp/rpms/15_2/el9/postgresql15-libs-15.2-1PGDG.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

yum install -y /tmp/rpms/15_2/el9/postgresql15-15.2-1PGDG.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

yum install -y /tmp/rpms/15_2/el9/postgresql15-server-15.2-1PGDG.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

yum install -y /tmp/rpms/15_2/el9/postgresql15-contrib-15.2-1PGDG.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

yum install -y /tmp/rpms/15_2/el9/pgbackrest-2.45-1.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

yum install -y /tmp/rpms/15_2/el9/pg_partman_15-4.7.3-1.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

echo -e "${GREEN} **** Successfully installed Postgres libraries, Client, Server, Contrib, PGbackrest and partman RPMs. ${RESET}"
echo "================================================================================================================"

echo -e "${GREEN} Installing patroni packages. ${RESET}"
yum install -y --nogpgcheck /tmp/rpms/patroni3/el9/python3-cdiff-1.0-1.rhel9.noarch.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

yum install -y --nogpgcheck /tmp/rpms/patroni3/el9/python3-etcd-0.4.5-20.rhel9.noarch.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

yum install -y --nogpgcheck /tmp/rpms/patroni3/el9/python3-ydiff-1.2-10.rhel9.noarch.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

yum install -y --nogpgcheck /tmp/rpms/patroni3/el9/python3-psycopg2-2.9.4-1.rhel9.x86_64.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

yum install -y --nogpgcheck /tmp/rpms/patroni3/el9/patroni-3.1.0-1PGDG.rhel9.noarch.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

yum install -y --nogpgcheck /tmp/rpms/patroni3/el9/patroni-etcd-3.1.0-1PGDG.rhel9.noarch.rpm
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi

echo -e "${GREEN} **** Successfully installed Patroni rpms. ${RESET}"
echo "================================================================================================================"

echo -e "${GREEN} Changing the ownership of postgres directories ${RESET}"
chown -R postgres:postgres /postgres_data
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi
chown -R postgres:postgres /postgres_dump
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi
chown -R postgres:postgres /postgres_log
if [[ $? -ne 0 ]];then
echo -e "${RED}Failed.${RESET}"
fi
echo -e "${GREEN} **** Successfully changed Postgres directory ownership ****${RESET}"
echo "================================================================================================================"


echo -e "${GREEN}Creating Patroni config directory${RESET}"
mkdir /usr/pgsql-15/patroni/
chown postgres:postgres /usr/pgsql-15/patroni/
chown postgres:postgres /etc/pgbackrest.conf
echo -e "${GREEN} **** Successfully created Patroni config directory ****${RESET}"
echo "================================================================================================================"


echo -e "${GREEN} Creating Patroni systemd service file ${RESET}"
touch /etc/systemd/system/patroni.service
chown postgres:postgres /etc/systemd/system/patroni.service

cat << EOL > /etc/systemd/system/patroni.service
[Unit]
Description=Runners to orchestrate a high-availability PostgreSQL - patroni
After=syslog.target network.target
 
[Service]
Type=simple
User=postgres
Group=postgres
 
# Read in configuration file if it exists, otherwise proceed
EnvironmentFile=-/etc/patroni_env.conf
 
# WorkingDirectory=~
 
# Where to send early-startup messages from the server
# This is normally controlled by the global default set by systemd
# StandardOutput=syslog
 
# Pre-commands to start watchdog device
# Uncomment if watchdog is part of your patroni setup
#ExecStartPre=-/usr/bin/sudo /sbin/modprobe softdog
#ExecStartPre=-/usr/bin/sudo /bin/chown postgres /dev/watchdog
 
# Start the patroni process
ExecStart=/usr/bin/patroni /usr/pgsql-15/patroni/patroni.yml
 
# Send HUP to reload from patroni.yml
ExecReload=/bin/kill -s HUP $MAINPID
 
# only kill the patroni process, not it's children, so it will gracefully stop postgres
KillMode=process
 
# Give a reasonable amount of time for the server to start up/shut down
TimeoutSec=60
 
# Do not restart the service if it crashes, we want to manually inspect database on failure
Restart=yes
 
[Install]
WantedBy=multi-user.target
EOL

systemctl enable patroni.service
echo -e "${GREEN} **** Successfully created Patroni service file and enabled Patroni ****${RESET}"
echo "================================================================================================================"



echo -e "${GREEN} **** Run the pre build job from jenkins : http://lxapsdbasdevs01:8080/view/Install/job/hci_prebuild/ ${RESET}"
echo -e "Initialize the DB and follow the remaing steps : https://tools.lowes.com/confluence/display/EA/HCI+Postgres+Standalone+Server+Build"

}

while true;
do
echo -e "Is this a Standalone or Patroni installation? [Standalone/Patroni]"
read install_type

if [[ $install_type == "Standalone" ]];then
standalone
break;
elif [[ $install_type == "Patroni" ]];then
patroni
break;
else
echo "Choose either Standalone or Patroni"
fi
done 

