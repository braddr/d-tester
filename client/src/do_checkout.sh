#!/bin/sh

#set -x

# this script checks out all the projects to build

# args:
#   1) directory to create and use

svn co http://svn.dsource.org/projects/dmd/trunk $1/dmd-trunk >> $1/checkout.log 2>&1
if [ $? -ne 0 ]; then
    echo "error checking out dmd"
    exit 1
fi

svn co http://svn.dsource.org/projects/druntime/trunk $1/druntime-trunk >> $1/checkout.log 2>&1
if [ $? -ne 0 ]; then
    echo "error checking out druntime"
    exit 1
fi

svn co http://svn.dsource.org/projects/phobos/trunk $1/phobos-trunk >> $1/checkout.log 2>&1
if [ $? -ne 0 ]; then
    echo "error checking out phobos"
    exit 1
fi

