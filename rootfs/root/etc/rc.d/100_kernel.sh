#!/bin/sh

# Link modprobe in case kernel needs to load modules itself
cd /sbin; rm modprobe 2>/dev/null; ln -s $(which modprobe) modprobe; cd ..

# Kernel bug workaround for ping
echo 0 99999999 > /proc/sys/net/ipv4/ping_group_range

# From here on filled by make-script
