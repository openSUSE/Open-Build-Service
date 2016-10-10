#!/bin/bash
# This script runs the test suites for the CI build

# Be verbose and fail script on the first error
set -xe

# Everything happens here
pushd src/api

# Which test suite should run? By default: all
if [ -z $1 ]; then
  TEST_SUITE="all"
else
  TEST_SUITE="$1"
fi


if test -z "$SUBTEST"; then
  export DO_COVERAGE=1
  export TESTOPTS="-v"
  case $TEST_SUITE in
    api)
      bundle exec rails test:api
      ;;
    webui)
      bundle exec rails test:webui
      ;;
    spider)
      unset DO_COVERAGE
      bundle exec rails test:spider
      ;;
    rubocop)
      bundle exec rails rubocop
      ;;
    rspec)
      bundle exec rspec
      ;;
    backend)
      pushd ../backend
      bundle exec make test_unit
      popd
      ;;
    *)
      bundle exec rails rubocop
      bundle exec rails test:api
      bundle exec rails test:webui
      bundle exec rspec
      pushd ../backend
      bundle exec make test_unit
      popd
      unset DO_COVERAGE
      bundle exec rails test:spider
      ;;
  esac
fi
