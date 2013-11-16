#!/sbin/sh
echo "Extracting tar..."
/tmp/gnutar --numeric-owner -C "/system" -xf /tmp/rom/system.tar.gz
exit $?