#!/bin/sh

DEST=""
DEV="/dev/video1"
RES="1280x720"
FPS="30"
LED="auto"
ROTATE="0"
FOCUS="auto"

for a in $@; do
    case $a in
        -h|--help)
            echo "TODO"
            exit 0
            ;;
        --dev=*)
            DEV="${a#--dev=}"
            ;;
        --res=*)
            RES="${a#--res=}"
            ;;
        --fps=*)
            FPS="${a#--fps=}"
            ;;
        --led=*)
            LED="${a#--led=}"
            ;;
        --rotate=*)
            ROTATE="${a#--rotate=}"
            ;;
        --soc)
            ROTATE="90"
            LED="off"
            FOCUS="25"
            ;;
        *)
            DEST="$a"
            ;;
    esac
done

res_w="${RES%x*}"
res_h="${RES#*x}"

lib="$LD_LIBRARY_PATH"
if [ -z "${lib##*/usr/local/lib*}" ]; then
    lib="${lib}:/usr/local/lib"
fi

echo "Disabling exposure priority"
v4l2-ctl -d ${DEV} -c exposure_auto_priority=0


led_val="3"
case $LED in
    off)
        led_val="0"
        ;;
    on)
        led_val="1"
        ;;
    blink)
        led_val="2"
        ;;
    *)
        led_val="3"
        ;;
esac
echo "Setting LED to $LED ($led_val)"
v4l2-ctl -d ${DEV} -c led1_mode=$led_val

rotate_cmd_part=""
case $ROTATE in
    0)
        ;;
    90)
        rotate_cmd_part="! videoflip method=clockwise"
        ;;
    180)
        rotate_cmd_part="! videoflip method=rotate-180"
        ;;
    270)
        rotate_cmd_part="! videoflip method=counterclockwise"
        ;;
esac

case $FOCUS in
    auto)
        v4l2-ctl -d ${DEV} -c focus_auto=1
        ;;
    *)
        v4l2-ctl -d ${DEV} -c focus_auto=0
        v4l2-ctl -d ${DEV} -c focus_absolute=${FOCUS}
        ;;
esac

if [ -n "$DEST" ]; then
    LD_LIBRARY_PATH="$lib" gst-launch -ev uvch264_src device=${DEV} name=src auto-start=true src.vfsrc ! queue ! video/x-raw-yuv,width=640,height=480,framerate=30/1 ${rotate_cmd_part} ! timeoverlay auto-resize=false ! xvimagesink sync=false \
    src.vidsrc ! queue ! video/x-h264,width=${res_w},height=${res_h},framerate=${FPS}/1,profile=high ! stamp sync-margin=2 ! h264parse ! queue ! ffmux_mp4 name=mux ! filesink location=\"${DEST}\" sync=true \
    alsasrc device="plughw:1,0" ! audio/x-raw-int,rate=44100,channels=2,depth=32 ! queue ! audioconvert ! queue ! faac ! queue ! mux.
else
    LD_LIBRARY_PATH="$lib" gst-launch -e uvch264_src device=${DEV} name=src auto-start=true src.vidsrc ! queue ! video/x-h264,width=${res_w},height=${res_h},framerate=${FPS}/1,profile=high ! \
    h264parse ! ffdec_h264 ${rotate_cmd_part} ! xvimagesink force-aspect-ratio=true
fi
