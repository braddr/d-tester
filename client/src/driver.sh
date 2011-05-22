#!/usr/bin/env bash

# set -x
shopt -s extglob

# start_run.ghtml                    --> new run id
# start_test.ghtml?runid=##&type=##" --> new test id
# finish_test.ghtml?testid=7&rc=100  --> nothing
# finish_run.ghtml?runid=##          --> nothing

# $1 == api
# $2 == arguments
function callcurl
{
    if [ "$runid" == "test" ]; then
        return;
    fi
    curl --silent "http://d.puremagic.com/test-results/add/$1.ghtml?$2"
}

function detectos
{
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
        x86_64|amd64)
            OS=${OS}_64
            ;;
        *)
            echo "unknown machine ($foo), aborting"
            exit 1;
    esac

    echo $OS
}

# $1 == runid
# $2 == rundir
function dossh
{
    if [ "$1" != "test" ]; then
        ssh dwebsite mkdir /home/dwebsite/test-results/$2
    fi
}

# $1 == runid
# $2 == rundir
# $3 == file
function doscp
{
    if [ "$1" != "test" ]; then
        scp -q $2/$3 dwebsite:/home/dwebsite/test-results/$2
    fi
}

# $1 == OS
# $2 == null or "test" or "force"
#   null: allow the service to determine if the test should run
#   test: do a local only test run
#   force: tell the service to execute a run even if there haven't been changes
function runtests
{
    OS=$1

    if [ "$2" == "test" ]; then
        runid=test
        rundir=test-$OS
    elif [ "$2" == "force" ]; then
        runid=$(callcurl start_run "os=$OS&force=1")
        rundir=$runid
    else
        runid=$(callcurl start_run "os=$OS")
        rundir=$runid
    fi

    if [ "x$runid" == "xskip" -o "x$runid" == "x" -o "x${runid:0:10}" == "x<!DOCTYPE" ]; then
        echo -e -n "Skipping run...\r"
        run_rc=2
        return
    else
        echo "Starting run $runid."
    fi

    if [ ! -d $rundir ]; then
        mkdir "$rundir"
    fi
    dossh $runid $rundir

    testid=$(callcurl start_test "runid=$runid&type=1")
    src/do_checkout.sh "$rundir" "$OS"
    rc=$?
    doscp $runid $rundir checkout.log
    callcurl finish_test "testid=$testid&rc=$rc"
    if [ $rc -eq 0 ]; then

        src/do_fixup.sh "$rundir" "$OS"
        doscp $runid $rundir checkout.log

        testid=$(callcurl start_test "runid=$runid&type=2")
        src/do_build_dmd.sh "$rundir" "$OS"
        build_dmd_rc=$?
        doscp $runid $rundir dmd-build.log
        callcurl finish_test "testid=$testid&rc=$build_dmd_rc"

        testid=$(callcurl start_test "runid=$runid&type=3")
        src/do_build_druntime.sh "$rundir" "$OS"
        build_druntime_rc=$?
        doscp $runid $rundir druntime-build.log
        callcurl finish_test "testid=$testid&rc=$build_druntime_rc"

        testid=$(callcurl start_test "runid=$runid&type=4")
        src/do_build_phobos.sh "$rundir" "$OS"
        build_phobos_rc=$?
        doscp $runid $rundir phobos-build.log
        callcurl finish_test "testid=$testid&rc=$build_phobos_rc"

        testid=$(callcurl start_test "runid=$runid&type=5")
        src/do_test_druntime.sh "$rundir" "$OS"
        test_druntime_rc=$?
        doscp $runid $rundir druntime-unittest.log
        callcurl finish_test "testid=$testid&rc=$test_druntime_rc"

        testid=$(callcurl start_test "runid=$runid&type=6")
        src/do_test_phobos.sh "$rundir" "$OS"
        test_phobos_rc=$?
        doscp $runid $rundir phobos-unittest.log
        callcurl finish_test "testid=$testid&rc=$test_phobos_rc"

        testid=$(callcurl start_test "runid=$runid&type=7")
        src/do_test_dmd.sh "$rundir" "$OS"
        test_dmd_rc=$?
        doscp $runid $rundir dmd-unittest.log
        callcurl finish_test "testid=$testid&rc=$test_dmd_rc"

        #testid=$(callcurl start_test "runid=$runid&type=8")
        #src/do_html_phobos.sh "$rundir" "$OS"
        #html_dmd_rc=$?
        #doscp $runid $rundir phobos-html.log
        # todo: should be condition on test mode
        #rsync --archive --compress --delete $rundir/phobos/web/2.0 dwebsite:/home/dwebsite/test-results/docs/$OS
        #callcurl finish_test "testid=$testid&rc=$html_dmd_rc"

    fi

    callcurl finish_run "runid=$runid"

    if [ -d "$rundir" -a "$runid" != "test" ]; then
        rm -rf "$rundir"
    fi

    run_rc=0
}

OS=$(detectos)

if [ $OS == "Linux_64" ]; then
    runtests Linux_64_64 $1
    rc1=$run_rc
    runtests Linux_32_64 $1
    rc2=$run_rc
    runtests Linux_64_32 $1
    rc3=$run_rc

    if [ $rc1 -eq 2 -a $rc2 -eq 2 -a $rc3 -eq 2 ]; then
        exit 2
    fi
else
    runtests $OS $1
    if [ $run_rc -eq 2 ]; then
        exit 2
    fi
fi

