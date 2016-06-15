#!/bin/bash

sourcearchive=$1
shift
prefix=$1
shift
limit=$1
shift

tdir=`mktemp -d`

# extract files
tar xJf $sourcearchive -C $tdir >&/dev/null

pushd $tdir/open-build-service*/src/api >& /dev/null
ruby.ruby2.3 -rbundler -e 'exit' || echo "_ERROR_BUNDLER_NOT_INSTALLED_"

mode="resolve"
if [ "$limig" == "production" ]; then
  mode="specs_for([:default, :assets])"
fi

ruby.ruby2.3 -rbundler -e 'Bundler.definition.'"$mode"' { |s| puts "rubygem('$prefix':#{s.name}) = #{s.version}" }' | while read i; do echo -n $i", "; done
popd >& /dev/null

#cleanup
rm -rf $tdir

