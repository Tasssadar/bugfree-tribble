#!/bin/bash
DEST_DIR="/home/tassadar/nexus/multirom"
TARGETS="omni_grouper-userdebug omni_flo-userdebug omni_mako-userdebug omni_hammerhead-userdebug"

API_KEY="--"
APP_ID="--"

# Include passwords and API things
if [ -e ~/mrom_cfg.sh ]; then
    . ~/mrom_cfg.sh
fi

nobuild=false
noclean=false
nodhst=false
nogoo=false
noxda=false
forcexda=false
build_spec=""
forceupload=false
recoveryonly=false
multiromonly=false
noupload=false
forcesync=false
nosync=false
recovery_patch=""
for a in $@; do
    case $a in
        -h|--help)
            echo "$0 [nobuild] [noclean] [nodhst] [nogoo] [device=mako|grouper|flo|hammerhead] [forceall] [forcenone] [forceupload] [noupload] [forcesync] [nosync] [forcexda] [noxda] [recovery] [multirom] [recovery_patch=00-59]"
            exit 0
            ;;
        nobuild)
            nobuild=true
            ;;
        noclean)
            noclean=true
            ;;
        nogoo)
            nogoo=true
            ;;
        nodhst)
            nodhst=true
            ;;
        noxda)
            noxda=true
            ;;
        forcexda)
            forcexda=true;
            ;;
        device=*)
            build_spec="$build_spec omni_${a#device=}-userdebug"
            ;;
        forceupload)
            forceupload=true
            ;;
        noupload)
            noupload=true
            ;;
        forcesync)
            forcesync=true
            ;;
        nosync)
            nosync=true
            ;;
        recovery)
            recoveryonly=true
            ;;
        multirom)
            multiromonly=true
            ;;
        recovery_patch=*)
            recovery_patch="${a#recovery_patch=}"
            ;;
        forceall)
            forcesync=true
            forceupload=true
            forcexda=true
            ;;
        forcenone)
            noupload=true
            noxda=true
            nosync=true
            ;;
    esac
done

acquire_pass() {
    if $3; then
        return 0
    fi

    if [ -n "$2" ]; then
         echo $2 | base64 -d
    else
        res=""
        while [ -z "$res" ]; do
            echo
            echo -n "Enter your $1 password: "
            read -s res
        done
        echo $res
    fi
}

get_unique_devices_array() {
    res=""
    print $1
    for dev in $1; do
        if [[ "$res" != *$dev* ]]; then
            res="${res} $dev"
        fi
    done
    echo $res
}

dhst_pass_int="$(acquire_pass "dev-host" $DHST_PASS $nodhst)"
gooim_pass_int="$(acquire_pass "goo.im" $GOOIM_PASS $nogoo)"
xda_pass_int="$(acquire_pass "XDA" $XDA_PASS $noxda)"

. build/envsetup.sh

upload=""
upload_devs=""
for t in $TARGETS; do
    if [ -n "$build_spec" ]; then
        requested=false
        for spec in $build_spec; do
            if [ "$t" == "$spec" ]; then
                requested=true
                break
            fi
        done
        if ! $requested; then
            continue
        fi
    fi

    lunch $t

    TARGET_DEVICE=$(basename $OUT)

    if ! $nobuild; then
        if ! $noclean; then
            rm -r "$OUT"
        fi

        if $recoveryonly; then
            make -j4 recoveryimage || exit 1
        elif $multiromonly; then
            make -j4 multirom_zip || exit 1
        else
            make -j4 recoveryimage multirom_zip || exit 1
        fi
    fi

    if ! $multiromonly; then
        do_auto_patch_increment="false"
        patch="$recovery_patch"
        if [ -z "$patch" ]; then
            do_auto_patch_increment="true"
            patch="00"
        fi

        files="$(RECOVERY_SUBVER="$patch" AUTO_PATCH_INCREMENT="$do_auto_patch_increment" PRINT_FILES="true" mrom_recovery_release.sh)"

        if [ "$?" != "0" ]; then
            echo "mrom_recovery_release.sh failed!"
            exit 1
        fi

        upload="${upload} ${files}"
        # add device for each recovery file
        for f in $files; do
            upload_devs="${upload_devs} ${TARGET_DEVICE}"
        done
    fi

    echo ""
    if ! $recoveryonly; then
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

# convert to array
upload=($upload)
upload_devs=($upload_devs)

if $nodhst && $nogoo; then
    noupload=true
fi

if $noupload; then
    echo "Upload disabled by cmdline args"
else
    echo "Do you want to upload these files to d-h.st and goo.im?"
    for (( i=0; i<${#upload[@]}; i++ )); do
        echo "  ${upload[$i]}"
    done

    if ! $forceupload; then
        echo -n "Upload? [y/N]: "
        read upload_files
    else
        echo "Upload forced, proceeding"
    fi

    if [ "$upload_files" = "y" ] || [ "$upload_files" = "Y" ] || $forceupload; then
        echo

        if ! $nodhst; then
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

        if ! $nogoo; then
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

if $nosync; then
    echo "Sync disabled by cmdline args"
else
    if ! $forcesync; then
        echo -n "Sync files to manager? [y/N]: "
        read upload_files
    else
        echo "Upload forced, proceeding"
    fi

    if [ "$upload_files" = "y" ] || [ "$upload_files" = "Y" ] || $forcesync; then
        mrom_sync.py
    fi
fi

if $noxda; then
    echo "XDA thread update disabled by cmdline args"
else
    if ! $forcexda; then
        echo -n "Update XDA threads? [y/N]: "
        read update_xda
    else
        echo "XDA Update force, proceeding"
        update_xda=true
    fi

    if [ "$update_xda" = "y" ] || [ "$update_xda" = "Y" ]; then
        token=$(dhst_cli.py -l "$DHST_LOGIN" -p "$dhst_pass_int" login)
        if [ "$?" != "0" ]; then
            echo "Failed to log-in to d-h.st"
            exit 1
        fi

        devices="$(get_unique_devices_array "${upload_devs[*]}")"
        for dev in $devices; do
            mrom_update_xda.py -u $XDA_LOGIN -p $xda_pass_int -s "$token" -d $dev
        done
    fi
fi
