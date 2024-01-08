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
        pkgs = import nixpkgs {
          inherit system;
        };
        hardware = {
          riscv-qemu = (import ./hardware/riscv-qemu.nix) { inherit nixpkgs system; };
          riscv-sipeed-lichee-rv = (import ./hardware/riscv-sipeed-lichee-rv.nix) { inherit nixpkgs system; };
          arm64-qemu = (import ./hardware/arm64-qemu.nix) { inherit nixpkgs system; };
          arm-qemu = (import ./hardware/arm-qemu.nix) { inherit nixpkgs system; };
        };

        initfs = import ./initfs.nix { inherit pkgs; };
        rootfs = import ./rootfs.nix { inherit pkgs; };
        package = import ./package.nix { inherit pkgs initfs rootfs; };

        simplix = builder: builtins.mapAttrs
          (_: hw: package hw (builder hw))
          hardware;
      in
      {

        ###################################################################
        packages = {
          # <simplix-flake>.packages.${system}.simplix (hw: {...})
          inherit simplix;

          # nix build .#hardware.<board>.{linux,bootloader,bootfs}
          inherit hardware;

          # nix build .#simplix-basic.<board> (e.g. .#simplix-basic.riscv-qemu)
          simplix-basic = simplix (hw: {
            withHost = false;
            userPkgs = with hw.pkgs-cross; [
              python3
              libgpiod
            ];
          });
        };

        ###################################################################
        # nix develop .#<board> (e.g. .#riscv-qemu)
        devShells = with pkgs; lib.concatMapAttrs
          (name: hw:
            let
              pkgs-cross = hw.pkgs-cross;
            in
            {
              ${name} =
                pkgs.mkShell
                  {
                    depsBuildBuild = with pkgs-cross;
                      [
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
                      karch="${hw.arch}"
                      board=${hw.boardname}

                      export ARCH="$karch"
                      export CROSS_COMPILE="${hw.config}-"

                      function kernel-config() {
                        echo "Kernel config for $board ($karch)"
                        kver=$1
                        config=$2

                        if [ -z "$kver" ] || [ -z "$config" ]; then
                          echo "Usage: kernel-config <kver> <config>"
                          echo "  e.g. kernel-config 6.6.8 menuconfig"
                          return
                        fi

                        cp ./hardware/$karch-$board-$kver.config ./dev/linux-$kver/.config 2>/dev/null | echo "No old config there..."
                        pushd ./dev/linux-$kver

                        make $config
                        popd
                        cp ./hardware/$karch-$board-$kver.config ./hardware/$karch-$board-$kver.config.old 2>/dev/nll
                        cp ./dev/linux-$kver/.config ./hardware/$karch-$board-$kver.config
                      }
                      kernel-config
                    '';
                  };
            })
          hardware;

        ###################################################################
        # nix develop
        devShell =
          pkgs.mkShell
            {
              nativeBuildInputs = with pkgs; [
                minicom
                qemu
              ];
            };
      }
    );
}
