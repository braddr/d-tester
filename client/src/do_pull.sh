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
N=3;
for i in `seq 1 $N`; do
    echo "fetching contents of $4 (attempt: $i/$N)" >> $top/$1/$3-merge.log 2>&1
    git fetch topull         >> $top/$1/$3-merge.log 2>&1
    if [ $? -eq 0 ]; then
        break
    fi
    echo -e "\tfailed to fetch from pull repo"
    if [ $i -eq $N ]; then
        exit 1
    fi
    sleep 5
done

echo >> $top/$1/$3-merge.log
echo "merging topull/$5" >> $top/$1/$3-merge.log
git merge topull/$5      >> $top/$1/$3-merge.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to merge pull repo"
    exit 1
fi

cd $top
