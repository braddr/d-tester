#!/usr/bin/env bash

# set -x

# this script checks out all the projects to build

# args:
#   1) directory to create and use
#   2) os
#   3) branch to checkout

PARALLELISM=1

# abort transfer if it drops below 1000 bytes per second for a minute
export GIT_HTTP_LOW_SPEED_LIMIT=1000
export GIT_HTTP_LOW_SPEED_TIME=60

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

# NOTE: must be absolute, code below depends on it
top=$PWD

if [ $# != 3 ]; then
    echo -e "\t3 args required: testdir, os, branch"
    exit 1
fi

echo -e "\tchecking out source trees"

if [ ! -d $top/$1 ]; then
    echo -e "\terror, test directory does not exist, quitting"
    exit 1
fi

if [ ! -d $top/source ]; then
    mkdir $top/source
fi

# cleanup non-bare versions if they exist
if [ -d $top/source/dmd ]; then
    rm -rf $top/source/dmd
fi
if [ -d $top/source/druntime ]; then
    rm -rf $top/source/druntime
fi
if [ -d $top/source/phobos ]; then
    rm -rf $top/source/phobos
fi

# 1 == logfile
# 2 == project
# 3 == repo
function update_repo()
{
    if [ ! -d $top/source/$2 ]; then
        echo "Creating source/$2" >> $1
        mkdir $top/source/$2
    fi

    if [ ! -d $top/source/$2/$3.git ]; then
        cd $top/source/$2
        echo "Cloning $2/$3:" >> $1
        git clone --mirror https://github.com/$2/$3.git >> $1 2>&1
        if [ $? -ne 0 ]; then
            echo -e "\terror cloning out $2/$3"
            exit 1
        fi
        cd $top/source/$2/$3.git
        git remote add origin https://github.com/$2/$3.git >> $1 2>&1
    fi

    cd $top/source/$2/$3.git
    echo "Fetching updates to $2/$3:" >> $1
    git remote update >> $1 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\terror updating $2/$3"
        exit 1
    fi

    echo >> $1
    echo >> $1
}

# 1 == logfile
# 2 == project
# 3 == repo
# 4 == branch
# 5 == build dir
function checkout()
{
    cd $top/$5
    echo "Cloning source/$2/$3.git into $5/$3, branch $4" >> $1
    git clone --shared --branch $4 $top/source/$2/$3.git $top/$5/$3 >> $1 2>&1

    cd $top/$5/$3
    echo "Head commit:" >> $1
    git log -1 >> $1 2>&1

    echo >> $1
    echo >> $1
}

logfile=$top/$1/checkout.log

update_repo $logfile D-Programming-Language dmd
update_repo $logfile D-Programming-Language druntime
update_repo $logfile D-Programming-Language phobos

checkout $logfile D-Programming-Language dmd $3 $1
checkout $logfile D-Programming-Language druntime $3 $1
checkout $logfile D-Programming-Language phobos $3 $1

cd $top

