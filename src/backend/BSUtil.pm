#
# Copyright (c) 2006, 2007 Michael Schroeder, Novell Inc.
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
################################################################
#
# collection of useful functions
#

package BSUtil;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw{writexml writestr readxml readstr ls mkdir_p xfork str2utf8 data2utf8 str2utf8xml data2utf8xml};

use XML::Structured;
use POSIX;
use Fcntl qw(:DEFAULT);
use File::Copy qw(copy move);
use Encode;
use Storable ();
use IO::Handle;

use strict;

our $fdatasync_before_rename;

sub set_fdatasync_before_rename {
  $fdatasync_before_rename = 1;
  if (!defined(&File::Sync::fdatasync_fd)) {
    eval {
      require File::Sync;
    };
    warn($@) if $@;
    *File::Sync::fdatasync_fd = sub {} unless defined &File::Sync::fdatasync_fd;
  }
}

sub do_fdatasync {
  my ($fd) = @_;
  set_fdatasync_before_rename() unless defined &File::Sync::fdatasync_fd;
  File::Sync::fdatasync_fd($fd);
}

sub writexml {
  my ($fn, $fnf, $dd, $dtd) = @_;
  my $d = XMLout($dtd, $dd);
  local *F;
  open(F, '>', $fn) || die("$fn: $!\n");
  (syswrite(F, $d) || 0) == length($d) || die("$fn write: $!\n");
  do_fdatasync(fileno(F)) if defined($fnf) && $fdatasync_before_rename;
  close(F) || die("$fn close: $!\n");
  return unless defined $fnf;
  $! = 0;
  move($fn, $fnf) || die("move $fn $fnf: $!\n");
}

sub writestr {
  my ($fn, $fnf, $d) = @_;
  local *F;
  open(F, '>', $fn) || die("$fn: $!\n");
  if (length($d)) {
    (syswrite(F, $d) || 0) == length($d) || die("$fn write: $!\n");
  }
  do_fdatasync(fileno(F)) if defined($fnf) && $fdatasync_before_rename;
  close(F) || die("$fn close: $!\n");
  return unless defined $fnf;
  move($fn, $fnf) || die("move $fn $fnf: $!\n");
}

sub appendstr {
  my ($fn, $d) = @_;
  local *F;
  open(F, '>>', $fn) || die("$fn: $!\n");
  if (length($d)) {
    (syswrite(F, $d) || 0) == length($d) || die("$fn write: $!\n");
  }
  close(F) || die("$fn close: $!\n");
}

sub readstr {
  my ($fn, $nonfatal) = @_;
  local *F;
  if (!open(F, '<', $fn)) {
    die("$fn: $!\n") unless $nonfatal;
    return undef;
  }
  my $d = '';
  1 while sysread(F, $d, 8192, length($d));
  close F;
  return $d;
}

sub readxml {
  my ($fn, $dtd, $nonfatal) = @_;
  my $d = readstr($fn, $nonfatal);
  return $d unless defined $d;
  if ($d !~ /<.*?>/s) {
    die("$fn: not xml\n") unless $nonfatal;
    return undef;
  }
  return XMLin($dtd, $d) unless $nonfatal;
  eval { $d = XMLin($dtd, $d); };
  return $@ ? undef : $d;
}

sub fromxml {
  my ($d, $dtd, $nonfatal) = @_;
  return XMLin($dtd, $d) unless $nonfatal;
  eval { $d = XMLin($dtd, $d); };
  return $@ ? undef : $d;
}

sub toxml {
  my ($d, $dtd) = @_;
  return XMLout($dtd, $d);
}

sub touch($) {
  my ($file) = @_;
  if (-e $file) {
    utime(time, time, $file); 
  } else {
    # create new file, mtime is anyway current
    local *F;
    open(F, '>>', $file) || die("$file: $!\n");
    close(F) || die("$file close: $!\n");
  }
}

sub ls {
  local *D;
  opendir(D, $_[0]) || return ();
  my @r = grep {$_ ne '.' && $_ ne '..'} readdir(D);
  closedir D;
  return @r;
}

sub mkdir_p {
  my ($dir) = @_;

  return 1 if -d $dir;
  my $pdir;
  if ($dir =~ /^(.+)\//) {
    $pdir = $1;
    mkdir_p($pdir) || return undef;
  }
  while (!mkdir($dir, 0777)) {
    my $e = $!;
    return 1 if -d $dir;
    if (defined($pdir) && ! -d $pdir) {
      mkdir_p($pdir) || return undef;
      next;
    }
    $! = $e;
    warn("mkdir: $dir: $!\n");
    return undef;
  }
  return 1;
}

