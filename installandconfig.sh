#!/bin/bash
# WARNING: this script will destroy data on the selected disk.
# This script can be run by executing the following:
#   curl -sL https://git.io/JeRYd | bash
set -uo pipefail
trap 's=$?; printf "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

### Get infomation from user ###
encrypt=$(dialog --stdout --inputbox "Do you want a fully encrypted setup (type 'yes' or 'no')?" 0 0) || exit 1
clear
: ${encrypt:?"You have to answer!"}

ssd=$(dialog --stdout --inputbox "Do you install on an SSD (type 'yes' or 'no')? (If so, we will only use 90% of available diskspace.)" 0 0) || exit 1
clear
: ${ssd:?"You have to answer!"}

hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

user_password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${user_password:?"password cannot be empty"}
user_password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$user_password" == "$user_password2" ]] || ( printf "Passwords did not match"; exit 1; )

root_password=$(dialog --stdout --passwordbox "Enter root password" 0 0) || exit 1
clear
: ${root_password:?"password cannot be empty"}
root_password2=$(dialog --stdout --passwordbox "Enter root password again" 0 0) || exit 1
clear
[[ "$root_password" == "$root_password2" ]] || ( printf "Passwords did not match"; exit 1; )

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear

network=$(dialog --stdout --inputbox "Do you want DHCP or static IP (type 'dhcp' or 'static')?" 0 0) || exit 1
clear
: ${network:?"You have to answer!"}

if [ "$network" = "static" ]; then
               ip=$(dialog --stdout --inputbox "Typ static IP:" 0 0) || exit 1
               clear
               : ${ip:?"You have to answer!"}

               gate=$(dialog --stdout --inputbox "Type IP of gateway:" 0 0) || exit 1
               clear
               : ${gate:?"You have to answer!"}
               
               dns=$(dialog --stdout --inputbox "Type IP of DNS:" 0 0) || exit 1
               clear
               : ${dns:?"You have to answer!"}
            fi


timedatectl set-ntp true

## Set the size of root to either 100% or 90%
if [ "$ssd" = "yes" ]; then
               root_size="90%"
               printf "root 90"
            else
               root_size="100%"
               printf "root 100"
            fi

### Setup the disk and partitions ###
parted --script ${device} -- mklabel gpt \
  mkpart ESP fat32 1Mib 2GiB \
  set 1 boot on \
  mkpart primary ext4 2GiB $root_size

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_root="$(ls ${device}* | grep -E "^${device}p?2$")"

wipefs "${part_boot}"
wipefs "${part_root}"

mkfs.vfat -F32 "${part_boot}"
mkfs.ext4 "${part_root}"

mount "${part_root}" /mnt
mkdir /mnt/boot
mount "${part_boot}" /mnt/boot

## Install Arch Linux and a few packages
pacstrap /mnt base base-devel linux linux-firmware intel-ucode bash-completion nano reflector dbus avahi git wget man openssh neofetch htop smartmontools

## Basic system configuration 
genfstab -U /mnt >> /mnt/etc/fstab
if [ "$ssd" = "yes" ]; then
  sed -i 's/relatime/noatime/g' /mnt/etc/fstab
fi
### Swap file creation
swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
fallocate -l $(($swap_size / 1024))G /mnt/swap
chmod 600 /mnt/swap
mkswap /mnt/swap
printf "/swap\tnone\tswap\tdefaults\t0\t0" >> /mnt/etc/fstab
printf "vm.swappiness=1" >> /mnt/etc/sysctl.d/99-sysctl.conf
### /tmp in RAM
if [ "$ssd" = "yes" ]; then
  cat <<EOF >> /mnt/etc/fstab

