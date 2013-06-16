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

echo -e "\ttesting GDC"

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
    Win_64)
        makecmd=/usr/bin/make
        MODEL=64
        ;;
    *)
        echo "unknown os: $2"
        exit 1;
esac

if [ "$3" == "pull" ]; then
    ARGS="-O -inline -release"
fi

cd $1/GDC/output-dir

$makecmd $EXTRA_ARGS check-d >> ../../GDC-unittest.log 2>&1

if [ $? -ne 0 ]; then
    echo -e "\tGDC tests had failures"
    exit 1;
fi

