{ pkgs }:
hardware:
let
  pkgs-cross = hardware.pkgs-cross;
in
pkgs-cross.stdenv.mkDerivation
{
  name = "simplix-status";

  depsBuildBuild = with pkgs-cross; [
    stdenv.cc
  ];

  buildInputs = with pkgs-cross; [
    libgpiod
  ];

  srcs = ./.;

  phases = [ "unpackPhase" "buildPhase" "installPhase" ];

  buildPhase = ''
    $CC -lgpiod main.c
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp ./a.out $out/bin/simplix-status
  '';
}
