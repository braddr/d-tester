#!/bin/bash

# set -x

# args:
#    1) directory for build

cd $1/druntime-trunk

make DMD=../dmd-trunk/src/dmd -f win32.mak >> ../druntime-build.log 2>&1
if [ $? -ne 0 ]; then
    echo "druntime failed to build"
    exit 1;
fi

