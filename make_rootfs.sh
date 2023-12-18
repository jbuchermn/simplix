#!/bin/sh
echo ""
echo "**********"
echo "Setting up rootfs"

mkdir -p ./output/rootfs

######## Setup dirs
mkdir -p ./output/rootfs/{usr/{bin,sbin,lib,include,libexec},dev,proc,sys,tmp,home,var,etc,run}
chmod a+rwxt ./output/rootfs/tmp
ln -s usr/{bin,sbin,lib} ./output/rootfs

######## Kernel modules
mkdir -p ./output/rootfs/lib/modules
cp -r ./output/qemu-modules/lib/* ./output/rootfs/lib/
cp -r ./output/board-modules/lib/* ./output/rootfs/lib/

######## Cross-compiled binaries
# Always clean nix store
rm -rf ./output/rootfs/nix/store
mkdir -p ./output/rootfs/nix/store
for i in $(nix path-info --recursive $TARGET_ROOT); do
	cp -r $i ./output/rootfs/nix/store/
done
sudo chown -R $(whoami) ./output/rootfs/nix
sudo chmod -R u+w ./output/rootfs/nix

# Setup shell
pushd ./output/rootfs/usr/bin && ln -s ${SIMPLIX_SHELL} sh; popd

######## Init
cat <<EOT > ./output/rootfs/sbin/init
#!/bin/sh
echo "Init..."

source ${TARGET_ROOT}/env.sh
export PATH=\$PATH:\$SIMPLIX_PATH
exec oneit /etc/startup.sh

EOT
chmod +x ./output/rootfs/sbin/init

# TODO
cat <<EOT > ./output/rootfs/etc/startup.sh
#!/bin/sh
echo "Starting up..."

echo "Loading modules..."
modprobe 8723ds

echo "Starting shell..."
/bin/sh

EOT
chmod +x ./output/rootfs/etc/startup.sh
