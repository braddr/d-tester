#!/usr/bin/env bash

# set -x

# args:
#    1) directory for build
#    2) os

. src/setup_env.sh "$2"

echo -e "\tbuilding GDC"

cd $1/GDC

#GCC_VER=5-20140831
GCC_VER=`cat gcc.version`
GCC_VER=${GCC_VER#gcc-}

if [ ! -f ../../src/gcc-$GCC_VER.tar.bz2 ]; then
    echo "Downloading gcc-$GCC_VER.tar.bz2 from www.netgull.com gcc mirror"
    curl --silent --output ../../src/gcc-$GCC_VER.tar.bz2 http://www.netgull.com/gcc/snapshots/$GCC_VER/gcc-$GCC_VER.tar.bz2
fi

tar jxf ../../src/gcc-$GCC_VER.tar.bz2 >> ../GDC-build.log 2>&1
./setup-gcc.sh gcc-$GCC_VER >> ../GDC-build.log 2>&1
mkdir output-dir
cd output-dir
../gcc-$GCC_VER/configure --disable-bootstrap --enable-languages=d --prefix=`pwd`/install-dir >> ../../GDC-build.log 2>&1
$makecmd $EXTRA_ARGS >> ../../GDC-build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "\tfailed to build GDC"
    exit 1
fi

