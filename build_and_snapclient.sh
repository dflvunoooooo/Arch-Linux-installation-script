#!/bin/bash
# install with curl -sL https://git.io/Jfhdr | bash
sudo cp /usr/lib/systemd/system/snapclient.service /usr/lib/systemd/system/snapclient.service.update.bak
sudo rm -r snapcast
git clone https://github.com/badaix/snapcast.git 
cd snapcast/externals 
git submodule update --init --recursive 
cd .. 
cd client 
make
sudo make install
sudo rm /usr/lib/systemd/system/snapclient.service.pacnew
sudo mv /usr/lib/systemd/system/snapclient.service /usr/lib/systemd/system/snapclient.service.pacnew
sudo mv /usr/lib/systemd/system/snapclient.service.update.bak /usr/lib/systemd/system/snapclient.service
