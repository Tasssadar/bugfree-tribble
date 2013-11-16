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

for f in $(ls *.c); do
    bin=$(basename $f .c)
    if [ "$1" != "uninstall" ]; then
        echo "Building $(pwd)/$f to $DEST/$bin"
        gcc $f -o "$DEST/$bin"
    else
        if [ ! -f "$DEST/$bin" ]; then
            echo "$DEST/$bin does not exists"
            continue
        fi
        echo "Removing $DEST/$bin"
        rm "$DEST/$bin"
    fi
done
