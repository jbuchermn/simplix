#!/bin/sh
KCONFIG_ALLCONFIG=""
for i in sh; do KCONFIG_ALLCONFIG="$KCONFIG_ALLCONFIG"$'\n'CONFIG_${i^^?}=y; done

sudo ln -s $(which bash) /bin/bash

cd toybox
make LDFLAGS="--static" CROSS_COMPILE="riscv64-unknown-linux-gnu-" defconfig KCONFIG_ALLCONFIG=<(echo $KCONFIG_ALLCONFIG)
make LDFLAGS="--static" CROSS_COMPILE="riscv64-unknown-linux-gnu-"

sudo rm /bin/bash
