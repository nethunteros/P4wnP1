#!/bin/bash

#    This file is part of P4wnP1.
#
#    Copyright (c) 2017, Marcus Mengs. 
#
#    P4wnP1 is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    P4wnP1 is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with P4wnP1.  If not, see <http://www.gnu.org/licenses/>.


# P4wnP1 install script.
#       Author: Marcus Mengs (MaMe82)
#
# Notes:
#   - install.sh should only be run ONCE
#   - work in progress (contains possible errors and typos)
#	- the script needs an Internet connection to install the required packages


# get DIR the script is running from (by CD'ing in and running pwd
wdir=$( cd $(dirname $BASH_SOURCE[0]) && pwd)

sudo apt-get install -y curl dosfstools

# check Internet conectivity against 
echo "Testing Internet connection and name resolution..."
if [ "$(curl -s http://www.msftncsi.com/ncsi.txt)" != "Microsoft NCSI" ]; then 
        echo "...[Error] No Internet connection or name resolution doesn't work! Exiting..."
        exit
fi
echo "...[pass] Internet connection works"

# check for Raspbian Jessie
echo "Testing if the system runs compatible release..."
if ! (grep -q -E "Raspbian.*jessie" /etc/os-release || grep -q -E "Raspbian.*stretch" /etc/os-release || grep -q -E "Kali" /etc/os-release) ; then
        echo "...[Error] Pi is not running Raspbian Jessie/Stretch or Kali! Exiting ..."
        exit
fi

echo "...[pass] Pi seems to be running Raspbian Jessie or Stretch"
if (grep -q -E "Raspbian.*stretch" /etc/os-release) ; then
	STRETCH=true
fi

# check for Kali Linux
echo "Testing if the system runs Kali..."
if (grep -q -E "Kali" /etc/os-release) ; then
        echo "Detected Kali"
        KALI=true
fi

echo "Backing up resolv.conf"
sudo cp /etc/resolv.conf /tmp/resolv.conf

echo "Installing needed packages..."
sudo apt-get -y update
sudo apt-get -y upgrade # include patched bluetooth stack

# hostapd gets installed in even if WiFi isn't present (SD card could be moved from "Pi Zero" to "Pi Zero W" later on)
sudo apt-get -y install dnsmasq git python-pip python-dev screen sqlite3 inotify-tools \
                        hostapd autossh bluez bluez-tools bridge-utils ethtool

# not needed in production setup
#sudo apt-get install -y tshark tcpdump

# at this point the nameserver in /etc/resolv.conf is set to 127.0.0.1, so we replace it with 8.8.8.8
#	Note: 
#	A better way would be to backup before dnsmasq install, with
#		$ sudo bash -c "cat /etc/resolv.conf > /tmp/backup"
#	and restore here with
#		$ sudo bash -c "cat /tmp/backup > /etc/resolv.conf"
sudo bash -c "cat /tmp/resolv.conf > /etc/resolv.conf"
# append 8.8.8.8 as fallback secondary dns
sudo bash -c "echo nameserver 8.8.8.8 >> /etc/resolv.conf"

# install pycrypto
echo "Installing needed python additions..."
# Fix: issue of conflicting filename 'setup.cfg' with paython setuptools
# Reported by  PoSHMagiC0de
# https://github.com/mame82/P4wnP1/issues/52#issuecomment-325236711
mv setup.cfg setup.bkp
sudo pip install pycrypto # already present on stretch
sudo pip install pydispatcher
mv setup.bkp setup.cfg

# Installing Responder isn't needed anymore as it is packed into the Repo as submodule
#echo "Installing Responder (patched MaMe82 branch with Internet connection emulation and wpad additions)..."
# clone Responder from own repo (at least till patches are merged into master)
#git clone -b EMULATE_INTERNET_AND_WPAD_ANYWAY --single-branch https://github.com/mame82/Responder

