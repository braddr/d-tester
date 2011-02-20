#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os

echo -e "\tbuilding dmd"

cd $1/dmd/src

makecmd=make
case "$2" in
    Darwin_32)
        makefile=osx.mak
        ;;
    FreeBSD_32)
        makefile=freebsd.mak
        makecmd=gmake
        ;;
    Linux_32|Linux_64)
        makefile=linux.mak
        ;;
    Win_32)
        makefile=win32.mak
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

$makecmd -f $makefile dmd >> ../../dmd-build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to build dmd"
    exit 1;
fi

