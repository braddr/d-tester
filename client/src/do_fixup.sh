#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os
#    3) project

. src/setup_env.sh "$2"

echo -e "\tapplying fixups to checked out source"

# fixups for DMD related build types

if [ "x$3" == "x1" -a "x${2:0:4}" == "Win_" ]; then
    # move minit.obj to be newer than minit.asm
    touch $1/druntime/src/rt/minit.obj

    if [ "$2" == "Win_64" ]; then
        # fix VC path issues
        (cd $1/dmd; patch -p1 < ../../src/diff-dmd-win64.diff)
        (cd $1/druntime; patch -p1 < ../../src/diff-druntime-win64.diff)
        (cd $1/phobos; patch -p1 < ../../src/diff-phobos-win64.diff)
    fi
fi

