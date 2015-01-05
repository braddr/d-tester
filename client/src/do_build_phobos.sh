#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os

. src/setup_env.sh "$2"

echo -e "\tbuilding phobos"

cd $1/phobos

$makecmd DMD=../dmd/src/dmd MODEL=$OUTPUT_MODEL $EXTRA_ARGS -f $makefile >> ../phobos-build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tphobos failed to build"
    exit 1
fi

$makecmd DMD=../dmd/src/dmd MODEL=$OUTPUT_MODEL $EXTRA_ARGS -f $makefile install >> ../phobos-build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to install $repo"
    exit 1
fi

