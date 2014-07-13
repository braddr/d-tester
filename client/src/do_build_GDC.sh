#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os

PARALLELISM=1

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

echo -e "\tbuilding GDC"

cd $1/GDC

makecmd=make
makefile=posix.mak
MODEL=32
EXTRA_ARGS="-j$PARALLELISM"
case "$2" in
    Darwin_32*)
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
        exit 1;
esac

#GCC_VER=4.8.1
#GCC_VER=4.9-20130929
#GCC_VER=4.9-20131117
#GCC_VER=4.9-20131201
#GCC_VER=4.10-20140518
#GCC_VER=4.10-20140521
#GCC_VER=4.10-20140608
GCC_VER=4.10-20140629
tar jxf ../../src/gcc-$GCC_VER.tar.bz2 >> ../GDC-build.log 2>&1
./setup-gcc.sh gcc-$GCC_VER >> ../GDC-build.log 2>&1
mkdir output-dir
cd output-dir
../gcc-$GCC_VER/configure --disable-bootstrap --enable-languages=d --prefix=`pwd`/install-dir >> ../../GDC-build.log 2>&1
$makecmd $EXTRA_ARGS >> ../../GDC-build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to build GDC"
    exit 1
fi

