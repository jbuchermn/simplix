{
  description = "Simplix RISC-V";

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
      in
      rec {
        targetSystem =
          let
            simplix-shell = (with pkgs-cross; bash);
            simplix-static-commandline = (with pkgs-cross.pkgsStatic; toybox.overrideAttrs (_: {
              # fortify-headers broken with musl (static toybox appears to always use musl)
              hardeningDisable = [ "all" ];
              configurePhase = ''
                KCONFIG=""
                for i in sh modprobe; do KCONFIG="$KCONFIG"$'\n'CONFIG_''${i^^?}=y; done
                make defconfig KCONFIG_ALLCONFIG=<(echo "$KCONFIG")
              '';
            }));
            simplix-wanted = with pkgs-cross;
              let
                python-basic = pkgs-cross.python3.withPackages (ps: with ps; [
                  setuptools
                ]);
              in
              [
                simplix-shell
                simplix-static-commandline

                iw

                gcc
                binutils
                gnumake

                python-basic
                vim
              ];

          in
          pkgs-cross.stdenv.mkDerivation {
            depsTargetTarget = simplix-wanted;
            phases = [ "installPhase" ];

            name = "target";

            installPhase = ''
              mkdir -p $out
              cat <<-EOF > $out/env.sh
              export SIMPLIX_PATH=${builtins.concatStringsSep ":" (map (x: "${x}/bin") simplix-wanted) }

              export SIMPLIX_SHELL=${simplix-shell}${simplix-shell.shellPath}
              export SIMPLIX_STATIC_CMDLINE=${simplix-static-commandline}/bin
              EOF
              chmod +x $out/env.sh
            '';
          };

        devShell =
          pkgs.mkShell {

            depsBuildBuild = with pkgs-cross; [
              stdenv.cc
            ];

            nativeBuildInputs = with pkgs;
              let
                python-basic = pkgs.python3.withPackages (ps: with ps; [
                  setuptools
                ]);
              in
              [
                qemu
                minicom

                # To use menuconfig
                ncurses

                # To compile u-boot and OpenSBI
                bison
                flex
                openssl
                bc
                swig
                dtc
                python-basic

              ];

            depsTargetTarget = [ targetSystem ];

            shellHook = ''
              export ARCH=${arch}
              export CROSS_TARGET=${config}
              export CROSS_COMPILE=${config}-
              export CC=''${CROSS_COMPILE}gcc
              export CXX=''${CROSS_COMPILE}g++

              export TARGET_ROOT=${targetSystem}
              echo "TARGET_ROOT=''$TARGET_ROOT"
              source ''$TARGET_ROOT/env.sh
              nix path-info --recursive --size --closure-size --human-readable ''$TARGET_ROOT
            '';
          };
      }
    );
}
