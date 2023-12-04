#!/bin/sh
cd opensbi
make CROSS_COMPILE=riscv64-unknown-linux-gnu- PLATFORM=generic FW_PIC=y -j$(nproc)
cd ..

cd u-boot-d1-wip
make CROSS_COMPILE=riscv64-unknown-linux-gnu- nezha_defconfig
make CROSS_COMPILE=riscv64-unknown-linux-gnu- OPENSBI=../opensbi/build/platform/generic/firmware/fw_dynamic.bin -j$(nproc)
cp ./u-boot-sunxi-with-spl.bin ../img/bootloader.bin
cd ..

cd linux-d1_all
make CROSS_COMPILE=riscv64-unknown-linux-gnu- ARCH=riscv defconfig
make CROSS_COMPILE=riscv64-unknown-linux-gnu- ARCH=riscv -j$(nproc)

cp ./arch/riscv/boot/Image ../img/linux
cd ..
