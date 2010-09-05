#!/bin/bash

#set -x

# args:
#    1) directory for build

cd $1/phobos-trunk/phobos

make DMD=../../dmd-trunk/src/dmd DRUNTIME_PATH=../../druntime-trunk -f posix.mak unittest >> ../../phobos-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo "druntime failed to build"
    exit 1;
fi

