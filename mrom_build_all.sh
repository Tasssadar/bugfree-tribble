#!/bin/bash
DEST_DIR="/home/tassadar/nexus/multirom"
TARGETS="cm_grouper-userdebug cm_flo-userdebug cm_mako-userdebug"
MEDIAFIRE_LOGIN="vbocek@gmail.com"

API_KEY="--"
APP_ID="--"

# Includ passwords and API things
if [ -e ~/mrom_cfg.sh ]; then
    . ~/mrom_cfg.sh
fi

nobuild="false"
noclean="false"
nofire="false"
nogoo="false"
build_spec=""
forceupload="false"
for a in $@; do
    case $a in
        -h|--help)
            echo "$0 [nobuild] [noclean] [nofire] [nogoo] [device=mako|grouper|flo] [forceupload]"
            exit 0
            ;;
        nobuild)
            nobuild="true"
            ;;
        noclean)
            noclean="true"
            ;;
        nofire)
            nofire="true"
            ;;
        device=*)
            build_spec="cm_${a#device=}-userdebug"
            ;;
        forceupload)
            forceupload="true"
            ;;
    esac
done

mediafire_pass_int=""
gooim_pass_int=""
if [ "$MEDIAFIRE_PASS" != "" ]; then
    mediafire_pass_int="$(echo $MEDIAFIRE_PASS | base64 -d)"
fi
if [ "$GOOIM_PASS" != "" ]; then
    gooim_pass_int="$(echo $GOOIM_PASS | base64 -d)"
fi

if [ "$nofire" != "true" ]; then
    while [ -z "$mediafire_pass_int" ]; do
        echo
        echo -n "Enter your mediafire password: "
        read -s mediafire_pass_int
    done
fi
if [ "$nogoo" != "true" ]; then
    while [ -z "$gooim_pass_int" ]; do
        echo
        echo -n "Enter your goo.im password: "
        read -s gooim_pass_int
    done
fi

. build/envsetup.sh

upload=""
upload_devs=""
for t in $TARGETS; do
    if [ -n "$build_spec" ] && [ "$build_spec" != "$t" ]; then
        continue
    fi

    lunch $t

    TARGET_DEVICE=$(basename $OUT)

    if [ "$nobuild" != "true" ]; then
        if [ "$noclean" != "true" ]; then
            rm -r "$OUT"
        fi
        make -j4 recoveryimage multirom_zip || exit 1
    fi

    mrom_recovery_release.sh || exit 1
    upload="${upload} $DEST_DIR/$TARGET_DEVICE/TWRP_multirom_${TARGET_DEVICE}_$(date +%Y%m%d).img"
    upload_devs="${upload_devs} ${TARGET_DEVICE}"
    echo ""
    for f in $(ls "$OUT"/multirom-*v*-*.zip*); do
        dest="$DEST_DIR/$TARGET_DEVICE/$(basename "$f" | sed s/-UNOFFICIAL//g)"

        if [[ "$dest" == *.zip ]]; then
            upload="${upload} $dest"
            upload_devs="${upload_devs} ${TARGET_DEVICE}"
        fi

        echo Copying $(basename $f) to $dest
        cp -a "$f" "$dest" || exit 1
    done
done

if [ "$nofire" == "true" ] && [ "$nogoo" == "true" ]; then
    echo "Upload disabled by cmdline args, exiting"
    exit 0
fi

echo "Do you want to upload these files to MediaFire and goo.im?"
for u in $upload; do
    echo "  $u"
done

if [ "$forceupload" != "true" ]; then
    echo -n "Upload? [y/N]: "
    read upload_files

    if [ "$upload_files" != "y" ] && [ "$upload_files" != "Y" ]; then
        echo
        echo "Not uploading anything"
        exit 0
    fi
else
    echo "Upload forced, proceeding"
fi

echo

upload=($upload)
upload_devs=($upload_devs)

if [ "$nofire" != "true" ]; then
    echo "Uploading to mediafire"
    token=$(mediafire_cli.py -l "$MEDIAFIRE_LOGIN" -p "$mediafire_pass_int" -k "$API_KEY" -i "$APP_ID" login)
    if [ "$?" != "0" ]; then
        echo "Failed to log-in to mediafire"
        exit 1
    fi

    for (( i=0; i<${#upload[@]}; i++ )); do
        u=${upload[$i]}
        dev=${upload_devs[$i]}

        mediafire_cli.py -t "$token" -d mrom_$dev upload "$u"
        if [ "$?" != "0" ]; then
            echo "Failed to upload $u to mediafire!"
            exit 1
        fi
        token=$(mediafire_cli.py -t "$token" renew)
    done
fi

if [ "$nogoo" != "true" ]; then
    echo
    echo "Uploading to goo.im..."
    for (( i=0; i<${#upload[@]}; i++ )); do
        u=${upload[$i]}
        dev=${upload_devs[$i]}

        echo "Uploading $u"
        sshpass -p $gooim_pass_int scp $u upload.goo.im:~/public_html/multirom/${dev}/
        if [ "$?" != "0" ]; then
            echo "Failed to upload $u to goo.im!"
            exit 1
        fi
    done
fi
