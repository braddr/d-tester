#!/bin/bash

#set -x

# args:
#    1) directory for build

cd $1/druntime-trunk

make DMD=../dmd-trunk/src/dmd -f posix.mak unittest >> ../druntime-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo "druntime unittest failed to build"
    exit 1;
fi

./unittest >> ../druntime-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo "druntime unittest failed to execute"
    exit 1;
fi

