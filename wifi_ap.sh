#!/bin/sh
if [ $# -eq 0 ] || [ "$1" = "on" ]; then
    echo "starting access point..."
    ifconfig wlan0 10.10.0.1
    /etc/init.d/isc-dhcp-server restart
    echo "1" > /proc/sys/net/ipv4/ip_forward
    hostapd -d -B /etc/hostapd/hostapd.conf
else
    echo "stopping access point..."
    /etc/init.d/isc-dhcp-server stop
    echo "0" > /proc/sys/net/ipv4/ip_forward
    killall -2 hostapd
fi
