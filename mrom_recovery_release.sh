#!/bin/sh
TMP="/tmp/"

if [ "$TARGET_PRODUCT" = "cm_flo" ]; then
    TAG="flo"
    OTHER="deb"
    CMPR="lzma"
    DCMPR="lzcat"
elif [ "$TARGET_PRODUCT" = "cm_grouper" ]; then
    TAG="grouper"
    OTHER="tilapia"
    CMPR="gzip"
    DCMPR="zcat"
elif [ "$TARGET_PRODUCT" = "cm_mako" ]; then
    TAG="mako"
    OTHER=""
    CMPR="gzip"
    DCMPR="zcat"
else
    echo Unknown device: $TARGET_PRODUCT
    exit 1
fi

DEST_DIR="/home/tassadar/nexus/multirom/$TAG/"
IMG_PATH="/home/tassadar/android/android-repo-cm/out/target/product/$TAG/recovery.img"
if [ "$RECOVERY_SUBVER" == "" ]; then
    RECOVERY_SUBVER="00"
fi

if [ "$#" -ge "1" ]; then
    DEST_NAME="TWRP_multirom_${TAG}_$(date +%Y%m%d)-$1.img"
elif [ "$RECOVERY_SUBVER" != "00" ]; then
    DEST_NAME="TWRP_multirom_${TAG}_$(date +%Y%m%d)-$RECOVERY_SUBVER.img"
else
    DEST_NAME="TWRP_multirom_${TAG}_$(date +%Y%m%d).img"
fi


if [ -d "$TMP/mrom_recovery_release" ]; then
    rm -r $TMP/mrom_recovery_release || exit 1
fi
mkdir $TMP/mrom_recovery_release
cd $TMP/mrom_recovery_release

cp -a $IMG_PATH ./
abootimg -x ./$(basename "$IMG_PATH")

if [ -n "$OTHER" ]; then
    mkdir init
    cd init
    $DCMPR ../initrd.img | cpio -i
    sed -e "s/ro.build.product=$TAG/ro.build.product=$OTHER/g" default.prop > ../default.prop
    mv ../default.prop default.prop


    find | sort | cpio --quiet -o -H newc | $CMPR > ../initrd.img
    cd ..
fi

grep -v "bootsize" bootimg.cfg > bootimg-new.cfg
abootimg --create "$DEST_DIR/$DEST_NAME" -f bootimg-new.cfg -c "name = mrom$(date +%Y%m%d)-$RECOVERY_SUBVER" -k zImage -r initrd.img

rm -r $TMP/mrom_recovery_release

md5sum "$DEST_DIR/$DEST_NAME"
