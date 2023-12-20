#!/bin/sh
qemu-system-riscv64 \
	-machine virt \
	-m 2G \
	-nographic \
	-device virtio-net-device,netdev=net \
	-netdev user,id=net,hostfwd=tcp::2222-:22 \
	-bios ./output/qemu-bootloader.elf \
	-drive if=none,format=raw,file=./output/sdcard.img,id=sdcard \
	-device virtio-blk-device,drive=sdcard
