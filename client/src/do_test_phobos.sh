#!/usr/bin/env bash

#set -x

# args:
#    1) directory for build
#    2) os

. src/setup_env.sh "$2"

echo -e "\ttesting phobos"

cd $1/phobos

# TODO: are those two copies needed for the new windows hosts?
case "$2" in
    stub)
        exit 0
        ;;
    Win_32)
        cp ../../../win32libs/dmd2/windows/bin/*.dll .
        ;;
    Win_64)
        cp ../../../win64libs/dmd2/windows/bin/* .
        ;;
esac

$makecmd DMD=../dmd/src/dmd MODEL=$OUTPUT_MODEL $EXTRA_ARGS -f $makefile unittest >> ../phobos-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tphobos tests failed"
    exit 1
fi

