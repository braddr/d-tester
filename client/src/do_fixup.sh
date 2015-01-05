#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os
#    3) project

. src/setup_env.sh "$2"

echo -e "\tapplying fixups to checked out source"

case "$3" in
    1)
        # need a conf files so that dmd can find the imports and libs from within the test
        case "$2" in
            Darwin_32|Darwin_64_32)
                cp src/dmd-darwin.conf $1/dmd/src/dmd.conf
                ;;
            Darwin_32_64|Darwin_64_64)
                cp src/dmd-darwin-64.conf $1/dmd/src/dmd.conf
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
            stub)
                ;;
            Win_32)
                cp src/sc$2.ini $1/dmd/src/sc.ini

                # move minit.obj to be newer than minit.asm
                touch $1/druntime/src/rt/minit.obj
                ;;
            Win_64)
                cp src/sc$2.ini $1/dmd/src/sc.ini

                # move minit.obj to be newer than minit.asm
                touch $1/druntime/src/rt/minit.obj

                # fix win64.mak to use right version of VS
                (cd $1/dmd; patch -p1 < ../../src/diff-dmd-win64.diff)
                (cd $1/druntime; patch -p1 < ../../src/diff-druntime-win64.diff)
                (cd $1/phobos; patch -p1 < ../../src/diff-phobos-win64.diff)
                ;;
        esac
        ;;
    2)
        ;;
esac

