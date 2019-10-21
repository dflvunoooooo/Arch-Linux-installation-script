#!/bin/bash
# WARNING: this script will destroy data on the selected disk.
# This script can be run by executing the following:
#   curl -sL https://git.io/JeRYd | bash
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

### Get infomation from user ###
hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear

timedatectl set-ntp true

### Setup the disk and partitions ###
swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
swap_end=$(( $swap_size + 2048 + 1 ))MiB

parted --script ${device} -- mklabel gpt \
  mkpart ESP fat32 1Mib 2GiB \
  set 1 boot on \
  mkpart primary linux-swap 2GiB ${swap_end} \
  mkpart primary ext4 ${swap_end} 100%

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
part_root="$(ls ${device}* | grep -E "^${device}p?3$")"

wipefs "${part_boot}"
wipefs "${part_swap}"
wipefs "${part_root}"

mkfs.vfat -F32 "${part_boot}"
mkswap "${part_swap}"
mkfs.ext4 "${part_root}"

swapon "${part_swap}"
mount "${part_root}" /mnt
mkdir /mnt/boot
mount "${part_boot}" /mnt/boot

### Install and configure the basic system ###
## Mirrorlist with reflector for european server
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
pacman -Sy --noconfirm reflector
reflector --country 'Germany' --country 'Romania' --country 'United Kingdom' --country 'Spain' --country 'Switzerland' --country 'Sweden' --country 'Slovenia' --country 'Portugal' --country 'Poland' --country 'Norway' --country 'Netherlands' --country 'Luxembourg' --country 'Lithuania'  --country 'Latvia' --country 'Italy' --country 'Ireland' --country 'Iceland' --country 'Hungary' --country 'Greece' --country 'France'  --country 'Finland' --country 'Denmark' --country 'Czechia' --country 'Croatia' --country 'Bulgaria' --country 'Belgium' --country 'Austria'  --latest 50 --age 24 --sort rate --save /etc/pacman.d/mirrorlist

pacstrap /mnt base base-devel linux linux-firmware intel-ucode bash-completion nano reflector dbus avahi networkmanager
genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
echo "${hostname}" > /mnt/etc/hostname

cp /mnt/etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist.bak
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

arch-chroot /mnt bootctl --path=/boot install

cat <<EOF > /mnt/boot/loader/loader.conf
default arch
EOF

cat <<EOF > /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux
initrd   /intel-ucode.img
initrd   /initramfs-linux.img
options  root=UUID=$(blkid -s UUID -o value "$part_root") rw
EOF

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime

echo "LANG=de_DE.UTF-8" > /mnt/etc/locale.conf
echo "de_DE.UTF-8 UTF-8" > /mnt/etc/locale.gen
arch-chroot /mnt locale-gen

wget -q https://svn.neo-layout.org/linux/console/neo.map -o /mnt/usr/share/kbd/keymaps/i386/qwertz/neo.map
echo KEYMAP=neo > /mnt/etc/vconsole.conf

arch-chroot /mnt useradd -m -g users -s /bin/bash -G wheel,video,audio,storage,games,input "$user"

arch-chroot /mnt systemctl enable avahi-daemon
arch-chroot /mnt systemctl enable NetworkManager.service

arch-chroot /mnt sudo -u "$user" git -C /mnt/home/"$user" clone https://aur.archlinux.org/aurman.git  &> /dev/null
arch-chroot /mnt sudo -u "$user" sh -c "cd /home/"$user"/aurman; makepkg -si --skippgpcheck --noconfirm"

