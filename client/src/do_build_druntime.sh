#!/bin/bash

# set -x

# args:
#    1) directory for build
#    2) os

cd $1/druntime

MODEL=32
case "$2" in
    Linux_32|Darwin_32|FreeBSD_32)
        makefile=posix.mak
        ;;
    Linux_64)
        makefile=posix.mak
        MODEL=64
        ;;
    Win_32)
        makefile=win32.mak
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

make DMD=../dmd/src/dmd MODEL=$MODEL -f $makefile >> ../druntime-build.log 2>&1
if [ $? -ne 0 ]; then
    echo "druntime failed to build"
    exit 1;
fi

