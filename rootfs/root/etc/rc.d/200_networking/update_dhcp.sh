#!/bin/sh
exec 1>/var/log/rc.d/200_networking/update_dhcp.sh.log 2>&1

if [ "$1" = "deconfig" ]; then
    echo "deconfig: resetting interface $interface..."
    ifconfig $interface 0.0.0.0
elif [ "$1" = "bound" ]; then
    echo "bound: binding interface $interface to $ip (router $router)..."
    ifconfig $interface $ip
    route add default gw $router dev $interface

    [ "$(date +%s)" -lt 10000000 ] && sntp -sq time.google.com
elif [ "$1" = "renew" ]; then
    echo "renew: setting default gateway"
    route add default gw $router dev $interface
fi
