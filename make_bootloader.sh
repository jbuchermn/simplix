#!/bin/sh
if [ "$1" == "qemu" ]; then

    pushd deps/u-boot
    make qemu-riscv64_smode_defconfig
    make -j$(nproc)
    popd

    pushd deps/opensbi
    make PLATFORM=generic FW_PAYLOAD_PATH=../u-boot/u-boot.bin -j$(nproc)
    cp ./build/platform/generic/firmware/fw_payload.elf ../../output/qemu-bootloader.elf
    popd

else

    pushd deps/opensbi
    make PLATFORM=generic FW_PIC=y -j$(nproc)
    popd

    pushd deps/u-boot-d1-wip
    make lichee_rv_dock_defconfig
    ./scripts/config --disable WATCHDOG
    ./scripts/config --disable WATCHDOG_AUTOSTART
    make OPENSBI=../opensbi/build/platform/generic/firmware/fw_dynamic.bin -j$(nproc)
    cp ./u-boot-sunxi-with-spl.bin ../../output/board-bootloader.bin
    popd

fi
