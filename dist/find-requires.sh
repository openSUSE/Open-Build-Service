#!/bin/bash

sourcearchive=$1
shift

tdir=`mktemp -d`

# extract files
tar xJf $sourcearchive -C $tdir

pushd $tdir/open-build-service*/src/api

ruby -rbundler -e 'Bundler.definition.resolve.to_a.each { |s| puts "rubygem(2.1.0:#{s.name}) = #{s.version}" }' | grep -v ':webui' | while read i; do echo -n $i", "; done
popd

#cleanup
rm -rf $tdir

