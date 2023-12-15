#!/bin/sh
find ./toybox -type f -exec sed -i 's/#\!\/bin\/bash/#\!\/usr\/bin\/env bash/g' {} +

LDFLAGS="--static"

KCONFIG=""
for i in sh route; do KCONFIG="$KCONFIG"$'\n'CONFIG_${i^^?}=y; done

echo "Building toybox with LDFLAGS=$LDFLAGS CROSS_COMPILE=$CROSS_COMPILE KCONFIG_ALLCONFIG=$KCONFIG"

cd deps/toybox
make defconfig KCONFIG_ALLCONFIG=<(echo "$KCONFIG") LDFLAGS=$LDFLAGS
make LDFLAGS=$LDFLAGS
