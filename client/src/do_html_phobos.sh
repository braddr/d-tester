#!/usr/bin/env bash

#set -x

# args:
#    1) directory for build
#    2) os

echo -e "\tgenerating html"

cd $1/phobos

DMD=../dmd/src/dmd
DOC=../web/2.0
MODEL=32

DD=WEBSITE_DIR

makecmd=make
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
    FreeBSD_64)
        makecmd=gmake
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

$makecmd DDOC=$DMD $DD=$DOC DMD=$DMD MODEL=$MODEL -f $makefile html >> ../phobos-html.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tphobos html generation failed"
    exit 1;
fi

