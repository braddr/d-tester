#!/bin/bash

#set -x

# args:
#    1) directory for build
#    2) os

cd $1/druntime-trunk

case "$2" in
    Linux_32|Darwin_32|FreeBSD_32)
        makefile=posix.mak
        ;;
    Win32)
        makefile=win32.mak
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

make DMD=../dmd-trunk/src/dmd -f $makefile unittest >> ../druntime-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo "druntime unittest failed to build"
    exit 1;
fi

./unittest >> ../druntime-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo "druntime unittest failed to execute"
    exit 1;
fi

