#!/bin/sh

# Args
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

function setup_initfs() {
	echo ""
	echo "**********"
	echo "Setting up initfs"

	rm -rf ./output/${PREF}-initfs

	# Setup directories
	mkdir -p ./output/${PREF}-initfs/{usr/{bin,sbin,lib},dev,proc,sys,mnt,tmp,home,var}
	chmod a+rwxt ./output/${PREF}-initfs/tmp
	ln -s usr/{bin,sbin,lib} ./output/${PREF}-initfs

	# Install command line (probably toybox)
	cp -av ${SIMPLIX_STATIC_CMDLINE}/* ./output/${PREF}-initfs/bin

	# Install kernel modules
	rm ./output/${PREF}-modules/build 2>/dev/null
	rm ./output/${PREF}-modules/source 2>/dev/null

	cp -r ./output/${PREF}-modules/lib/modules/* ./output/${PREF}-initfs/lib/modules/

	# Write init script
	cat <<-'EOF' > ./output/${PREF}-initfs/init
	#!/bin/sh

	export HOME=/home PATH=/bin:/sbin

	mount -t devtmpfs dev dev

	# TODO: Unclear - why? Has sth to do with controlling terminal?
	! 2>/dev/null <0 && exec 0<>/dev/console 1>&0 2>&1
	for i in ,fd /0,stdin /1,stdout /2,stderr; do 
		ln -sf /proc/self/fd${i/,*/} dev/${i/*,/};
	done

	mkdir -p dev/pts && mount -t devpts dev/pts dev/pts
	mount -t proc proc proc
	mount -t sysfs sys sys

	for i in {1..3}; do
		echo "Looking for root..."
		root=$(blkid | grep "LABEL=\"root\"" | sed -e 's/^\(.*\):.*$/\1/')
		if [ -e "$root" ]; then
			break
		fi
		sleep 5
	done

	if [ -e "$root" ]; then
		echo "Root at: $root"
		mount $root /mnt

		cd /mnt
		mount --rbind /dev dev
		mount -t proc /proc proc
		mount --rbind /sys sys
		chroot . oneit init

	else
		echo "Could not find root"
		/bin/sh
	fi

	EOF
	chmod +x ./output/${PREF}-initfs/init
}


function pack_initfs(){
	echo ""
	echo "**********"
	echo "Packing initfs"

	pushd ./output/${PREF}-initfs
	find . | cpio -o -H newc -R root:root | gzip > ../${PREF}-initramfs.cpio.gz
	popd
}

function setup_bootfs(){
	echo ""
	echo "**********"
	echo "Setting up bootfs"

	rm -rf ./output/${PREF}-bootfs

	# Boot script
	rm ./output/${PREF}-boot.cmd
	if [ "${PREF}" = "board" ]; then
		cat <<-EOT >> ./output/${PREF}-boot.cmd
		# Prevent overlapping load of ramdisk and kernel
		setenv ramdisk_addr_r 0x48000000  # default 0x41C00000
		setenv kernel_addr_r  0x41000000
		EOT
	fi

	cat <<-EOT >> ./output/${PREF}-boot.cmd
	printenv
	fatload ${BOOTDEV} 0:1 \${kernel_addr_r} linux
	fatload ${BOOTDEV} 0:1 \${ramdisk_addr_r} u-initrd
	setenv bootargs "${APPEND}"
	booti \${kernel_addr_r} \${ramdisk_addr_r} \${fdtcontroladdr}
	EOT

	# Assemble kernel, initramfs and boot script
	mkdir -p ./output/${PREF}-bootfs
	cp ./output/${PREF}-linux ./output/${PREF}-bootfs/linux
	${MKIMAGE} -A riscv -O linux -T script -C none -d ./output/${PREF}-boot.cmd ./output/${PREF}-bootfs/boot.scr
	${MKIMAGE} -A riscv -O linux -T ramdisk -d ./output/${PREF}-initramfs.cpio.gz ./output/${PREF}-bootfs/u-initrd
}

setup_initfs
pack_initfs
setup_bootfs
