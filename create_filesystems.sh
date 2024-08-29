#!/bin/bash

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

id=`whoami`
if [[ $id != "root" ]]; then
echo "Run this script as root user"
exit 1
fi


echo -e "${GREEN}Which is the data disk?${RESET}"
read data_disk
pvs|grep -i $data_disk 2> /dev/null
if [[ `echo $?` == 0 ]];then
echo -e "${RED}Logical volume already created on this disk.${RESET}"
exit 1
fi


echo -e "${GREEN}Which is the pg log disk${RESET}?"
read log_disk
pvs|grep -i $log_disk 2> /dev/null
if [[ `echo $?` == 0 ]];then
echo -e "${RED}Logical volume already created on this disk.${RESET}"
exit 1
fi

echo -e "${GREEN}Which is the backup disk?${RESET}"
read dump_disk
pvs|grep -i $dump_disk 2> /dev/null
if [[ `echo $?` == 0 ]];then
echo -e "${RED}Logical volume already created on this disk.${RESET}"
exit 1
fi

if [[ $data_disk == "" ]];then
echo -e "${RED} Please provide disk name.${RESET}"
exit 1
fi

if [[ $log_disk == "" ]];then
echo -e "${RED} Please provide disk name.${RESET}"
exit 1
fi

if [[ $dump_disk == "" ]];then
echo -e "${RED} Please provide disk name.${RESET}"
exit 1
fi


if [[ $data_disk == $log_disk ]] || [[ $data_disk == $dump_disk ]] || [[ $log_disk == $dump_disk ]];then
echo -e "${RED}Please provide different disks for different filesystems.${RESET}"
exit 1
fi

while true;
do
echo -e "${RED}/postgres_data${RESET} will be created on ${RED}""$data_disk""${RESET}. \n${RED}/postgres_log${RESET} will be created on ${RED}"$log_disk"${RESET}. \n${RED}/postgres_dump${RESET} will be created on ${RED}"$dump_disk"${RESET}."
echo "Is this ok? [y/n]"
read confirmation

if [[ $confirmation == "n" ]];then
exit 1
elif [[ $confirmation == "y" ]]; then
echo -e "${GREEN}Creating Physical volumes.${RESET}"
pvcreate $data_disk
pvcreate $log_disk
pvcreate $dump_disk
break;
else
echo "Enter either 'y' or 'n'"
fi
done

while true;
do
echo -e "${GREEN} Do you want to proceed with volume group creation? [y/n] ${RESET}"
read vg_confirmation

if [[ $vg_confirmation == "n" ]];then
echo -e "${RED}Aborting.${RESET}"
exit 1
elif [[ $vg_confirmation == "y" ]]; then
echo -e "${GREEN}Creating volume groups.${RESET}"
vgcreate pg_data_vg $data_disk
vgcreate pg_log_vg $log_disk
vgcreate pg_dump_vg $dump_disk
break;
else
echo "Enter either 'y' or 'n'"
fi
done


while true;
do
echo -e "${GREEN} Do you want to proceed with Logical volume creation? [y/n] ${RESET}"
read lv_confirmation

if [[ $lv_confirmation == "n" ]];then
echo -e "${RED}Aborting.${RESET}"
exit 1
elif [[ $lv_confirmation == "y" ]]; then
echo -e "${GREEN}Creating Logical volumes.${RESET}"
lvcreate -l+100%FREE -n postgres_data pg_data_vg
lvcreate -l+100%FREE -n postgres_log pg_log_vg
lvcreate -l+100%FREE -n postgres_dump pg_dump_vg
break;
else
echo "Enter either 'y' or 'n'"
fi
done

echo "======================================================================"
echo -e "${GREEN}Creating the directories.${RESET}"
mkdir /postgres_data
mkdir /postgres_dump
mkdir /postgres_log
echo -e "${GREEN}**** Successfully created the directories. ****${RESET}"
echo "======================================================================"

echo -e "${GREEN}Creating the File systmes.${RESET}"
mkfs.ext4 /dev/mapper/pg_data_vg-postgres_data
mkfs.ext4 /dev/mapper/pg_dump_vg-postgres_dump
mkfs.ext4 /dev/mapper/pg_log_vg-postgres_log
echo -e "${GREEN}**** Successfully created the file systems. ****${RESET}"
echo "======================================================================"

echo -e "${GREEN}Adding entries to FSTAB.${RESET}"
echo "/dev/mapper/pg_data_vg-postgres_data /postgres_data ext4 defaults,nodev 0 0">> /etc/fstab
echo "/dev/mapper/pg_dump_vg-postgres_dump /postgres_dump ext4 defaults,nodev 0 0">> /etc/fstab
echo "/dev/mapper/pg_log_vg-postgres_log /postgres_log ext4 defaults,nodev 0 0">> /etc/fstab
echo -e "${GREEN}**** Successfully added the entries to FSTAB. ****${RESET}"
echo "======================================================================"

echo -e "${GREEN}Mounting the filesystems.${RESET}"
mount /postgres_data
mount /postgres_dump
mount /postgres_log
echo -e "${GREEN}**** Successfully mounted the filesystems. ****${RESET}"
echo "======================================================================"

echo -e "${GREEN}Modifying the directory permissions.${RESET}"
chmod -R 700 /postgres_data
chmod -R 700 /postgres_dump
chmod -R 700 /postgres_log
echo -e "${GREEN}**** Successfully modified the permissions. ****${RESET}"
echo "======================================================================"


rm -rf  /postgres_data/lost+found
rm -rf  /postgres_dump/lost+found
rm -rf  /postgres_log/lost+found



