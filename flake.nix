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
        libc = "musl";
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
            cc-shell = (with pkgs-cross; bash);
            cc-wanted = (with pkgs-cross;
              let
                python-basic = pkgs-cross.python3.withPackages (ps: with ps; [
                  setuptools
                ]);
              in
              [
                cc-shell

                busybox
                iw

                gcc
                binutils
                gnumake

                python-basic
              ]) ++ (with pkgs-cross.pkgsStatic; [
            ]);

          in
          pkgs-cross.stdenv.mkDerivation {
            depsTargetTarget = cc-wanted;
            phases = [ "installPhase" ];

            name = "target";

            installPhase = ''
              mkdir -p $out
              cat <<-EOF > $out/env.sh
              export CC_PATH=${builtins.concatStringsSep ":" (map (x: "${x}/bin") cc-wanted) }

              # TODO
              export CC_SHELL=${cc-shell}/bin/bash
              EOF
              chmod +x $out/env.sh
            '';
          };

        devShell =
          pkgs.mkShell {

            depsBuildBuild = with pkgs-cross; [
              stdenv.cc
            ];

            # Can't compile gcc with the unnecessarily strict settings
            hardeningDisable = [ "all" ];

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
              export CC=''$NIX_CC_FOR_BUILD
              export CXX=''$NIX_CXX_FOR_BUILD

              export TARGET_ROOT=${targetSystem}
              echo "TARGET_ROOT=''$TARGET_ROOT"
              source ''$TARGET_ROOT/env.sh
            '';
          };
      }
    );
}
