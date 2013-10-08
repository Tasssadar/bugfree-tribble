#!/bin/sh
# based of kernel's scripts/extract-ikconfig

read_version()
{
	tmp1=$(cat $1 | strings | grep 'Linux version ')
	if [ -n "$tmp1" ]; then
		echo $tmp1
		exit 0
	fi
}

try_decompress()
{
	for	pos in `tr "$1\n$2" "\n$2=" < "$img" | grep -abo "^$2"`
	do
		pos=${pos%%:*}
		tail -c+$pos "$img" | $3 > $tmp2 2> /dev/null
		read_version $tmp2
	done
}

# Check invocation:
me=${0##*/}
img=$1
if	[ $# -ne 1 -o ! -s "$img" ]
then
	echo "Usage: $me <kernel-image>" >&2
	exit 2
fi

# Prepare temp files:
tmp1=/tmp/ikconfig$$.1
tmp2=/tmp/ikconfig$$.2
trap "rm -f $tmp1 $tmp2" 0

# Initial attempt for uncompressed images or objects:
read_version "$img"

# That didn't work, so retry after decompression.
try_decompress '\037\213\010' xy    gunzip
try_decompress '\3757zXZ\000' abcde unxz
try_decompress 'BZh'          xy    bunzip2
try_decompress '\135\0\0\0'   xxx   unlzma
try_decompress '\211\114\132' xy    'lzop -d'

# Bail out:
echo "$me: Cannot find kernel version." >&2
exit 1
