#/bin/bash
if [ $# -ne 1 ] ; then 
    echo "Only one parameter (seconds) expected"
    exit 0
fi

itr=$1
while [ $itr -ge 0 ] ; do
    echo -n -e "\r$itr seconds remaining..."
    sleep 1
    let itr=itr-1
done
echo ""
echo "Complete"
echo "Timer for $1 seconds has expired" | wall
