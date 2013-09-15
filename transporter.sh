#!/bin/bash

PORT=9000
if [ $# -lt 1 ]; then
    echo "Usage: $0 ip_address [port]"
    exit 1
fi
if [ $# -gt 1 ]; then
    PORT=$2
fi
gst-launch -v playbin2 uri=rtsp://$1:$PORT/android.dsp uridecodebin0::source::rtpbin0::latency=10