# Temoraere Dateien in den RAM
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
EOF
fi
### Localisation
printf "${hostname}" > /mnt/etc/hostname
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
printf "KEYMAP=de-latin1" > /mnt/etc/vconsole.conf
printf "LANG=de_DE.UTF-8\nLANG=DE.UTF-8\nLC_CTYPE="de_DE.UTF-8"\nLC_NUMERIC="de_DE.UTF-8"\nLC_TIME="de_DE.UTF-8"\nLC_COLLATE="de_DE.UTF-8"\nLC_MONETARY="de_DE.UTF-8"\nLC_MESSAGES="de_DE.UTF-8"\nLC_PAPER="de_DE.UTF-8"\nLC_NAME="de_DE.UTF-8"\nLC_ADDRESS="de_DE.UTF-8"\nLC_TELEPHONE="de_DE.UTF-8"\nLC_MEASUREMENT="de_DE.UTF-8"\nLC_IDENTIFICATION="de_DE.UTF-8"\nLC_ALL=de_DE.UTF-8" > /mnt/etc/locale.conf
sed -i '/de_DE.UTF-8 UTF-8/s/^#//g' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
mv /mnt/etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist.bak
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
### Run Makepkg in RAM
sed -i 's+#BUILDDIR=/tmp/makepkg+BUILDDIR=/tmp/makepkg+g' /mnt/etc/makepkg.conf
### Change I/O scheduler, depending on whether the disk is rotating or not
cat <<\EOF > /mnt/etc/udev/rules.d/60-ioschedulers.rules
# set scheduler for NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
# set scheduler for SSD and eMMC
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# set scheduler for rotating disks
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF

## Network configuration for DHCP or static IP via sysemd-network (see arch wiki: https://wiki.archlinux.org/index.php/Systemd-networkd#Wired_adapter_using_a_static_IP)
if [ "$network" = "static" ]; then
               cat <<EOF > /mnt/etc/systemd/network/20-wired-static.network
[Match]
Name=en*

[Network]
Address=$ip/24
Gateway=$gate
DNS=$dns
EOF
else
               cat <<EOF > /mnt/etc/systemd/network/20-wired.network
[Match]
Name=en*

[Network]
DHCP=ipv4
EOF
fi

## Quickening IP/TCP
cat <<\EOF > /mnt/etc/sysctl.d/99-sysctl.conf
# https://wiki.archlinux.org/index.php/Sysctl#Improving_performance
# IP/TCP quickening
net.core.netdev_max_backlog = 100000
net.core.netdev_budget = 50000
net.core.netdev_budget_usecs = 5000
net.core.somaxconn = 1024
net.core.rmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_default = 1048576
net.core.wmem_max = 16777216
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 1048576 2097152
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 30000
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.tcp_mtu_probing = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_syncookies = 1
# IP Stack hardening
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
EOF

## SSH configuration
printf "AllowUsers  $user" >> /mnt/etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /mnt/etc/ssh/sshd_config
sed -i 's/#Port 22/Port 22222/g' /mnt/etc/ssh/sshd_config
cat <<\EOF >> /mnt/etc/ssh/sshd_config

KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group14-sha256,diffie-hellman-group18-sha512
MACs umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
HostKeyAlgorithms ssh-rsa,rsa-sha2-256,rsa-sha2-512
EOF

## Sudo configuration
sed -i '/%wheel ALL=(ALL) ALL/s/^#//g' /mnt/etc/sudoers

## Install and config bootloader
arch-chroot /mnt bootctl --path=/boot install
cat <<EOF > /mnt/boot/loader/loader.conf
default arch
EOF
root_uuid=$(blkid -s UUID -o value "$part_root")
cat <<EOF > /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux
initrd   /intel-ucode.img
initrd   /initramfs-linux.img
options  root=UUID=$root_uuid rw
EOF

