#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

apt-get -y update && \
apt-get -y dist-upgrade

depCERT=/etc/ssl/deployment-cert
memREPO=https://repo.memore.de/memorecerts
boxMODEL=$(dmidecode | grep -A3 '^System Information')
boxSERIAL=$(dmidecode -s system-serial-number)

memLOGS=/var/log/memore

install_pkgs () {
        if ! dpkg -s $1 >/dev/null 2>&1;
        then
                apt-get install -y $1
                if ! dpkg -s $1 >/dev/null 2>&1;
                then
                echo "could not install $1"
                exit
                fi
        fi
}

check_status () {
        httpSTATUS=$(curl -w "%{http_code}" $1)
        if ! [ $httpSTATUS -eq 302 ];
        then
                n="0"
                until [ "$n" -ge 2 ]
                do
                sleep 15
                curl -w "%{http_code}" $1 && break
                n=$((n+1))
                done
                echo "could not resolve $1"
                exit
        fi
}

check_status "backend.memore.de"
install_pkgs "memorehostname"
install_pkgs "modulesinstaller"

#set variable
memoreHOSTNAME="$(python3 /opt/memore/GetUniqueHostname.py)"
if ! grep "memoreHOSTNAME=" /etc/environment;
then
        echo export memoreHOSTNAME=$memoreHOSTNAME | tee -a /etc/environment
else
        sed -i "s/memoreHOSTNAME=.*/memoreHOSTNAME=$memoreHOSTNAME/g" /etc/environment
fi
source /etc/environment

#set memoreHOSTNAME
if ! [ $HOSTNAME == $memoreHOSTNAME ];
then
        hostnamectl set-hostname $memoreHOSTNAME
        sed -i "s/127.0.1.1 .*/127.0.1.1 $memoreHOSTNAME/g" /etc/hosts
        memCERT=/etc/ssl/$memoreHOSTNAME
        wget --certificate=$depCERT.crt --private-key=$depCERT.pem $memREPO/$memoreHOSTNAME.crt -O $memCERT.crt
        wget --certificate=$depCERT.crt --private-key=$depCERT.pem $memREPO/$memoreHOSTNAME.key -O $memCERT.pem
        chmod 444 $memCERT.*
        if [ -f "$memCERT.crt" ] && [ -f "$memCERT.pem" ];
        then
                sed -i "s/deployment-cert/$memoreHOSTNAME/g" /etc/apt/apt.conf.d/55clientcert
                rm $depCERT.*
        else
		echo "Could not load $memoreHOSTNAME Certs"
		exit
        fi
fi

#Logfile
tee -a $memLOGS/memoreBox_info <<EOF

memoreBox-No.
	$memoreHOSTNAME

Installation date
	`date`

$boxMODEL

EOF

#Box Serial No
echo $boxSERIAL > $memLOGS/box-serial

#execute modulesinstaller as memore user
cd /opt/memore/modulesinstaller
sudo -u memore ./ModulesInstaller.x86_64

systemctl set-default graphical.target

echo "Setup completed!"
