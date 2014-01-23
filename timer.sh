#!/bin/sh
if [ $# -ne 1 ] ; then 
    echo "Only one parameter (seconds) expected"
    exit 0
fi

itr=$1
while [ $itr -ge 0 ] ; do
    printf "\r$itr seconds remaining..."
    sleep 1
    itr=$((itr-1))
done
echo ""
echo "Complete"
echo "Timer for $1 seconds have expired" | wall
