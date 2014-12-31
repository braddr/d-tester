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

    trycount=0
    sleepdur=1
    rc=1
    while [ $rc -ne 0 ]; do
        curloutput=`timelimit -q -p -t 30 curl --silent --fail "https://auto-tester.puremagic.com/addv2/$1?clientver=5&$2"`
        rc=$?
        if [ $rc -ne 0 ]; then
            echo -e "\tcurl failed, rc=$rc, retrying in $sleepdur seconds..." 1>&2
            sleep $sleepdur
            trycount=$(expr $trycount + 1)
            sleepdur=$(expr $sleepdur \* 2)
            if [ $sleepdur -gt 120 ]; then
                sleepdur=120
            fi
        fi
    done
    if [ -n "$curloutput" ]; then
        echo "$curloutput"
    fi
}

# $1 == testid
# $2 == rundir
# $3 == file
# $4 == runmode
function uploadlog
{
    if [ "$runid" == "test" ]; then
        return
    fi

    trycount=0
    sleepdur=1
    rc=1
    while [ $rc -ne 0 ]; do
        curloutput=`timelimit -q -p -t 30 curl --silent --fail -T $2/$3 "https://auto-tester.puremagic.com/addv2/upload_$4?clientver=5&testid=$1"`
        rc=$?
        if [ $rc -ne 0 ]; then
            echo -e "\tcurl failed, rc=$rc, 1=$1, 2=$2, 3=$3, 4=$4, retrying in $sleepdur seconds..." 1>&2
            sleep $sleepdur
            trycount=$(expr $trycount + 1)
            sleepdur=$(expr $sleepdur \* 2)
            if [ $sleepdur -gt 120 ]; then
                sleepdur=120
            fi
        fi
    done
    if [ -n "$curloutput" ]; then
        echo "$curloutput"
    fi
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

# $1 == rundir
# $2 == OS
# $3 == owner
# $4 == repository
# $5 == branch
function checkoutRepeat
{
    rc=1
    while [ $rc -ne 0 ]; do
        timelimit -q -p -t $TESTER_TIMEOUT src/do_checkout.sh "$1" "$2" "$3" "$4" "$5"
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
        data=("test" "master" "1" "$OS")
        data=("${data[@]}" "3")
        data=("${data[@]}" "1" "D-Programming-Language" "dmd" "master")
        data=("${data[@]}" "2" "D-Programming-Language" "druntime" "master")
        data=("${data[@]}" "3" "D-Programming-Language" "phobos" "master")
        data=("${data[@]}" 1 0)
        #if [ "$runmode" == "pull" ]; then
        #    data=("${data[@]}" 17 0 "https://github.com/yebblies/dmd.git" "issue4923")
        #fi
        data=("${data[@]}" 15 0)
        data=("${data[@]}" 15 1)
        data=("${data[@]}" 15 2)
        data=("${data[@]}" 16 0)
        data=("${data[@]}" 16 1)
        data=("${data[@]}" 16 2)
    elif [ "$2" == "test-GDC" ]; then
        data=("test" "master" "2" "$OS")
        data=("${data[@]}" "1")
        data=("${data[@]}" "13" "D-Programming-GDC" "GDC" "master")
        data=("${data[@]}" 1 0)
        #if [ "$runmode" == "pull" ]; then
        #    # fix
        #    data=("${data[@]}" 17 0 "https://github.com/yebblies/dmd.git" "issue4923")
        #fi
        data=("${data[@]}" 15 0)
        data=("${data[@]}" 16 0)
    else
        data=($(callcurl get_runnable_pull "os=$OS&hostname=`hostname`$extraargs"))
    fi
    runid="${data[0]}"

    if [[ ! ($runid =~ ^-?[0-9]+$) ]]; then
        echo "Unexpected output from get_runnable_pull: $(data[@])"
        echo -e -n "Skipping run ($OS)...\r"
        run_rc=2
        return
    fi

    runmode="${data[1]}"
    projecttype="${data[2]}"
    OS="${data[3]}"
    data=("${data[@]:4}")

    num_rbs=${data[0]}
    # sets of (repoid owner name branch)
    repobranches=(${data[@]:1:4*$num_rbs})
    steps=(${data[@]:1+4*$num_rbs})

    rundir=$runmode-$runid-$OS

    pretest
    # add project when that data is available
    echo -e "\nStarting $runmode run $runid, platform: $OS"

    if [ ! -d $rundir ]; then
        mkdir "$rundir"
    fi

    run_rc=0
    while [ $run_rc -eq 0 -a ${#steps[@]} -gt 0 ]; do
        repoid=${repobranches[${steps[1]}*4]}
        reponame=${repobranches[${steps[1]}*4 + 2]}
        testid=$(callcurl start_${runmode}_test "runid=$runid&type=${steps[0]}&repoid=$repoid")
        if [[ ! ($testid =~ ^-?[0-9]+$) ]]; then
            if [ "x${testid:0:5}" != "xabort" ]; then
                echo "Unexpected output from start_${runmode}_test, aborting: $testid"
            fi
            run_rc=3
            break
        fi
        case ${steps[0]} in
            1) # checkout
                x=("${repobranches[@]}")
                while [ ${#x[@]} -gt 0 ]; do
                    checkoutRepeat "$rundir" "$OS" "${x[1]}" "${x[2]}" "${x[3]}"
                    x=(${x[@]:4})
                done
                src/do_fixup.sh "$rundir" "$OS" "$projecttype"
                step_rc=$?
                logname=checkout.log
                ;;
            15)
                timelimit -q -p -t $TESTER_TIMEOUT src/do_build_${reponame}.sh "$rundir" "$OS"
                step_rc=$?
                logname=${reponame}-build.log
                ;;
            16)
                timelimit -q -p -t $TESTER_TIMEOUT src/do_test_${reponame}.sh "$rundir" "$OS" "$runmode"
                step_rc=$?
                logname=${reponame}-unittest.log
                ;;
            17)
                timelimit -q -p -t $TESTER_TIMEOUT src/do_pull.sh "$rundir" "$OS" "$reponame" "${steps[2]}" "${steps[3]}"
                step_rc=$?
                logname=${reponame}-merge.log
                steps=(${steps[@]:2}) # trim extra fields
                ;;
            18)
                src/do_daily_maintenance.sh
                ;;
        esac
        if [ $step_rc -gt 1 ]; then
            echo "timed out after $TESTER_TIMEOUT seconds, step failed" >> $rundir/$logname
            step_rc=1
        fi
        steps=(${steps[@]:2})
        uploadlog $testid $rundir $logname $runmode
        curlrc=$(callcurl finish_${runmode}_test "testid=$testid&rc=$step_rc")
        if [ "$runmode" == "pull" -a $step_rc -ne 0 ]; then
            run_rc=1
        elif [[ ! ($testid =~ ^-?[0-9]+$) ]]; then
            if [ "x${curlrc:0:5}" != "xabort" ]; then
                echo "Unexpected output from finish_${runmode}_test, aborting: $testid"
            fi
            run_rc=3
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
        if [ -d /cores ]; then rm -f /cores/*; fi
    fi
}

TESTER_TIMEOUT=3600
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

