#!/bin/bash

# set -x

# args:
#    1) directory for build

cd $1/dmd-trunk/src

make -f win32.mak dmd >> ../../dmd-build.log 2>&1
if [ $? -ne 0 ]; then
    echo "failed to build dmd"
    exit 1;
fi

