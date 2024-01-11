{ pkgs }:
pkgs-cross:
linux:
{ userPkgs ? [ ]
, withHost ? false
, withDebug ? true
, regulatoryCountry ? "DE"
}:
let
  simplix-shell = (with pkgs-cross; bash.override { interactive = true; });
  simplix-toybox = (with pkgs-cross; toybox.overrideAttrs (prev: {
    configurePhase = ''
      KCONFIG=""
      for i in sh modprobe route dhcp; do KCONFIG="$KCONFIG"$'\n'CONFIG_''${i^^?}=y; done
      make defconfig KCONFIG_ALLCONFIG=<(echo "$KCONFIG")
    '';
  }));
  simplix-base = with pkgs-cross; [
    (wpa_supplicant.override { dbusSupport = false; withPcsclite = false; })
    (openssh.override { withKerberos = false; withFIDO = false; })

    curl
    xz
    vim
  ];
  simplix-debug = with pkgs-cross; [
    iw
    wirelesstools
    iproute2
    strace
  ];
  simplix-cacert = (with pkgs-cross; cacert);
  simplix-regdb = (with pkgs-cross; wireless-regdb);
  simplix-host = with pkgs-cross; [
    git
    gcc
    binutils
    gnumake
  ];

  target-system = pkgs-cross.stdenv.mkDerivation rec {
    name = "target";
    depsTargetTarget = simplix-base ++ [
      simplix-cacert
      simplix-shell
      simplix-toybox
    ] ++ userPkgs
      ++ (pkgs.lib.optionals withHost simplix-host)
      ++ (pkgs.lib.optionals withDebug simplix-debug);

    phases = [ "installPhase" ];

    installPhase = ''
      mkdir -p $out
      cat <<-EOF > $out/env.sh
      export SIMPLIX_PATH="${builtins.concatStringsSep ":" (map (x: "${x}/bin") depsTargetTarget) }"
      export SIMPLIX_LD_FLAGS="${builtins.concatStringsSep " " (map (x: "-L${x}/lib") depsTargetTarget) }"
      export SIMPLIX_C_FLAGS="${builtins.concatStringsSep " " (map (x: "-I${x}/include") depsTargetTarget) }"
      EOF
      chmod +x $out/env.sh

    '';
  };
in
pkgs-cross.stdenv.mkDerivation
{
  name = "rootfs";
  depsTargetTarget = [ target-system ];

  nativeBuildInputs = with pkgs; [
    nix
  ];

  srcs = ./.;

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''

    ROOT=$out/rootfs
    mkdir -p $ROOT


    ######## Core
    cp -r ./root/* $ROOT

    ### FHS directory structure
    mkdir -p $ROOT/{usr/{bin,sbin,lib,include,libexec},dev,proc,sys,tmp,home,var,etc,run}
    chmod a+rwxt $ROOT/tmp
    ln -s usr/{bin,sbin,lib} $ROOT

    ### Modules and firmware
    mkdir -p $ROOT/lib/{modules,firmware}
    [ -d "${linux}/modules" ] && cp -r ${linux}/modules/* $ROOT/lib/modules
    [ -d "${linux}/firmware" ] && cp -r ${linux}/firmware/* $ROOT/lib/firmware


    ######## Cross-compiled binaries
    cat <<'EOT' >> $ROOT/../make.sh
    function make_store(){
      nix path-info --recursive --size --closure-size --human-readable ${target-system}

      mkdir -p $1/nix/store
      for i in $(nix path-info --recursive ${target-system}); do
          cp -r $i $1/nix/store/
      done
      sudo chown -R root $1/nix
      sudo chmod -R u+w $1/nix
    }
    EOT

    ### Setup shell
    pushd $ROOT/usr/bin && ln -s ${simplix-shell}${simplix-shell.shellPath} sh; popd


    ######## Basic configuration
    echo "simplix" > $ROOT/etc/hostname
    cat <<EOT > $ROOT/etc/hosts
    127.0.0.1 localhost
    127.0.0.1 simplix
    EOT

    cat <<'EOF' >$ROOT/etc/passwd
    root::0:0:root:/home:/bin/sh
    nobody:x:65534:65534:nobody:/proc/self:/dev/null
    EOF

    echo -e 'root:x:0:\nnobody:x:65534:' > $ROOT/etc/group

    cat <<EOT > $ROOT/etc/profile
    source ${target-system}/env.sh
    export PATH=\$PATH:\$SIMPLIX_PATH
    EOT


    ######## Init
    cat <<EOT > $ROOT/sbin/init
    #!/bin/sh
    echo "Init..."
    source /etc/profile
    exec oneit /etc/rc
    EOT
    chmod +x $ROOT/sbin/init

    ### 100 - Kernel: modules and such
    [ -e "${linux}/load_modules.sh" ] && cat ${linux}/load_modules.sh >> $ROOT/etc/rc.d/100_kernel.sh
    cp -r ${simplix-regdb}/lib/firmware/* $ROOT/lib/firmware/

    ### 200 - Networking
    echo "nameserver 8.8.8.8" > $ROOT/etc/resolv.conf

    ### 300 - SSL
    mkdir -p $ROOT/etc/ssl/certs
    cp ${simplix-cacert}/etc/ssl/certs/ca-bundle.crt $ROOT/etc/ssl/certs
    pushd $ROOT/etc/ssl/certs
    ln -s ca-bundle.crt ca-certificates.crt
    popd

    ### 310 - SSH
    mkdir -p $ROOT/var/empty
    mkdir -p $ROOT/home/.ssh

    cat <<EOT >> $ROOT/etc/passwd
    sshd:x:33:33::/run/sshd/:/sbin/nologin
    EOT

    cat <<EOT >> $ROOT/etc/group
    ssh:x:33:
    EOT

    mkdir -p $ROOT/etc/ssh
    cat <<EOT >> $ROOT/etc/ssh/sshd_config
    PermitRootLogin yes
    EOT


    ######## Secrets to be stored during packaging and to be removed during init
    mkdir -p $ROOT/etc/secrets
    cat <<'EOT' >> $ROOT/../make.sh
    function make_secrets(){
      read -p "WiFi SSID: " ssid
      if [ ! -z "$ssid" ]; then
        read -s -p "WiFi Password: " passwd
    cat <<EOF > $1/etc/secrets/wpa_supplicant.conf
    update_config=1
    country=${regulatoryCountry}
    network={
      ssid="$ssid"
      scan_ssid=1
      key_mgmt=WPA-PSK
      psk="$passwd"
    }
    EOF
      fi
      [ -e "/home/$2/.ssh/id_rsa.pub" ] && cat /home/$2/.ssh/id_rsa.pub >> $1/etc/secrets/authorized_keys
    }
    EOT
  '';
}
