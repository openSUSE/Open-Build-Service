package BSRepServer;

use strict;
use warnings;

use BSConfiguration;
use BSRPC ':https';
use BSUtil;
#use BSFileDB;
use BSHTTP;
use BSXML;
use Build;
use BSSolv;

my $proxy;
$proxy = $BSConfig::proxy if defined($BSConfig::proxy);

my $historylay = [qw{versrel bcnt srcmd5 rev time duration}];
my $reporoot = "$BSConfig::bsdir/build";
my $extrepodir = "$BSConfig::bsdir/repos";
my $extrepodb = "$BSConfig::bsdir/db/published";
my @binsufs = qw{rpm deb pkg.tar.gz pkg.tar.xz};
my $binsufsre = join('|', map {"\Q$_\E"} @binsufs);

sub getconfig {
  my ($projid, $repoid, $arch, $path) = @_;

  my @configpath = map {"path=$_"} @{$path || []};
  my $config = BSRPC::rpc("$BSConfig::srcserver/getconfig", undef, "project=$projid", "repository=$repoid", @configpath);
  my $bconf = Build::read_config($arch, [split("\n", $config)]);
  $bconf->{'binarytype'} ||= 'UNDEFINED';
  return $bconf;
}

sub map_to_extrep {
  my ($prp, $prp_ext) = @_;

  my $extrep = "$extrepodir/$prp_ext";
  return $extrep unless $BSConfig::publishredirect;
  if ($BSConfig::publishedredirect_use_regex || $BSConfig::publishedredirect_use_regex) {
    for my $key (sort {$b cmp $a} keys %{$BSConfig::publishredirect}) {
      if ($prp =~ /^$key/) {
        $extrep = $BSConfig::publishredirect->{$key};
        last;
      }
    }
  } elsif (exists($BSConfig::publishredirect->{$prp})) {
    $extrep = $BSConfig::publishredirect->{$prp};
  }
  $extrep = $extrep->($prp, $prp_ext) if $extrep && ref($extrep) eq 'CODE';
  return $extrep;
}

sub get_downloadurl {
  my ($prp, $prp_ext) = @_;
  if ($BSConfig::prp_ext_map && exists $BSConfig::prp_ext_map->{$prp}) {
    return $BSConfig::prp_ext_map->{$prp};
  }
  my $extrep = map_to_extrep($prp, $prp_ext);
  $extrep = [ $extrep ] unless ref $extrep;
  return $extrep->[2] if $extrep->[2];
  BSConfiguration::check_configuration_once();
  return undef unless $BSConfig::repodownload;
  if ($extrep->[0] =~ /^\Q$BSConfig::bsdir\E\/repos\/(.*)$/) {
    my $url = "$BSConfig::repodownload/$1/";
    $url =~ s!//$!/!;
    return $url;
  }
  return "$BSConfig::repodownload/$prp_ext/";
}

sub addrepo_remote {
  my ($pool, $prp, $arch, $remoteproj) = @_;
  my ($projid, $repoid) = split('/', $prp, 2);
  return undef unless $remoteproj;
  print "fetching remote repository state for $prp\n";
  my $param = {
    'uri' => "$remoteproj->{'remoteurl'}/build/$remoteproj->{'remoteproject'}/$repoid/$arch/_repository",
    'timeout' => 200, 
    'receiver' => \&BSHTTP::cpio_receiver,
    'proxy' => $proxy,
  };
  my $cpio = BSRPC::rpc($param, undef, "view=cache");
  my %cpio = map {$_->{'name'} => $_->{'data'}} @{$cpio || []}; 
  if (exists $cpio{'repositorycache'}) {
    my $cache = BSUtil::fromstorable($cpio{'repositorycache'}, 2);
    delete $cpio{'repositorycache'};	# free mem
    return undef unless $cache;
    # free some unused entries to save mem
    for (values %$cache) {
      delete $_->{'path'};
      delete $_->{'id'};
    }
    delete $cache->{'/external/'};
    delete $cache->{'/url'};
    return $pool->repofromdata($prp, $cache);
  } else {
    # return empty repo
    return $pool->repofrombins($prp, '');
  }
}

