#!/bin/bash

# args:
#    1) directory for build
#    2) os

# NOTE: not all changes apply to all OS', but there's no conflicts, so just apply everything

# need a conf files so that dmd can find the imports and libs from within the test
cp src/dmd.conf $1/dmd/src
cp src/sc.ini $1/dmd/src

#cd $1
#patch -p0 < ../src/dmd-libm.patch
#cd ..

# strip off the abs path for dmc and let the path take care of finding it
cd $1
patch -p0 < ../src/patch-dmd-win32.mak
cd ..

# move minit.obj to be newer than minit.asm
touch $1/druntime/src/rt/minit.obj
