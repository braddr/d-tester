#!/usr/bin/env bash

#set -x
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
        return;
    fi
    if [ "$runmode" == "trunk" ]; then
        urlsuffix=".ghtml"
    fi
    curl --silent "$serverurl/$1$urlsuffix?$2"
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

# $1 == runid
# $2 == rundir
function dossh
{
    if [ "$1" != "test" ]; then
        ssh dwebsite mkdir $serverlogs/$2
    fi
}

# $1 == runid
# $2 == rundir
# $3 == file
function doscp
{
    if [ "$1" != "test" ]; then
        scp -q $2/$3 dwebsite:$serverlogs/$2
    fi
}

# $1 == OS
# $2 == runid
# $3 == rundir
# if runmode == pull
#   $4 == project (dmd, druntime, phobos)
#   $5 == git url
#   $6 == git ref
function execute_one_test
{
    case "$runmode" in
        trunk)
            s=start_test
            f=finish_test
            ;;
        pull)
            s=start_pull_test
            f=finish_pull_test
            ;;
    esac

    testid=$(callcurl $s "runid=$runid&type=1")
    src/do_checkout.sh "$rundir" "$OS"
    rc=$?
    doscp $runid $rundir checkout.log
    callcurl $f "testid=$testid&rc=$rc"
    if [ $rc -ne 0 ]; then
        run_rc=1
        return
    fi

    src/do_fixup.sh "$rundir" "$OS"
    rc=$?
    doscp $runid $rundir checkout.log
    if [ $rc -ne 0 ]; then
        run_rc=1
        return
    fi

    if [ "$runmode" == "pull" ]; then
        case "$4" in
            dmd)
                typeid=9
                ;;
            druntime)
                typeid=10
                ;;
            phobos)
                typeid=11
                ;;
        esac
        testid=$(callcurl $s "runid=$runid&type=$typeid")
        src/do_pull.sh "$rundir" "$OS" "$4" "$5" "$6"
        rc=$?
        doscp $runid $rundir $4-merge.log
        callcurl $f "testid=$testid&rc=$rc"
        if [ $rc -ne 0 ]; then
            run_rc=1;
            return
        fi
    fi

    testid=$(callcurl $s "runid=$runid&type=2")
    src/do_build_dmd.sh "$rundir" "$OS"
    rc=$?
    doscp $runid $rundir dmd-build.log
    callcurl $f "testid=$testid&rc=$rc"
    if [ $rc -ne 0 ]; then
        run_rc=1
        return
    fi

    testid=$(callcurl $s "runid=$runid&type=3")
    src/do_build_druntime.sh "$rundir" "$OS"
    rc=$?
    doscp $runid $rundir druntime-build.log
    callcurl $f "testid=$testid&rc=$rc"
    if [ $rc -ne 0 ]; then
        run_rc=1
        return
    fi

    testid=$(callcurl $s "runid=$runid&type=4")
    src/do_build_phobos.sh "$rundir" "$OS"
    rc=$?
    doscp $runid $rundir phobos-build.log
    callcurl $f "testid=$testid&rc=$rc"
    if [ $rc -ne 0 ]; then
        run_rc=1
        return
    fi

    testid=$(callcurl $s "runid=$runid&type=5")
    src/do_test_druntime.sh "$rundir" "$OS"
    rc=$?
    doscp $runid $rundir druntime-unittest.log
    callcurl $f "testid=$testid&rc=$rc"
    if [ $rc -ne 0 ]; then
        run_rc=1
        return
    fi

    testid=$(callcurl $s "runid=$runid&type=6")
    src/do_test_phobos.sh "$rundir" "$OS"
    rc=$?
    doscp $runid $rundir phobos-unittest.log
    callcurl $f "testid=$testid&rc=$rc"
    if [ $rc -ne 0 ]; then
        run_rc=1
        return
    fi

    testid=$(callcurl $s "runid=$runid&type=7")
    src/do_test_dmd.sh "$rundir" "$OS" "$runmode"
    rc=$?
    doscp $runid $rundir dmd-unittest.log
    callcurl $f "testid=$testid&rc=$rc"
    if [ $rc -ne 0 ]; then
        run_rc=1
        return
    fi
}

# $1 == OS
# $2 == null or "test" or "force"
#   null: allow the service to determine if the test should run
#   test: do a local only test run
#   force: tell the service to execute a run even if there haven't been changes
#     -- force has no meaning for runmode == pull right now
function runtests
{
    OS=$1

    if [ "$2" == "force" ]; then
        extraargs="&force=1"
    fi

    case "$runmode" in
        trunk)
            if [ "$2" == "test" ]; then
                runid=test
                rundir=test-$OS
            else
                runid=$(callcurl start_run "os=$OS&hostname=`hostname`$extraargs")
                rundir=$runid
            fi
            fr=finish_run
            ;;
        pull)
            data=($(callcurl get_runnable_pull "os=$OS&hostname=`hostname`$extraargs"));
            runid=${data[0]}
            project=${data[1]}
            giturl=${data[2]}
            gitref=${data[3]}
            # note, sha not used
            sha=${data[4]}
            rundir=pull-$runid
            fr=finish_pull_run
            ;;
    esac

    if [ "x$runid" == "xskip" -o "x$runid" == "x" -o "x${runid:0:9}" == "x<!DOCTYPE" -o "x${runid:0:17}" == "Unable to dispatch" ]; then
        echo -e -n "Skipping run ($OS)...\r"
        run_rc=2
        return
    fi

    pretest
    echo -e "\nStarting run $runid ($OS)."
    run_rc=0

    if [ ! -d $rundir ]; then
        mkdir "$rundir"
    fi
    dossh $runid $rundir

    execute_one_test $1 $runid $rundir $project $giturl $gitref
    echo -e "\trun_rc=$run_rc"

    callcurl $fr "runid=$runid"

    if [ -d "$rundir" -a "$runid" != "test" ]; then
        rm -rf "$rundir"
    fi
}

platforms=($(detectos))
runmode=trunk

function pretest
{
    return
}

if [ -f configs/`hostname` ]; then
    . configs/`hostname`
fi

if [ "$1" == "pull" ]; then
    runmode=pull
    shift
fi

case "$runmode" in
    trunk)
        serverurl=http://d.puremagic.com/test-results/add
        serverlogs=/home/dwebsite/test-results
        ;;
    pull)
        serverurl=http://d.puremagic.com/test-results/addv2
        serverlogs=/home/dwebsite/pull-results
        ;;
esac

rc=2
for OS in ${platforms[*]}; do
    runtests $OS $1
    if [ $run_rc -ne 2 ]; then
        rc=0
    fi
done

exit $rc

