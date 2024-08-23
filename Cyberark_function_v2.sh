cyberark () {
	id=`whoami`
	local action="$1"
	local hostname="$2"
	local filename="$3"
	local targetdir="$4"
	
	usage () {
		echo -e "------------------------------------------------------------"
		echo -e "Cyberark function can be used to either ${RED}SSH${COLOR_OFF} or ${RED}SCP${COLOR_OFF}."
		echo ""
		echo -e "Example of SSH: ${GREEN}cyberark ssh lxpgstestdevs03${COLOR_OFF}"
		echo -e "Example of SCP to remote server : ${GREEN}cyberark push lxpgstestdevs03 <filename/dirname> <target directory>${COLOR_OFF}"
		echo -e "Example of SCP from remote server : ${GREEN}cyberark pull lxpgstestdevs03 <remote filename/dirname>${COLOR_OFF}  #File will be saved in Downloads"
		echo -e "------------------------------------------------------------"
		return 1
	}
	usage_ssh () {
		echo -e "------------------------------------------------------------"
		echo -e "Needs ${RED}hostname${COLOR_OFF}..."
		echo ""
		echo -e "Example : ${GREEN}cyberark ssh lxpgstestdevs03${COLOR_OFF}"
		echo -e "------------------------------------------------------------"
		return 1
	}
	usage_scp () {
		echo -e "------------------------------------------------------------"
		echo -e "Needs ${RED}hostname${COLOR_OFF} , ${RED}filename${COLOR_OFF} and ${RED}target-directory${COLOR_OFF}..."
		echo ""
		echo -e "Example of SCP to remote server : ${GREEN}cyberark push lxpgstestdevs03 <filename/dirname> <target directory>${COLOR_OFF}"
		echo -e "Example of SCP from remote server : ${GREEN}cyberark pull lxpgstestdevs03 <remote filename/dirname>${COLOR_OFF}  #File will be saved in Downloads"
		echo -e "------------------------------------------------------------"
		return 1
	}
	if [[ "${#}" -lt 1 ]] || [[ $1 == "--help" ]]
	then
		usage
		break &> /dev/null
	fi
	if [[ "${#}" -lt 2 ]] && [[ $1 == "ssh" ]]
	then
		usage_ssh
		break &> /dev/null
	fi
	if [[ "${#}" -lt 2 ]] && ([[ $1 == "scp" ]] || [[ $1 == "push" ]] || [[ $1 == "pull" ]])
	then
		usage_scp
		break &> /dev/null
	fi
	
	local latest_key=$(find /Users/${id}/Downloads/ -name '*key*.openssh*' -mmin -720 -exec stat -f "%B %N" {} \; | sort -n | tail -1 | awk '{$1=""; print substr($0,2)}')
	local new_filename="/Users/${id}/Downloads/key.openssh"
	if [[ -e $latest_key ]]
	then
		mv "$latest_key" "$new_filename"
	else
		echo -e "${RED}Download key from Cyberark portal and retry${COLOR_OFF}"	
		echo -e "${GREEN}Link${COLOR_OFF} : https://mswebcpasprdw02.lowes.com/PasswordVault/v10/PSM-SSH-MFA-Caching "	
	fi
	
	local keyfile="/Users/${id}/Downloads/key.openssh"
	
	if [[ -e $keyfile ]]
	then
		chmod 600 $keyfile
		local hostkey_present=`cat /Users/${id}/.ssh/known_hosts|grep -i cyberark`
		if [[ -n $hostkey_present ]]
		then
			sed -i '' '/cyberark/d' /Users/${id}/.ssh/known_hosts
		fi
		if [[ $1 == "ssh" ]]
		then
			ssh -o stricthostkeychecking=no -o ConnectTimeout=3 -i $keyfile ${id}@postgres@${2}.lowes.com@cyberark-psmp.lowes.com
		elif [[ $1 == "push" ]]
		then
			if [[ -d $3 ]]
			then
				scp -r -O -i $keyfile $3 ${id}@postgres@${2}.lowes.com@cyberark-psmp.lowes.com:${4}
			else
				scp -O -i $keyfile $3 ${id}@postgres@${2}.lowes.com@cyberark-psmp.lowes.com:${4}
			fi
		elif [[ $1 == "pull" ]]
		then 
		    scp -r -O -i $keyfile ${id}@postgres@${2}.lowes.com@cyberark-psmp.lowes.com:${3} /Users/${id}/Downloads
		fi
	fi
}