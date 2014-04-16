#!/bin/bash

# Must be !/bin/bash because ". build/envsetup.sh" is bash-only!!

set -e

CDIMAGE_PATH="/opt/cdimage"
TREE_PATH="/opt/ubuntu-touch"
DEVICES="hammerhead deb"
DEVICES_REQ=""
SERIES="trusty"
CLEAN_OUT=true
FORCE=false
NOSYNC=false

PATH="/sbin:$PATH"

handle_args() {
    for arg in $1; do
        case $arg in
            noclean)
                CLEAN_OUT=false
                ;;
            force)
                FORCE=true
                ;;
            device=*)
                DEVICES_REQ="${DEVICES_REQ} ${arg#device=}"
                ;;
            nosync)
                NOSYNC=true
                ;;
            *)
                echo "unknown arg $arg"
                ;;
        esac
    done
}

is_device_req() {
    ([ -n "$DEVICES_REQ" ]) || return 0

    for dev_req in $DEVICES_REQ; do
        if [ "$dev_req" = "$1" ]; then
            return 0
        fi
    done

    return 1
}

build() {
    cd "$TREE_PATH"

    $NOSYNC || /home/tassadar/bin/repo sync

    if $CLEAN_OUT; then
        echo "Removing /out/target/"
        rm -rf out/target/
    fi

    . build/envsetup.sh

    for dev in $DEVICES; do
        is_device_req $dev || continue

        lunch aosp_$dev-userdebug

        time make
    done
}

create_and_enter_cdimage_dir() {
    mkdir -p "$CDIMAGE_PATH"
    cd "$CDIMAGE_PATH"

    dir="$(date +%Y%m%d)"
    itr="1"

    while [ -d "$dir" ]; do
        dir="$(date +%Y%m%d).${itr}"
        itr=$((itr+1))
    done

    mkdir "$dir"
    cd "$dir"
}

copy_images() {
    # why the fuck is boot armhf and the rest is not
    images_armhf="boot"
    images_armel="recovery system"
    for dev in $DEVICES; do
        is_device_req $dev || continue

        for img in $images_armhf; do
            cp "${TREE_PATH}/out/target/product/${dev}/${img}.img" "./${SERIES}-preinstalled-${img}-armhf+${dev}.img"
        done

        for img in $images_armel; do
            cp "${TREE_PATH}/out/target/product/${dev}/${img}.img" "./${SERIES}-preinstalled-${img}-armel+${dev}.img"
        done
    done
}

replace_keyring() {
    imgdir="$(pwd)"

    for dev in $DEVICES; do
        is_device_req $dev || continue

        tmpdir="$(mktemp -d)"
        recovery_file="${SERIES}-preinstalled-recovery-armel+${dev}.img"

        cp "$recovery_file" "$tmpdir/recovery.img"
        cd "$tmpdir"

        bbootimg -x recovery.img
        mkdir init && cd init
        zcat ../initrd.img | cpio -i

        cp -a "$1" "etc/system-image/"
        cp -a "$1.asc" "etc/system-image/"

        ( find . ! -name . | sort | cpio --quiet -o -H newc ) | gzip > ../initrd.img
        cd ..

        bbootimg -u "${imgdir}/${recovery_file}" -c "bootsize=0" -r initrd.img

        cd "$imgdir"
        rm -r "$tmpdir"
    done
}

generate_checksums() {
    md5sum -b *.img > MD5SUMS
    sha1sum -b *.img > SHA1SUMS
    sha256sum -b *.img > SHA256SUMS
}

purge_old_images() {
    cnt=$(ls -1 -Icustom "$CDIMAGE_PATH" | wc -l)
    if [ "$cnt" -gt "3" ]; then
        cnt=$((cnt-3))
        for img in $(ls -1r -Icustom --sort=time --time=ctime "${CDIMAGE_PATH}" | head --lines=${cnt}); do
            echo "Erasing old cdimage $img..."
            rm -r "${CDIMAGE_PATH}/${img}"
        done
    fi
}

load_last_build_timestamp() {
    if [ -e "${TREE_PATH}/last_build.txt" ]; then
        cat "${TREE_PATH}/last_build.txt"
    else
        echo "0"
    fi
}

check_pkg_version() {
    pkg_stamp="$(get_android_pkg_ver.py)"
    if [ "$?" = "0" ] && [ "$pkg_stamp" -gt "$1" ]; then
        echo "$pkg_stamp"
    else
        echo "0"
    fi
}

handle_args "$*"

last_build="$(load_last_build_timestamp)"
pkg_stamp="$(check_pkg_version $last_build)"

$FORCE || [ "$pkg_stamp" -gt "0" ] || ( echo "Exiting, ubuntu package was not updated since $last_build" && exit 1 )

build

create_and_enter_cdimage_dir
copy_images
replace_keyring "/opt/system-image-www/gpg/archive-master.tar.xz"
generate_checksums
purge_old_images

echo "$pkg_stamp" > "${TREE_PATH}/last_build.txt"
