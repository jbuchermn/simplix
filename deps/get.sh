#!/bin/sh
git clone https://github.com/riscv-software-src/opensbi
git clone https://github.com/u-boot/u-boot
git clone https://github.com/smaeul/u-boot -b d1-wip u-boot-d1-wip

git clone https://github.com/landley/toybox

git clone --depth 1 --single-branch --branch v6.6 https://github.com/torvalds/linux
git clone https://github.com/lwfinger/rtl8723ds
