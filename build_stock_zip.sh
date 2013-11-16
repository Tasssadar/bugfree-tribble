#!/bin/sh
PKG_TEMPLATE="/home/tassadar/scripts/package_template"
CHECK_PROPS="ro.product.device ro.build.product"
SCRIPT_PATH="package/META-INF/com/google/android/updater-script"

fail() {
    echo $1
    exit 1
}

if [ $(whoami) != "root" ]; then
    echo "Run this script as root!"
    exit 1
fi

if [ "$#" -lt "1" ]; then
    echo "Usage $0 DEVICE"
    exit 1
fi

DEVICE="$1"
case $DEVICE in
    grouper|tilapia)
        BOOT_DEV="/dev/block/platform/sdhci-tegra.3/by-name/LNX"
        SYS_DEV="/dev/block/platform/sdhci-tegra.3/by-name/APP"
        CHECK_NAMES="grouper tilapia"
        ;;
    flo|deb)
        BOOT_DEV="/dev/block/platform/msm_sdcc.1/by-name/boot"
        SYS_DEV="/dev/block/platform/msm_sdcc.1/by-name/system"
        CHECK_NAMES="flo deb"
        ;;
    *)
        echo "Unknown device \"$DEVICE\"!"
        exit 1
        ;;
esac

if [ ! -f "boot.img" ]; then
    echo "boot.img not found!"
    exit 1
fi

if [ ! -f "system-mod.img" ]; then
    if [ ! -f "system.img" ]; then
        echo "system.img was not found in this folder!"
        exit 1
    fi

    echo "Converting system.img to normal image..."
    simg2img system.img system-mod.img
fi

mkdir -p system
umount system &> /dev/null

mount -o loop -t ext4 system-mod.img system || fail "Mount failed!"

echo "Creating package..."
rm -rf package &> /dev/null
mkdir -p package/rom
cp -a ${PKG_TEMPLATE}/* package/


echo "Creating tar with system files..."
cd system
tar -cz --numeric-owner -f ../package/rom/system.tar.gz ./*
cd ..

echo "Processing boot.img..."
cp boot.img package/
rm -rf boot &> /dev/null
mkdir boot
cp boot.img boot/
cd boot
extract_bootimg.sh boot.img > /dev/null || fail "Failed to extract boot image!"
cp init/file_contexts ../package/ || fail "Failed to copy file_contexts!"
cd ..
rm -r boot


echo "Creating script..."

assert_str="assert("
for dev in $CHECK_NAMES; do
    for prop in $CHECK_PROPS; do
        assert_str="${assert_str}getprop(\"$prop\") == \"$dev\" || "
    done
    assert_str="${assert_str}\n       "
done
assert_str="${assert_str% || \\n *});\n"
printf "$assert_str" > $SCRIPT_PATH

echo "format(\"ext4\", \"EMMC\", \"${SYS_DEV}\", \"0\", \"/system\");" >> $SCRIPT_PATH
echo "mount(\"ext4\", \"EMMC\", \"${SYS_DEV}\", \"/system\");" >> $SCRIPT_PATH

cat "package/script_body" >> $SCRIPT_PATH || fail "Failed to write script body!"
rm package/script_body

echo 'ui_print("Extracting boot.img...");' >> $SCRIPT_PATH
echo "package_extract_file(\"boot.img\", \"${BOOT_DEV}\");" >> $SCRIPT_PATH

echo 'ui_print("Setting xattrs...");' >> $SCRIPT_PATH
gen_android_metadata system >> $SCRIPT_PATH || fail "Failed to generate metadata!"

echo 'unmount("/system");' >> $SCRIPT_PATH
echo 'ui_print("Installation complete!");' >> $SCRIPT_PATH


echo "Packing into ZIP..."
ver=$(basename $(pwd) | grep -o --color=never '\-.*');
name="${DEVICE}_${ver#-}.zip"

rm ../$name &> /dev/null
cd package
zip -r0 ../${DEVICE}_${ver#-}.zip ./* || fail "Failed to create ZIP file!"
cd ..

umount system

echo
echo "ZIP \"$name\" was successfuly created!"
