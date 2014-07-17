#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os

PARALLELISM=1

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

echo -e "\tbuilding dmd"

top=$PWD
cd $1/dmd/src

# expose temporary hack to make a dmd compiler available
export PATH=$PATH:$top/master-test-$2/dmd/src
which dmd >> ../../dmd-build.log 2>&1

makecmd=make
makefile=posix.mak
MODEL=32
EXTRA_ARGS="-j$PARALLELISM"
case "$2" in
    Darwin_32*)
        MODEL=64
        ;;
    Darwin_64*)
        MODEL=64
        ;;
    FreeBSD_32)
        makecmd=gmake
        ;;
    FreeBSD_64)
        makecmd=gmake
        MODEL=64
        ;;
    Linux_32*)
        ;;
    Linux_64*)
        MODEL=64
        ;;
    stub)
        ;;
    Win_32)
        makefile=win32.mak
        EXTRA_ARGS=""
        ;;
    Win_64)
        makefile=win32.mak
        EXTRA_ARGS=""
        ;;
    *)
        echo "unknown os: $2"
        exit 1
esac

$makecmd MODEL=$MODEL $EXTRA_ARGS -f $makefile dmd >> ../../dmd-build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to build dmd"
    exit 1
fi

