#!/bin/bash
 
HOME=/home/memore
boxMODEL=$(dmidecode | grep -A3 '^System Information')

echo "Startin Setup"

#download deployment certificates
wget https://repo.memore.de/memorecerts/deployment-cert.crt -O /etc/ssl/deployment-cert.crt
wget https://repo.memore.de/memorecerts/deployment-cert.key -O /etc/ssl/deployment-cert.pem
chmod 444 /etc/ssl/deployment-cert.*
 
#setting up certificates
tee /etc/apt/apt.conf.d/55clientcert <<EOF
Acquire::https::repo.memore.de {
Verify-Peer "true";
Verify-Host "true";
 
SslCert "/etc/ssl/deployment-cert.crt";
SslKey "/etc/ssl/deployment-cert.pem";
};
EOF
 
#disable ubuntu-archive repo
sed -i 's/^deb /#deb /g' /etc/apt/sources.list

#download retrobrain.net certs
mkdir /usr/local/share/ca-certificates/retrobrain
wget http://bootserver.retrobrain.net/it//retrobrain-ca.crt -O /usr/local/share/ca-certificates/retrobrain/retrobrain-ca.crt
wget http://bootserver.retrobrain.net/it//retrobrain-net-ca.crt -O /usr/local/share/ca-certificates/retrobrain/retrobrain-net-ca.crt
update-ca-certificates

#add memore Repo´s
tee /etc/apt/sources.list.d/repo.retrobrain.list <<EOF
deb https://repo.memore.de/repository/box-ubuntu focal main restricted
 
deb https://repo.memore.de/repository/box-ubuntu focal-updates main restricted
 
deb https://repo.memore.de/repository/box-ubuntu focal universe
deb https://repo.memore.de/repository/box-ubuntu focal-updates universe
 
deb https://repo.memore.de/repository/box-ubuntu focal multiverse
deb https://repo.memore.de/repository/box-ubuntu focal-updates multiverse
 
deb https://repo.memore.de/repository/box-ubuntu focal-backports main restricted universe multiverse
 
 
deb https://repo.memore.de/repository/box-ubuntu focal-security main restricted
deb https://repo.memore.de/repository/box-ubuntu focal-security universe
deb https://repo.memore.de/repository/box-ubuntu focal-security multiverse
EOF
 
touch /etc/apt/sources.list.d/memoremain.list
echo 'deb [arch=amd64] https://repo.memore.de/repository/main/ focal main' | tee /etc/apt/sources.list.d/memoremain.list
 
wget --certificate=/etc/ssl/deployment-cert.crt --private-key=/etc/ssl/deployment-cert.pem -qO - https://repo.memore.de/repository/repokeys/main-deb.txt |
apt-key add -

#NUC11 setup
if [[ "$boxMODEL" =~ "NUC11" ]];
then
	if ! grep "intel_iommu=on" /etc/default/grub | grep -q "8086:4905"; 
	then
		sed -ine \
		's,^GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)",GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet splash intel_iommu=on vfio-pci.ids=8086:4905",g' \
		/etc/default/grub
	fi
	
	grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
	update-grub
	wget -qO - https://repositories.intel.com/graphics/intel-graphics.key |
	apt-key add -
	apt-add-repository \
	'deb [arch=amd64] https://repositories.intel.com/graphics/ubuntu focal main'

	apt-get update
	apt-get dist-upgrade -y
	apt-get install -y \
	intel-opencl-icd \
	intel-level-zero-gpu level-zero \
	intel-media-va-driver-non-free libmfx1
		
	stat -c "%G" /dev/dri/render*
	groups memore

	gpasswd -a memore render
	#newgrp render
else	
	if ! grep "quiet splash" /etc/default/grub; 
	then
		sed -ine \
		's,^GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)",GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet splash",g' \
		/etc/default/grub
		update-grub
	fi
	apt-get update
	apt-get dist-upgrade -y
fi
sed "s/#GRUB_GFXMODE=640x480/GRUB_GFXMODE=1920x1080/g" -i /etc/default/grub

#Libfreenect2 DEP's
apt-get install -y \
libusb-1.0-0-dev \
libturbojpeg0-dev \
libglfw3-dev \
beignet-dev \
libva-dev \
libjpeg-dev \
libopenni2-dev \
libfreenect2
 
#memore
apt-get install -y \
memoremain \
memorehostname \
memore-plymouth \
pip \
memoremainwatcher \
modulesinstaller \
nuitrackactivation

#plymouth splash screen
apt-get install -y \
plymouth-themes \
plymouth-x11 \
memore-plymouth

#xorg
apt-get install -y xorg
systemctl set-default multi-user.target
 
#Nuitrack
apt-get install -y \
libbluetooth-dev \
freeglut3 \
freeglut3-dev \
libcurl4-gnutls-dev \
libgtk2.0-0 \
libxmu-dev \
libxi-dev

apt-get install -y \
nuitrack
chown -R memore:memore /usr/etc/nuitrack/data
usermod -a -G video memore

#Install missing fonts
apt-get install -y \
xfonts-base \
xfonts-100dpi \
xfonts-75dpi \
gsfonts \
ttf-xfree86-nonfree \
fonts-freefont-ttf

#Autologin tty1
mkdir "/etc/systemd/system/getty@tty1.service.d"
tee /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
Type=idle
ExecStart=
ExecStart=-/sbin/agetty --autologin memore --noclear %I 38400 linux
EOF
 
#Disable message of the day when login
touch $HOME/.hushlogin
 
#Xorg file
touch $HOME/.xinitrc
echo /usr/bin/python3 /opt/memore/watcher/MemoreMainWatcher.py > /home/memore/.xinitrc
chown memore:memore /home/memore/.xinitrc

#Disable wait for network
systemctl disable systemd-networkd-wait-online.service
systemctl mask systemd-networkd-wait-online.service
 
#Disable Cloud-init services
touch /etc/cloud/cloud-init.disabled

#permissions for memore user
echo "memore  ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers

#custom AccountService
tee /var/lib/AccountsService/users/memore <<EOF
[User]
Session=
XSession=custom
Icon=/home/memore/.face
SystemAccount=true

[InputSource0]
xkb=de

EOF

#custom.desktop for memore autostart
tee /usr/share/xsessions/custom.desktop <<EOF
[Desktop Entry]
Name=Xsession
Exec=/etc/X11/Xsession
EOF

#xsession symlink
ln -s $HOME/.xinitrc $HOME/.xsession

#gdm3 autostart
sed -i '/\[daemon\]/a \   AutomaticLoginEnable = true' /etc/gdm3/custom.conf
sed -i '/\   AutomaticLoginEnable = true/a \   AutomaticLogin = memore' /etc/gdm3/custom.conf

#edit gsettings for custom power-button
gsettings set org.gnome.settings-daemon.plugins.power button-power nothing

#disable standby
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type nothing
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing

#install python lib
pip3 install events

#Clean
apt-get autoremove -y
apt-get autoclean -y

clear
echo "Setup Complete!"
