#!/bin/bash

# set -x

# args:
#    1) directory for build
#    2) os

cd $1/druntime

case "$2" in
    Linux_32|Darwin_32|FreeBSD_32)
        makefile=posix.mak
        ;;
    Win_32)
        makefile=win32.mak
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

make DMD=../dmd/src/dmd -f $makefile >> ../druntime-build.log 2>&1
if [ $? -ne 0 ]; then
    echo "druntime failed to build"
    exit 1;
fi

