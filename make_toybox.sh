#!/bin/sh
find ./toybox -type f -exec sed -i 's/#\!\/bin\/bash/#\!\/usr\/bin\/env bash/g' {} +

LDFLAGS="--static"
CC=gcc

KCONFIG=""
for i in sh route modprobe dhcp ip vi expr; do KCONFIG="$KCONFIG"$'\n'CONFIG_${i^^?}=y; done

echo "Building toybox with LDFLAGS=$LDFLAGS CROSS_COMPILE=$CROSS_COMPILE CC=$CC KCONFIG_ALLCONFIG=$KCONFIG"

cd deps/toybox
make defconfig KCONFIG_ALLCONFIG=<(echo "$KCONFIG") LDFLAGS=$LDFLAGS CC=$CC
make LDFLAGS=$LDFLAGS CC=$CC
