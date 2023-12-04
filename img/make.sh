#!/bin/sh
CARD=/dev/null
PARTBOOT=/dev/null
PARTROOT=/dev/null

function setup_img(){
    echo ""
    echo "**********"
    echo "Setting up loopback..."

    CARD=/dev/loop0
    PARTBOOT=/dev/loop0p1
    PARTROOT=/dev/loop0p2

    if losetup -l | grep -q ${CARD}; then
        echo "Already st up"
    else
        [ -f "./output.img" ] && rm ./output.img
        dd if=/dev/zero of=./output.img bs=1M count=256
        losetup -P ${CARD} ./output.img
    fi
}

function setup_sdcard(){
    CARD=/dev/sdb
    PARTBOOT=/dev/sdb1
    PARTROOT=/dev/sdb2

    read -p "Using ${CARD} - press enter to continue"
}

function cleanup(){
    echo ""
    echo "**********"
    echo "Cleaning up..."
    losetup -d ${CARD} 2>/dev/null

    umount ./bootfs
    rm -rf ./bootfs
    rm -rf ./initfs
}


UBOOT=./bootloader.bin
LINUX=./linux

function format(){
    echo ""
    echo "**********"
    echo "Writing bootloader..."
    dd if=${UBOOT} of=${CARD} bs=1024 seek=128

    echo ""
    echo "**********"
    echo "Creating partitions..."
    blockdev --rereadpt ${CARD}
    cat <<EOT | sfdisk ${CARD}
1M,32M,c
,,L
EOT

    echo ""
    echo "**********"
    echo "Formatting partitions..."
    mkfs.vfat ${PARTBOOT}
    mkfs.ext4 ${PARTROOT}
}

function setup_initfs(){
    echo ""
    echo "**********"
    echo "Creating initfs"

    mkdir -p ./initfs
    rm -rf ./initfs/*

    cp ../main/main ./initfs/init
}

function setup_boot_partition(){
    echo ""
    echo "**********"
    echo "Writing to boot partition"

    mkdir -p ./bootfs
    mount ${PARTBOOT} ./bootfs

    rm -rf ./bootfs/*

    cp ${LINUX} ./bootfs/linux
    # kernel modules

    cd ./initfs
    chown -R root ./
    find . -printf '%P\n' | cpio -o -H newc -R +0:+0 | gzip > ../bootfs/initramfs.cpio.gz
    cd ..

    mkdir -p ./bootfs/extlinux
    cat <<EOT >> ./bootfs/extlinux/extlinux.conf
label default
    linux /linux
    append earlycon=sbi console=ttyS0,115200n8 rootwait cma=96M init=/init
    initrd /initramfs.cpio.gz
EOT

    chown -R root ./bootfs/*
}

# 6. Write root partition
# echo ""
# echo "**********"
# read -p "Writing root partition - press enter to continue"
# mkdir -p ./mnt
# mount ${cardroot} ./mnt/
# mkdir -p ./mnt/sbin
# chmod a+rwxt ./mnt/sbin
# cp ../main/main ./mnt/sbin/main
# chmod +x ./mnt/sbin/main
# chown -R root ./mnt/sbin
# umount ./mnt/


setup_img
format
setup_initfs
setup_boot_partition
cleanup
