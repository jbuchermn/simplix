#!/bin/sh
qemu-system-riscv64 \
    -machine virt \
    -m 512M \
    -nographic \
    -bios ./output/qemu-bootloader.elf \
    -drive if=none,format=raw,file=./output/sdcard.img,id=sdcard \
    -device virtio-blk-device,drive=sdcard
