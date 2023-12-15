#!/bin/sh

mkdir -p ./output/rootfs

# Setup dirs
mkdir -p ./output/rootfs/{usr/{bin,sbin,lib,include,libexec},dev,proc,sys,tmp,home,var}
chmod a+rwxt ./output/rootfs/tmp
ln -s usr/{bin,sbin,lib} ./output/rootfs

# Toybox
pushd deps/toybox
PREFIX=../../output/rootfs make install
popd

# Crossnative toolchain - TODO: playground
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/bin/* ./output/rootfs/usr/bin
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/lib/* ./output/rootfs/usr/lib
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/libexec/* ./output/rootfs/usr/libexec
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/riscv64-unknown-linux-musl/bin/* ./output/rootfs/usr/bin
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/riscv64-unknown-linux-musl/sysroot/lib/* ./output/rootfs/lib
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/riscv64-unknown-linux-musl/sysroot/usr/lib/* ./output/rootfs/usr/lib
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/riscv64-unknown-linux-musl/sysroot/usr/include/* ./output/rootfs/usr/include
pushd  ./output/rootfs/usr/lib/
rm ld-musl-riscv64.so.1
ln -s libc.so ld-musl-riscv64.so.1
popd

cat <<EOT > ./output/rootfs/home/main.c
#include <stdio.h>

int main(){
    printf("Hello, world!\n");
    return 0;
}

EOT

cat <<EOT > ./output/rootfs/home/compile.sh
#!/bin/sh
riscv64-unknown-linux-musl-gcc --sysroot=/ main.c
EOT
chmod +x ./output/rootfs/home/compile.sh

# Setup root fs
pushd ./output/rootfs
ln -s ./bin/sh ./init
popd

