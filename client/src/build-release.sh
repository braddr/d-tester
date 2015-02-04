#!/usr/bin/env bash

# set -x

builddir=release-build

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

if [ -d $builddir ]; then
    rm -rf $builddir
fi

if [ ! -d $builddir ]; then
    mkdir $builddir
fi

function abort
{
    echo "step failed, aborting"
    exit 1
}

top=$PWD

owner="D-Programming-Language"
branch="auto-tester-testing"

for platform in ${platforms[@]}; do
    for repo in "dmd" "druntime" "phobos"; do
        if [ -d $top/$builddir/$repo ]; then
            rm -r $top/$builddir/$repo
        fi
        rm -f $top/$builddir/*$repo*.log

        src/do_checkout.sh "$builddir" "$platform" "$owner" "$repo" "$branch"
    done

    src/do_fixup.sh "$builddir" "$platform" "1"

    for repo in "dmd" "druntime" "phobos"; do
        if [ "$?" -ne 0 ]; then
            abort
        fi
        src/do_build_$repo.sh "$builddir" "$platform" 
        if [ "$?" != 0 ]; then
            abort
        fi
    done
done

