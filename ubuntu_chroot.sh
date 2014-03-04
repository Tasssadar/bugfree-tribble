#!/bin/sh

CHROOT_PATH="/home/tassadar/ubuntu-chroot"
CHROOT_CMD="/bin/bash"

if [ $(whoami) != "root" ]; then
    echo "Root is needed to run chroot, restarting with sudo..."
    sudo $0
    exit $?
fi

for arg in "$@"; do
    case $arg in
        --cmd=*)
            CHROOT_CMD="${arg#--cmd=}"
            ;;
        --path=*)
            CHROOT_PATH="${arg#--path=}"
            ;;
    esac
done

fail() {
    umount "${CHROOT_PATH}/dev" "${CHROOT_PATH}/proc" "${CHROOT_PATH}/sys" >/dev/null 2>&1
    echo $1
    exit 1
}

([ -d "${CHROOT_PATH}" ]) || fail "Path ${CHROOT_PATH} does not exist!"

umount "${CHROOT_PATH}/dev" "${CHROOT_PATH}/proc" "${CHROOT_PATH}/sys" >/dev/null 2>&1

for dir in dev proc sys; do
    mount -o bind /$dir "${CHROOT_PATH}/${dir}" || fail "Failed to bind-mount ${dir}!"
done

LANG=C chroot "${CHROOT_PATH}" ${CHROOT_CMD}

umount "${CHROOT_PATH}/dev" "${CHROOT_PATH}/proc" "${CHROOT_PATH}/sys" >/dev/null 2>&1
