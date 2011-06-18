#!/usr/bin/env bash

#set -x

# args:
#    1) directory for build
#    2) os

echo -e "\ttesting phobos"

cd $1/phobos

makecmd=make
makefile=posix.mak
MODEL=32
case "$2" in
    Darwin_32)
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
        makefile=win32.mak
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

$makecmd DMD=../dmd/src/dmd MODEL=$MODEL -f $makefile unittest >> ../phobos-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tphobos tests failed"
    exit 1;
fi

