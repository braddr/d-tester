#!/bin/bash

set -x
shopt -s extglob

# start_run.ghtml                    --> new run id
# start_test.ghtml?runid=##&type=##" --> new test id
# finish_test.ghtml?testid=7&rc=100  --> nothing
# finish_run.ghtml?runid=##          --> nothing

function callcurl
{
    if [ "$runid" == "test" ]; then
        return;
    fi
    curl --silent "http://d.puremagic.com/test-results/add/$1.ghtml?$2"
}

foo=`uname`
case "$foo" in
    Linux|Darwin|FreeBSD)
        OS=$foo
        ;;
    CYGWIN_NT-5.1)
        OS=Win
        ;;
    *)
        echo "unknown os ($foo), aborting"
        exit 1
        ;;
esac

foo=`uname -m`
case "$foo" in
    i[3456]86)
        OS=${OS}_32
        ;;
    x86_64)
        OS=${OS}_64
        ;;
    *)
        echo "unknown machine ($foo), aborting"
        exit 1;
esac

if [ "$1" == "test" ]; then
    runid=test
else
    runid=$(callcurl start_run "os=$OS")
fi

echo "runid: $runid"

if [ ! -d $runid ]; then
    mkdir "$runid"
fi
ssh dwebsite mkdir ~/.www/test-results/$runid

testid=$(callcurl start_test "runid=$runid&type=1")
src/do_checkout.sh "$runid" "$OS"
rc=$?
scp -q $runid/checkout.log dwebsite:~/.www/test-results/$runid
callcurl finish_test "testid=$testid&rc=$rc"
if [ $rc -ne 0 ]; then
    callcurl finish_run "runid=$runid"
    exit 1;
fi

src/do_fixup.sh "$runid" "$OS"

testid=$(callcurl start_test "runid=$runid&type=2")
src/do_build_dmd.sh "$runid" "$OS"
build_dmd_rc=$?
scp -q $runid/dmd-build.log dwebsite:~/.www/test-results/$runid
callcurl finish_test "testid=$testid&rc=$build_dmd_rc"

testid=$(callcurl start_test "runid=$runid&type=3")
src/do_build_druntime.sh "$runid" "$OS"
build_druntime_rc=$?
scp -q $runid/druntime-build.log dwebsite:~/.www/test-results/$runid
callcurl finish_test "testid=$testid&rc=$build_druntime_rc"

testid=$(callcurl start_test "runid=$runid&type=4")
src/do_build_phobos.sh "$runid" "$OS"
build_phobos_rc=$?
scp -q $runid/phobos-build.log dwebsite:~/.www/test-results/$runid
callcurl finish_test "testid=$testid&rc=$build_phobos_rc"

testid=$(callcurl start_test "runid=$runid&type=5")
src/do_test_druntime.sh "$runid" "$OS"
test_druntime_rc=$?
scp -q $runid/druntime-unittest.log dwebsite:~/.www/test-results/$runid
callcurl finish_test "testid=$testid&rc=$test_druntime_rc"

testid=$(callcurl start_test "runid=$runid&type=6")
src/do_test_phobos.sh "$runid" "$OS"
test_phobos_rc=$?
scp -q $runid/phobos-unittest.log dwebsite:~/.www/test-results/$runid
callcurl finish_test "testid=$testid&rc=$test_phobos_rc"

testid=$(callcurl start_test "runid=$runid&type=7")
src/do_test_dmd.sh "$runid" "$OS"
test_dmd_rc=$?
scp -q $runid/dmd-unittest.log dwebsite:~/.www/test-results/$runid
callcurl finish_test "testid=$testid&rc=$test_dmd_rc"

callcurl finish_run "runid=$runid"

# gather results for publication

# TODO: figure out how to get the right revision ids
# TODO: include in test db?

# dmdrev=`grep "Checked out revision" $runid/dmd-checkout.log | tail -1`
# dmdrev=${dmdrev#Checked out revision }
# dmdrev=${dmdrev%.}
# 
# druntimerev=`grep "Checked out revision" $runid/druntime-checkout.log | tail -1`
# druntimerev=${druntimerev#Checked out revision }
# druntimerev=${druntimerev%.}
# 
# phobosrev=`grep "Checked out revision" $runid/phobos-checkout.log | tail -1`
# phobosrev=${phobosrev#Checked out revision }
# phobosrev=${phobosrev%.}
# 
# echo "Tests based on:"
# echo "  dmd      : $dmdrev"
# echo "  druntime : $druntimerev"
# echo "  phobos   : $phobosrev"
# echo
# echo "Build results:"
# echo "  dmd      : $build_dmd_rc"
# echo "  druntime : $build_druntime_rc"
# echo "  phobos   : $build_phobos_rc"
# echo
# echo "Test results:"
# echo "  dmd      : $test_dmd_rc"
# echo "  druntime : $test_druntime_rc"
# echo "  phobos   : $test_phobos_rc"

