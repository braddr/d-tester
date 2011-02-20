#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os

echo -e "\tbuilding druntime"

cd $1/druntime

makecmd=make
MODEL=32
case "$2" in
    Linux_32|Darwin_32)
        makefile=posix.mak
        ;;
    Linux_64)
        makefile=posix.mak
        MODEL=64
        ;;
    FreeBSD_32)
        makefile=posix.mak
        makecmd=gmake
        ;;
    Win_32)
        makefile=win32.mak
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

$makecmd DMD=../dmd/src/dmd MODEL=$MODEL -f $makefile >> ../druntime-build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tdruntime failed to build"
    exit 1;
fi

