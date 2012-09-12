#!/usr/bin/env bash

#set -x

# args:
#    1) directory for build
#    2) os

PARALLELISM=1

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

echo -e "\tgenerating html"

cd $1/phobos

DMD=../dmd/src/dmd
DOC=../web/2.0
MODEL=32

DD=WEBSITE_DIR

makecmd=make
makefile=posix.mak
case "$2" in
    Darwin_32|Darwin_64_32)
        ;;
    Darwin_32_64|Darwin_64_64)
        MODEL=64
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
        DR=DRUNTIME
        makefile=win32.mak
        DD=DOC
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

$makecmd DDOC=$DMD $DD=$DOC DMD=$DMD MODEL=$MODEL -f $makefile html >> ../phobos-html.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tphobos html generation failed"
    exit 1;
fi

