#!/bin/bash
yum install glibc.i686
apt install libc6:i386
tar xvf E_so.tar -C /lib
chmod -R 777 * /lib
