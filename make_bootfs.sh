#!/bin/sh

# Parse args
if [ "$1" == "qemu" ]; then
    PREF="qemu"
    BOOTDEV="virtio"
    MKIMAGE=./deps/u-boot/tools/mkimage
    APPEND="earlycon=sbi console=ttyS0,115200n8 init=/init"
else
    PREF="board"
    BOOTDEV="mmc"
    MKIMAGE=./deps/u-boot-d1-wip/tools/mkimage
    APPEND="earlycon=sbi console=ttyS0,115200n8 ignore_loglevel init=/init"
fi

mkdir -p ./output/${PREF}-initfs

# Make initfs
rm -rf ./output/${PREF}-initfs
mkdir -p ./output/${PREF}-initfs/{tmp,dev,home,mnt,proc,root,sys,usr/{bin,sbin,lib},var}
chmod a+rwxt ./output/${PREF}-initfs/tmp
ln -s usr/{bin,sbin,lib} ./output/${PREF}-initfs

pushd deps/toybox
PREFIX=../../output/${PREF}-initfs make install
popd

rm ./output/${PREF}-modules/build 2>/dev/null
rm ./output/${PREF}-modules/source 2>/dev/null

# Alternatively append gzip - TODO: What is the difference?
mkdir -p ./output/${PREF}-initfs/lib/modules
cp -r ./output/${PREF}-modules/lib/modules ./output/${PREF}-initfs/lib/modules

cat <<'EOF' > ./output/${PREF}-initfs/init
#!/bin/sh

export HOME=/home PATH=/bin:/sbin

mount -t devtmpfs dev dev

# TODO: Unclear - why?
! 2>/dev/null <0 && exec 0<>/dev/console 1>&0 2>&1
for i in ,fd /0,stdin /1,stdout /2,stderr; do 
    ln -sf /proc/self/fd${i/,*/} dev/${i/*,/};
done

mkdir -p dev/pts && mount -t devpts dev/pts dev/pts
mount -t proc proc proc
mount -t sysfs sys sys

root=$(blkid | grep "LABEL=\"root\"" | sed -e 's/^\(.*\):.*$/\1/')
echo "Root at: $root"

if [ -e "$root" ]; then
    mount $root /mnt

    cd /mnt
    mount --rbind /dev dev
    mount -t proc /proc proc
    mount --rbind /sys sys
    chroot . oneit ./init

else
    echo "Could not find root"
    /bin/sh
fi

EOF
chmod +x ./output/${PREF}-initfs/init

# Assemble initfs
TMP=`mktemp -d`
cp -r ./output/${PREF}-initfs/* $TMP

TARGET=$(pwd)/output/${PREF}-initramfs.cpio.gz
pushd $TMP
find . | cpio -o -H newc -R root:root | gzip > $TARGET
popd
rm -rf $TMP

# Boot script
rm ./output/${PREF}-boot.cmd
if [ "${PREF}" = "board" ]; then
cat <<EOT >> ./output/${PREF}-boot.cmd
# Prevent overlapping load of ramdisk and kernel
setenv ramdisk_addr_r 0x48000000  # default 0x41C00000
setenv kernel_addr_r  0x41000000
EOT
fi

cat <<EOT >> ./output/${PREF}-boot.cmd
printenv
fatload ${BOOTDEV} 0:1 \${kernel_addr_r} linux
fatload ${BOOTDEV} 0:1 \${ramdisk_addr_r} u-initrd
setenv bootargs "${APPEND}"
booti \${kernel_addr_r} \${ramdisk_addr_r} \${fdtcontroladdr}
EOT

# Assemble bootfs
rm -rf ./output/${PREF}-bootfs
mkdir -p ./output/${PREF}-bootfs
${MKIMAGE} -A riscv -O linux -T script -C none -d ./output/${PREF}-boot.cmd ./output/${PREF}-bootfs/boot.scr
${MKIMAGE} -A riscv -O linux -T ramdisk -d ./output/${PREF}-initramfs.cpio.gz ./output/${PREF}-bootfs/u-initrd
cp ./output/${PREF}-linux ./output/${PREF}-bootfs/linux

