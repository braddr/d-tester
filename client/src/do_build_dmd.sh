#!/bin/bash

# set -x

# args:
#    1) directory for build
#    2) os

cd $1/dmd-trunk/src

case "$2" in
    Linux_32)
        makefile=linux.mak
        ;;
    Darwin_32)
        makefile=osx.mak
        ;;
    FreeBSD_32)
        makefile=freebsd.mak
        ;;
    Win32)
        makefile=win32.mak
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

make -f $makefile dmd >> ../../dmd-build.log 2>&1
if [ $? -ne 0 ]; then
    echo "failed to build dmd"
    exit 1;
fi

