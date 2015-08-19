#!/bin/sh
#
# This script installs dependencies on travis 
#

###############################################################################
# Script content for 'Build' step
###############################################################################
#
# Either invoke as described above or copy into an 'Execute shell' 'Command'.
#

set -xe

sudo chmod a+w /etc/apt/sources.list.d
echo 'deb http://download.opensuse.org/repositories/OBS:/Server:/2.6/xUbuntu_12.04 /' > /etc/apt/sources.list.d/opensuse.list
#sudo apt-get update
sudo apt-get update -o Dir::Etc::sourcelist="sources.list.d/opensuse.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"

cat > /etc/apt/sources.list.d/security.list << EOF
deb http://security.ubuntu.com/ubuntu precise-security main restricted
deb http://security.ubuntu.com/ubuntu precise-security universe
deb http://security.ubuntu.com/ubuntu precise-security multiverse
EOF
sudo apt-get update -o Dir::Etc::sourcelist="sources.list.d/security.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"

# dependencies of backend
sudo apt-get install --force-yes travis-deps libxml-parser-perl libfile-sync-perl python-rpm python-urlgrabber python-sqlitecachec python-libxml2 createrepo libbssolv-perl sphinxsearch libjson-xs-perl libxml-simple-perl libgd-gd2-perl

pushd src/api
if test "$REMOVEGEMLOCK" = true; then
  rm Gemfile.lock
fi
gem install bundler
echo 'gem "coveralls"' >> Gemfile
bundle install
popd

