#!/bin/sh
cd u-boot
make CROSS_COMPILE=riscv64-unknown-linux-gnu- qemu-riscv64_smode_defconfig
make CROSS_COMPILE=riscv64-unknown-linux-gnu- -j$(nproc)

cd ../opensbi
make CROSS_COMPILE=riscv64-unknown-linux-gnu- PLATFORM=generic FW_PAYLOAD_PATH=../u-boot/u-boot.bin -j$(nproc)
cp ./build/platform/generic/firmware/fw_payload.elf ../img/bootloader.bin
cd ..

cd linux-d1_all

make CROSS_COMPILE=riscv64-unknown-linux-gnu- ARCH=riscv defconfig
make CROSS_COMPILE=riscv64-unknown-linux-gnu- ARCH=riscv -j$(nproc)

cp ./arch/riscv/boot/Image ../img/linux
cd ..
