#!/bin/sh

if [ $(whoami) != "root" ]; then
    echo "Run this script as root!"
    exit 1
fi

device=""
url=""
tmpdir="$(mktemp -d)"
initialdir="$(pwd)"

fail() {
    echo $1
    rm -rf "$tmpdir"
    exit 1
}

for arg in $@; do
    case $arg in
        http://*|https://*)
            url="${arg}"
            ;;
        *)
            device="$arg"
            ;;
    esac
done

cd "$tmpdir"
wget "$url/boot.img" || fail "Failed to download $url/boot.img"
wget "$url/system.img" || fail "Failed to download $url/system.img"

output="${initialdir}/ubuntu-touch-4.4.2-system-armel+${device}.zip"
build_stock_zip.sh $device --utouch --out="$output" || fail "build_stock_zip.sh failed!"

owner="$(stat -c '%U' "$initialdir")"
chown $owner:$owner $output

rm -rf "$tmpdir"
