#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os

PARALLELISM=1

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

echo -e "\tbuilding compiler"

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

tar jxf ../../src/gcc-4.8.0.tar.bz2
./setup-gcc.sh gcc-4.8.0
mkdir output-dir
cd output-dir
../gcc-4.8.0/configure --disable-bootstrap --enable-languages=d --prefix=`pwd`/install-dir
make
if [ $? -ne 0 ]; then
    echo -e "\tfailed to build compiler"
    exit 1
fi