# calls mkdir_p and changes ownership of the created directory to the
# supplied user and group if provided.
sub mkdir_p_chown {
  my ($dir, $user, $group) = @_;

  if (!(-d $dir)) {
    mkdir_p($dir) || return undef;
  }
  return 1 unless defined($user) || defined($group);

  $user = -1 unless defined $user;
  $group = -1 unless defined $group;
  
  if ($user  !~ /^-?\d+$/ && !($user = getpwnam($user))) {
    warn "user $user unknown\n"; return undef
  }
  if ($group !~ /^-?\d+$/ && !($group = getgrnam($group))) {
    warn "group $group unknown\n"; return undef
  }

  my @s = stat($dir);
  if ($s[4] != $user || $s[5] != $group) {
    if (!chown $user, $group, $dir) {
      warn "failed to chown $dir to $user:$group\n"; return undef;
    }
  }
  return 1;
}

sub drop_privs_to {
  my ($user, $group) = @_;

  if (defined($group)) {
    $group = getgrnam($group) unless $group =~ /^\d+$/;
    die("unknown group\n") unless defined $group;
    if ($) != $group || $( != $group) {
      ($), $() = ($group, $group);
      die("setgid: $!\n") if $) != $group;
    }
  }
  if (defined($user)) {
    $user = getpwnam($user) unless $user =~ /^\d+$/;
    die("unknown user\n") unless defined $user;
    if ($> != $user || $< != $user) {
      ($>, $<) = ($user, $user);
      die("setuid: $!\n") if $> != $user;
    }
  }
}

sub cleandir {
  my ($dir) = @_;

  my $ret = 1;
  return 1 unless -d $dir;
  for my $c (ls($dir)) {
    if (! -l "$dir/$c" && -d _) {
      cleandir("$dir/$c");
      $ret = undef unless rmdir("$dir/$c");
    } else {
      $ret = undef unless unlink("$dir/$c");
    }
  }
  return $ret;
}

sub linktree {
  my ($from, $to) = @_;
  return unless -d $from;
  mkdir_p($to);
  my @todo = sort(ls($from));
  while (@todo) {
    my $f = shift @todo;
    if (! -l "$from/$f" && -d _) {
      mkdir_p("$to/$f");
      unshift @todo, map {"$f/$_"} ls("$from/$f");
    } else {
      link("$from/$f", "$to/$f") || copy("$from/$f", "$to/$f") || die("link $from/$f $to/$f: $!\n");
    }
  }
}

sub treeinfo {
  my ($dir) = @_;
  my @info;
  my @todo = sort(ls($dir));
  while (@todo) {
    my $f = shift @todo;
    my @s = lstat("$dir/$f");
    next unless @s;
    if (-d _) { 
      push @info, "$f";
      unshift @todo, map {"$f/$_"} ls("$dir/$f");
    } else {
      push @info, "$f $s[9]/$s[7]/$s[1]";
    }    
  }
  return \@info;
}

sub xfork {
  my $pid;
  while (1) {
    $pid = fork();
    last if defined $pid;
    die("fork: $!\n") if $! != POSIX::EAGAIN;
    sleep(5);
  }
  return $pid;
}

sub cp {
  my ($from, $to, $tof) = @_;
  local *F;
  local *T;
  open(F, '<', $from) || die("$from: $!\n");
  open(T, '>', $to) || die("$to: $!\n");
  my $buf;
  while (sysread(F, $buf, 8192)) {
    (syswrite(T, $buf) || 0) == length($buf) || die("$to write: $!\n");
  }
  close(F);
  close(T) || die("$to: $!\n");
  if (defined($tof)) {
    move($to, $tof) || die("move $to $tof: $!\n");
  }
}

sub checkutf8 {
  my ($oct) = @_;
  Encode::_utf8_off($oct);
  return 1 unless defined $oct;
  return 1 unless $oct =~ /[\200-\377]/;
  eval {
    Encode::_utf8_on($oct);
    encode('UTF-8', $oct, Encode::FB_CROAK);
  };
  return $@ ? 0 : 1;
}

