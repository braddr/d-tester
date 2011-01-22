#!/bin/sh

#set -x

# this script checks out all the projects to build

# args:
#   1) directory to create and use
#   2) os

top=$PWD

if [ ! -d $top/source ]; then
    mkdir $top/source
fi

if [ ! -d $top/source/dmd ]; then
    cd $top/source
    svn co http://svn.dsource.org/projects/dmd/trunk dmd >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo "error checking out dmd"
        exit 1
    fi
else
    cd $top/source/dmd
    svn update >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo "error updating dmd"
        exit 1
    fi
fi
cp -r $top/source/dmd $top/$1/dmd

if [ ! -d $top/source/druntime ]; then
    cd $top/source
    git clone git://github.com/D-Programming-Language/druntime.git druntime >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo "error checking out druntime"
        exit 1
    fi
else
    cd $top/source/druntime
    git fetch origin >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo "error checking out druntime"
        exit 1
    fi
fi
cp -r $top/source/druntime $top/$1/druntime

if [ ! -d $top/source/phobos ]; then
    cd $top/source
    svn co http://svn.dsource.org/projects/phobos/trunk phobos >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo "error checking out phobos"
        exit 1
    fi
else
    cd $top/source/phobos
    svn update >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo "error updating phobos"
        exit 1
    fi
fi
cp -r $top/source/phobos $top/$1/phobos

cd $top

