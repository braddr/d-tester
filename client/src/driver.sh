#!/bin/bash

set -x
shopt -s extglob

# start_run.ghtml  --> new run id
# start_test.ghtml?runid=##&type=##" --> new test id
# finish_test.ghtml?testid=7&rc=100  --> nothing

function callcurl
{
    curl --silent "http://d.puremagic.com/test-results/add/$1.ghtml?$2"
}

runid=$(callcurl start_run "os=win_32")

echo "runid: $runid"

if [ ! -d $runid ]; then
    mkdir "$runid"
fi
ssh dwebsite mkdir ~/.www/test-results/$runid

testid=$(callcurl start_test "runid=$runid&type=1")
src/do_checkout.sh "$runid"
rc=$?
callcurl finish_test "testid=$testid&rc=$rc"
scp -q $runid/checkout.log dwebsite:~/.www/test-results/$runid
if [ $rc -ne 0 ]; then
    exit 1;
fi

src/do_fixup.sh "$runid"

testid=$(callcurl start_test "runid=$runid&type=2")
src/do_build_dmd.sh "$runid"
build_dmd_rc=$?
callcurl finish_test "testid=$testid&rc=$build_dmd_rc"
scp -q $runid/dmd-build.log dwebsite:~/.www/test-results/$runid

testid=$(callcurl start_test "runid=$runid&type=3")
src/do_build_druntime.sh "$runid"
build_druntime_rc=$?
callcurl finish_test "testid=$testid&rc=$build_druntime_rc"
scp -q $runid/druntime-build.log dwebsite:~/.www/test-results/$runid

testid=$(callcurl start_test "runid=$runid&type=4")
src/do_build_phobos.sh "$runid"
build_phobos_rc=$?
callcurl finish_test "testid=$testid&rc=$build_phobos_rc"
scp -q $runid/phobos-build.log dwebsite:~/.www/test-results/$runid

testid=$(callcurl start_test "runid=$runid&type=5")
src/do_test_druntime.sh "$runid"
test_druntime_rc=$?
callcurl finish_test "testid=$testid&rc=$test_druntime_rc"
scp -q $runid/druntime-unittest.log dwebsite:~/.www/test-results/$runid

testid=$(callcurl start_test "runid=$runid&type=6")
src/do_test_phobos.sh "$runid"
test_phobos_rc=$?
callcurl finish_test "testid=$testid&rc=$test_phobos_rc"
scp -q $runid/phobos-unittest.log dwebsite:~/.www/test-results/$runid

testid=$(callcurl start_test "runid=$runid&type=7")
src/do_test_dmd.sh "$runid"
test_dmd_rc=$?
callcurl finish_test "testid=$testid&rc=$test_dmd_rc"
scp -q $runid/dmd-unittest.log dwebsite:~/.www/test-results/$runid

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

