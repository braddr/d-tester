#!/usr/bin/env bash

# args:
#    1) directory for build
#    2) os

parallelism=1

if [ -f ./tester.cfg ]; then
    . ./tester.cfg
fi

echo -e "\tapplying fixups to checked out source"

# need a conf files so that dmd can find the imports and libs from within the test
case "$2" in
    Darwin_32)
        cp src/dmd-darwin.conf $1/dmd/src/dmd.conf
        ;;
    FreeBSD_32)
        cp src/dmd-freebsd.conf $1/dmd/src/dmd.conf
        ;;
    FreeBSD_64)
        cp src/dmd-freebsd-64.conf $1/dmd/src/dmd.conf
        ;;
    Linux_32|Linux_64_32)
        cp src/dmd-linux.conf $1/dmd/src/dmd.conf
        ;;
    Linux_32_64|Linux_64_64)
        cp src/dmd-linux-64.conf $1/dmd/src/dmd.conf
        ;;
    Win_32)
        cp src/sc.ini $1/dmd/src

        # move minit.obj to be newer than minit.asm
        touch $1/druntime/src/rt/minit.obj
        ;;
esac

