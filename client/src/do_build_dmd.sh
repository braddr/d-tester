#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os

. src/setup_env.sh "$2"

if [ "${2:0:7}" == "Darwin_" ]; then
    BINDIR=bin
else
    BINDIR=bin$COMPILER_MODEL
fi

echo -e "\tbuilding dmd"

top=$PWD
cd $1/dmd/src

# expose a prebuilt dmd
HOST_DC=`ls -1 $top/release-build/install/*/$BINDIR/dmd`
echo "HOST_DC=$HOST_DC" >> ../../dmd-build.log 2>&1

$makecmd MODEL=$COMPILER_MODEL HOST_DC=$HOST_DC $EXTRA_ARGS -f $makefile dmd >> ../../dmd-build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to build dmd"
    exit 1
fi

$makecmd MODEL=$COMPILER_MODEL HOST_DC=$HOST_DC $EXTRA_ARGS -f $makefile install >> ../../dmd-build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to install $repo"
    exit 1
fi

