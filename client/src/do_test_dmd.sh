#!/bin/bash

#set -x

# args:
#    1) directory for build
#    2) os

cd $1/dmd/test

/usr/bin/make -j2 >> ../../dmd-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo "failed to test dmd"
    exit 1;
fi

