#!/bin/bash

#set -x

# args:
#    1) directory for build
#    2) os

cd $1/phobos/phobos

DMD=../../dmd/src/dmd
DRUNTIME=../../druntime
DOC=../web/2.0
MODEL=32

DR=DRUNTIME_PATH
DD=WEBSITE_DIR

case "$2" in
    Linux_32|Darwin_32|FreeBSD_32)
        makefile=posix.mak
        ;;
    Linux_64)
        makefile=posix.mak
        MODEL=64
        ;;
    Win_32)
        DR=DRUNTIME
        makefile=win32.mak
        DD=DOC
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

make DDOC=$DMD $DD=$DOC DMD=$DMD $DR=$DRUNTIME MODEL=$MODEL -f $makefile html >> ../../phobos-html.log 2>&1
if [ $? -ne 0 ]; then
    echo "phobos html generation failed"
    exit 1;
fi

