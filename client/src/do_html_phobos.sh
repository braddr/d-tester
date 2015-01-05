#!/usr/bin/env bash

## TODO: not tested, used, or likely functional

#set -x

# args:
#    1) directory for build
#    2) os

. src/setup_env.sh "$2"

echo -e "\tgenerating html"

cd $1/phobos

DMD=../dmd/src/dmd
DOC=../web/2.0

if [ "${2:0:4}" == "Win_" ]; then
    DD=DOC
else
    DD=WEBSITE_DIR
fi

$makecmd DDOC=$DMD $DD=$DOC DMD=$DMD MODEL=$OUTPUT_MODEL -f $makefile html >> ../phobos-html.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tphobos html generation failed"
    exit 1
fi