sub addrepo_scan {
  my ($pool, $prp, $arch) = @_;
  my $dir = "$reporoot/$prp/$arch/:full";
  my $repobins = {};
  my $cnt = 0; 

  my $cache;
  if (-s "$dir.solv") {
    eval {$cache = $pool->repofromfile($prp, "$dir.solv");};
    warn($@) if $@;
    return $cache if $cache;
    print "local repo $prp\n";
  }
  my @bins;
  local *D;
  if (opendir(D, $dir)) {
    @bins = grep {/\.(?:$binsufsre)$/s && !/^\.dod\./s} readdir(D);
    closedir D;
    if (!@bins && -s "$dir.subdirs") {
      for my $subdir (split(' ', readstr("$dir.subdirs"))) {
        push @bins, map {"$subdir/$_"} grep {/\.(?:$binsufsre)$/} ls("$dir/$subdir");    }
    }
  }
  for (splice @bins) {
    my @s = stat("$dir/$_");
    next unless @s;
    push @bins, $_, "$s[9]/$s[7]/$s[1]";
  }
  if ($cache) {
    $cache->updatefrombins($dir, @bins);
  } else {
    $cache = $pool->repofrombins($prp, $dir, @bins);
  }
  return $cache;
}

sub read_gbininfo {
  my ($dir, $collect) = @_;
  my $gbininfo = BSUtil::retrieve("$dir/:bininfo", 1);
  if ($gbininfo) {
    my $gbininfo_m = BSUtil::retrieve("$dir/:bininfo.merge", 1);
    if ($gbininfo_m) {
      for (keys %$gbininfo_m) {
	if ($gbininfo_m->{$_}) {
	  $gbininfo->{$_} = $gbininfo_m->{$_};
	} else {
          # keys with empty values will be deleted
	  delete $gbininfo->{$_};
	}
      }
    }
  }
  if (!$gbininfo && $collect) {
    $gbininfo = {};
    for my $packid (grep {!/^[:\.]/} sort(ls($dir))) {
      next if $packid eq '_deltas' || $packid eq '_volatile' || ! -d "$dir/$packid";
      $gbininfo->{$packid} = read_bininfo("$dir/$packid");
    }
  }
  return $gbininfo;
}

sub read_bininfo {
  my ($dir) = @_;
  my $bininfo = BSUtil::retrieve("$dir/.bininfo", 1);
  return $bininfo if $bininfo;
  # .bininfo not present or old style, generate it
  $bininfo = {};
  for my $file (ls($dir)) {
    if ($file =~ /\.(?:$binsufsre)$/) {
      my @s = stat("$dir/$file");
      my ($hdrmd5, $leadsigmd5);
      $hdrmd5 = Build::queryhdrmd5("$dir/$file", \$leadsigmd5);
      next unless $hdrmd5;
      my $r = {'filename' => $file, 'id' => "$s[9]/$s[7]/$s[1]"};
      $r->{'hdrmd5'} = $hdrmd5;
      $r->{'leadsigmd5'} = $leadsigmd5 if $leadsigmd5;
      $bininfo->{$file} = $r;
    } elsif ($file =~ /-appdata\.xml$/) {
      local *F;
      open(F, '<', "$dir/$file") || next;
      my @s = stat(F);
      next unless @s;
      my $ctx = Digest::MD5->new;
      $ctx->addfile(*F);
      close F;
      $bininfo->{$file} = {'md5sum' => $ctx->hexdigest(), 'filename' => $file, 'id' => "$s[9]/$s[7]/$s[1]"};
    } elsif ($file eq '.nosourceaccess') {
      $bininfo->{'.nosourceaccess'} = {};
    } elsif ($file eq '.channelinfo' || $file eq 'updateinfo.xml') {
      $bininfo->{'.nouseforbuild'} = {};
    }
  }
  return $bininfo;
}

1;
