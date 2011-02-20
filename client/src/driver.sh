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
    CYGWIN_NT-5.1|CYGWIN_NT-6.1)
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

if [ "x$runid" == "xskip" ]; then
    echo "Skipping run..."
    exit 2
fi

if [ ! -d $runid ]; then
    mkdir "$runid"
fi
ssh dwebsite mkdir /home/dwebsite/test-results/$runid

testid=$(callcurl start_test "runid=$runid&type=1")
src/do_checkout.sh "$runid" "$OS"
rc=$?
scp -q $runid/checkout.log dwebsite:/home/dwebsite/test-results/$runid
callcurl finish_test "testid=$testid&rc=$rc"
if [ $rc -eq 0 ]; then

    src/do_fixup.sh "$runid" "$OS"

    testid=$(callcurl start_test "runid=$runid&type=2")
    src/do_build_dmd.sh "$runid" "$OS"
    build_dmd_rc=$?
    scp -q $runid/dmd-build.log dwebsite:/home/dwebsite/test-results/$runid
    callcurl finish_test "testid=$testid&rc=$build_dmd_rc"

    testid=$(callcurl start_test "runid=$runid&type=3")
    src/do_build_druntime.sh "$runid" "$OS"
    build_druntime_rc=$?
    scp -q $runid/druntime-build.log dwebsite:/home/dwebsite/test-results/$runid
    callcurl finish_test "testid=$testid&rc=$build_druntime_rc"

    testid=$(callcurl start_test "runid=$runid&type=4")
    src/do_build_phobos.sh "$runid" "$OS"
    build_phobos_rc=$?
    scp -q $runid/phobos-build.log dwebsite:/home/dwebsite/test-results/$runid
    callcurl finish_test "testid=$testid&rc=$build_phobos_rc"

    testid=$(callcurl start_test "runid=$runid&type=5")
    src/do_test_druntime.sh "$runid" "$OS"
    test_druntime_rc=$?
    scp -q $runid/druntime-unittest.log dwebsite:/home/dwebsite/test-results/$runid
    callcurl finish_test "testid=$testid&rc=$test_druntime_rc"

    testid=$(callcurl start_test "runid=$runid&type=6")
    src/do_test_phobos.sh "$runid" "$OS"
    test_phobos_rc=$?
    scp -q $runid/phobos-unittest.log dwebsite:/home/dwebsite/test-results/$runid
    callcurl finish_test "testid=$testid&rc=$test_phobos_rc"

    testid=$(callcurl start_test "runid=$runid&type=7")
    src/do_test_dmd.sh "$runid" "$OS"
    test_dmd_rc=$?
    scp -q $runid/dmd-unittest.log dwebsite:/home/dwebsite/test-results/$runid
    callcurl finish_test "testid=$testid&rc=$test_dmd_rc"

    #testid=$(callcurl start_test "runid=$runid&type=8")
    #src/do_html_phobos.sh "$runid" "$OS"
    #html_dmd_rc=$?
    #scp -q $runid/phobos-html.log dwebsite:/home/dwebsite/test-results/$runid
    #rsync --archive --compress --delete $runid/phobos/web/2.0 dwebsite:/home/dwebsite/test-results/docs/$OS
    #callcurl finish_test "testid=$testid&rc=$html_dmd_rc"

fi

callcurl finish_run "runid=$runid"

if [ -d "$runid" -a "$runid" != "test" ]; then
    rm -rf "$runid"
fi