# disable interfering services
echo "Disabeling unneeded services to shorten boot time ..."
sudo update-rc.d ntp disable # not needed for stretch (only jessie)
sudo update-rc.d avahi-daemon disable
sudo update-rc.d dhcpcd disable
sudo update-rc.d networking disable
sudo update-rc.d avahi-daemon disable
sudo update-rc.d dnsmasq disable # we start this by hand later on

echo "Create udev rule for HID devices..."
# rule to set access rights for /dev/hidg* to 0666 
echo 'SUBSYSTEM=="hidg",KERNEL=="hidg[0-9]", MODE="0666"' > /tmp/udevrule
sudo bash -c 'cat /tmp/udevrule > /lib/udev/rules.d/99-usb-hid.rules'

echo "Enable SSH server..."
sudo update-rc.d ssh enable

echo "Checking network setup.."
# set manual configuration for usb0 (RNDIS) if not already done
if ! grep -q -E '^iface usb0 inet manual$' /etc/network/interfaces; then
	echo "Entry for manual configuration of RNDIS interface not found, adding..."
	sudo /bin/bash -c "printf '\niface usb0 inet manual\n' >> /etc/network/interfaces"
else
	echo "Entry for manual configuration of RNDIS interface found"
fi

# set manual configuration for usb1 (CDC ECM) if not already done
if ! grep -q -E '^iface usb1 inet manual$' /etc/network/interfaces; then
	echo "Entry for manual configuration of CDC ECM interface not found, adding..."
	sudo /bin/bash -c "printf '\niface usb1 inet manual\n' >> /etc/network/interfaces"
else
	echo "Entry for manual configuration of CDC ECM interface found"
fi

echo "Unpacking John the Ripper Jumbo edition..."
cd john-1-8-0-jumbo_raspbian_jessie_precompiled/
git fetch
git checkout jtr_stretch
cd ..
if $STRETCH; then
	tar zxf john-1-8-0-jumbo_raspbian_jessie_precompiled/john-1-8-0-jumbo_raspbian_stretch_precompiled.tar.gz
else
	tar xJf john-1-8-0-jumbo_raspbian_jessie_precompiled/john-1.8.0-jumbo-1_precompiled_raspbian_jessie.tar.xz
fi


# overwrite Responder configuration
echo "Configure Responder..."
sudo mkdir -p /var/www
sudo chmod a+r /var/www
cp conf/default_Responder.conf Responder/Responder.conf
sudo cp conf/default_index.html /var/www/index.html
sudo chmod a+r /var/www/index.html


# create 128 MB image for USB storage
echo "Creating 128 MB image for USB Mass Storage emulation"
mkdir -p $wdir/USB_STORAGE
dd if=/dev/zero of=$wdir/USB_STORAGE/image.bin bs=1M count=128
mkdosfs $wdir/USB_STORAGE/image.bin

# create folder to store loot found
mkdir -p $wdir/collected


# create systemd service unit for P4wnP1 startup
if [ ! -f /etc/systemd/system/P4wnP1.service ]; then
        echo "Injecting P4wnP1 startup script..."
        cat <<- EOF | sudo tee /etc/systemd/system/P4wnP1.service > /dev/null
                [Unit]
                Description=P4wnP1 Startup Service
                #After=systemd-modules-load.service
                After=local-fs.target
                DefaultDependencies=no
                Before=sysinit.target

                [Service]
                #Type=oneshot
                Type=forking
                RemainAfterExit=yes
                ExecStart=/bin/bash $wdir/boot/boot_P4wnP1
                StandardOutput=journal+console
                StandardError=journal+console

                [Install]
                #WantedBy=multi-user.target
                WantedBy=sysinit.target
EOF
fi

sudo systemctl enable P4wnP1.service

# create systemd service for bluetooth NAP
if [ ! -f /etc/systemd/system/P4wnP1-bt-nap.service ]; then
        echo "Injecting P4wnP1 BLUETOOTH NAP startup script..."
        cat << EOF | sudo tee /etc/systemd/system/P4wnP1-bt-nap.service > /dev/null

[Unit]
Description=P4wnP1 Bluetooth NAP service
After=bluetooth.service
PartOf=bluetooth.service

