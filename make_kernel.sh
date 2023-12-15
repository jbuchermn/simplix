#!/bin/sh
pushd deps/linux-d1_all
make ARCH=riscv defconfig
./scripts/config --enable SERIAL_EARLYCON_RISCV_SBI

make ARCH=riscv -j$(nproc)

if [ "$1" == "qemu" ]; then
    cp ./arch/riscv/boot/Image ../../output/qemu-linux

    mkdir -p ../../output/qemu-modules
    make ARCH=riscv -j$(nproc) INSTALL_MOD_PATH=../../output/qemu-modules modules_install
else
    cp ./arch/riscv/boot/Image ../../output/board-linux

    mkdir -p ../../output/board-modules
    make ARCH=riscv -j$(nproc) INSTALL_MOD_PATH=../../output/board-modules modules_install
fi

popd
