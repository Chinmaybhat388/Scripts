#!/bin/bash

HOST=`hostname`

PGDATA=`ps -ef | grep bin/postgres | grep -- -D | grep -v grep| grep -v pg_basebackup| grep -v pg_dump | awk '{print $10}'|head -1`

if [[ -z $PGDATA ]]; then
PGDATA=`psql -c "show data_directory" -t`
fi


PGPATH="$(dirname `ps -ef | grep bin/postgres | grep -- -D | grep -v grep | awk '{print $8}'|head -1`)"

if [[ -z $PGPATH ]]; then
PGPATH="$(dirname `ps -ef | grep bin/postgres  |  grep -v grep |  awk '{print $8}'|head -1`)"
fi

PGPATH=$PGPATH/
PATH=$PATH:$PGPATH

stanza_created=`/usr/bin/pgbackrest info`
echo $stanza_created >> /tmp/pgbackrest_stanza.log

if [[ ! -e $PGDATA/standby.signal ]]; then
    is_leader="t"
fi

echo $is_leader >> /tmp/pgbackrest_stanza.log

if [[ $is_leader == "t" ]] && [[ $stanza_created == "No stanzas exist in the repository." ]]
then
	if [[ -s /etc/pgbackrest.conf ]]
	then
	echo "Creating a stanza" >> /tmp/pgbackrest_stanza.log
	pgbackrest --stanza=main --log-level-console=info stanza-create >> /tmp/pgbackrest_stanza.log
	if [[ $? != 0 ]]
	then
		mail -s "Stanza creation failed on $HOST" chinmay.kr@lowes.com
	fi
	fi
fi