[Service]
Type=forking
RemainAfterExit=yes
ExecStart=/bin/bash /root/P4wnP1/boot/init_bt.sh
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=bluetooth.target

EOF
fi

sudo systemctl enable P4wnP1-bt-nap.service

if ! grep -q -E '^.+P4wnP1 STARTUP$' /root/.profile; then
	echo "Adding P4wnP1 startup script to /root/.profile..."
cat << EOF >> /root/.profile
# P4wnP1 STARTUP
source /tmp/profile.sh
declare -f onLogin > /dev/null && onLogin
EOF
fi

# removing FSCK from fstab, as this slows down boot (jumps in on stretch nearly every boot)
echo "Disable FSCK on boot ..."
sudo sed -i -E 's/[12]$/0/g' /etc/fstab

# enable autologin for user pi (requires RASPBIAN JESSIE LITE, should be checked)
echo "Enable autologin for user pi..."
sudo ln -fs /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty1.service

# setup USB gadget capable overlay FS (needs Pi Zero, but shouldn't be checked - setup must 
# be possible from other Pi to ease up Internet connection)
echo "Enable overlay filesystem for USB gadgedt suport..."
sudo sed -n -i -e '/^dtoverlay=/!p' -e '$adtoverlay=dwc2' /boot/config.txt

# add libcomposite to /etc/modules
echo "Enable kernel module for USB Composite Device emulation..."
if [ ! -f /tmp/modules ]; then sudo touch /etc/modules; fi
sudo sed -n -i -e '/^libcomposite/!p' -e '$alibcomposite' /etc/modules

echo "Removing all former modules enabled in /boot/cmdline.txt..."
sudo sed -i -e 's/modules-load=.*dwc2[',''_'a-zA-Z]*//' /boot/cmdline.txt

# still needed on current stretch releas, kernel 4.9.41+ ships still
# with broken HID gadget module (installing still needs a cup of coffee)
# Note:  last working Jessie version was the one with kernel 4.4.50+
#        stretch kernel known working is 4.9.45+ (only available via update right now)

# Raspbian stretch with Kernel >= 4.9.50+ needed for working bluetooth nap
if $STRETCH ; then
    echo "Installing kernel update ..."
    sudo rpi-update
fi

echo "Generating keypair for use with AutoSSH..."
source $wdir/setup.cfg

mkdir -p -- "$(dirname -- "$AUTOSSH_PRIVATE_KEY")"

ssh-keygen -q -N "" -C "P4wnP1" -f $AUTOSSH_PRIVATE_KEY && SUCCESS=true
if $SUCCESS; then
        echo "... keys created"
        echo
        echo "Use \"$wdir/ssh/pushkey.sh\""
        echo "in order to promote the public key to a remote SSH server"
else
	echo "Creation of SSH key pair failed!"
fi


echo
echo
echo "===================================================================================="
echo "If you came till here without errors, you shoud be good to go with your P4wnP1..."
echo "...if not - sorry, you're on your own, as this is work in progress"
echo 
echo "Attach P4wnP1 to a host and you should be able to SSH in with pi@172.16.0.1 (via RNDIS/CDC ECM)"
echo
echo "If you use a USB OTG adapter to attach a keyboard, P4wnP1 boots into interactive mode"
echo
echo "If you're using a Pi Zero W, a WiFi AP should be opened. You could use the AP to setup P4wnP1, too."
echo "          WiFi name:    P4wnP1"
echo "          Key:          MaMe82-P4wnP1"
echo "          SSH access:    root@172.24.0.1 (password: toor)"
echo
echo "  or via Bluetooth NAP:    root@172.26.0.1 (password: toor)"
echo
echo "Go to your installation directory. From there you can alter the settings in the file 'setup.cfg',"
echo "like payload and language selection"
echo 
echo "If you're using a Pi Zero W, give the HID backdoor a try ;-)"
echo
echo "You need to reboot the Pi now!"
echo "===================================================================================="

