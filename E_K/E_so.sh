#!/bin/bash
apt install libc6:i386 -y
tar xvf E_so.tar -C /lib
chmod -R 777 * /lib
