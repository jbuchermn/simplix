{ nixpkgs, system }:
let
  arch = "arm";
  cpu = "armv7l";
  libc = "gnueabihf";
  config = "${cpu}-unknown-linux-${libc}";
  pkgs = import nixpkgs {
    inherit system;
  };
  pkgs-cross = import nixpkgs {
    inherit system;
    crossSystem = {
      inherit config;
    };
  };
in
rec
{
  ###################################################################
  inherit arch config pkgs-cross;
  boardname = "bpi-m2zero";

  ###################################################################
  bootloader = pkgs.stdenv.mkDerivation
    {
      depsBuildBuild = with pkgs-cross; [
        stdenv.cc
      ];

      nativeBuildInputs = with pkgs; [
        stdenv.cc
        bison
        flex
        bc
        swig
        dtc
        openssl
        (python3.withPackages (ps: with ps; [
          setuptools
        ]))
      ];

      name = "arm-bpi-m2zero-bootloader";
      srcs = [
        (pkgs.fetchgit
          {
            url = "https://github.com/u-boot/u-boot";
            rev = "v2023.10";
            hash = "sha256-f0xDGxTatRtCxwuDnmsqFLtYLIyjA5xzyQcwfOy3zEM=";
          })
      ];

      sourceRoot = ".";

      phases = [ "unpackPhase" "patchPhase" "buildPhase" "installPhase" ];

      postPatch = ''
        patchShebangs ./u-boot/scripts
        patchShebangs ./u-boot/tools
      '';

      buildPhase = ''
        export ARCH=${arch}
        export CROSS_TARGET=${config}
        export CROSS_COMPILE=${config}-

        pushd u-boot
        make bananapi_m2_zero_defconfig
        make -j$(nproc)
        popd

        ls -al u-boot
      '';

      installPhase = ''
        mkdir -p $out
        cp ./u-boot/u-boot-sunxi-with-spl.bin $out/bootloader.bin

        cat <<'EOT' > $out/make.sh
        function flash_bootloader(){
          dd if=$self_dir/bootloader.bin of=$1 bs=512 seek=16
        }
        EOT
      '';
    };

  ###################################################################
  linux =
    pkgs.stdenv.mkDerivation
      rec {
        name = "arm-bpi-m2zero-linux";
        kernel-release = "6.6.8";

        depsBuildBuild = with pkgs-cross; [
          stdenv.cc
        ];

        nativeBuildInputs = with pkgs; [
          flex
          bison
          bc
          openssl
          perl
          kmod

          # breakpointHook
        ];

        srcs = [
          (pkgs.fetchurl
            {
              url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${kernel-release}.tar.xz";
              hash = "sha256-UDbENOEeSzbY2j9ImFH3+CnPeF+n94h0aFN6nqRXJBY=";
            })

          ./${kernel-release}.config
          ./brcmfmac43430-sdio.bin
          ./brcmfmac43430-sdio.clm_blob
          ./brcmfmac43430-sdio.AP6212.txt
        ];

        phases = [ "unpackPhase" "patchPhase" "configurePhase" "buildPhase" "installPhase" ];

        sourceRoot = ".";
        preUnpack = ''
          unpackCmdHooks+=(_try)
          _try() {
            if [[ "$1" =~ \.tar.xz$ ]]; then return 1; fi
            cp "$1" ./$(stripHash "$1")
          }
        '';

        postPatch = ''
          patchShebangs ./linux*/scripts
        '';

        configurePhase = ''
          export ARCH=${arch}
          export CROSS_COMPILE=${config}-

          pushd linux*
          cp ../${kernel-release}.config ./.config
          popd
        '';

        buildPhase = ''
          mkdir -p ./mod_root
          pushd linux*
          make -j$(nproc) zImage modules dtbs
          make -j$(nproc) INSTALL_MOD_PATH=../mod_root modules_install
          popd
        '';

        installPhase = ''
          mkdir -p $out/modules
          mkdir -p $out/firmware/brcm

          pushd linux*
          cp ./arch/$ARCH/boot/zImage $out/zImage
          cp -r ./arch/$ARCH/boot/dts $out/dts
          cp -r ../mod_root/lib/modules/* $out/modules
          popd

          cp ./brcmfmac43430-sdio.bin $out/firmware/brcm/brcmfmac43430-sdio.bin
          cp ./brcmfmac43430-sdio.clm_blob $out/firmware/brcm/brcmfmac43430-sdio.clm_blob
          cp ./brcmfmac43430-sdio.AP6212.txt $out/firmware/brcm/brcmfmac43430-sdio.sinovoip,bpi-m2-zero.txt
        '';
      };

  ###################################################################
  env = ''
    # TODO: SIMPLIX_STATUS_GPIO
  '';

  init = ''
    modprobe brcmfmac

    # Wait for wifi devices to show up
    echo "Waiting for wifi device"
    until ls /sys/class/ieee80211/*/device/net/ 2>/dev/null; do
      echo "."
      sleep 1
    done
  '';

  ###################################################################
  bootfs = initfs: pkgs.stdenv.mkDerivation
    {
      name = "arm-bpi-m2zero-bootfs";

      nativeBuildInputs = with pkgs; [
        ubootTools
      ];

      phases = [ "installPhase" ];

      installPhase = ''
        BOOT=$out/bootfs
        mkdir -p $BOOT

        cat <<'EOT' >> $out/boot.cmd
        echo "*************** Begin boot script ***************"
        printenv
        fatload mmc 0:1 ''${kernel_addr_r} z-linux
        fatload mmc 0:1 ''${ramdisk_addr_r} u-initrd
        setenv bootargs "console=ttyS0,115200 earlyprintk=serial init=/init"
        echo "***************  End boot script  ***************"
        echo "bootz..."
        bootz ''${kernel_addr_r} ''${ramdisk_addr_r} ''${fdtcontroladdr}
        EOT

        mkimage -A ${arch} -O linux -T script -C none -d $out/boot.cmd $BOOT/boot.scr

        cp ${linux}/zImage $BOOT/z-linux
        mkimage -A ${arch} -O linux -T ramdisk -d ${initfs}/initramfs.cpio.gz $BOOT/u-initrd
      '';
    };
}
