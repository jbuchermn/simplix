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
        [ -f "./output/sdcard.img" ] && rm ./output/sdcard.img
        dd if=/dev/zero of=./output/sdcard.img bs=1M count=512
        losetup -P ${CARD} ./output/sdcard.img
    fi
}

function setup_sdcard(){
    CARD=$1
    PARTBOOT="$(echo $1)1"
    PARTROOT="$(echo $1)2"

    read -p "Using ${CARD} - press enter to continue"
}

function cleanup(){
    echo ""
    echo "**********"
    echo "Cleaning up..."
    losetup -d ${CARD} 2>/dev/null

    umount ./output/mnt/bootfs 2>/dev/null
    umount ./output/mnt/rootfs 2>/dev/null
}

function format(){

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
    mkfs.ext4 -L root ${PARTROOT}

    echo ""
    echo "**********"
    echo "Mounting partitions"
    mkdir -p ./output/mnt/bootfs
    mkdir -p ./output/mnt/rootfs
    mount ${PARTBOOT} ./output/mnt/bootfs
    mount ${PARTROOT} ./output/mnt/rootfs
}

function write_bootloader(){
    echo ""
    echo "**********"
    echo "Writing bootloader..."
    dd if=./output/${PREF}-bootloader.bin of=${CARD} bs=512 seek=16
}

function write_bootfs(){
    echo ""
    echo "**********"
    echo "Copying bootfs"

    rm -rf ./output/mnt/bootfs/*
    cp -r ./output/${PREF}-bootfs/* ./output/mnt/bootfs
    sudo chown -R root ./output/mnt/bootfs/*
}

function write_rootfs(){
    echo ""
    echo "**********"
    echo "Copying rootfs"

    pushd ./output/rootfs
    for i in ./*; do
        cp -r $i ../mnt/rootfs/$i
        sudo chown -R root ../mnt/rootfs/$i
    done
    popd
}


if [ "$1" == "qemu" ]; then
    PREF="qemu"

    setup_img
    format
    write_bootfs
    write_rootfs
    cleanup
else
    PREF="board"
    setup_sdcard "$1"
    format
    write_bootfs
    write_bootloader
    write_rootfs
    cleanup
fi
