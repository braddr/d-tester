#!/usr/bin/env bash

#set -x

# args:
#    1) directory for build
#    2) os

echo -e "\ttesting dmd"

makecmd=make
MODEL=32
case "$2" in
    Linux_32|Darwin_32)
        ;;
    FreeBSD_32)
        makecmd=gmake
        ;;
    Linux_64)
        MODEL=64
        ;;
    Win_32)
        makecmd=/usr/bin/make
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

cd $1/dmd/test

$makecmd MODEL=$MODEL -j2 >> ../../dmd-unittest.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tdmd tests had failures"
    exit 1;
fi

