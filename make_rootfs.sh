#!/bin/sh
	echo ""
	echo "**********"
	echo "Setting up rootfs"

mkdir -p ./output/rootfs

######## Setup dirs
mkdir -p ./output/rootfs/{usr/{bin,sbin,lib,include,libexec},dev,proc,sys,tmp,home,var}
chmod a+rwxt ./output/rootfs/tmp
ln -s usr/{bin,sbin,lib} ./output/rootfs

######## Toybox
pushd deps/toybox
PREFIX=../../output/rootfs make install
popd

######## Kernel modules
mkdir -p ./output/rootfs/lib/modules
cp -r ./output/qemu-modules/lib/* ./output/rootfs/lib/
cp -r ./output/board-modules/lib/* ./output/rootfs/lib/

######## Toolchain
# gcc executables, with prefix
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/bin/* ./output/rootfs/usr/bin
pushd ./output/rootfs/usr/bin
chmod -R u+w ./
for i in ./riscv64-unknown-linux-musl-*; do
    name=$(echo $i | sed -e 's/riscv64-unknown-linux-musl-//')
    ln -s $i $name
done
popd

# gcc internal libs / headers
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/lib/* ./output/rootfs/usr/lib

# libc and the like
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/riscv64-unknown-linux-musl/sysroot/usr/lib/* ./output/rootfs/usr/lib

# libgcc and the like, some executable, some lib, ld-musl-riscv64 linking to libc
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/riscv64-unknown-linux-musl/sysroot/lib/* ./output/rootfs/usr/lib
chmod -R u+w ./output/rootfs/usr/lib

# Fix ld - libc symlink
pushd  ./output/rootfs/usr/lib/
rm ld-musl-riscv64.so.1
ln -s libc.so ld-musl-riscv64.so.1
popd

# gcc internal executables
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/libexec/* ./output/rootfs/usr/libexec
chmod -R u+w ./output/rootfs/usr/libexec

# includes
cp -r tools/crossnative-toolchain/riscv64-unknown-linux-musl/riscv64-unknown-linux-musl/sysroot/usr/include/* ./output/rootfs/usr/include
chmod -R u+w ./output/rootfs/usr/include


######## Hello world
pushd ./output/rootfs/home
cat <<EOT > ./main.c
#include <stdio.h>

int main(){
	printf("Hello, world!\n");
	return 0;
}

EOT

cat <<EOT > ./compile.sh
#!/bin/sh
gcc --sysroot=/ main.c
EOT
chmod +x ./compile.sh

git clone https://github.com/wkusnierczyk/make
popd

######## Init
pushd ./output/rootfs
ln -s ./bin/sh ./init
popd

