#!/bin/sh
if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

OUTPUTS="LVDS1 VGA1 HDMI1"
OUTPUTS_CNT="3"

# args: [xrandr line] [output]
grep_for_active() {
    echo $1 | grep -E -q "^$2 connected .*[0-9]{1,4}x[0-9]{1,4}\\+.*\\(.*\\).*$" && echo "true" || echo "false"
}

# args: [xrandr line]
grep_for_resolution() {
    echo $1 | grep -E -o "[0-9]{1,4}x[0-9]{1,4}" || echo "0x0"
}

# args: [array] [output] [print to stdout]
search_output_array() {
    array="$1"
    for o in $OUTPUTS; do
        if [ "$2" = "$o" ]; then
            ([ "$3" = "true" ]) && echo ${array%% *}
            ([ ${array%% *} = "true" ]) && return 0 || return 1
        else
            array=${array#* }
        fi
    done

    return 1
}

# args: [output]
is_connected() {
    search_output_array "$connected" "$1"
    return $?
}

# args: [output]
is_active() {
    search_output_array "$active" "$1"
    return $?
}

# args: [output]
get_resolution() {
    echo $(search_output_array "$resolution" "$1" "true")
}

print_vals() {
    echo "connected: $connected"
    echo "active: $active"
    echo "resolutions: $resolution"
}

counter=0
connected=""
active=""
resolution=""

tmp_file=$(mktemp)
xrandr > "$tmp_file"
while read line; do
    for o in $OUTPUTS; do
        # check if line starts with watched output
        ([ "${line##$o*}" ]) && continue
        counter=$((counter+1))

        if [ ! "${line##$o connected*}" ]; then
            connected="${connected}true "
        else
            connected="${connected}false "
        fi

        active="${active}$(grep_for_active "$line" "$o") "
        resolution="${resolution}$(grep_for_resolution "$line") "
    done
done < "$tmp_file"

rm "$tmp_file"

if [ "$counter" != "$OUTPUTS_CNT" ]; then
    echo "counter != OUTPUTS_CNT, something went wrong when reading xrandr!"
    exit 1
fi

print_vals

if is_active "LVDS1"; then
    echo "- LVDS1 active"

    # If VGA1 is connected, try to clone the screen to it, in 1024x768
    if is_connected "VGA1"; then
        if ! is_active "VGA1"; then
            echo "-- Start VGA1"
            xrandr --output LVDS1 --mode "1024x768" --output VGA1 --mode "1024x768"
        else
            echo "-- Stop VGA1" 
            xrandr --output LVDS1 --auto --output VGA1 --off
        fi
    # If HDMI is connected, try to switch to it
    elif is_connected "HDMI1"; then
        if ! is_active "HDMI1"; then
            echo "-- Start HDMI1"
            xrandr --output LVDS1 --off --output HDMI1 --auto
        elif [ "$(get_resolution "HDMI1")" = "1024x768" ] && [ "$(get_resolution "LVDS1")" = "1024x768" ]; then
            echo "-- Stop LVDS1"
            echo "-- Set HDMI1 to auto"
            xrandr --output LVDS1 --off --output HDMI1 --auto
        else
            echo "-- Stop LVDS1"
            xrandr --output LVDS1 --off
        fi
    # If nothing is connected, turn everything else than LVDS1 off and switch to 1024x768 and back
    else
        if [ "$(get_resolution "LVDS1")" = "1366x768" ]; then
            echo "-- setting LVDS1 to 1024x768"
            xrandr --output LVDS1 --mode "1024x768" --output VGA1 --off --output HDMI1 --off
        else
            echo "-- setting LVDS1 to auto"
            xrandr --output LVDS1 --auto --output VGA1 --off --output HDMI1 --off
        fi
    fi
else
    echo "- LVDS1 inactive"

    # If HDMI1 is active, stop it and switch to LVDS1
    if is_active "HDMI1"; then
        echo "-- Stop HDMI1"
        xrandr --output LVDS1 --auto --output HDMI1 --off
    # If everything is inactive, turn on LVDS1 and switch everything else off
    elif ! is_active "HDMI1" && ! is_active "VGA1"; then
        echo "-- Activating LVDS1"
        xrandr --output LVDS1 --auto --output VGA1 --off --output HDMI1 --off
    fi
fi
