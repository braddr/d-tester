#!/bin/bash

#set -x

# args:
#    1) directory for build

cd $1/phobos-trunk/phobos

make DMD=../../dmd-trunk/src/dmd DRUNTIME=../../druntime-trunk -f win32.mak unittest >> ../../phobos-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo "phobos tests failed"
    exit 1;
fi

