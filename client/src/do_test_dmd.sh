#!/bin/bash

#set -x

# args:
#    1) directory for build
#    2) os

cd $1/dmd-trunk/test

/usr/bin/make -j3 quick >> ../../dmd-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo "failed to test dmd"
    exit 1;
fi