## Reflector Configuration 
cat <<EOF > /mnt/etc/systemd/system/reflector.service
[Unit]
Description=Pacman mirrorlist update
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/reflector  --protocol https --country 'Germany' --country 'Romania' --country 'United Kingdom' --country 'Spain' --country 'Switzerland' --country 'Sweden' --country 'Slovenia' --country 'Portugal' --country 'Poland' --country 'Norway' --country 'Netherlands' --country 'Luxembourg' --country 'Lithuania'  --country 'Latvia' --country 'Italy' --country 'Ireland' --country 'Iceland' --country 'Hungary' --country 'Greece' --country 'France'  --country 'Finland' --country 'Denmark' --country 'Czechia' --country 'Croatia' --country 'Bulgaria' --country 'Belgium' --country 'Austria'  --latest 50 --age 24 --sort rate --save /etc/pacman.d/mirrorlist

[Install]
RequiredBy=multi-user.target
EOF

cat <<EOF > /mnt/etc/systemd/system/reflector.timer
[Unit]
Description=Run reflector weekly

[Timer]
OnCalendar=Mon *-*-* 7:00:00
RandomizedDelaySec=15h
Persistent=true

[Install]
WantedBy=timers.target
EOF

## Add User
arch-chroot /mnt useradd -m -G users,wheel,video,audio,storage,input -s /bin/bash "$user"

## Neofetch configuration
mkdir -p /mnt/home/$user/.config/neofetch
curl -sL https://git.io/JeV8r > /mnt/home/$user/.config/neofetch/config
arch-chroot /mnt chown -R $user:$user /home/$user/.config/
printf "\n\n### Neofetch Aufruf\nneofetch" >> /etc/bash.bashrc

## Aliase Festlegen
printf "\n\n###Alias\nalias ls='ls -Alh --group-directories-first --color=auto'\nalias ip='ip -c=auto'\nalias update='aurman -Syu --noconfirm --noedit;  echo;  echo ----------------;  echo Update Finished;'" >> /etc/bash.bashrc


## Systemd activieren
arch-chroot /mnt systemctl enable avahi-daemon.service
arch-chroot /mnt systemctl enable systemd-networkd.service
arch-chroot /mnt systemctl enable systemd-resolved.service
arch-chroot /mnt systemctl enable sshd.service
arch-chroot /mnt systemctl enable smartd
arch-chroot /mnt systemctl enable reflector.timer
if [ "$ssd" = "yes" ]; then
  arch-chroot /mnt systemctl enable fstrim.timer
fi

## S.M.A.R.T Notification
sed -i 's/^DEVICESCAN/DEVICESCAN -m m.westhoff@posteo.de -M exec \/usr\/local\/bin\/smartdnotify/' /etc/smartd.conf
smarttext="#!/bin/sh\nsudo -u $user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$user/bus notify-send "
smarttext+='"S.M.A.R.T Error ($SMARTD_FAILTYPE)" "$SMARTD_MESSAGE" --icon=dialog-warning'
printf "$smarttext" > /mnt/usr/local/bin/smartdnotify
chmod +x /mnt/usr/local/bin/smartdnotify

## Install aurman
## remove password of user so sudo -u will not ask for password
arch-chroot /mnt passwd -d "$user"
## Now git and install
arch-chroot /mnt sudo -u "$user" git -C /home/"$user" clone https://aur.archlinux.org/aurman.git  &> /dev/null
arch-chroot /mnt sudo -u "$user" sh -c "cd /home/"$user"/aurman; makepkg -si --skippgpcheck --noconfirm"
rm -r /mnt/home/"$user"/aurman

## Password for root and user
arch-chroot /mnt <<EOF 
printf "$root_password\n$root_password" | passwd root
EOF
arch-chroot /mnt <<EOF 
printf "$user_password\n$user_password" | passwd "$user"
EOF

## Delete bash history to erase passwords
# not working
# arch-chroot /mnt history -c

printf "\n######################################################################################\n\nYou can later login via ssh with the user $user and the port 22222\n\nYou should check that the network interface name matches that in /etc/systemd/network/20-wired.network\n\n######################################################################################\n"
