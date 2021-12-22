# Copyright (c) 2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file COPYING); if not, write to the
# Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#
package BSSrcServer::Scmsync;

use BSConfiguration;
use BSUtil;
use BSRevision;
use BSCpio;
use BSVerify;
use BSXML;

use strict;

my $projectsdir = "$BSConfig::bsdir/projects";
my $srcrep = "$BSConfig::bsdir/sources";

my $uploaddir = "$srcrep/:upload";


our $notify = sub {};
our $notify_repservers = sub {};
our $runservice = sub {};

#
# low level helpers
#
sub deletepackage {
  my ($cgi, $projid, $packid) = @_;
  local $cgi->{'comment'} ||= 'package was deleted';
  # kill upload revision
  unlink("$projectsdir/$projid.pkg/$packid.upload-MD5SUMS");
  # add delete commit to both source and meta
  BSRevision::addrev_local_replace($cgi, $projid, $packid);
  BSRevision::addrev_meta_replace($cgi, $projid, $packid);
  # now do the real delete of the package
  BSRevision::delete_rev($cgi, $projid, $packid, "$projectsdir/$projid.pkg/$packid.rev", "$projectsdir/$projid.pkg/$packid.rev.del");
  BSRevision::delete_rev($cgi, $projid, $packid, "$projectsdir/$projid.pkg/$packid.mrev", "$projectsdir/$projid.pkg/$packid.mrev.del");
  # get rid of the generated product packages as well
}

sub undeletepackage {
  my ($cgi, $projid, $packid) = @_;
  local $cgi->{'comment'} ||= 'package was undeleted';
  BSRevision::undelete_rev($cgi, $projid, $packid, "$projectsdir/$projid.pkg/$packid.mrev.del", "$projectsdir/$projid.pkg/$packid.mrev");
  if (-s "$projectsdir/$projid.pkg/$packid.rev.del") {
    BSRevision::undelete_rev($cgi, $projid, $packid, "$projectsdir/$projid.pkg/$packid.rev.del", "$projectsdir/$projid.pkg/$packid.rev");
  }
}

sub putpackage {
  my ($cgi, $projid, $packid, $pack) = @_;
  local $cgi->{'comment'} ||= 'package was updated';
  mkdir_p($uploaddir);
  writexml("$uploaddir/$$.2", undef, $pack, $BSXML::pack);
  BSRevision::addrev_meta_replace($cgi, $projid, $packid, [ "$uploaddir/$$.2", "$projectsdir/$projid.pkg/$packid.xml", '_meta' ]);
}

sub putconfig {
  my ($cgi, $projid, $config) = @_;
  local $cgi->{'comment'} ||= 'config was updated';
  if (defined($config) && $config ne '') {
    mkdir_p($uploaddir);
    writestr("$uploaddir/$$.2", undef, $config);
    BSRevision::addrev_local_replace($cgi, $projid, undef, [ "$uploaddir/$$.2", "$projectsdir/$projid.conf", '_config' ]);
  } else {
    BSRevision::addrev_local_replace($cgi, $projid, undef, [ undef, "$projectsdir/$projid.conf", '_config' ]);
  }
}

