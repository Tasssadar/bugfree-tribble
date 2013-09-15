#!/bin/sh

if [ "$1" == "--help" ]; then
    echo "$0 [on/off]"
    echo "    toggle AMD gpu power state"
    exit 0
elif [ "$1" == "on" ]; then
    echo "\_SB.PCI0.PEG0.PEGP._ON" > /proc/acpi/call
else
    echo "\_SB.PCI0.PEG0.PEGP._OFF" > /proc/acpi/call
fi

if [ "$?" != "0" ]; then
    echo "Failed to switch, maybe you're not root?"
    exit 1
else
    echo "Success!"
    exit 0
fi
