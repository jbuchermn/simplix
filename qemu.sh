#!/bin/sh
# qemu-system-riscv64 -machine virt -nographic -kernel ./linux-d1_all/arch/riscv/boot/Image -append "root=/dev/vda ro console=ttyS0"
qemu-system-riscv64 \
    -machine virt \
    -m 2G \
    -nographic \
    -bios ./img/bootloader.bin \
    -drive if=none,format=raw,file=./img/output.img,id=sdcard \
    -device virtio-blk-device,drive=sdcard

    # -device sdhci-pci \
    # -device sd-card,drive=sdcard

    # -device ich9-ahci,id=ahci \
    # -device ide-hd,drive=img,bus=ahci.0

