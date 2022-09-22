#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

fileNAME=`basename "$0"`
imgMAJOR=1
imgMINOR=5
imgNAME=memoreOS-$imgMAJOR-$imgMINOR
newMAJOR=$((imgMAJOR+1))
newMINOR=$((imgMINOR+1))

echo "Do you want to create a new major or minor version?"
PS3='Select an option: '
app=("New-Major" "New-Minor" "Quit")
select fav in "${app[@]}";do
case $fav in
"New-Major")
rm memoreOS*.iso
sed -i "s/imgMAJOR=$imgMAJOR/imgMAJOR=$newMAJOR/g" $fileNAME
resetMINOR=0
sed -i "s/imgMINOR=$imgMINOR/imgMINOR=$resetMINOR/g" $fileNAME
newNAME=memoreOS-$newMAJOR-$resetMINOR
#Download ISO
#wget -N https://cdimage.ubuntu.com/ubuntu-server/focal/daily-live/current/focal-live-server-amd64.iso
break
;;
"New-Minor")
rm memoreOS*.iso
sed -i "s/imgMINOR=$imgMINOR/imgMINOR=$newMINOR/g" $fileNAME
newNAME=memoreOS-$imgMAJOR-$newMINOR
break
;;
"Quit")
echo "Process aborted!"
exit
;;
*) echo "Input not allowed: $REPLY";;
esac
done

#Install required packages
apt-get install -y \
cloud-init \
p7zip-full \
xorriso \
isolinux \
syslinux

if ! [ -f iso/ ];
then
	#Create source file directory
	mkdir -p iso/nocloud/
	
	#Unpack ISO
	7z -y x ubuntu-20.04.4-live-server-amd64.iso -oiso

	#Edit grub.cfg / txt.cfg
	sed -i 's|---|autoinstall ds=nocloud\\\;s=/cdrom/nocloud/ fsck.mode=skip   ---|g' iso/boot/grub/grub.cfg
	sed -i '/^set timeout/i set default=3' iso/boot/grub/grub.cfg
	sed -i 's|---|autoinstall ds=nocloud;s=/cdrom/nocloud/ fsck.mode=skip    ---|g' iso/isolinux/txt.cfg
	sed -i 's|default live|default hwe-live|g' iso/isolinux/txt.cfg

	#create meta-data
	touch iso/nocloud/meta-data

	#Disable mandatory md5 checksum on boot
	md5sum iso/.disk/info > iso/md5sum.txt
	sed -i 's|iso/|./|g' iso/md5sum.txt
fi

#copy files
mkdir -p builds/$newNAME
cp memore-startup.sh builds/$newNAME/.
sed -i "s|memoreOS-.*|$newNAME|g" user-data
cp user-data builds/$newNAME/.
cp user-data iso/nocloud/.

#Generate a new autoinstall ISO Image
xorriso -as mkisofs -r \
  -V Ubuntu\ custom\ amd64 \
  -o $newNAME.iso \
  -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot \
  -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
  -isohybrid-gpt-basdat -isohybrid-apm-hfsplus \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin  \
  iso/boot iso
