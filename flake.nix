{
  description = "Simplix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
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

        hardware = {
          riscv-qemu = (import ./hardware/riscv-qemu.nix) { inherit nixpkgs system; };
          riscv-sipeed-lichee-rv = (import ./hardware/riscv-sipeed-lichee-rv.nix) { inherit nixpkgs system; };
        };

        initfs = (import ./initfs.nix) { inherit pkgs pkgs-cross; };
        rootfs = (import ./rootfs.nix) { inherit pkgs pkgs-cross; };
        package = (import ./package.nix) { inherit pkgs pkgs-cross initfs rootfs; };
      in
      rec {
        # test = hardware.riscv-qemu.bootloader;
        # test = hardware.riscv-sipeed-lichee-rv.bootloader;
        # test = hardware.riscv-sipeed-lichee-rv.linux;
        # test = hardware.riscv-qemu.linux;
        # test = hardware.riscv-sipeed-lichee-rv.bootfs initfs;
        # test = hardware.riscv-qemu.bootfs initfs;
        # test = rootfs
        #   hardware.riscv-sipeed-lichee-rv.linux
        #   {
        #     simplix-user = with pkgs-cross; [ python3 ];
        #   };
        test = package hardware.riscv-sipeed-lichee-rv {
          simplix-user = with pkgs-cross; [ python3 ];
        };

        ###################################################################
        devShell =
          pkgs.mkShell {

            # TODO: Is providing the correct cross-compiler for menuconfig necessary?
            # - Try with make menuconfig (without ccc), add cc, make oldconfig
            # - In this case this should be moved into hardware
            depsBuildBuild = with pkgs-cross; [
              stdenv.cc
            ];

            nativeBuildInputs = with pkgs; [
              minicom
              qemu

              # kernel menuconfig
              ncurses
              flex
              bison
              bc
            ];

            shellHook = ''
              function kernel-config() {
                kver=$1
                karch=$2
                board=$3
                config=$4

                if [ -z "$kver" ] || [ -z "$karch" ] || [ -z "$board" ] || [ -z "$config" ]; then
                  echo "Usage: kernel-config <kver> <karch> <board> <config>"
                  echo "  e.g. kernel-config 6.6.8 riscv sipeed-lichee-rv menuconfig"
                  return
                fi

                if [ "$karch" != "riscv" ]; then
                  echo "TODO: Not implemented yet";
                  return
                fi

                cp ./hardware/$karch-$board-$kver.config ./dev/linux-$kver/.config
                pushd ./dev/linux-$kver

                export ARCH=$karch
                export CROSS_COMPILE=${config}-
                make $config
                popd
                cp ./hardware/$karch-$board-$kver.config ./hardware/$karch-$board-$kver.config.old
                cp ./dev/linux-$kver/.config ./hardware/$karch-$board-$kver.config
              }
            '';
          };
      }
    );
}
