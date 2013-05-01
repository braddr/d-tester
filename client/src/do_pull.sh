#!/usr/bin/env bash

#set -x

# this script checks out all the projects to build

# args:
#   1) directory to create and use
#   2) os
#   3) project (dmd, druntime, phobos)
#   4) git url
#   5) git ref

PARALLELISM=1

# abort transfer if it drops below 1000 bytes per second for a minute
export GIT_HTTP_LOW_SPEED_LIMIT=1000
export GIT_HTTP_LOW_SPEED_TIME=60

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

top=$PWD

echo -e "\tmerging pull: $3 $4 $5"

cd $top/$1/$3

echo "setting up remote topull -> $4" >> $top/$1/$3-merge.log 2>&1
git remote add topull $4 >> $top/$1/$3-merge.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to setup pull repo"
    exit 1
fi

echo >> $top/$1/$3-merge.log
echo "fetching contents of $4" >> $top/$1/$3-merge.log 2>&1
git fetch topull         >> $top/$1/$3-merge.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to fetch from pull repo"
    exit 1
fi

echo >> $top/$1/$3-merge.log
echo "merging topull/$5" >> $top/$1/$3-merge.log
git merge topull/$5      >> $top/$1/$3-merge.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to merge pull repo"
    exit 1
fi

cd $top
