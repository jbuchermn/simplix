#!/bin/sh
[ -e "/etc/secrets/wpa_supplicant.conf" ] && cat /etc/secrets/wpa_supplicant.conf >> /etc/wpa_supplicant.conf
rm -f /etc/secrets/wpa_supplicant.conf

mkdir -p /var/log/rc.d/200_networking

ifconfig lo 127.0.0.1
hostname $(cat /etc/hostname)

wifi_dev=""
eth_dev=""
inet_dev=""

if [ -e "/etc/wpa_supplicant.conf" ]; then
    for i in $(ls /sys/class/ieee80211/*/device/net/ 2>/dev/null); do
        echo "Starting up $i..."
        ifconfig $i up
        wpa_supplicant -B -i $i -c /etc/wpa_supplicant.conf -f /var/log/rc.d/200_networking/wpa_supplicant.log && wifi_dev=$i
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
    echo "Starting DHCP for $inet_dev..."
    dhcp -i $inet_dev -b -s /etc/rc.d/200_networking/update_dhcp.sh > /var/log/rc.d/200_networking/dhcp.log
else
    echo "No internet device, skipping dhcp..."
fi
