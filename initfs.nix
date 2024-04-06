{ pkgs }:
pkgs-cross:
let
  simplix-toybox = (with pkgs-cross.pkgsStatic; toybox.overrideAttrs (prev: {
    # fortify-headers broken with musl (static toybox appears to always use musl)
    hardeningDisable = [ "all" ];
    configurePhase = ''
      KCONFIG=""
      for i in sh modprobe route dhcp; do KCONFIG="$KCONFIG"$'\n'CONFIG_''${i^^?}=y; done
      make defconfig KCONFIG_ALLCONFIG=<(echo "$KCONFIG")
    '';
  }));
in
pkgs-cross.stdenv.mkDerivation {
  name = "initfs";

  buildInputs = with pkgs-cross; [
    simplix-toybox
  ];

  nativeBuildInputs = with pkgs; [
    cpio
  ];

  phases = [ "installPhase" ];

  installPhase = ''
    ROOT=$out/initfs
    mkdir -p $ROOT

    # Setup directories
    mkdir -p $ROOT/{usr/{bin,sbin,lib},dev,proc,sys,mnt,tmp,home,var}
    chmod a+rwxt $ROOT/tmp
    ln -s usr/{bin,sbin,lib} $ROOT

    # Install command line (probably toybox)
    cp -av ${simplix-toybox}/bin/* $ROOT/bin

    # Write init script
    cat <<-'EOF' > $ROOT/init
    #!/bin/sh
    echo "Starting initfs /init..."

    export HOME=/home PATH=/bin:/sbin

    mount -t devtmpfs dev dev

    # TODO: Unclear - why? Has sth to do with controlling terminal?
    ! 2>/dev/null <0 && exec 0<>/dev/console 1>&0 2>&1
    for i in ,fd /0,stdin /1,stdout /2,stderr; do 
        ln -sf /proc/self/fd''${i/,*/} dev/''${i/*,/};
    done

    # TODO: Add kernel modules?

    mkdir -p dev/pts && mount -t devpts dev/pts dev/pts
    mount -t proc proc proc
    mount -t sysfs sys sys

    echo "Waiting for root..."
    for i in {1..60}; do
        echo "."
        root=$(blkid | grep "LABEL=\"root\"" | sed -e 's/^\(.*\):.*$/\1/')
        if [ -e "$root" ]; then
            break
        fi
        sleep 1
    done

    if [ -e "$root" ]; then
        echo "Root at: $root - handing over"
        mount $root /mnt
        exec switch_root /mnt /sbin/init

    else
        echo "Can't find root - running shell"
        /bin/sh

    fi
    EOF
    chmod +x $ROOT/init

    pushd $ROOT
    find . | cpio -o -H newc -R root:root | gzip > $out/initramfs.cpio.gz
  '';
}










