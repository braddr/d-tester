#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os

echo -e "\tbuilding dmd"

cd $1/dmd/src

makecmd=make
MODEL=32
PARALLELISM="-j2"
case "$2" in
    Darwin_32)
        makefile=osx.mak
        ;;
    FreeBSD_32)
        makefile=freebsd.mak
        makecmd=gmake
        ;;
    FreeBSD_64)
        makefile=freebsd.mak
        makecmd=gmake
        MODEL=64
        PARALLELISM="-j6"
        ;;
    Linux_32|Linux_64)
        makefile=linux.mak
        ;;
    Win_32)
        makefile=win32.mak
        PARALLELISM=""
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

$makecmd MODEL=$MODEL $PARALLELISM -f $makefile dmd >> ../../dmd-build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to build dmd"
    exit 1;
fi

