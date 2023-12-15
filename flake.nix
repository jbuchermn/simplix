{
  description = "RISC-V CC environment";

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
      in
      {
        devShell =
          pkgs.mkShell {

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
                ncurses
                minicom

                # ???
                openssl
                bison
                flex
                swig
                bc
                dtc

                # OpenSBI
                python-basic

                # crosstool-NG
                automake
                help2man
                libtool
              ];

            shellHook = ''
              # crosstool-NG
              unset CC;
              unset CXX;
            '';

          };
      }
    );
}
