#!/bin/bash

# args:
#    1) directory for build
#    2) os

# NOTE: not all changes apply to all OS', but there's no conflicts, so just apply everything

# need a conf files so that dmd can find the imports and libs from within the test
case "$2" in
    Darwin_32)
        cp src/dmd-darwin.conf $1/dmd/src/dmd.conf
        ;;
    FreeBSD_32)
        cp src/dmd-freebsd.conf $1/dmd/src/dmd.conf
        ;;
    Linux_32)
        cp src/dmd-linux.conf $1/dmd/src/dmd.conf
        ;;
    Linux_64)
        cp src/dmd-linux-64.conf $1/dmd/src/dmd.conf
        ;;
    Win_32)
        cp src/sc.ini $1/dmd/src
        ;;
esac


cd $1

# strip off the abs path for dmc and let the path take care of finding it
patch -p0 < ../src/patch-dmd-win32.mak

cd ..

# move minit.obj to be newer than minit.asm
touch $1/druntime/src/rt/minit.obj
