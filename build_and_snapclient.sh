#!/bin/bash
sudo rm -r snapcast
git clone https://github.com/badaix/snapcast.git 
cd snapcast/externals 
git submodule update --init --recursive 
cd .. 
cd lient 
make && sudo make install
