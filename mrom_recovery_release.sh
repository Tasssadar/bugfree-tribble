#!/bin/sh
TMP="/tmp/"

if [ -z "$TARGET_DEVICE" ]; then
    TARGET_DEVICE=$(basename $OUT)
fi

case $TARGET_DEVICE in
    flo)
        TAG="flo"
        OTHER="deb"
        CMPR="lzma"
        DCMPR="lzcat"
        ;;
    grouper)
        TAG="grouper"
        OTHER="tilapia"
        CMPR="gzip"
        DCMPR="zcat"
        ;;
    *)
        TAG="$TARGET_DEVICE"
        OTHER=""
        CMPR="gzip"
        DCMPR="zcat"
        ;;
esac

DEST_DIR="/home/tassadar/nexus/multirom/$TAG/"
DEST_DIR_OTHER="/home/tassadar/nexus/multirom/$OTHER/"
IMG_PATH="/home/tassadar/android/android-repo-om/out/target/product/$TAG/recovery.img"

if [ "$RECOVERY_SUBVER" = "" ]; then
    RECOVERY_SUBVER="00"
fi

if [ "$#" -ge "1" ]; then
    DEST_NAME="TWRP_multirom_${TAG}_$(date +%Y%m%d)-$1.img"
elif [ "$RECOVERY_SUBVER" != "00" ]; then
    DEST_NAME="TWRP_multirom_${TAG}_$(date +%Y%m%d)-$RECOVERY_SUBVER.img"
else
    DEST_NAME="TWRP_multirom_${TAG}_$(date +%Y%m%d).img"
fi

if [ "$AUTO_PATCH_INCREMENT" = "true" ]; then
    while [ -f "$DEST_DIR/$DEST_NAME" ] && [ "$RECOVERY_SUBVER" -lt "60" ]; do
        RECOVERY_SUBVER=$(printf "%02d" $((RECOVERY_SUBVER+1)) )
        DEST_NAME="TWRP_multirom_${TAG}_$(date +%Y%m%d)-$RECOVERY_SUBVER.img"
    done
fi

if [ -d "$TMP/mrom_recovery_release" ]; then
    rm -r $TMP/mrom_recovery_release || exit 1
fi
mkdir $TMP/mrom_recovery_release
cd $TMP/mrom_recovery_release

cp -a $IMG_PATH ./

if [ -n "$OTHER" ]; then
    bbootimg -x ./$(basename "$IMG_PATH") >/dev/null 2>&1 || exit 1

    mkdir init
    cd init

    $DCMPR ../initrd.img | cpio -i >/dev/null 2>&1

    sed -i -e "s/ro.build.product=$TAG/ro.build.product=$OTHER/g" default.prop
    sed -i -e "s/ro.product.device=$TAG/ro.product.device=$OTHER/g" default.prop

    find | sort | cpio --quiet -o -H newc | $CMPR > ../initrd.img
    cd ..

    DEST_NAME_OTHER="TWRP_multirom_${OTHER}_$(date +%Y%m%d)"
    if [ "$RECOVERY_SUBVER" != "00" ]; then
        DEST_NAME_OTHER="${DEST_NAME_OTHER}-${RECOVERY_SUBVER}.img"
    else
        DEST_NAME_OTHER="${DEST_NAME_OTHER}.img"
    fi

    grep -v "bootsize" bootimg.cfg > bootimg-new.cfg
    bbootimg --create "$DEST_DIR_OTHER/$DEST_NAME_OTHER" -f bootimg-new.cfg -c "name = mrom$(date +%Y%m%d)-$RECOVERY_SUBVER" -k zImage -r initrd.img >/dev/null 2>&1 || exit 1
    if [ "$PRINT_FILES" = "true" ]; then
        printf "${DEST_DIR_OTHER}${DEST_NAME_OTHER} "
    else
        md5sum "$DEST_DIR_OTHER/$DEST_NAME_OTHER"
    fi
fi

bbootimg -u $(basename "$IMG_PATH") -c "name = mrom$(date +%Y%m%d)-$RECOVERY_SUBVER" >/dev/null 2>&1 || exit 1
cp ./$(basename "$IMG_PATH") "${DEST_DIR}/$DEST_NAME"

rm -r $TMP/mrom_recovery_release

if [ "$PRINT_FILES" = "true" ]; then
    printf "${DEST_DIR}${DEST_NAME}\n"
else
    md5sum "$DEST_DIR/$DEST_NAME"
fi
