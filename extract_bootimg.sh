#!/bin/sh
if [ "$#" -lt "1" ]; then
    echo "Usage: $0 [boot.img]"
    exit 0
fi

bbootimg -i $1
bbootimg -x $1

if [ -d "./init" ]; then
    rm -rf init
fi
mkdir init || exit 1
cd init
zcat ../initrd.img | cpio -i || lzcat ../initrd.img | cpio -i
