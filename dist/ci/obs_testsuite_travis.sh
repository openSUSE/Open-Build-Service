#!/bin/sh
#
# This script runs all build service test suites depending on $SUBTEST
#

###############################################################################
# Script content for 'Build' step
###############################################################################
#
# Either invoke as described above or copy into an 'Execute shell' 'Command'.
#

set -xe

. `dirname $0`/obs_testsuite_common.sh

ret=0
export OBS_REPORT_DIR=results/
export HEADLESS=forsure

cd src/api

if test -z "$SUBTEST"; then
  export DO_COVERAGE=1
  export TESTOPTS="-v"
  bundle exec rake test:api
  bundle exec rake test:webui
  bundle exec rubocop -Dc .rubocop.yml
  cat coverage/.last_run.json
  ruby -rcoveralls -e 'Coveralls.push!'
fi

case $SUBTEST in
  rake:*)
   SUBTEST=${SUBTEST/rake:/}
   bundle exec rake $SUBTEST --trace
   ;;
  api:*)
   SUBTEST=${SUBTEST/api:/}
   thetest=${SUBTEST/:*/}
   thename=${SUBTEST/*:/}
   bundle exec ruby -Itest test/$thetest --name=$thename || ret=1
   tail -n 6000 log/test.log
   ;;
esac

cd ../..
cleanup
exit $ret

