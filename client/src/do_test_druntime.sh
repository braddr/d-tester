#!/usr/bin/env bash

#set -x

# args:
#    1) directory for build
#    2) os

echo -e "\ttesting druntime"

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
        makecmd=gmake
        makefile=posix.mak
        ;;
    Win_32)
        makefile=win32.mak
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

$makecmd DMD=../dmd/src/dmd MODEL=$MODEL -f $makefile unittest >> ../druntime-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tdruntime unittest failed to build"
    exit 1;
fi

if [ $2 == "Win_32" ]; then
    ./unittest >> ../druntime-unittest.log 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\tdruntime unittest failed to execute"
        exit 1;
    fi
fi

