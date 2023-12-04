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
        pkgs-cross = import nixpkgs {
          inherit system;
          crossSystem = {
            config = "riscv64-unknown-linux-gnu";
          };
        };
        python-with-my-packages = pkgs.python3.withPackages (ps: with ps; [
          setuptools
        ]);
      in
      {
        devShell =
          pkgs.mkShell {
            depsBuildBuild = with pkgs-cross; [
              stdenv.cc
              musl
            ];

            nativeBuildInputs = with pkgs; [
              bison
              flex
              swig
              bc
              ncurses
              dtc
              qemu

              python-with-my-packages
            ];

            buildInputs = with pkgs; [
              openssl
              ncurses
              glibc
            ];
          };
      }
    );
}
