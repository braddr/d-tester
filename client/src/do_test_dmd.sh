#!/bin/bash

#set -x

# args:
#    1) directory for build

cd $1/dmd-trunk/test

make quick >> ../../dmd-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo "failed to test dmd"
    exit 1;
fi

