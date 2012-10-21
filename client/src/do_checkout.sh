#!/usr/bin/env bash

#set -x

# this script checks out all the projects to build

# args:
#   1) directory to create and use
#   2) os

PARALLELISM=1

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

top=$PWD

echo -e "\tchecking out source trees"

if [ ! -d $top/source ]; then
    mkdir $top/source
fi

echo "Checking out dmd:" >> $top/$1/checkout.log 2>&1
if [ ! -d $top/source/dmd ]; then
    cd $top/source
    git clone https://github.com/D-Programming-Language/dmd.git dmd >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\terror checking out dmd"
        exit 1
    fi
else
    cd $top/source/dmd
    git pull origin >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\terror updating dmd"
        exit 1
    fi
fi
echo "Head commit:" >> $top/$1/checkout.log 2>&1
git log -1 >> $top/$1/checkout.log 2>&1
git clone --shared $top/source/dmd $top/$1/dmd >> $top/$1/checkout.log 2>&1

echo >> $top/$1/checkout.log 2>&1
echo "Checkout out druntime:" >> $top/$1/checkout.log 2>&1
if [ ! -d $top/source/druntime ]; then
    cd $top/source
    git clone https://github.com/D-Programming-Language/druntime.git druntime >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\terror checking out druntime"
        exit 1
    fi
else
    cd $top/source/druntime
    git pull origin >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\terror checking out druntime"
        exit 1
    fi
fi
echo "Head commit:" >> $top/$1/checkout.log 2>&1
git log -1 >> $top/$1/checkout.log 2>&1
git clone --shared $top/source/druntime $top/$1/druntime >> $top/$1/checkout.log 2>&1

echo >> $top/$1/checkout.log 2>&1
echo "Checkout out phobos:" >> $top/$1/checkout.log 2>&1
if [ ! -d $top/source/phobos ]; then
    cd $top/source
    git clone https://github.com/D-Programming-Language/phobos.git phobos >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\terror checking out phobos"
        exit 1
    fi
else
    cd $top/source/phobos
    git pull origin >> $top/$1/checkout.log 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\terror updating phobos"
        exit 1
    fi
fi
echo "Head commit:" >> $top/$1/checkout.log 2>&1
git log -1 >> $top/$1/checkout.log 2>&1
git clone --shared $top/source/phobos $top/$1/phobos >> $top/$1/checkout.log 2>&1

cd $top

