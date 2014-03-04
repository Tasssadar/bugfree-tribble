#!/bin/sh
if [ $# -eq 0 ] || [ "$1" = "on" ]; then
    echo "starting access point..."
    ifconfig wlan0 10.10.0.1
    /etc/init.d/isc-dhcp-server restart
    echo "1" > /proc/sys/net/ipv4/ip_forward
    hostapd -d -B /etc/hostapd/hostapd.conf

    # forward eth0
    iptables -t nat -I POSTROUTING -o eth0 -j MASQUERADE
    iptables -I FORWARD -i wlan0 -s 10.10.0.0/24 -j ACCEPT
    iptables -I FORWARD -i eth0 -d 10.10.0.0/24 -j ACCEPT
else
    echo "stopping access point..."

    iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
    iptables -D FORWARD -i wlan0 -s 10.10.0.0/24 -j ACCEPT
    iptables -D FORWARD -i eth0 -d 10.10.0.0/24 -j ACCEPT

    /etc/init.d/isc-dhcp-server stop
    echo "0" > /proc/sys/net/ipv4/ip_forward
    killall -2 hostapd
fi
