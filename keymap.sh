#!/bin/bash
wget https://svn.neo-layout.org/linux/console/neo.map -o /mnt/usr/share/kbd/keymaps/i386/qwertz/neo.map
echo "KEYMAP=neo" > /mnt/etc/vconsole.conf
