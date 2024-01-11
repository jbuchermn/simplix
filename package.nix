{ pkgs, initfs, rootfs }:
hardware:
rootfs-config:
let
  simplix-bootloader = hardware.bootloader;
  simplix-bootfs = hardware.bootfs (initfs hardware.pkgs-cross);
  simplix-rootfs = rootfs hardware.pkgs-cross hardware.linux rootfs-config;
in
pkgs.stdenv.mkDerivation {
  name = "package";

  srcs = ./package.sh;
  preUnpack = ''
    unpackCmdHooks+=(_tryShellFile)
    _tryShellFile() {
      if ! [[ "$1" =~ \.sh$ ]]; then return 1; fi
      mkdir -p package
      cp "$1" ./package/$(stripHash "$1")
    }
  '';

  phases = [ "unpackPhase" "installPhase" ];
  installPhase = ''
    mkdir -p $out
    ln -s ${simplix-bootloader}/bootloader* $out
    ln -s ${simplix-bootfs}/bootfs $out/bootfs
    ln -s ${simplix-rootfs}/rootfs $out/rootfs

    cat <<'EOT' > $out/make.sh
    #!/usr/bin/env bash
    EOT

    [ -e "${simplix-bootloader}/make.sh" ] && cat ${simplix-bootloader}/make.sh >> $out/make.sh
    [ -e "${simplix-bootfs}/make.sh" ] && cat ${simplix-bootfs}/make.sh >> $out/make.sh
    [ -e "${simplix-rootfs}/make.sh" ] && cat ${simplix-rootfs}/make.sh >> $out/make.sh

    cat ./package.sh >> $out/make.sh

    chmod +x $out/make.sh
  '';
}
