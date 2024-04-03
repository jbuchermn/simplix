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
  inherit arch config pkgs-cross;
  boardname = "sipeed-lichee-rv";

  ###################################################################
  bootloader = pkgs.stdenv.mkDerivation
    {
      name = "sipeed-lichee-rv-bootloader";

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

      srcs = [
        (pkgs.fetchgit
          {
            url = "https://github.com/riscv-software-src/opensbi";
            rev = "v1.3.1";
            hash = "sha256-JNkPvmKYd5xbGB2lsZKWrpI6rBIckWbkLYu98bw7+QY=";
          })

        (pkgs.fetchgit
          {
            url = "https://github.com/smaeul/u-boot";
            rev = "2e89b706f5c956a70c989cd31665f1429e9a0b48";
            hash = "sha256-POjP3PPuluYNTWWo5EUFWT0K3zYFWBFviPOGIhnejCA=";
          })
      ];

      phases = [ "unpackPhase" "patchPhase" "buildPhase" "installPhase" ];

      sourceRoot = ".";

      postPatch = ''
        patchShebangs ./opensbi/scripts
        patchShebangs ./u-boot*/scripts
        patchShebangs ./u-boot*/tools/*
      '';

      buildPhase = ''
        export ARCH=${arch}
        export CROSS_TARGET=${config}
        export CROSS_COMPILE=${config}-

        pushd opensbi
        make PLATFORM=generic FW_PIC=y -j$(nproc)
        popd

        pushd u-boot*
        make lichee_rv_dock_defconfig
        cat scripts/config
        ./scripts/config --disable WATCHDOG
        ./scripts/config --disable WATCHDOG_AUTOSTART
        make OPENSBI=../opensbi/build/platform/generic/firmware/fw_dynamic.bin -j$(nproc)
        popd

      '';

      installPhase = ''
        mkdir -p $out
        cp ./u-boot*/u-boot-sunxi-with-spl.bin $out/bootloader.bin

        cat << 'EOT' > $out/make.sh
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
        name = "riscv-sipeed-lichee-rv-linux";
        kernel-release = "6.6.8";

        # --- State ---
        # WiFi: rtl8723ds driver
        #   - should be handled by rtw88 in the future (>= 6.7)
        # GPIO:
        # Speaker:
        # MIC:
        # MIC Array:
        # HDMI:
        # Video Engine:
        # Dispay Engine:
        # Deinterlacer:
        # DSP HiFi4:
        # G2D:
        # Thermal sensor:
        # [...]

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

          (pkgs.fetchgit
            {
              url = "https://github.com/lwfinger/rtl8723ds";
              rev = "52e593e8c889b68ba58bd51cbdbcad7fe71362e4";
              hash = "sha256-SszvDuWN9opkXyVQAOLjnNtPp93qrKgnGvzK0y7Y9b0=";
            })

          ./riscv-sipeed-lichee-rv-${kernel-release}.config
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
          make -j$(nproc) Image modules
          make -j$(nproc) INSTALL_MOD_PATH=../mod_root modules_install
          popd

          KSRC=$(pwd)/linux-${kernel-release}
          pushd rtl8723ds*
          echo "DEBUG - Kernel source is $KSRC"
          make KSRC=$KSRC -j$(nproc)
          popd
        '';

        installPhase = ''
          mkdir -p $out/modules

          pushd linux*
          cp ./arch/$ARCH/boot/Image $out/Image
          popd

          pushd rtl8723ds*
          install -D -p -m 644 ./8723ds.ko ../mod_root/lib/modules/${kernel-release}/kernel/drivers/net/wireless/8723ds.ko
          popd

          depmod -a -b ./mod_root ${kernel-release}

          cp -r ./mod_root/lib/modules/* $out/modules
        '';
      };

  ###################################################################
  env = ''
    export SIMPLIX_STATUS_GPIO="-G /dev/gpiochip0 -g 65"
  '';

  init = ''
    modprobe 8723ds
  '';


  ###################################################################
  bootfs = initfs: pkgs.stdenv.mkDerivation
    {
      name = "sipeed-lichee-rv-bootfs";

      nativeBuildInputs = with pkgs; [
        ubootTools
      ];

      phases = [ "installPhase" ];

      installPhase = ''
        BOOT=$out/bootfs
        mkdir -p $BOOT

        cat <<'EOT' >> $out/boot.cmd
        # Prevent overlapping load of ramdisk and kernel
        setenv ramdisk_addr_r 0x48000000  # default 0x41C00000
        setenv kernel_addr_r  0x41000000

        printenv
        fatload mmc 0:1 ''${kernel_addr_r} linux
        fatload mmc 0:1 ''${ramdisk_addr_r} u-initrd
        setenv bootargs "earlycon=sbi console=ttyS0,115200n8 init=/init"
        booti ''${kernel_addr_r} ''${ramdisk_addr_r} ''${fdtcontroladdr}
        EOT

        cp ${linux}/Image $BOOT/linux
        mkimage -A ${arch} -O linux -T script -C none -d $out/boot.cmd $BOOT/boot.scr
        mkimage -A ${arch} -O linux -T ramdisk -d ${initfs}/initramfs.cpio.gz $BOOT/u-initrd
      '';
    };
}
