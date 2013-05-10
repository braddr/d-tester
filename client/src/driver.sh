#!/usr/bin/env bash

# set -x
shopt -s extglob

# start_run.ghtml?os=##              --> new run id, optional addition: force=1
# start_test.ghtml?runid=##&type=##" --> new test id
# finish_test.ghtml?testid=7&rc=100  --> nothing
# finish_run.ghtml?runid=##          --> nothing

# $1 == api
# $2 == arguments
function callcurl
{
    if [ "$runid" == "test" ]; then
        return
    fi
    curl --silent "http://d.puremagic.com/test-results/addv2/$1?$2"
}

function detectos
{
    foo=`uname`
    case "$foo" in
        Linux|Darwin|FreeBSD)
            OS=$foo
            ;;
        CYGWIN_NT-5.1|CYGWIN_NT-6.[01])
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
            exit 1
    esac

    echo $OS
}

# $1 == testid
# $2 == rundir
# $3 == file
function uploadlog
{
    if [ "$runid" != "test" ]; then
        curl --silent -T $2/$3 "http://d.puremagic.com/test-results/addv2/upload_master?testid=$1"
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

    if [ "$2" == "force" ]; then
        extraargs="&force=1"
    fi

    if [ "$2" == "test" ]; then
        runid=test
        rundir=test-$OS
        branch=staging
    else
        data=($(callcurl get_runnable_master "os=$OS&hostname=`hostname`$extraargs"))
        runid=${data[0]}
        data=(${data[@]:1})
        rundir=$runid
        if [ ${#data[*]} != 0 ]; then
            branch=${data[0]}
            data=(${data[@]:1})
        else
            branch=master
        fi
    fi

    if [ "x$runid" == "xskip" -o "x$runid" == "x" -o "x${runid:0:9}" == "x<!DOCTYPE" ]; then
        echo -e -n "Skipping run...\r"
        run_rc=2
        return
    else
        pretest
        echo "Starting run $runid, platform $OS, branch $branch."
    fi

    if [ ! -d $rundir ]; then
        mkdir "$rundir"
    fi

    testid=$(callcurl start_master_test "runid=$runid&type=1")

    rc=1
    while [ $rc -ne 0 ]; do
        src/do_checkout.sh "$rundir" "$OS" "$branch"
        rc=$?
        if [ $rc -ne 0 ]; then
            sleep 60
        fi
    done
    uploadlog $testid $rundir checkout.log
    callcurl finish_master_test "testid=$testid&rc=$rc"
    if [ $rc -eq 0 ]; then

        src/do_fixup.sh "$rundir" "$OS"
        #uploadlog $testid $rundir checkout.log

        testid=$(callcurl start_master_test "runid=$runid&type=2")
        src/do_build_dmd.sh "$rundir" "$OS"
        build_dmd_rc=$?
        uploadlog $testid $rundir dmd-build.log
        callcurl finish_master_test "testid=$testid&rc=$build_dmd_rc"

        testid=$(callcurl start_master_test "runid=$runid&type=3")
        src/do_build_druntime.sh "$rundir" "$OS"
        build_druntime_rc=$?
        uploadlog $testid $rundir druntime-build.log
        callcurl finish_master_test "testid=$testid&rc=$build_druntime_rc"

        testid=$(callcurl start_master_test "runid=$runid&type=4")
        src/do_build_phobos.sh "$rundir" "$OS"
        build_phobos_rc=$?
        uploadlog $testid $rundir phobos-build.log
        callcurl finish_master_test "testid=$testid&rc=$build_phobos_rc"

        testid=$(callcurl start_master_test "runid=$runid&type=5")
        src/do_test_druntime.sh "$rundir" "$OS"
        test_druntime_rc=$?
        uploadlog $testid $rundir druntime-unittest.log
        callcurl finish_master_test "testid=$testid&rc=$test_druntime_rc"

        testid=$(callcurl start_master_test "runid=$runid&type=6")
        src/do_test_phobos.sh "$rundir" "$OS"
        test_phobos_rc=$?
        uploadlog $testid $rundir phobos-unittest.log
        callcurl finish_master_test "testid=$testid&rc=$test_phobos_rc"

        testid=$(callcurl start_master_test "runid=$runid&type=7")
        src/do_test_dmd.sh "$rundir" "$OS"
        test_dmd_rc=$?
        uploadlog $testid $rundir dmd-unittest.log
        callcurl finish_master_test "testid=$testid&rc=$test_dmd_rc"

        #testid=$(callcurl start_master_test "runid=$runid&type=8")
        #src/do_html_phobos.sh "$rundir" "$OS"
        #html_dmd_rc=$?
        #uploadlog $testid $rundir phobos-html.log
        # todo: should be condition on test mode
        #rsync --archive --compress --delete $rundir/phobos/web/2.0 dwebsite:/home/dwebsite/test-results/docs/$OS
        #callcurl finish_master_test "testid=$testid&rc=$html_dmd_rc"

    fi

    callcurl finish_master_run "runid=$runid"

    if [ -d "$rundir" -a "$runid" != "test" ]; then
        rm -rf "$rundir"
    fi

    run_rc=0
}

platforms=($(detectos))
function pretest
{
    return
}

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

rc=2
for OS in ${platforms[*]}; do
    runtests $OS $1
    if [ $run_rc -ne 2 ]; then
        rc=0
    fi
done

exit $rc

