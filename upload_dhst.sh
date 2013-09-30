#!/bin/sh
if [ "$#" != "2" ]; then
    echo "Usage: $0 [file] [destination folder]"
    exit 1
fi

# Include passwords and API things
if [ ! -e ~/mrom_cfg.sh ]; then
    echo "Failed to find ~/mrom_cfg.sh!"
    exit 1
fi

. ~/mrom_cfg.sh

dhst_pass_int="$(echo $DHST_PASS | base64 -d)"

echo "Uploading $1 to d-h.st..."
token=$(dhst_cli.py -l "$DHST_LOGIN" -p "$dhst_pass_int" login)
if [ "$?" != "0" ]; then
    echo "Failed to log-in to d-h.st"
    exit 1
fi

dhst_cli.py -t "$token" -d "$2" upload "$1"
if [ "$?" != "0" ]; then
    echo "Failed to upload $u to d-h.st!"
    exit 1
fi

echo "Upload was successful"
