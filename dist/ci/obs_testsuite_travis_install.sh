#!/bin/bash
# This script installs dependencies for the CI build 

# Be verbose and fail script on the first error
set -xe

TEST_SUITE="$1"

sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C5C219E7

# Install updates from our own repository
sudo chmod a+w /etc/apt/sources.list.d
echo 'deb http://download.opensuse.org/repositories/OBS:/Server:/Unstable/xUbuntu_12.04 /' > /etc/apt/sources.list.d/opensuse.list

# We could use this to only update the package list from the OBS,
# but apprently this is not possible anymore. So we update all package lists.
# sudo apt-get update -o APT::Get::List-Cleanup "false" -o Dir::Etc::sourcelist "/etc/apt/sources.list.d/opensuse.list" -o Dir::Etc::sourceparts "";
sudo apt-get update

# Install the dependencies of the backend
sudo apt-get install --force-yes travis-deps libxml-parser-perl libfile-sync-perl python-rpm python-urlgrabber python-sqlitecachec python-libxml2 createrepo libbssolv-perl sphinxsearch libjson-xs-perl libxml-simple-perl libgd-gd2-perl

if [ "$TEST_SUITE" == "backend" ]; then
  sudo apt-get install --force-yes libdevel-cover-perl
fi
