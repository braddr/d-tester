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
    curl --silent "http://d.puremagic.com/test-results/addv2/$1?clientver=4&$2"
}

function detectos
{
    foo=`uname`
    case "$foo" in
        Linux|Darwin|FreeBSD)
            OS=$foo
            ;;
        CYGWIN_NT-5.1|CYGWIN_NT-6.[01]|CYGWIN_NT-6.2-WOW64)
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
# $4 == runmode
function uploadlog
{
    if [ "$runid" != "test" ]; then
        curl --silent -T $2/$3 "http://d.puremagic.com/test-results/addv2/upload_$4?clientver=3&testid=$1"
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

    if [ "$2" == "test-DMD" ]; then
        data=("test" "master" "D-Programming-Language" "$OS")
        data=(${data[@]} "3" "1" "dmd" "master" "2" "druntime" "master" "3" "phobos" "master")
        data=(${data[@]} 1 0)
        #if [ "$runmode" == "pull" ]; then
        #    data=(${data[@]} 9 0 "https://github.com/yebblies/dmd.git" "issue4923")
        #fi
        data=(${data[@]} 2 0 3 1 4 2 5 1 6 2 7 0)
    elif [ "$2" == "test-GDC" ]; then
        data=("test" "master" "D-Programming-GDC" "$OS")
        data=(${data[@]} "1" "13" "GDC" "master")
        data=(${data[@]} 1 0)
        #if [ "$runmode" == "pull" ]; then
        #    # fix
        #    data=(${data[@]} 14 0 "https://github.com/yebblies/dmd.git" "issue4923")
        #fi
        data=(${data[@]} 12 0 13 0)
    else
        data=($(callcurl get_runnable_pull "os=$OS&hostname=`hostname`$extraargs"))
    fi
    runid=${data[0]}

    if [ "x$runid" == "x" -o "x$runid" == "xskip" -o "x$runid" == "xbad" -o "x$runid" == "xunauthorized" -o "x${runid:0:9}" == "x<!DOCTYPE" -o "x${runid:0:17}" == "Unable to dispatch" ]; then
        echo -e -n "Skipping run ($OS)...\r"
        run_rc=2
        return
    fi

    runmode=${data[1]}
    project=${data[2]}
    OS=${data[3]}
    data=(${data[@]:4})

    num_rbs=${data[0]}
    # sets of (repoid reponame branch)
    #repobranches=(1 dmd $branch 2 druntime $branch 3 phobos $branch)
    repobranches=(${data[@]:1:3*$num_rbs})
    steps=(${data[@]:1+3*$num_rbs})

    rundir=$runmode-$runid-$OS

    pretest
    echo -e "\nStarting $runmode run $runid ($OS), project: $project"

    if [ ! -d $rundir ]; then
        mkdir "$rundir"
    fi

    run_rc=0
    while [ $run_rc -eq 0 -a ${#steps[@]} -gt 0 ]; do
        testid=$(callcurl start_${runmode}_test "runid=$runid&type=${steps[0]}")
        reponame=${repobranches[${steps[1]}*3 + 1]}
        case ${steps[0]} in
            1) # checkout
                x=("${repobranches[@]}")
                while [ ${#x[@]} -gt 0 ]; do
                    checkoutRepeat "$rundir" "$OS" "$project" "${x[1]}" "${x[2]}"
                    x=(${x[@]:3})
                done
                src/do_fixup.sh "$rundir" "$OS" "$project"
                step_rc=$?
                logname=checkout.log
                ;;
            2|3|4|12)
                src/do_build_${reponame}.sh "$rundir" "$OS"
                step_rc=$?
                logname=${reponame}-build.log
                ;;
            5|6|7|13)
                src/do_test_${reponame}.sh "$rundir" "$OS" "$runmode"
                step_rc=$?
                logname=${reponame}-unittest.log
                ;;
            9|10|11|14)
                src/do_pull.sh "$rundir" "$OS" "$reponame" "${steps[2]}" "${steps[3]}"
                step_rc=$?
                logname=${reponame}-merge.log
                steps=(${steps[@]:2}) # trim extra fields
                ;;
        esac
        steps=(${steps[@]:2})
        uploadlog $testid $rundir $logname $runmode
        callcurl finish_${runmode}_test "testid=$testid&rc=$step_rc"
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

