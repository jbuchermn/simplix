#!/bin/sh
echo ""
echo "**********"
echo "Setting up rootfs"

mkdir -p ./output/rootfs

######## Setup dirs
mkdir -p ./output/rootfs/{usr/{bin,sbin,lib,include,libexec},dev,proc,sys,tmp,home,var}
chmod a+rwxt ./output/rootfs/tmp
ln -s usr/{bin,sbin,lib} ./output/rootfs

######## Kernel modules
mkdir -p ./output/rootfs/lib/modules
cp -r ./output/qemu-modules/lib/* ./output/rootfs/lib/
cp -r ./output/board-modules/lib/* ./output/rootfs/lib/

######## Cross-compiled binaries
mkdir -p ./output/rootfs/nix/store
for i in $(nix path-info --recursive $TARGET_ROOT); do
	cp -r $i ./output/rootfs/nix/store/
done
sudo chown -R $(whoami) ./output/rootfs/nix
sudo chmod -R u+w ./output/rootfs/nix

# TODO! Setup shell
pushd ./output/rootfs/usr/bin && ln -s ${CC_SHELL} sh; popd


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
cat <<EOT > ./output/rootfs/sbin/init
#!/bin/sh
echo "Starting up..."

source ${TARGET_ROOT}/env.sh
export PATH=\$PATH:\$CC_PATH

echo "Path is \$PATH..."
echo "Bash..."
/bin/sh

EOT
chmod +x ./output/rootfs/sbin/init