#
# sync functions
#
sub sync_package {
  my ($cgi, $projid, $packid, $pack, $info) = @_;

  if (!$pack) {
    return unless -e "$projectsdir/$projid.pkg/$packid.xml";
    print "scmsync: delete $projid/$packid\n";
    eval { delpackage($cgi, $projid, $packid) };
    warn($@) if $@;
    $notify_repservers->('package', $projid, $packid);
    $notify->("SRCSRV_DELETE_PACKAGE", { "project" => $projid, "package" => $packid, "sender" => ($cgi->{'user'} || "unknown"), "comment" => $cgi->{'comment'}, "requestid" => $cgi->{'requestid'} });
    return;
  }

  my $undeleted;
  if (! -e "$projectsdir/$projid.pkg/$packid.xml" && -e "$projectsdir/$projid.pkg/$packid.rev.del") {
    print "scmsync: undelete $projid/$packid\n";
    eval { undeletepackage($cgi, $projid, $packid) };
    warn($@) if $@;
    $notify->("SRCSRV_UNDELETE_PACKAGE", { "project" => $projid, "package" => $packid, "sender" => ($cgi->{'user'} || "unknown"), "comment" => $cgi->{'comment'} });
    $undeleted = 1;
  }
  my $oldpack = BSRevision::readpack_local($projid, $packid, 1);

  if ($undeleted || !$oldpack || !BSUtil::identical($pack, $oldpack)) {
    print "scmsync: update $projid/$packid\n";
    putpackage($cgi, $projid, $packid, $pack);
    my %except = map {$_ => 1} qw{title description devel person group url};
    if ($undeleted || !BSUtil::identical($oldpack, $pack, \%except)) {
      $notify_repservers->('package', $projid, $packid);
    }
    $notify->($oldpack ? "SRCSRV_UPDATE_PACKAGE" : "SRCSRV_CREATE_PACKAGE", { "project" => $projid, "package" => $packid, "sender" => ($cgi->{'user'} || "unknown")});
  }

  my $needtrigger;
  $needtrigger = 1 if $pack->{'scmsync'} && (!$oldpack || $undeleted || $oldpack->{'scmsync'} ne $pack->{'scmsync'});
  if ($pack->{'scmsync'} && !$needtrigger && $info) {
    my $lastrev = eval { BSRevision::getrev_local($projid, $packid) };
    $needtrigger = 1 if $lastrev && $lastrev->{'comment'} && $lastrev->{'comment'} =~ /\[info=([0-9a-f]{1,128})\]$/ && $info ne $1;
  }
  if ($needtrigger) {
    print "scmsync: trigger $projid/$packid\n";
    $runservice->($cgi, $projid, $packid, $pack->{'scmsync'});
  }
}

sub sync_config {
  my ($cgi, $projid, $config) = @_;

  if (!defined($config) || $config eq '') {
    return unless -e "$projectsdir/$projid.conf";
    print "scmsync: delete $projid/_config\n";
  } else {
    my $oldconfig = readstr("$projectsdir/$projid.conf", 1);
    $oldconfig = '' unless defined $oldconfig;
    return if $oldconfig eq $config;
    print "scmsync: update $projid/_config\n";
  }
  putconfig($cgi, $projid, $config);
  $notify_repservers->('project', $projid);
  $notify->("SRCSRV_UPDATE_PROJECT_CONFIG", { "project" => $projid, "sender" => ($cgi->{'user'} || "unknown") });
}

sub sync_project {
  my ($cgi, $projid, $cpiofd) = @_;

  my $proj = BSRevision::readproj_local($projid);
  die("Project $projid is not controlled by obs-scm\n") unless $proj->{'scmsync'};
  die("Project $projid is a remote project\n") if $proj->{'remoteurl'};
  $cpiofd->flush();
  seek($cpiofd, 0, 0);
  my $cpio = BSCpio::list($cpiofd);
  my %files = map {$_->{'name'} => $_}  grep {$_->{'cpiotype'} == 8} @$cpio;

  # update all packages
  for my $packid (grep {s/\.xml$//} sort keys %files) {
    my $ent = $files{"$packid.xml"};
    my $pack;
    eval {
      BSVerify::verify_packid($packid);
      die("bad package '$packid'\n") if $packid eq '_project' || $packid eq '_product';
      die("bad package '$packid'\n") if $packid =~ /(?<!^_product)(?<!^_patchinfo):./;
      die("$packid: xml is too big\n") if $ent->{'size'} > 1000000;
      my $packxml = BSCpio::extract($cpiofd, $ent);
      $pack = BSUtil::fromxml($packxml, $BSXML::pack);
      $pack->{'project'} = $projid;
      $pack->{'name'} = $packid;
      BSVerify::verify_pack($pack);
    };
    if ($@) {
      warn($@);
      next;
    }
    my $info;
    my $infoent = $files{"$packid.info"};
    $info = BSCpio::extract($cpiofd, $infoent) if $infoent && $infoent->{'size'} < 100000;
    chomp $info if $info;
    sync_package($cgi, $projid, $packid, $pack, $info);
  }

  # delete packages that no longer exist
  for my $packid (sort(BSRevision::lspackages_local($projid))) {
    sync_package($cgi, $projid, $packid, undef) unless $files{"$packid.xml"};
  }

  # update the project config
  my $config = '';
  if ($files{'_config'}) {
    my $ent = $files{'_config'};
    eval {
      die("_config: size is too big\n") if $ent->{'size'} > 1000000;
      $config = BSCpio::extract($cpiofd, $ent);
    };
    if ($@) {
      warn($@);
      $config = undef;
    }
  }
  sync_config($cgi, $projid, $config) if defined $config;

  return { 'project' => $projid, 'package' => '_project', 'rev' => 'obsscm' };
}

1;