sub str2utf8 {
  my ($oct) = @_;
  return $oct unless defined $oct;
  return $oct unless $oct =~ /[^\011\012\015\040-\176]/s;
  eval {
    Encode::_utf8_on($oct);
    $oct = encode('UTF-8', $oct, Encode::FB_CROAK);
  };
  if ($@) {
    # assume iso-8859-1
    eval {
      Encode::_utf8_off($oct);
      $oct = encode('UTF-8', $oct, Encode::FB_CROAK);
    };
    if ($@) {
      Encode::_utf8_on($oct);
      $oct = encode('UTF-8', $oct, Encode::FB_XMLCREF);
    }
  }
  Encode::_utf8_off($oct);	# just in case...
  return $oct;
}

sub data2utf8 {
  my ($d) = @_;
  if (ref($d) eq 'ARRAY') {
    for my $dd (@$d) {
      if (ref($dd) eq '') {
        $dd = str2utf8($dd);
      } else {
        data2utf8($dd);
      }
    }
  } elsif (ref($d) eq 'HASH') {
    for my $dd (keys %$d) {
      if (ref($d->{$dd}) eq '') {
        $d->{$dd} = str2utf8($d->{$dd});
      } else {
        data2utf8($d->{$dd});
      }
    }
  }
}

sub str2utf8xml {
  my ($oct) = @_;
  return $oct unless defined $oct;
  return $oct unless $oct =~ /[^\011\012\015\040-\176]/s;
  $oct = str2utf8($oct);
  Encode::_utf8_on($oct);
  # xml does not accept all utf8 chars, escape the illegal
  $oct =~ s/([\000-\010\013\014\016-\037\177])/sprintf("&#x%x;",ord($1))/sge;
  $oct =~ s/([\x{d800}-\x{dfff}\x{fffe}\x{ffff}])/sprintf("&#x%x;",ord($1))/sge;
  Encode::_utf8_off($oct);
  return $oct;
}

sub data2utf8xml {
  my ($d) = @_;
  if (ref($d) eq 'ARRAY') {
    for my $dd (@$d) {
      if (ref($dd) eq '') {
        $dd = str2utf8xml($dd);
      } else {
        data2utf8xml($dd);
      }
    }
  } elsif (ref($d) eq 'HASH') {
    for my $dd (keys %$d) {
      if (ref($d->{$dd}) eq '') {
        $d->{$dd} = str2utf8xml($d->{$dd});
      } else {
        data2utf8xml($d->{$dd});
      }
    }
  }
}

sub waituntilgone {
  my ($fn, $timeout) = @_;
  while (1) {
    return 1 unless -e $fn;
    return 0 if defined($timeout) && $timeout <= 0;
    select(undef, undef, undef, .1);
    $timeout -= .1 if defined $timeout;
  }
}

sub lockopen {
  my ($fg, $op, $fn, $nonfatal) = @_;

  local *F = $fg; 
  while (1) {
    if (!open(F, $op, $fn)) {
      return undef if $nonfatal;
      die("$fn: $!\n");
    }
    fcntl(F, F_SETFL, O_EXCL | O_NONBLOCK) || die("fcntl $fn: $!\n");
    my @s = stat(F);
    return 1 if @s && $s[3];
    close F;
  }
}

sub lockcheck {
  my ($op, $fn) = @_;
  local *F;
  while (1) {
    if (!open(F, $op, $fn)) {
      return -1;
    }
    if (!fcntl(F, F_SETFL, O_EXCL | O_NONBLOCK)) {
      close(F);
      return 0;
    }
    my @s = stat(F);
    close F;
    return 1 if @s && $s[3];
  }
}

sub lockopenxml {
  my ($fg, $op, $fn, $dtd, $nonfatal) = @_;
  if (!lockopen($fg, $op, $fn, $nonfatal)) {
    die("$fn: $!\n") unless $nonfatal;
    return undef;
  }
  my $d = readxml($fn, $dtd, $nonfatal);
  if (!$d) {
    local *F = $fg;
    close F;
  }
  return $d;
}

sub lockcreatexml {
  my ($fg, $fn, $fnf, $dd, $dtd) = @_;

  local *F = $fg; 
  writexml($fn, undef, $dd, $dtd);
  open(F, '<', $fn) || die("$fn: $!\n");
  fcntl(F, F_SETFL, O_EXCL | O_NONBLOCK) || die("fcntl lock: $!\n");
  if (!(link($fn, $fnf) || copy($fn, $fnf))) {
    unlink($fn);
    close F;
    return undef;
  }
  unlink($fn);
  return 1;
}

