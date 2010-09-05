#!/bin/bash

# need a conf file so that dmd can find the imports and libs from within the test
cp src/dmd.conf $1/dmd-trunk/src
cp src/sc.ini $1/dmd-trunk/src

# strip off the abs path for dmc and let the path take care of finding it
cd $1
patch -p0 < ../src/patch-dmd-win32.mak
cd ..

# move minit.obj to be newer than minit.asm
touch $1/druntime-trunk/src/rt/minit.obj
