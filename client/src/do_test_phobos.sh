#!/bin/bash

#set -x

# args:
#    1) directory for build
#    2) os

echo -e "\ttesting phobos"

cd $1/phobos

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

if [ "$2" == "Win_32" ]; then
    make DMD=../dmd/src/dmd DRUNTIME=../druntime MODEL=$MODEL -f $makefile unittest >> ../phobos-unittest.log 2>&1
else
    make DMD=../dmd/src/dmd DRUNTIME_PATH=../druntime MODEL=$MODEL -f $makefile unittest >> ../phobos-unittest.log 2>&1
fi
if [ $? -ne 0 ]; then
    echo -e "\tphobos tests failed"
    exit 1;
fi

