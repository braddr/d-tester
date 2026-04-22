#!/bin/bash

# set -x

basedir=/media/ephemeral0/auto-tester

cd $basedir/pull-results

#for x in 0 1 2 3 4 5 6 7 8 9; do
    prefix=`cat $basedir/next-pull-prefix-to-archive`

    ids=`ls -1d pull-${prefix}???`
    archive=pull-results-${prefix}000-${prefix}999.tar.gz

    echo "creating $archive"
    tar zcf $basedir/zips/${archive} ${ids}
    ~/auto-tester.puremagic.com/bin/s3curl --id braddr --put $basedir/zips/${archive} --contentType application/x-gtar -- http://braddr.s3.amazonaws.com/d-backups/${archive}

    echo `expr $prefix + 1` > $basedir/next-pull-prefix-to-archive
#done

