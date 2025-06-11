#Hosts is a list of all your inventory to be looped through.
hosts=(host_1 host_2 host_3 host_4)


#Add all the hosts already checked into this list.
checked_hosts=()
#Add all the hosts in the current cluster. Will be cleared at the end of each iteration.
current_cluster_nodes=()

for host in ${hosts[@]};
do
    if [[ " ${checked_hosts[*]} " == *" $host "*  ]];
    then
        continue
    fi

    IP=`ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $host 'hostname -i'`

    #Some servers can't be reached through ssh.
    if [[ -z $IP ]];
    then
        echo "Unable to ssh to $host"
        continue
    fi

    #Get the scope of the Patroni cluster through Patroni REST API
    cluster_name=`wget --timeout 5 -O - -q -t 1 http://$IP:8008/patroni|jq -r '.patroni'|jq -r '.scope'`
    #Get all the nodes of a Patroni cluster through Patroni REST API
    cluster_nodes=`wget --timeout 5 -O - -q -t 1 http://$IP:8008/cluster | jq|grep -i name|awk '{print $2}'|sed 's/[",]//g' | xargs`
    
    #Add the nodes to the lists initialized above.
    if [[ -n $cluster_nodes ]];
    then
        for node in $cluster_nodes;
        do
        checked_hosts+=("$node")
        current_cluster_nodes+=("$node")
        done
    fi


    if [[ -n $cluster_nodes ]];
    then
        echo "======================================================================================================================================================"
        for node in ${current_cluster_nodes[@]};
        do
            echo "$node :"
            cpu_count=$(ssh "$node" 'lscpu | grep -E "^CPU\(s\):[[:space:]]+[0-9]+" | awk "{print \$2}"')
            ram_total=$(ssh "$node" 'lsmem | grep -i "Total online memory" | awk "{print \$4}"')
            echo "CPU : $cpu_count"
            echo "RAM : $ram_total"
        done
        echo "======================================================================================================================================================"

    elif [[ -z $cluster_nodes ]];
    then
        echo "======================================================================================================================================================"
        printf "\n\n"
        echo "$host is a standalone node."
        printf "\n\n"
        echo "======================================================================================================================================================"

    fi

    
    current_cluster_nodes=()
done 

