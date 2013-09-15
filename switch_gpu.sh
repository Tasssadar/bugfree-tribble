#!/bin/sh

if [ $(whoami) != "root" ] ; then
    echo "must be root"
    exit 1
fi


if [ $1 = "intel" ]; then
    echo "Switching to Intel..."
    cp /etc/X11/xorg.conf.intel /etc/X11/xorg.conf
    aticonfig --px-igpu
    /usr/lib/fglrx/switchlibGL intel
elif [ $1 = "ati" ]; then
    echo "Switching to ATI..."
    cp /etc/X11/xorg.conf.ati /etc/X11/xorg.conf
    aticonfig --px-dgpu
    /usr/lib/fglrx/switchlibGL amd
else
    echo "arg 1 must be \"intel\" or \"ati\""
    exit 1
fi

/etc/init.d/kdm stop
sleep 3
/etc/init.d/kdm start
