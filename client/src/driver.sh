#!/usr/bin/env bash

# set -x
shopt -s extglob

# get_runnable_master_run.ghtml?os=##       --> new run id, optional addition: force=1
# start_master_test.ghtml?runid=##&type=##" --> new test id
# finish_master_test.ghtml?testid=7&rc=100  --> nothing
# finish_master_run.ghtml?runid=##          --> nothing

# $1 == api
# $2 == arguments
function callcurl
{
    if [ "$runid" == "test" ]; then
        return
    fi
    curl --silent "http://d.puremagic.com/test-results/addv2/$1?clientver=2&$2"
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
        curl --silent -T $2/$3 "http://d.puremagic.com/test-results/addv2/upload_$runmode?clientver=2&testid=$1"
    fi
}

# $1 == rundir
# $2 == OS
# $3 == project
# $4 == repository
# $5 == branch
function checkoutRepeat
{
    rc=1
    while [ $rc -ne 0 ]; do
        src/do_checkout.sh "$1" "$2" "$3" "$4" "$5"
        rc=$?
        if [ $rc -ne 0 ]; then
            sleep 60
        fi
    done
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

    if [ "$2" == "test" ]; then
        if [ "$runmode" == "pull" ]; then
            data=("test" "master" "dmd" "https://github.com/yebblies/dmd.git" "issue4923" "unusedsha")
        else
            data=("test" "master")
        fi
    else
        data=($(callcurl get_runnable_$runmode "os=$OS&hostname=`hostname`$extraargs"))
    fi
    runid=${data[0]}
    branch=${data[1]}
    if [ "$runmode" == "pull" ]; then
        repo=${data[2]}
        giturl=${data[3]}
        gitref=${data[4]}
        # note, sha not used
        sha=${data[5]}
    fi

    rundir=$runmode-$runid-$OS
    project=D-Programming-Language
    # pairs of (repo branch)
    repobranches=(dmd $branch druntime $branch phobos $branch)
    # pairs of (type rb_index)
    if [ "$runmode" == "pull" ]; then
        case "$repo" in
            dmd)
                typeid=9
                repoid=0
                ;;
            druntime)
                typeid=10
                repoid=1
                ;;
            phobos)
                typeid=11
                repoid=2
                ;;
        esac
        steps=(1 0 $typeid $repoid 2 0 3 1 4 2 5 1 6 2 7 0)
    else
        steps=(1 0 2 0 3 1 4 2 5 1 6 2 7 0)
    fi

    if [ "x$runid" == "xskip" -o "x$runid" == "x" -o "x${runid:0:9}" == "x<!DOCTYPE" -o "x${runid:0:17}" == "Unable to dispatch" ]; then
        echo -e -n "Skipping run ($OS)...\r"
        run_rc=2
        return
    fi

    pretest
    echo -e "\nStarting run $runid ($OS), project: $project"

    if [ ! -d $rundir ]; then
        mkdir "$rundir"
    fi

    run_rc=0
    while [ $run_rc -eq 0 -a ${#steps[@]} -gt 0 ]; do
        testid=$(callcurl start_${runmode}_test "runid=$runid&type=${steps[0]}")
        case ${steps[0]} in
            1) # checkout
                x=("${repobranches[@]}")
                while [ ${#x[@]} -gt 0 ]; do
                    checkoutRepeat "$rundir" "$OS" "$project" "${x[0]}" "${x[1]}"
                    x=(${x[@]:2})
                done
                src/do_fixup.sh "$rundir" "$OS"
                step_rc=$?
                logname=checkout.log
                ;;
            2|3|4)
                src/do_build_${repobranches[${steps[1]}*2]}.sh "$rundir" "$OS"
                step_rc=$?
                logname=${repobranches[${steps[1]}*2]}-build.log
                ;;
            5|6|7)
                src/do_test_${repobranches[${steps[1]}*2]}.sh "$rundir" "$OS" "$runmode"
                step_rc=$?
                logname=${repobranches[${steps[1]}*2]}-unittest.log
                ;;
            9|10|11)
                src/do_pull.sh "$rundir" "$OS" "$repo" "$giturl" "$gitref"
                step_rc=$?
                logname=${repobranches[${steps[1]}*2]}-merge.log
                ;;
        esac
        uploadlog $testid $rundir $logname
        callcurl finish_${runmode}_test "testid=$testid&rc=$step_rc"
        steps=(${steps[@]:2})
        if [ "$runmode" == "pull" -a $step_rc -ne 0 ]; then
            run_rc=1
        fi
    done

    #testid=$(callcurl start_${runmode}_test "runid=$runid&type=8")
    #src/do_html_phobos.sh "$rundir" "$OS"
    #html_dmd_rc=$?
    #uploadlog $testid $rundir phobos-html.log
    # todo: should be condition on test mode
    #rsync --archive --compress --delete $rundir/phobos/web/2.0 dwebsite:/home/dwebsite/test-results/docs/$OS
    #callcurl finish_${runmode}_test "testid=$testid&rc=$html_dmd_rc"

    callcurl finish_${runmode}_run "runid=$runid"
    echo -e "\trun_rc=$run_rc"

    if [ -d "$rundir" -a "$runid" != "test" ]; then
        rm -rf "$rundir"
    fi
}

platforms=($(detectos))
runmode=master

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

rc=2
for OS in ${platforms[*]}; do
    runtests $OS $1
    if [ $run_rc -ne 2 ]; then
        rc=0
    fi
done

exit $rc

