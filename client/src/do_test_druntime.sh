#!/usr/bin/env bash

#set -x

# args:
#    1) directory for build
#    2) os

. src/setup_env.sh "$2"

echo -e "\ttesting druntime"

cd $1/druntime

if [ "$2" == "stub" ]; then
    exit 0
fi

$makecmd DMD=../dmd/src/dmd MODEL=$OUTPUT_MODEL $EXTRA_ARGS -f $makefile unittest >> ../druntime-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tdruntime unittest failed to build"
    exit 1
fi
