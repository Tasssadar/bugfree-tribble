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

mediafire_pass_int="$(echo $MEDIAFIRE_PASS | base64 -d)"

echo "Uploading $1 to mediafire..."
token=$(mediafire_cli.py -l "$MEDIAFIRE_LOGIN" -p "$mediafire_pass_int" -k "$API_KEY" -i "$APP_ID" login)
if [ "$?" != "0" ]; then
    echo "Failed to log-in to mediafire"
    exit 1
fi

mediafire_cli.py -t "$token" -d "$2" upload "$1"
if [ "$?" != "0" ]; then
    echo "Failed to upload $u to mediafire!"
    exit 1
fi

echo "Upload was successful"
