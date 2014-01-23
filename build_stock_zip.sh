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
    echo "Usage $0 DEVICE [--userdata]"
    exit 1
fi

IMAGES="system"
for arg in "$@"; do
    case $arg in
        grouper|tilapia)
            DEVICE="$arg"
            BOOT_DEV="/dev/block/platform/sdhci-tegra.3/by-name/LNX"
            SYS_DEV="/dev/block/platform/sdhci-tegra.3/by-name/APP"
            CHECK_NAMES="grouper tilapia"
            ;;
        flo|deb)
            DEVICE="$arg"
            BOOT_DEV="/dev/block/platform/msm_sdcc.1/by-name/boot"
            SYS_DEV="/dev/block/platform/msm_sdcc.1/by-name/system"
            CHECK_NAMES="flo deb"
            ;;
        mako)
            DEVICE="$arg"
            BOOT_DEV="/dev/block/platform/msm_sdcc.1/by-name/boot"
            SYS_DEV="/dev/block/platform/msm_sdcc.1/by-name/system"
            CHECK_NAMES="mako"
            ;;
        hammerhead)
            DEVICE="$arg"
            BOOT_DEV="/dev/block/platform/msm_sdcc.1/by-name/boot"
            SYS_DEV="/dev/block/platform/msm_sdcc.1/by-name/system"
            CHECK_NAMES="hammerhead"
            ;;

        --userdata)
            IMAGES="${IMAGES} userdata"
            ;;
        *)
            echo "Unknown arg \"$arg\""
            exit 1
            ;;
    esac
done

if [ ! -f "boot.img" ]; then
    echo "boot.img not found!"
    exit 1
fi

echo "Creating package..."
rm -rf package >word 2>&1
mkdir -p package/rom
cp -a ${PKG_TEMPLATE}/* package/


for img in $IMAGES; do
    mkdir -p "mnt_images/$img"
    umount "mnt_images/$img" >word 2>&1

    if [ ! -f "$img-mod.img" ]; then
        if [ ! -f "$img.img" ]; then
            echo "$img.img was not found in this folder!"
            exit 1
        fi

        echo "Converting $img.img to normal image..."
        simg2img $img.img $img-mod.img
    fi

    mount -o loop -t ext4 $img-mod.img mnt_images/$img || fail "Mount failed!"

    echo "Creating tar with $img files..."
    cd mnt_images/$img
    tar -cz --numeric-owner -f ../../package/rom/$img.tar.gz ./*
    cd ../..
done


echo "Processing boot.img..."
cp boot.img package/
rm -rf boot >word 2>&1
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
cd mnt_images
# must be "gen_android_metadata system", always - it writes the path into updater-script!
gen_android_metadata system >> ../$SCRIPT_PATH || fail "Failed to generate metadata!"
cd ..

echo 'unmount("/system");' >> $SCRIPT_PATH
echo 'ui_print("Installation complete!");' >> $SCRIPT_PATH


echo "Packing into ZIP..."
ver=$(basename $(pwd) | grep -o --color=never '\-.*');
name="${DEVICE}_${ver#-}.zip"

rm ../$name >word 2>&1
cd package
zip -r0 ../${ver#-}_${DEVICE}.zip ./* || fail "Failed to create ZIP file!"
cd ..

umount mnt_images/system >word 2>&1
umount mnt_images/userdata >word 2>&1
rmdir mnt_images/system >word 2>&1
rmdir mnt_images/userdata >word 2>&1
rmdir mnt_images >word 2>&1

echo
echo "ZIP \"$name\" was successfuly created!"
