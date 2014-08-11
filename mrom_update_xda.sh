#!/bin/sh
devices=""
for a in $@; do
    case $a in
        -h|--help)
            echo "$0 [device=*dev*]"
            exit 0
            ;;
        device=*)
            devices="${devices} -d ${a#device=}"
            ;;
    esac
done

# Include passwords and API things
if [ ! -e ~/mrom_cfg.sh ]; then
    echo "Failed to find ~/mrom_cfg.sh!"
    exit 1
fi

. ~/mrom_cfg.sh

basket_pass_int="$(echo $BASKET_PASS | base64 -d)"
xda_pass_int="$(echo $XDA_PASS | base64 -d)"

mrom_update_xda.py -u $XDA_LOGIN -p $xda_pass_int --basket-login=$BASKET_LOGIN --basket-pass=$basket_pass_int $devices