sub isotime {
  my ($t) = @_;
  my @lt = localtime($t || time());
  return sprintf "%04d-%02d-%02d %02d:%02d:%02d", $lt[5] + 1900, $lt[4] + 1, @lt[3,2,1,0];
}

# XXX: does that really belong here?
#
# Algorithm:
# each enable/disable has a score:
# +1 if it's a disable
# +2 if the arch matches
# +4 if the repo matches
#
sub enabled {
  my ($repoid, $disen, $default, $arch) = @_;

  # filter matching elements, check for shortcuts
  return $default unless $disen;
  my @dis = grep { (!defined($_->{'arch'}) || $_->{'arch'} eq $arch) && 
                   (!defined($_->{'repository'}) || $_->{'repository'} eq $repoid)
                 } @{$disen->{'disable'} || []};
  return 1 if !@dis && $default;
  my @ena = grep { (!defined($_->{'arch'}) || $_->{'arch'} eq $arch) && 
                   (!defined($_->{'repository'}) || $_->{'repository'} eq $repoid)
                 } @{$disen->{'enable'} || []};
  return @dis ? 0 : $default unless @ena;
  return @ena ? 1 : $default unless @dis;

  # have @dis and @ena, need to do score thing...
  my $disscore = 0;
  for (@dis) {
    my $score = 1;
    $score += 2 if defined($_->{'arch'});
    $score += 4 if defined($_->{'repository'});
    if ($score > $disscore) {
      return 0 if $score == 7;		# can't max this!
      $disscore = $score;
    }
  }
  my $enascore = 0;
  for (@ena) {
    my $score = 0;
    $score += 2 if defined($_->{'arch'});
    $score += 4 if defined($_->{'repository'});
    if ($score > $enascore) {
      return 1 if $enascore == 6;		# can't max this!
      $enascore = $score;
    }
  }
  return $enascore > $disscore ? 1 : 0;
}

sub store {
  my ($fn, $fnf, $dd) = @_;
  if ($fdatasync_before_rename && defined($fnf)) {
    local *F;
    open(F, '>', $fn) || die("$fn: $!\n");
    if (!Storable::nstore_fd($dd, \*F)) {
      die("nstore_fd $fn: $!\n");
    }
    (\*F)->flush();
    do_fdatasync(fileno(F));
    close(F) || die("$fn close: $!\n");
  } else {
    if (!Storable::nstore($dd, $fn)) {
      die("nstore $fn: $!\n");
    }
  }
  return unless defined $fnf;
  $! = 0;
  move($fn, $fnf) || die("move $fn $fnf: $!\n");
}

sub retrieve {
  my ($fn, $nonfatal) = @_;
  my $dd;
  if (!$nonfatal) {
    $dd = ref($fn) ? Storable::fd_retrieve($fn) : Storable::retrieve($fn);
    die("retrieve $fn: $!\n") unless $dd;
  } else {
    eval {
      $dd = ref($fn) ? Storable::fd_retrieve($fn) : Storable::retrieve($fn);
    };
    if (!$dd && $nonfatal == 2) {
      if ($@) {
        warn($@);
      } else {
        warn("retrieve $fn: $!\n");
      }
    }
  }
  return $dd;
}

sub ping {
  my ($pingfile) = @_;
  local *F;
  if (sysopen(F, $pingfile, POSIX::O_WRONLY|POSIX::O_NONBLOCK)) {
    syswrite(F, 'x');
    close(F);
  }
}

sub restartexit {
  my ($arg, $name, $runfile, $pingfile) = @_;
  return unless $arg;
  if ($arg eq '--stop' || $arg eq '--exit') {
    if (!(-e "$runfile.lock") || lockcheck('>>', "$runfile.lock")) {
      print "$name not running.\n";
      exit 0;
    }    
    print "exiting $name...\n";
    BSUtil::touch("$runfile.exit");
    ping($pingfile) if $pingfile;
    BSUtil::waituntilgone("$runfile.exit");
    exit(0);
  }
  if ($ARGV[0] eq '--restart') {
    die("$name not running.\n") if !(-e "$runfile.lock") || BSUtil::lockcheck('>>', "$runfile.lock");
    print "restarting $name...\n";
    BSUtil::touch("$runfile.restart");
    ping($pingfile) if $pingfile;
    BSUtil::waituntilgone("$runfile.restart");
    exit(0);
  }
}

1;
