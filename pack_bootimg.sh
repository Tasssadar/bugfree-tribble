#!/bin/sh
if [ "$#" -lt "1" ]; then
    echo "Usage: $0 [output-boot.img]"
    exit 0
fi

abootimg-pack-initrd -f initrd.img init || exit 1
grep -v "bootsize" bootimg.cfg > bootimg-new.cfg || exit 1
abootimg --create "$1" -f bootimg-new.cfg -k zImage -r initrd.img
abootimg -i "$1"
