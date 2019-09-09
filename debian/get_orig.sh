#!/bin/bash

DEBIAN_DIR=$(dirname $0)
CUR_DIR=$PWD

read_dom () {
	local IFS=\>
	read -d \< ENTITY CONTENT
	local RET=$?
	TAG_NAME=${ENTITY%% *}
	ATTRIBUTES=${ENTITY#* }
	return $RET
}

UPS_VER=""
UPS_FILE=""
DEB_VER=""
TAG_NAME=""
ATTRIBUTE=""

echo "Checking…"
cd "$DEBIAN_DIR"/../
while read_dom
do
	if [ "$TAG_NAME" = "upstream-version" ]
	then
		UPS_VER="$CONTENT"
	fi
	if [ "$TAG_NAME" = "debian-mangled-uversion" ]
	then
		DEB_VER="$CONTENT"
	fi
	if [ "$TAG_NAME" = "upstream-url" ]
	then
		UPS_FILE="${CONTENT##*/}"
	fi
done < <(uscan --dehs --report)

echo "Debian: $DEB_VER, upstream $UPS_VER"

if [ "$DEB_VER" = "$UPS_VER" ]
then
	echo "same version, no action"
fi

echo upstream looks newer, fetching $UPS_VER
uscan --force-download --destdir "$CUR_DIR"
RET=$?
cd "$CUR_DIR"
if [ ! -f "$UPS_FILE" ]
then	
	echo "uscan should download ${UPS_FILE} but it did not."
	exit 1
fi
if [ ! -f clamav_${UPS_VER}.orig.tar.gz ]
then
	echo "repacking…"
	mk-origtargz --copy --copyright $DEBIAN_DIR/copyright --package clamav -v ${UPS_VER} ${UPS_FILE}
	if [ ! -f clamav_${UPS_VER}.orig.tar.gz ]
	then
		echo "Repacked and I am still missing"
		echo "clamav_${UPS_VER}.orig.tar.gz."
		exit 1
	fi
fi

if [ $RET -eq 1 ]
then
	echo "Seems that you are up-to-date"
	exit 0
fi

if [ $RET -ne 0 ]
then
	echo "uscan terminated with non-zero exit code $RET."
	exit 1
fi

tmpdir="$(mktemp -d repack_dir_XXXXXX)"

mv clamav_${UPS_VER}.orig.tar.gz $tmpdir/clamav-${UPS_VER}.tar.gz
echo "Running split-tarball.sh $tmpdir ${UPS_VER}"
$DEBIAN_DIR/split-tarball.sh $tmpdir ${UPS_VER}
rm -r $tmpdir
