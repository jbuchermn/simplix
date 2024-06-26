# Provided code inserted here

img_path=/tmp/output.img
blk_dev=/dev/null
part_boot=/dev/null
part_root=/dev/null
mount_dir=$(mktemp -d)

self=$(readlink -f "$0")
self_dir=$(dirname "$self")

function setup_img(){
  echo ""
  echo "**********"
  echo "Setting up loopback..."

  img_path=$1
  blk_dev=/dev/loop0
  part_boot=/dev/loop0p1
  part_root=/dev/loop0p2

  if  losetup -l | grep -q $blk_dev; then
    echo "Already set up"
  else
  [ -f "$img_path" ] && rm $img_path
  dd if=/dev/zero of=$img_path bs=1M count=1024
    losetup -P $blk_dev $img_path
  fi
}

function setup_blk(){
  blk_dev=$1
  part_boot="$(echo $1)1"
  part_root="$(echo $1)2"

  if [ ! -e "$blk_dev" ]; then
    echo "Could not find $blk_dev..."
    exit 1
  fi

  read -p "Using $blk_dev - press enter to continue"
}

function format(){
  echo ""
  echo "**********"
  echo "Creating partitions..."
  blockdev --rereadpt $blk_dev
cat <<EOF |  sfdisk $blk_dev || exit 1
1M,128M,c
,,L
EOF

  echo ""
  echo "**********"
  echo "Formatting partitions..."
  mkfs.vfat $part_boot
  mkfs.ext4 -L root $part_root

  echo ""
  echo "**********"
  echo "Mounting partitions"
  mkdir -p $mount_dir/bootfs
  mkdir -p $mount_dir/rootfs
  mount $part_boot $mount_dir/bootfs
  mount $part_root $mount_dir/rootfs
}

function cleanup(){
  echo ""
  echo "**********"
  echo "Cleaning up..."
  losetup -d $blk_dev 2>/dev/null

  umount $mount_dir/bootfs 2>/dev/null
  umount $mount_dir/rootfs 2>/dev/null
  rm -rf $mount_dir
}

function write_bootfs(){
  echo ""
  echo "**********"
  echo "Copying bootfs"

  rm -rf $mount_dir/bootfs/*
  cp $self_dir/bootfs/* $mount_dir/bootfs
  chown -R root $mount_dir/bootfs
}

function write_rootfs(){
  echo ""
  echo "**********"
  echo "Copying rootfs"

  pushd $self_dir/rootfs
  for i in ./*; do
    cp -r $i $mount_dir/rootfs/$i
    chown -R root $mount_dir/rootfs/$i
  done
  popd
}

function make_home() {
  h="$1"
  if [ -z "$h" ]; then
    h="./home"
  fi

  if [ -d "$h" ]; then
    echo "Copying home from $h..."
    mkdir -p $mount_dir/rootfs/home
    cp -r $h/* $mount_dir/rootfs/home/ 2>/dev/null
    sudo chown -R root $mount_dir/rootfs/home
  fi
}

if [ -z "$2" ]; then
  echo "Usage: make.sh <target> <user> [<home>]. Run as root"
  echo "Target can be /dev/sd... or ../../result.img"
  echo "Home defaults to ./home"
  exit 1
fi
if [ "$(id -u)" -ne 0 ]; then echo "Please run as root." >&2; exit 1; fi

case $1 in
  /dev/sd*)
    setup_blk $1
    ;;
  *)
    setup_img $1
    ;;
esac

format
write_bootfs
write_rootfs
make_home "$3"

# Provided by rootfs
make_store "$mount_dir/rootfs"
make_secrets "$mount_dir/rootfs" "$2"

# Provided by bootloader
flash_bootloader "$blk_dev"

cleanup

case $1 in
  /dev/sd*)
    ;;
  *)
    chown $2 $1
    ;;
esac

