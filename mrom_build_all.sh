#!/bin/bash
DEST_DIR="/home/tassadar/nexus/multirom"
TARGETS="omni_grouper-userdebug omni_flo-userdebug omni_mako-userdebug omni_hammerhead-userdebug"

API_KEY="--"
APP_ID="--"

# Include passwords and API things
if [ -e ~/mrom_cfg.sh ]; then
    . ~/mrom_cfg.sh
fi

nobuild="false"
noclean="false"
nodhst="false"
nogoo="false"
build_spec=""
forceupload="false"
recoveryonly="false"
multiromonly="false"
noupload="false"
forcesync="false"
nosync="false"
recovery_patch=""
for a in $@; do
    case $a in
        -h|--help)
            echo "$0 [nobuild] [noclean] [nodhst] [nogoo] [device=mako|grouper|flo|hammerhead] [forceupload] [noupload] [forcesync] [nosync] [recovery] [multirom] [recovery_patch=00-59]"
            exit 0
            ;;
        nobuild)
            nobuild="true"
            ;;
        noclean)
            noclean="true"
            ;;
        nodhst)
            nodhst="true"
            ;;
        device=*)
            build_spec="omni_${a#device=}-userdebug"
            ;;
        forceupload)
            forceupload="true"
            ;;
        noupload)
            noupload="true"
            ;;
        forcesync)
            forcesync="true"
            ;;
        nosync)
            nosync="true"
            ;;
        recovery)
            recoveryonly="true"
            ;;
        multirom)
            multiromonly="true"
            ;;
        recovery_patch=*)
            recovery_patch="${a#recovery_patch=}"
            ;;
    esac
done

dhst_pass_int=""
gooim_pass_int=""
if [ "$DHST_PASS" != "" ]; then
    dhst_pass_int="$(echo $DHST_PASS | base64 -d)"
fi
if [ "$GOOIM_PASS" != "" ]; then
    gooim_pass_int="$(echo $GOOIM_PASS | base64 -d)"
fi

if [ "$nodhst" != "true" ]; then
    while [ -z "$dhst_pass_int" ]; do
        echo
        echo -n "Enter your d-h.st password: "
        read -s dhst_pass_int
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

        if [ "$recoveryonly" == "true" ]; then
            make -j4 recoveryimage || exit 1
        elif [ "$multiromonly" == "true" ]; then
            make -j4 multirom_zip || exit 1
        else
            make -j4 recoveryimage multirom_zip || exit 1
        fi
    fi

    if [ "$multiromonly" == "false" ]; then
        do_auto_patch_increment="false"
        if [ -z "$recovery_patch" ]; then
            do_auto_patch_increment="true"
        fi

        RECOVERY_SUBVER="$recovery_patch" AUTO_PATCH_INCREMENT="$do_auto_patch_increment" mrom_recovery_release.sh || exit 1

        patch=""
        if [ "$recovery_patch" != "00" ]; then
            patch="-$recovery_patch"
        fi

        upload="${upload} $DEST_DIR/$TARGET_DEVICE/TWRP_multirom_${TARGET_DEVICE}_$(date +%Y%m%d)${patch}.img"
        upload_devs="${upload_devs} ${TARGET_DEVICE}"
    fi

    echo ""
    if [ "$recoveryonly" == "false" ]; then
        for f in $(ls "$OUT"/multirom-*v*-*.zip*); do
            dest="$DEST_DIR/$TARGET_DEVICE/$(basename "$f" | sed s/-UNOFFICIAL//g)"

            if [[ "$dest" == *.zip ]]; then
                upload="${upload} $dest"
                upload_devs="${upload_devs} ${TARGET_DEVICE}"
            fi

            echo Copying $(basename $f) to $dest
            cp -a "$f" "$dest" || exit 1
        done
    fi
done

if [ "$nodhst" = "true" ] && [ "$nogoo" = "true" ]; then
    noupload="true"
fi

if [ "$noupload" = "true" ]; then
    echo "Upload disabled by cmdline args"
else
    echo "Do you want to upload these files to d-h.st and goo.im?"
    for u in $upload; do
        echo "  $u"
    done

    if [ "$forceupload" != "true" ]; then
        echo -n "Upload? [y/N]: "
        read upload_files
    else
        echo "Upload forced, proceeding"
    fi

    if [ "$upload_files" = "y" ] || [ "$upload_files" = "Y" ] || [ "$forceupload" = "true" ]; then
        echo

        upload=($upload)
        upload_devs=($upload_devs)

        if [ "$nodhst" != "true" ]; then
            echo "Uploading to d-h.st"
            token=$(dhst_cli.py -l "$DHST_LOGIN" -p "$dhst_pass_int" login)
            if [ "$?" != "0" ]; then
                echo "Failed to log-in to d-h.st"
                exit 1
            fi

            for (( i=0; i<${#upload[@]}; i++ )); do
                u=${upload[$i]}
                dev=${upload_devs[$i]}

                dhst_cli.py -t "$token" -d multirom/$dev upload "$u"
                if [ "$?" != "0" ]; then
                    echo "Failed to upload $u to d-h.st!"
                    exit 1
                fi
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
    else
        echo
        echo "Not uploading anything"
    fi
fi

if [ "$nosync" = "true" ]; then
    echo "Sync disabled by cmdline args"
else
    if [ "$forcesync" != "true" ]; then
        echo -n "Sync files to manager? [y/N]: "
        read upload_files
    else
        echo "Upload forced, proceeding"
    fi

    if [ "$upload_files" = "y" ] || [ "$upload_files" = "Y" ] || [ "$forcesync" = "true" ]; then
        mrom_sync.py
    fi
fi
