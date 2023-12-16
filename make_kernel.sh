#!/bin/sh
pushd deps/linux
if [ "$1" = "initial" ]; then
	make ARCH=riscv defconfig
fi

##### State
# WiFi: rtl8723ds driver
#   - should be handled by rtw88 in the future (>= 6.7)
# GPIO:
# Speaker:
# MIC:
# MIC Array:
# HDMI:
# Video Engine:
# Dispay Engine:
# Deinterlacer:
# DSP HiFi4:
# G2D:
# Thermal sensor:
# [...]

# Common config
./scripts/config --enable SERIAL_EARLYCON_RISCV_SBI
./scripts/config --enable SWAP


if [ "$1" = "qemu" -o "$2" = "qemu" ]; then
	# qemu config

	# build and install
	make ARCH=riscv -j$(nproc)
	cp ./arch/riscv/boot/Image ../../output/qemu-linux

	mkdir -p ../../output/qemu-modules
	make ARCH=riscv -j$(nproc) INSTALL_MOD_PATH=../../output/qemu-modules modules_install
	popd
else
	# board config
	# See https://github.com/sehraf/d1-riscv-arch-image-builder/blob/main/1_compile.sh
	./scripts/config --enable CFG80211
	./scripts/config --enable MAC80211
	# RTL8723DS??
	# https://github.com/lwfinger/rtw88

	./scripts/config --enable MEDIA_SUPPORT
	./scripts/config --enable MEDIA_CONTROLLER
	./scripts/config --enable MEDIA_CONTROLLER_REQUEST_API
	./scripts/config --enable V4L_MEM2MEM_DRIVERS
	./scripts/config --enable VIDEO_SUNXI_CEDRUS

	# build and install
	make ARCH=riscv -j$(nproc)
	cp ./arch/riscv/boot/Image ../../output/board-linux

	mkdir -p ../../output/board-modules
	make ARCH=riscv -j$(nproc) INSTALL_MOD_PATH=../../output/board-modules modules_install
	popd

	# rtl8723
	pushd ./deps/rtl8723ds
	make ARCH=riscv KSRC=../linux -j$(nproc)
	KERNEL_RELEASE=6.6.0
	install -D -p -m 644 ./8723ds.ko ../../output/board-modules/lib/modules/${KERNEL_RELEASE}/kernel/drivers/net/wireless/8723ds.ko
	popd

	depmod -a -b ./output/board-modules ${KERNEL_RELEASE}
fi

