#!/usr/bin/env bash

LOG=`pwd`/tester.log

echo "Performing GIT repo maintenance" >> $LOG
for x in `find ./source -maxdepth 2 -mindepth 2 -type d`; do
    echo $x >> $LOG
    (cd $x; du -sh .; git gc --aggressive; du -sh .) >> $LOG 2>&1
    echo >> $LOG
done

