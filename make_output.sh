#!/bin/sh
[ -z "$1" ] && exit 1
[ -z "$2" ] && exit 1
pushd output && ls . | grep -xv ".*linux\|.*-bootloader.*\|.*modules" | xargs sudo rm -rf; popd
./make_bootfs.sh "$1"
./make_rootfs.sh
sudo ./make_final.sh "$2"
ME=$(whoami)
sudo chown $ME output/sdcard.img
