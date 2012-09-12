#!/usr/bin/env bash

#set -x

# args:
#    1) directory for build
#    2) os
#    3) runmode (trunk, pull)

PARALLELISM=1

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

echo -e "\ttesting dmd"

makecmd=make
MODEL=32
EXTRA_ARGS="-j$PARALLELISM"
case "$2" in
    Darwin_32|Darwin_64_32)
        ;;
    Darwin_32_64|Darwin_64_64)
        MODEL=64
        ;;
    FreeBSD_32)
        makecmd=gmake
        ;;
    FreeBSD_64)
        makecmd=gmake
        MODEL=64
        ;;
    Linux_32|Linux_64_32)
        ;;
    Linux_32_64|Linux_64_64)
        MODEL=64
        ;;
    Win_32)
        makecmd=/usr/bin/make
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

if [ "$3" == "pull" ]; then
    ARGS="-O -inline -release"
fi

cd $1/dmd/test

$makecmd MODEL=$MODEL test_results/d_do_test >> ../../dmd-unittest.log 2>&1
if [ ! -z "$ARGS" ]; then
    $makecmd MODEL=$MODEL $EXTRA_ARGS ARGS="$ARGS" >> ../../dmd-unittest.log 2>&1
else
    $makecmd MODEL=$MODEL $EXTRA_ARGS >> ../../dmd-unittest.log 2>&1
fi

if [ $? -ne 0 ]; then
    echo -e "\tdmd tests had failures"
    exit 1;
fi

