#!/usr/bin/env bash

# set -x

# args:
#   1) os

PARALLELISM=1

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

makecmd=make
makefile=posix.mak
COMPILER_MODEL=32
OUTPUT_MODEL=32
EXTRA_ARGS="-j$PARALLELISM"
EXE=""

case "$1" in
    Darwin_32)
        ;;
    Darwin_32_64)
        OUTPUT_MODEL=64
        ;;
    Darwin_64_32)
        COMPILER_MODEL=64
        ;;
    Darwin_64_64)
        COMPILER_MODEL=64
        OUTPUT_MODEL=64
        ;;
    FreeBSD_32)
        makecmd=gmake
        ;;
    FreeBSD_64)
        makecmd=gmake
        COMPILER_MODEL=64
        OUTPUT_MODEL=64
        ;;
    Linux_32)
        ;;
    Linux_32_64)
        OUTPUT_MODEL=64
        ;;
    Linux_64_32)
        COMPILER_MODEL=64
        ;;
    Linux_64_64)
        COMPILER_MODEL=64
        OUTPUT_MODEL=64
        ;;
    stub)
        ;;
    Win_32)
        makefile=win32.mak
        EXTRA_ARGS=""
        EXE=.exe
        ;;
    Win_64)
        makefile=win32.mak
        EXTRA_ARGS=""
        EXE=.exe
        OUTPUT_MODEL=64
        ;;
    *)
        echo "unknown os: $1"
        exit 1;
esac

