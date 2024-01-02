{ nixpkgs, system }:
let
  arch = "riscv";
  cpu = "riscv64";
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

      name = "bootloader-riscv-qemu";
      srcs = [
        (pkgs.fetchgit
          {
            url = "https://github.com/riscv-software-src/opensbi";
            rev = "v1.3.1";
            hash = "sha256-JNkPvmKYd5xbGB2lsZKWrpI6rBIckWbkLYu98bw7+QY=";
          })

        (pkgs.fetchgit
          {
            url = "https://github.com/u-boot/u-boot";
            rev = "v2023.10";
            hash = "sha256-f0xDGxTatRtCxwuDnmsqFLtYLIyjA5xzyQcwfOy3zEM=";
          })
      ];

      phases = [ "unpackPhase" "patchPhase" "buildPhase" "installPhase" ];

      sourceRoot = ".";

      postPatch = ''
        patchShebangs ./opensbi/scripts
      '';

      buildPhase = ''
        export ARCH=${arch}
        export CROSS_TARGET=${config}
        export CROSS_COMPILE=${config}-

        pushd u-boot
        make qemu-riscv64_smode_defconfig
        make -j$(nproc)
        popd

        pushd opensbi
        make PLATFORM=generic FW_PAYLOAD_PATH=../u-boot/u-boot.bin -j$(nproc)
        popd
      '';

      installPhase = ''
        mkdir -p $out
        cp ./opensbi/build/platform/generic/firmware/fw_payload.elf $out/bootloader.elf

        cat <<'EOT' > $out/make.sh
        function flash_bootloader(){
          echo "No need to flash bootloader on qemu, placing start script in qemu.sh..."
          if [ -e "./qemu.sh" ]; then
            rm ./qemu.sh
          fi
        cat <<EOF > ./qemu.sh
          #!/bin/sh
          qemu-system-riscv64 \\
            -machine virt \\
            -m 2G \\
            -nographic \\
            -device virtio-net-device,netdev=net \\
            -netdev user,id=net,hostfwd=tcp::2222-:22 \\
            -bios $self_dir/bootloader.elf \\
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
        name = "riscv-qemu-linux";
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

          ./riscv-qemu-${kernel-release}.config
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
          pushd linux*
          make -j$(nproc)
          popd
        '';

        installPhase = ''
          mkdir -p $out/modules

          pushd linux*
          cp ./arch/$ARCH/boot/Image $out/Image
          make -j$(nproc) INSTALL_MOD_PATH=$out/modules modules_install
          popd
        '';
      };

  ###################################################################
  bootfs = initfs: pkgs.stdenv.mkDerivation
    {
      name = "bootfs";

      nativeBuildInputs = with pkgs; [
        ubootTools
      ];

      phases = [ "installPhase" ];

      installPhase = ''
        BOOT=$out/bootfs
        mkdir -p $BOOT

        cat <<'EOT' >> $out/boot.cmd
        printenv
        fatload virtio 0:1 ''${kernel_addr_r} linux
        fatload virtio 0:1 ''${ramdisk_addr_r} u-initrd
        setenv bootargs "earlycon=sbi console=ttyS0,115200n8 init=/init"
        booti ''${kernel_addr_r} ''${ramdisk_addr_r} ''${fdtcontroladdr}
        EOT

        cp ${linux}/Image $BOOT/linux
        mkimage -A ${arch} -O linux -T script -C none -d $out/boot.cmd $BOOT/boot.scr
        mkimage -A ${arch} -O linux -T ramdisk -d ${initfs}/initramfs.cpio.gz $BOOT/u-initrd
      '';
    };
}
