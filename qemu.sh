#!/bin/sh
qemu-system-riscv64 \
    -machine virt \
    -m 2G \
    -nographic \
    -bios ./img/bootloader.bin \
    -drive if=none,format=raw,file=./img/output.img,id=sdcard \
    -device virtio-blk-device,drive=sdcard
