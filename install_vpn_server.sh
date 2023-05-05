#!/bin/bash

validate_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
	echo $stat
}

validate_port()
{
	port=$1
	if ! [[ $port =~ ^[0-9]+$ ]]; then
		echo 1
		return
	fi
	if [[ $port -lt 0 ]]; then
		echo 1
		return
	fi
	if [[ $port -gt 65535 ]]; then
		echo 1
		return
	fi
	echo 0
}


read -p "Enter your server's IP address: " ip
ip_ok=$(validate_ip "$ip")
while [[ $ip_ok -ne 0 ]]; do
	echo "Invalid IP address."
	read -p "Enter your server's IP address: " ip
	ip_ok=$(validate_ip "$ip")
done

read -p "Enter username [root]:" username
username=${username:-root}

read -p "Enter protocole (1 for udp, 0 for tcp)[1]:" proto_index
proto_index=${proto_index:-1}
until [[ "$proto_index" =~ ^[01]*$ ]]; do
	echo "$proto_index: invalid selection."
	read -p "Enter protocole (1 for udp, 0 for tcp)[1]:" proto_index
	proto_index=${proto_index:-1}
done
if [ $proto_index -eq 1 ]; then proto='udp'; else proto='tcp'; fi

read -p "Enter port number [1194]:" port
port=${port:-1194}
port_ok=$(validate_port "$port")
while [[ $port_ok -ne 0 ]]; do
	echo "Invalid port number."
	read -p "Enter port number [1194]:" port
	port=${port:-1194}
	port_ok=$(validate_port "$port")
done

read -p "Is your server accessible with 'ssh_key' access key? [y/n]" access
until [[ "$access" =~ ^[yYnN]*$ ]]; do
	echo "$access: invalid selection."
	read -p "Is your server accessible with 'ssh_key' access key? [y/n]" access
done

if [[ "$access" =~ ^[nN]$ ]]; then
	yes | ssh-copy-id -o StrictHostKeyChecking=no -i ssh_key "$username@$ip"
fi

echo -e "\n====== Uploading necessary files ======\n"
cp openvpn_config_files/server-template.conf openvpn_config_files/server.conf
sed -i "s/{proto}/$proto/" openvpn_config_files/server.conf
sed -i "s/{port}/$port/" openvpn_config_files/server.conf
sed -i "s/{een}/$proto_index/" openvpn_config_files/server.conf
scp -rp -o "StrictHostKeyChecking no" -i ssh_key openvpn_config_files/ "$username@$ip:~/"
rm openvpn_config_files/server.conf
echo -e "done\n"

interface=$(ssh -i ssh_key "$username@$ip" ". /etc/profile && ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)'")
ssh -i ssh_key "$username@$ip" << END
	echo -e "==== Removing old instances ===="
	yes | sudo apt remove openvpn
	sudo rm -r /etc/openvpn
	echo -e "done\n"

	echo "====== Installing OpenVPN ======"
	sudo apt update
	sudo apt install -y openvpn ufw
	echo -e "done\n"

	echo "====== Configuring system ======"
	cd ~/
	sed -i "s/{interface}/$interface/" openvpn_config_files/before.rules
	yes | sudo cp -rf openvpn_config_files/before.rules /etc/ufw/before.rules
	yes | sudo cp -rf openvpn_config_files/ufw /etc/default/ufw
	yes | sudo cp -rf openvpn_config_files/sysctl.conf /etc/sysctl.conf
	echo -e "done\n"

	echo "====== Copying OpenVPN server files ======"
	sudo cp -rf openvpn_config_files/{ca.crt,dh.pem,server.conf,server.crt,server.key,ta.key} /etc/openvpn/
	echo -e "done\n"

	echo "====== Configuring firewall ======"
	sudo ufw allow 1194/udp
	sudo ufw allow "$port"
	sudo ufw allow OpenSSH
	sudo ufw disable
	yes | sudo ufw enable
	echo -e "done\n"

	echo "====== Starting OpenVPN ======"
	sudo systemctl start openvpn@server
	sudo systemctl enable openvpn@server
	sudo systemctl status openvpn@server
	echo -e "done\n"

	echo "Rebooting server..."
	sudo reboot
END

echo "====== Creating ovpn file ======"
read -p "Enter file name for this server: " filename
while [[ ${#filename} -eq 0 ]]; do
	echo "File name can not be empty!"
	read -p "Enter file name for this server: " filename
done

cp openvpn_config_files/template.ovpn "ovpn_files/$filename.ovpn"
sed -i "s/{ip}/$ip/" "ovpn_files/$filename.ovpn"
sed -i "s/{proto}/$proto/" "ovpn_files/$filename.ovpn"
sed -i "s/{port}/$port/" "ovpn_files/$filename.ovpn"
echo "Config file created successfully. You can find it in the ovpn_files folder. Copy or add it to your host."
read -n 1 -s -r -p "Press any key to exit"
