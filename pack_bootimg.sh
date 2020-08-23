#!/bin/sh
if [ "$#" -lt "1" ]; then
    echo "Usage: $0 [output-boot.img]"
    exit 0
fi

dtb_part=""
if [ -f "dtb.img" ]; then
    dtb_part="-d dtb.img"
fi

#abootimg-pack-initrd -f initrd.img init || exit 1
( cd init && find | sort | cpio --quiet -o -H newc --owner root:root ) | gzip > initrd.img

grep -v "bootsize" bootimg.cfg > bootimg-new.cfg || exit 1
bbootimg --create "$1" -f bootimg-new.cfg -k zImage -r initrd.img $dtb_part
bbootimg -i "$1"
