#!/bin/bash

#set -x

# args:
#    1) directory for build

cd $1/phobos-trunk/phobos

make DMD=../../dmd-trunk/src/dmd DRUNTIME_PATH=../../druntime-trunk -f posix.mak >> ../../phobos-build.log 2>&1
if [ $? -ne 0 ]; then
    echo "phobos failed to build"
    exit 1;
fi

