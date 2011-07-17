#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os

parallelism=1

if [ -f ./tester.cfg ]; then
    . ./tester.cfg
fi

echo -e "\tbuilding dmd"

cd $1/dmd/src

makecmd=make
makefile=posix.mak
MODEL=32
PARALLELISM="-j$parallelism"
case "$2" in
    Darwin_32)
        ;;
    FreeBSD_32)
        makecmd=gmake
        ;;
    FreeBSD_64)
        makecmd=gmake
        MODEL=64
        ;;
    Linux_32*)
        ;;
    Linux_64*)
        MODEL=64
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

