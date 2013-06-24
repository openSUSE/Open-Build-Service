#!/bin/sh
#
# This script runs all build service test suites and calculates code coverage
#

###############################################################################
# Job configuration template
###############################################################################
#
# Project name: obs_testsuite_coverage
# Description:
#   OBS testsuite code coverage on git master branch.
#
#   Updates source code repository and runs all testsuites. It
#   generates coverage reports and todo/fixme reports as well as code statistics.
#
# Source Code Management:
#   Git:
#     Repositories: git://github.com/openSUSE/open-build-service.git
#     Branches to build: master
#     Repository browser: githubweb
#       URL: https://github.com/openSUSE/open-build-service
#     Excluded Regions:
#       docs
#
# Build Triggers:
#   Poll SCM:
#     Schedule: 2 1 * * *
#
# Build:
#   Execute shell:
#     Command: sh dist/ci/obs_testsuite_coverage.sh
#
# Post Build Actions: #FIXME
#   Publish JUnit test result report:
#     Test report XMLs: src/webui/results/*.xml
#   Publish Rails Notes report: 1
#     Rake working directory: src/webui
#   Publish Rails stats report: 1
#     Rake working directory: src/webui
#   Publish Rcov report:
#     Rcov report directory:  src/webui/coverage
#

###############################################################################
# Script content for 'Build' step
###############################################################################
#
# Either invoke as described above or copy into an 'Execute shell' 'Command'.
#

set -xe
. `dirname $0`/obs_testsuite_common.sh

export HEADLESS=forsure
export DO_COVERAGE=rcov
setup_git
setup_api

echo "Enter API rails root and running rcov"
cd src/api
mkdir -p coverage
bundle exec rake test --trace
cd ../..

echo "Enter WebUI rails root and running rcov"
setup_api
setup_webui

cd src/webui
mkdir -p coverage
bundle exec rake test --trace 
cd ../..

cleanup
