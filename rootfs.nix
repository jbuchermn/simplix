{ pkgs }:
pkgs-cross:
linux:
{ simplix-user
, withHost ? true
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
    vim
  ];
  simplix-cacert = (with pkgs-cross; cacert);
  simplix-host = with pkgs-cross; [
    git
    gcc
    binutils
    gnumake
  ];

  target-system = pkgs-cross.stdenv.mkDerivation rec {
    name = "${linux.name}-target";
    depsTargetTarget = simplix-base ++ [
      simplix-shell
      simplix-toybox
    ] ++ simplix-user
      ++ (pkgs.lib.optionals withHost simplix-host);

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

  phases = [ "installPhase" ];

  installPhase = ''
    ROOT=$out/rootfs
    mkdir -p $ROOT

    ######## Setup dirs
    mkdir -p $ROOT/{usr/{bin,sbin,lib,include,libexec},dev,proc,sys,tmp,home,var,etc,run}
    chmod a+rwxt $ROOT/tmp
    ln -s usr/{bin,sbin,lib} $ROOT

    ######## Kernel modules
    mkdir -p $ROOT/lib/modules
    cp -r ${linux}/modules/lib/* $ROOT/lib/

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

    # Setup shell
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

    ######## Secrets to be stored during packaging and to be removed during init
    mkdir -p $ROOT/etc/secrets
    cat <<'EOT' >> $ROOT/../make.sh
    function make_secrets(){
      read -p "WiFi SSID: " ssid
      if [ ! -z "$ssid" ]; then
        read -s -p "WiFi Password: " passwd
    cat <<EOF > $1/etc/secrets/wpa_supplicant.conf
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

    ######## Init
    mkdir -p $ROOT/etc/rc.d

    cat <<EOT > $ROOT/sbin/init
    #!/bin/sh
    echo "Init..."

    source ${target-system}/env.sh
    export PATH=\$PATH:\$SIMPLIX_PATH
    exec oneit /etc/rc

    EOT
    chmod +x $ROOT/sbin/init

    cat <<'EOT' > $ROOT/etc/rc
    #!/bin/sh
    echo "Setting up log dir /var/log/rc.d"
    rm -rf /var/log/rc.d-archive-2
    [ -d "/var/log/rc.d-archive-1" ] && cp -r /var/log/rc.d-archive-1 /var/log/rc.d-archive-2
    [ -d "/var/log/rc.d" ] && cp -r /var/log/rc.d /var/log/rc.d-archive-1
    mkdir -p /var/log/rc.d

    echo "Starting..."
    for i in $(ls -1 /etc/rc.d/ 2>/dev/null | sort); do
    	[ -d /etc/rc.d/"$i" ] && continue;
    	echo "$i..."
    	echo -e "\n******************" >> /var/log/rc.d/"$i".log
    	/bin/sh /etc/rc.d/"$i" >> /var/log/rc.d/"$i".log 2>&1
    	cat /var/log/rc.d/"$i".log
    done

    echo "Main..."
    if [ -e "$HOME/main.sh" ]; then
    	/bin/sh "$HOME/main.sh"
    else
    	cd $HOME; /bin/sh
    fi

    EOT
    chmod +x $ROOT/etc/rc

    ######## Modules

    ### Kernel: modules and such
    cat <<EOT >> $ROOT/etc/rc.d/100_kernel.sh
    #!/bin/sh
    # Kernel bug workaround for ping
    echo 0 99999999 > /proc/sys/net/ipv4/ping_group_range
    EOT
    [ -e "${linux}/load_modules.sh" ] && cat ${linux}/load_modules.sh >> $ROOT/etc/rc.d/100_kernel.sh

    ### Networking

    cat <<'EOT' > $ROOT/etc/rc.d/200_networking.sh
    #!/bin/sh
    [ -e "/etc/secrets/wpa_supplicant.conf" ] && cat /etc/secrets/wpa_supplicant.conf >> /etc/wpa_supplicant.conf
    rm -f /etc/secrets/wpa_supplicant.conf

    ifconfig lo 127.0.0.1
    hostname $(cat /etc/hostname)

    wifi_dev=""
    eth_dev=""
    inet_dev=""

    if [ -e "/etc/wpa_supplicant.conf" ]; then
        for i in $(ls /sys/class/ieee80211/*/device/net/); do
            echo "Starting up $i..."
            ifconfig $i up
            wpa_supplicant -B -i $i -c /etc/wpa_supplicant.conf && wifi_dev=$i
        done
    fi

    for i in $(ifconfig -a | grep eth | sed -e 's/ .*//'); do
        if ifconfig $i | grep -q virtio; then
            echo "Detected virtio driver, assuming qemu with IP 10.0.2.15"
            ifconfig $i 10.0.2.15 && eth_dev=$i
        else
            echo "Testing $i..."
            dhcp -i $i -n -q && eth_dev=$i
        fi
    done

    if [ ! -z "$eth_dev" ]; then
        inet_dev=$eth_dev
    elif [ ! -z "$wifi_dev" ]; then
        inet_dev=$wifi_dev
    fi

    if [ ! -z "$inet_dev" ]; then
        echo "Going for $inet_dev..."
        dhcp -i $inet_dev -s /etc/rc.d/200_networking/update_dhcp.sh
    else
        echo "No internet device, skipping dhcp..."
    fi

    [ "$(date +%s)" -lt 10000000 ] && sntp -sq time.google.com
    EOT

    mkdir -p $ROOT/etc/rc.d/200_networking
    cat <<'EOT' > $ROOT/etc/rc.d/200_networking/update_dhcp.sh
    #!/bin/sh
    mkdir -p /var/log/rc.d/200_networking
    exec 1>/var/log/rc.d/200_networking/update_dhcp.sh.log 2>&1

    if [ "$1" = "deconfig" ]; then
        echo "deconfig: resetting interface $interface..."
        ifconfig $interface 0.0.0.0
    elif [ "$1" = "bound" ]; then
        echo "bound: binding interface $interface to $ip (router $router)..."
        ifconfig $interface $ip
        route add default gw $router dev $interface
    elif [ "$1" = "renew" ]; then
        echo "renew: setting default gateway"
        route add default gw $router dev $interface
    fi
    EOT

    echo "nameserver 8.8.8.8" > $ROOT/etc/resolv.conf

    ### SSL
    mkdir -p $ROOT/etc/ssl/certs
    cp ${simplix-cacert}/etc/ssl/certs/ca-bundle.crt $ROOT/etc/ssl/certs
    pushd $ROOT/etc/ssl/certs
    ln -s ca-bundle.crt ca-certificates.crt
    popd

    ### SSH
    mkdir -p $ROOT/var/empty
    mkdir -p $ROOT/home/.ssh

    cat <<'EOT' > $ROOT/etc/rc.d/210_ssh.sh
    #!/bin/sh
    [ -e "/etc/secrets/authorized_keys" ] && cat /etc/secrets/authorized_keys >> /home/.ssh/authorized_keys
    rm -f /etc/secrets/authorized_keys

    if [ ! -e "/etc/ssh/ssh_host_rsa_key" ]; then
        echo "Generating SSH key..."
        ssh-keygen -A
    fi
    $(which sshd)

    EOT

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



    ### Finish init
    find $ROOT/etc/rc.d -name '*.sh' -exec chmod +x {} \;
  '';
}
