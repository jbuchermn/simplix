#!/bin/sh
echo ""
echo "**********"
echo "Setting up rootfs"

mkdir -p ./output/rootfs


######## Setup dirs
mkdir -p ./output/rootfs/{usr/{bin,sbin,lib,include,libexec},dev,proc,sys,tmp,home,var,etc,run}
chmod a+rwxt ./output/rootfs/tmp
ln -s usr/{bin,sbin,lib} ./output/rootfs


######## Kernel modules
mkdir -p ./output/rootfs/lib/modules
cp -r ./output/qemu-modules/lib/* ./output/rootfs/lib/
cp -r ./output/board-modules/lib/* ./output/rootfs/lib/


######## Cross-compiled binaries
# Always clean nix store
rm -rf ./output/rootfs/nix/store
mkdir -p ./output/rootfs/nix/store
for i in $(nix path-info --recursive $SIMPLIX_ROOT); do
	cp -r $i ./output/rootfs/nix/store/
done
sudo chown -R $(whoami) ./output/rootfs/nix
sudo chmod -R u+w ./output/rootfs/nix

# Setup shell
pushd ./output/rootfs/usr/bin && ln -s ${SIMPLIX_SHELL} sh; popd

######## Basic configuration

# TODO: Does not seem to be enough, also check /etc/hosts?
echo "simplix" > ./output/rootfs/etc/hostname

cat <<'EOF' >./output/rootfs/etc/passwd
root::0:0:root:/home:/bin/sh
nobody:x:65534:65534:nobody:/proc/self:/dev/null
EOF

echo -e 'root:x:0:\nnobody:x:65534:' > ./output/rootfs/etc/group


cat <<EOT > ./output/rootfs/etc/profile
source ${SIMPLIX_ROOT}/env.sh
export PATH=\$PATH:\$SIMPLIX_PATH
EOT


######## Init
mkdir -p ./output/rootfs/etc/rc.d

cat <<EOT > ./output/rootfs/sbin/init
#!/bin/sh
echo "Init..."

source ${SIMPLIX_ROOT}/env.sh
export PATH=\$PATH:\$SIMPLIX_PATH
exec oneit /etc/rc

EOT
chmod +x ./output/rootfs/sbin/init

cat <<'EOT' > ./output/rootfs/etc/rc
#!/bin/sh
echo "Setting up log dir /var/log/rc.d"
if [ -d "/var/log/rc.d" ]; then
	rm -rf /var/log/rc.d-archive-2
	cp -r /var/log/rc.d-archive-1 /var/log/rc.d-archive-2
	cp -r /var/log/rc.d /var/log/rc.d-archive-1
fi
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
chmod +x ./output/rootfs/etc/rc


######## Modules

### Kernel: modules and such
cat <<EOT > ./output/rootfs/etc/rc.d/100_kernel.sh
#!/bin/sh

# Load modules
# TODO: Only in case of board
modprobe 8723ds

# Kernel bug workaround for ping
echo 0 99999999 > /proc/sys/net/ipv4/ping_group_range
EOT


### Networking

cat <<'EOT' > ./output/rootfs/etc/rc.d/200_networking.sh
#!/bin/sh
ifconfig lo 127.0.0.1

wifi_dev=""
eth_dev=""
inet_dev=""

if [ -f "/etc/wpa_supplicant.conf" ]; then
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

mkdir -p ./output/rootfs/etc/rc.d/200_networking
cat <<'EOT' > ./output/rootfs/etc/rc.d/200_networking/update_dhcp.sh
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

echo "nameserver 8.8.8.8" > ./output/rootfs/etc/resolv.conf

if [ ! -z "$SIMPLIX_SSID" ] && [ ! -z "$SIMPLIX_PSK" ]; then
cat <<-EOF > ./output/rootfs/etc/wpa_supplicant.conf
	network={
		ssid="$SIMPLIX_SSID"
		scan_ssid=1
		key_mgmt=WPA-PSK
		psk="$SIMPLIX_PSK"
	}
	EOF
else
	echo "No \$SIMPLIX_SSID or no \$SIMPLIX_PSK - skipping wpa_supplicant config..."
fi

### SSH
mkdir -p ./output/rootfs/var/empty

cat <<'EOT' > ./output/rootfs/etc/rc.d/210_ssh.sh
#!/bin/sh
if [ ! -e /etch/ssh/ssh_host_rsa_key ]; then
	echo "Generating SSH key..."
	ssh-keygen -A
fi
$(which sshd)

EOT

cat <<EOT >> ./output/rootfs/etc/passwd
sshd:x:33:33::/run/sshd/:/sbin/nologin
EOT

cat <<EOT >> ./output/rootfs/etc/group
ssh:x:33:
EOT

mkdir -p ./output/rootfs/etc/ssh
cat <<EOT >> ./output/rootfs/etc/ssh/sshd_config
PermitRootLogin yes
EOT

mkdir -p ./output/rootfs/home/.ssh
[ -e "$HOME/.ssh/id_rsa.pub" ] && cat $HOME/.ssh/id_rsa.pub >> ./output/rootfs/home/.ssh/authorized_keys


### Finish init
find ./output/rootfs/etc/rc.d -name '*.sh' -exec chmod +x {} \;

