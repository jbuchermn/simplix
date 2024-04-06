{ nixpkgs, system }:
let
  arch = "arm";
  cpu = "armv6l";
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
  boardname = "rpi-zero-w";

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

      name = "arm-${boardname}-bootloader";
      srcs = [
        (pkgs.fetchgit
          {
            url = "https://github.com/u-boot/u-boot";
            rev = "v2023.10";
            hash = "sha256-f0xDGxTatRtCxwuDnmsqFLtYLIyjA5xzyQcwfOy3zEM=";
          })

        (pkgs.fetchurl
          {
            url = "https://github.com/raspberrypi/firmware/raw/master/boot/bootcode.bin";
            sha256 = "sha256-r2A+vZfntpLDAZVWP3slZW6wXVeDjPGnFeu0cNFhTOQ=";
          })

        (pkgs.fetchurl
          {
            url = "https://github.com/raspberrypi/firmware/raw/master/boot/fixup.dat";
            sha256 = "sha256-ysdS/FaEXutey8ZwjGeWadgHBjrCKIFzBUcUCBLTuwQ=";
          })

        (pkgs.fetchurl
          {
            url = "https://github.com/raspberrypi/firmware/raw/master/boot/start.elf";
            sha256 = "sha256-flmTUxUdm+JZHcqBrRDeaYD+zMbix/ho1olFQAr2z00=";
          })
      ];

      sourceRoot = ".";

      phases = [ "unpackPhase" "patchPhase" "buildPhase" "installPhase" ];

      preUnpack = ''
        unpackCmdHooks+=(_tryBinDatElfFile)
        _tryBinDatElfFile() {
          if ! [[ "$1" =~ \.bin$ ]] && ! [[ "$1" =~ \.dat$ ]] && ! [[ "$1" =~ \.elf$ ]]; then return 1; fi
          mkdir -p firmware
          cp "$1" ./firmware/$(stripHash "$1")
        }
      '';

      postPatch = ''
        patchShebangs ./u-boot/scripts
        patchShebangs ./u-boot/tools
      '';

      buildPhase = ''
        export ARCH=${arch}
        export CROSS_TARGET=${config}
        export CROSS_COMPILE=${config}-

        pushd u-boot
        make rpi_0_w_defconfig
        make -j$(nproc)
        popd
      '';

      installPhase = ''
        mkdir -p $out

        cp ./u-boot/u-boot.bin $out/
        cp -r ./firmware $out/firmware

        cat <<'EOT' > $out/make.sh
        function flash_bootloader(){
          echo "Not flashing bootloader on RPi, copying u-boot with kernel"
        }
        EOT
      '';
    };

  ###################################################################
  linux =
    pkgs.stdenv.mkDerivation
      rec {
        name = "arm-${boardname}-linux";
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
          ./brcmfmac43430-sdio.txt
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

          cp ./brcmfmac43430-sdio.bin $out/firmware/brcm/
          cp ./brcmfmac43430-sdio.clm_blob $out/firmware/brcm/
          cp ./brcmfmac43430-sdio.txt $out/firmware/brcm/brcmfmac43430-sdio.raspberrypi,model-zero-w.txt
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
      name = "arm-${boardname}-bootfs";

      nativeBuildInputs = with pkgs; [
        ubootTools
      ];

      phases = [ "installPhase" ];

      installPhase = ''
        BOOT=$out/bootfs
        mkdir -p $BOOT

        cp ${bootloader}/firmware/* $BOOT/
        cp ${linux}/dts/broadcom/bcm2835-rpi-zero-w.dtb $BOOT/

        cat <<'EOT' >> $BOOT/config.txt
        enable_uart=1
        kernel=u-boot.bin
        EOT

        cp ${bootloader}/u-boot.bin $BOOT/

        cat <<'EOT' >> $out/boot.cmd
        echo "*************** Begin boot script ***************"
        printenv
        fatload mmc 0:1 ''${loadaddr} z-linux
        fatload mmc 0:1 ''${fdt_addr_r} ''${fdtfile}
        fatload mmc 0:1 ''${ramdisk_addr_r} u-initrd
        setenv bootargs 8250.nr_uarts=1 console=ttyS0,115200
        echo "***************  End boot script  ***************"
        echo "bootz..."
        bootz ''${loadaddr} ''${ramdisk_addr_r} ''${fdt_addr_r}
        EOT

        mkimage -A ${arch} -O linux -T script -C none -d $out/boot.cmd $BOOT/boot.scr

        cp ${linux}/zImage $BOOT/z-linux
        mkimage -A ${arch} -O linux -T ramdisk -d ${initfs}/initramfs.cpio.gz $BOOT/u-initrd
      '';
    };
}
