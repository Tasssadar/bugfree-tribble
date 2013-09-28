#!/bin/sh
DEST="/usr/local/bin"
for f in $(ls *.sh *.py); do
    if [ "$1" != "uninstall" ]; then
        echo "link $(pwd)/$f to $DEST/$f"
        ln -s $(pwd)/$f $DEST/$f
    else
        if [ ! -L "$DEST/$f" ]; then
            echo "$DEST/$f does not exists or isn't symbolic link, skipping"
            continue
        fi
        echo "Removing $DEST/$f"
        rm "$DEST/$f"
    fi
done
