#!/bin/bash

clusters=("cluster1" "cluster2")


for cluster in "${clusters[@]}"; do
echo $cluster
# Get the list of IP addresses from your command
gcloud compute instances list --format="table(metadata.items.consul_srv,name,networkInterfaces.networkIP,machineType,labels.db_technical_contact,labels.db_environment,labels.db_app_tier)[box,no-heading]" --filter="metadata.consul_srv=$cluster"

nodes=$(gcloud compute instances list --format="get(networkInterfaces[0].networkIP)" --filter="$cluster")

# Loop over each IP address in the nodes variable
for node in $nodes; do
    echo $node
    ssh -o StrictHostKeyChecking=no chinmay@$node "sudo cat /data1/pgdata/config/patroni.yml|grep -i -A 5 etcd| grep -i hosts"
done
echo "=================================================================================================================================="
echo " "
echo "=================================================================================================================================="
done