#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os

parallelism=1

if [ -f ./tester.cfg ]; then
    . ./tester.cfg
fi

echo -e "\tbuilding druntime"

cd $1/druntime

makecmd=make
makefile=posix.mak
MODEL=32
PARALLELISM="-j$parallelism"
case "$2" in
    Darwin_32)
        ;;
    Linux_32|Linux_64_32)
        ;;
    Linux_32_64|Linux_64_64)
        MODEL=64
        ;;
    FreeBSD_32)
        makecmd=gmake
        ;;
    FreeBSD_64)
        makecmd=gmake
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

$makecmd DMD=../dmd/src/dmd MODEL=$MODEL $PARALLELISM -f $makefile >> ../druntime-build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tdruntime failed to build"
    exit 1;
fi

