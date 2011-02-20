#!/usr/bin/env bash

# args:
#    1) directory for build
#    2) os

echo -e "\tapplying fixups to checked out source"

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

        # strip off the abs path for dmc and let the path take care of finding it
        cd $1
        patch -p0 < ../src/patch-dmd-win32.mak >> ../$1/checkout.log 2>&1
        cd ..

        # move minit.obj to be newer than minit.asm
        touch $1/druntime/src/rt/minit.obj
        ;;
esac

