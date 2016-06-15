#
# Copyright (c) 2016 Michael Schroeder, Novell Inc.
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
# Pgp packet parsing functions
#

package BSPgp;

use MIME::Base64 ();

use strict;

sub pkdecodetaglenoff {
  my ($pkg) = @_;
  my $tag = unpack('C', $pkg);
  die("not a pgp packet\n") unless $tag & 128; 
  my $len;
  my $off = 1; 
  if ($tag & 64) {
    # new packet format
    $tag &= 63;  
    $len = unpack('C', substr($pkg, 1)); 
    if ($len < 192) {
      $off = 2; 
    } elsif ($len != 255) {
      $len = (($len - 192) << 8) + unpack('C', substr($pkg, 2)) + 192; 
      $off = 3; 
    } else {
      $len = unpack('N', substr($pkg, 2)); 
      $off = 5; 
    }    
  } else {
    # old packet format
    if (($tag & 3) == 0) { 
      $len = unpack('C', substr($pkg, 1)); 
      $off = 2; 
    } elsif (($tag & 3) == 1) { 
      $len = unpack('n', substr($pkg, 1)); 
      $off = 3; 
    } elsif (($tag & 3) == 1) { 
      $len = unpack('N', substr($pkg, 1)); 
      $off = 6; 
    } else {
      die("can't deal with unspecified packet length\n");
    }    
    $tag = ($tag & 60) >> 2;
  }
  return ($tag, $len, $off);
}

sub pk2expire {
  my ($pk) = @_;
  my ($rex, $rct);
  while ($pk ne '') {
    my ($tag, $len, $off) = pkdecodetaglenoff($pk);
    my $pack = substr($pk, $off, $len);
    $pk = substr($pk, $len + $off);
    next if $tag != 2;
    my $sver = unpack('C', substr($pack, 0, 1));
    next unless $sver == 4;
    my $stype = unpack('C', substr($pack, 1, 1));
    next unless $stype == 19; # positive certification of userid and pubkey
    my $plen = unpack('n', substr($pack, 4, 2));
    $pack = substr($pack, 6, $plen);
    my ($ct, $ex);
    while ($pack ne '') {
      $pack = pack('C', 0xc0).$pack;
      my ($stag, $slen, $soff) = pkdecodetaglenoff($pack);
      my $spack = substr($pack, $soff, $slen);
      $pack = substr($pack, $slen + $soff);
      $stag = unpack('C', substr($spack, 0, 1));
      $ct = unpack('N', substr($spack, 1, 4)) if $stag == 2;
      $ex = unpack('N', substr($spack, 1, 4)) if $stag == 9;
    }
    $rex = $ex if defined($ex) && (!defined($rex) || $rex > $ex);
    $rct = $ct if defined($ct) && (!defined($rct) || $rct > $ct);
  }
  return defined($rct) && defined($rex) ? $rct + $rex : undef;
}

sub pk2algo {
  my ($pk) = @_;
  my ($tag, $len, $off) = pkdecodetaglenoff($pk);
  die("not a public key\n") unless $tag == 6;
  my $pack = substr($pk, $off, $len);
  my $ver = unpack('C', substr($pack, 0, 1));
  my $algo;
  if ($ver == 3) {
    $algo = unpack('C', substr($pack, 7, 1));
  } elsif ($ver == 4) {
    $algo = unpack('C', substr($pack, 5, 1));
  } else {
    die("unknown pubkey version\n");
  }
  return 'rsa' if $algo == 1;
  return 'dsa' if $algo == 17;
  die("unknown pubkey algorithm\n");
}

sub pk2signtime {
  my ($pk) = @_; 
  my ($tag, $len, $off) = pkdecodetaglenoff($pk);
  die("not a signature\n") unless $tag == 2;
  my $pack = substr($pk, $off, $len);
  my $sver = unpack('C', substr($pack, 0, 1));
  return unpack('N', substr($pack, 3, 4)) if $sver == 3;
  die("unsupported sig version\n") if $sver != 4;
  my $plen = unpack('n', substr($pack, 4, 2));
  $pack = substr($pack, 6, $plen);
  while ($pack ne '') {
    $pack = pack('C', 0xc0).$pack;
    ($tag, $len, $off) = pkdecodetaglenoff($pack);
    my $spack = substr($pack, $off, $len);
    $pack = substr($pack, $len + $off);
    $tag = unpack('C', substr($spack, 0, 1));
    return unpack('N', substr($spack, 1, 4)) if $tag == 2;
  }
  return undef;
}

sub unarmor {
  my ($str) = @_;
  $str =~ s/.*\n\n//s;
  $str =~ s/\n=.*/\n/s;
  my $pk = MIME::Base64::decode($str);
  die("unarmor failed\n") unless $pk;
  return $pk;
}

1;
