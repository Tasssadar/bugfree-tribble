#!/sbin/sh
fail() {
    echo "Extraction failed!"
    exit 1
}

echo "Extracting system.tar.gz..."
/tmp/gnutar --numeric-owner -C "/system" -xf /tmp/rom/system.tar.gz || fail

if [ -f /tmp/rom/userdata.tar.gz ]; then
    echo "Extracting userdata.tar.gz..."
    /tmp/gnutar --numeric-owner -C "/data" -xf /tmp/rom/userdata.tar.gz || fail
fi
