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

dhst_pass_int="$(echo $DHST_PASS | base64 -d)"
xda_pass_int="$(echo $XDA_PASS | base64 -d)"

echo "Logging in to d-h.st..."
token=$(dhst_cli.py -l "$DHST_LOGIN" -p "$dhst_pass_int" login)
if [ "$?" != "0" ]; then
    echo "Failed to log-in to d-h.st"
    exit 1
fi

mrom_update_xda.py -u $XDA_LOGIN -p $xda_pass_int -s "$token" $devices
