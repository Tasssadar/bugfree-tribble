#!/bin/sh

cd /opt/ubuntu-touch/
py_flock /opt/system-image/state/global.lock "./build.sh > \"/opt/build_logs/device-$(date +%Y%m%d-%T).txt\" 2>&1"
exit $?

