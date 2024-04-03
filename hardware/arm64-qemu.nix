{ nixpkgs, system }:
let
  arch = "arm64";
  cpu = "aarch64";
  libc = "gnu";
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
  boardname = "qemu";

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

      name = "arm64-qemu-bootloader";
      srcs =
        (pkgs.fetchgit
          {
            url = "https://github.com/u-boot/u-boot";
            rev = "v2023.10";
            hash = "sha256-f0xDGxTatRtCxwuDnmsqFLtYLIyjA5xzyQcwfOy3zEM=";
          });

      phases = [ "unpackPhase" "patchPhase" "buildPhase" "installPhase" ];

      buildPhase = ''
        export ARCH=${arch}
        export CROSS_TARGET=${config}
        export CROSS_COMPILE=${config}-

        make qemu_arm64_defconfig
        make -j$(nproc)
      '';

      installPhase = ''
        mkdir -p $out
        cp ./u-boot.bin $out/bootloader.bin

        cat <<'EOT' > $out/make.sh
        function flash_bootloader(){
          echo "No need to flash bootloader on qemu, placing start script in qemu.sh..."
          if [ -e "./qemu.sh" ]; then
            rm ./qemu.sh
          fi
        cat <<EOF > ./qemu.sh
          #!/bin/sh
          qemu-system-aarch64 \\
            -machine virt \\
            -cpu cortex-a57 \\
            -m 2G \\
            -nographic \\
            -device virtio-net-device,netdev=net \\
            -netdev user,id=net,hostfwd=tcp::2222-:22 \\
            -bios $self_dir/bootloader.bin \\
            -drive if=none,format=raw,file=\$1,id=sdcard \\
            -device virtio-blk-device,drive=sdcard
        EOF
        chmod +x ./qemu.sh
        }
        EOT
      '';
    };

  ###################################################################
  linux =
    pkgs.stdenv.mkDerivation
      rec {
        name = "arm64-qemu-linux";
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

          ./arm64-qemu-${kernel-release}.config
        ];

        phases = [ "unpackPhase" "patchPhase" "configurePhase" "buildPhase" "installPhase" ];

        sourceRoot = ".";
        preUnpack = ''
          unpackCmdHooks+=(_tryConfigFile)
          _tryConfigFile() {
            if ! [[ "$1" =~ \.config$ ]]; then return 1; fi
            cp "$1" ./
          }
        '';

        postPatch = ''
          patchShebangs ./linux*/scripts
        '';

        configurePhase = ''
          export ARCH=${arch}
          export CROSS_COMPILE=${config}-

          pushd linux*
          cp ../*.config ./.config
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

          pushd linux*
          cp ./arch/$ARCH/boot/zImage $out/zImage
          cp -r ./arch/$ARCH/boot/dts $out/dts
          cp -r ../mod_root/lib/modules/* $out/modules
          popd
        '';
      };

  ###################################################################
  bootfs = initfs: pkgs.stdenv.mkDerivation
    {
      name = "arm64-qemu-bootfs";

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
        fatload virtio 0:1 ''${kernel_addr_r} linux
        fatload virtio 0:1 ''${ramdisk_addr_r} u-initrd
        setenv bootargs "console=ttyAMA0 debug earlyprintk=serial init=/init"
        echo "***************  End boot script  ***************"
        booti ''${kernel_addr_r} ''${ramdisk_addr_r} ''${fdtcontroladdr}
        EOT

        cp ${linux}/Image $BOOT/linux
        mkimage -A ${arch} -O linux -T script -C none -d $out/boot.cmd $BOOT/boot.scr
        mkimage -A ${arch} -O linux -T ramdisk -d ${initfs}/initramfs.cpio.gz $BOOT/u-initrd
      '';
    };
}
