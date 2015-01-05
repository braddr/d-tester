#!/usr/bin/env bash

#set -x

# args:
#    1) directory for build
#    2) os
#    3) runmode (trunk, pull)

. src/setup_env.sh "$2"

echo -e "\ttesting GDC"

if [ "$3" == "pull" ]; then
    ARGS="-O -inline -release"
fi

cd $1/GDC/output-dir

$makecmd $EXTRA_ARGS check-d >> ../../GDC-unittest.log 2>&1

if [ $? -ne 0 ]; then
    echo -e "\tGDC tests had failures"
    exit 1;
fi

