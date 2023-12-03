#!/bin/sh
card=/dev/loop0
cardboot=${card}p1
cardroot=${card}p2

uboot=./bootloader.bin
linux=./Image

# 1. Create image
read -p "Creating image - press enter to continue"
[ -f "./output.img" ] && rm ./output.img
dd if=/dev/zero of=./output.img bs=1M count=256
losetup -P ${card} ./output.img

# 2. Write bootloader
echo ""
echo "**********"
read -p "Writing bootloader - press enter to continue"
dd if=${uboot} of=${card} bs=1024 seek=8

# 3. Create boot and root partitions
echo ""
echo "**********"
read -p "Creating partitions - press enter to continue"
blockdev --rereadpt ${card}
cat <<EOT | sfdisk ${card}
1M,32M,c
,,L
EOT

# # 4. Format partitions
echo ""
echo "**********"
read -p "Formatting partitions - press enter to continue"
mkfs.vfat ${cardboot}
mkfs.ext4 ${cardroot}

sleep 1
partuuidroot=$(lsblk -no UUID ${cardroot})
echo "Root partition has UUID ${partuuidroot}"

# 5. Write boot partition
echo ""
echo "**********"
read -p "Writing boot partition - press enter to continue"
mkdir -p ./mnt
mount ${cardboot} ./mnt/
cp ${linux} ./mnt/$(basename ${linux})
mkdir -p ./mnt/extlinux
cat <<EOT >> ./mnt/extlinux/extlinux.conf
label default
    linux /$(basename ${linux})
    append root=PARTUUID=${partuuidroot} console=ttyS0 earlycon=sbi init=/sbin/main
EOT
umount ./mnt/

# 6. Write root partition
echo ""
echo "**********"
read -p "Writing root partition - press enter to continue"
mkdir -p ./mnt
mount ${cardroot} ./mnt/
mkdir -p ./mnt/sbin
chmod a+rwxt ./mnt/sbin
cp ../main/main ./mnt/sbin/main
chmod +x ./mnt/sbin/main
chown -R root ./mnt/sbin
umount ./mnt/


# 7. Free everything
echo ""
echo "**********"
read -p "Freeing loopback - press enter to continue"
losetup -d ${card}
