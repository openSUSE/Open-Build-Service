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

package BSSched::BuildJob::Package;

use strict;
use warnings;

use Digest::MD5 ();
use Build;		# for get_deps
use BSSolv;		# for gen_meta
use BSSched::BuildJob;

my @binsufs = qw{rpm deb pkg.tar.gz pkg.tar.xz};
my $binsufsre = join('|', map {"\Q$_\E"} @binsufs);

=head1 NAME

BSSched::BuildJob::Package - A Class to handle standard package builds

=head1 SYNOPSIS

my $h = BSSched::BuildJob::Package->new()

$h->check();

$h->expand();

$h->rebuild();

=cut

=head2 new - TODO: add summary

 TODO: add description

=cut

sub new {
  return bless({}, $_[0]);
}

=head2 expand - TODO: add summary

 TODO: add description

=cut

sub expand {
  shift;
  goto &Build::get_deps;
}

=head2 check - check if a package needs to be rebuilt

 TODO: add description

=cut

sub check {
  my ($self, $ctx, $packid, $pdata, $info, $buildtype) = @_;
  my $projid = $ctx->{'project'};
  my $repoid = $ctx->{'repository'};
  my $repo = $ctx->{'repo'};
  my $prp = $ctx->{'prp'};
  my $notready = $ctx->{'notready'};
  my $dep2src = $ctx->{'dep2src'};
  my $edeps = $ctx->{'edeps'}->{$packid} || [];
  my $depislocal = $ctx->{'depislocal'};
  my $gdst = $ctx->{'gdst'};
  my $gctx = $ctx->{'gctx'};
  my $reporoot = $gctx->{'reporoot'};
  my $myarch = $gctx->{'arch'};

  # check for localdep repos
  if (exists($pdata->{'originproject'})) {
    if ($repo->{'linkedbuild'} && $repo->{'linkedbuild'} eq 'localdep') {
      if (!grep {$depislocal->{$_}} @$edeps) {
        return ('excluded', 'project link, only depends on non-local packages');
      }
    }
  }

  # calculate if we're blocked
  my @blocked = grep {$notready->{$dep2src->{$_}}} @$edeps;
  @blocked = () if $repo->{'block'} && $repo->{'block'} eq 'never';
  if ($ctx->{'cychash'}->{$packid}) {
    # package belongs to a cycle, prune blocked list
    my $cycpass = $ctx->{'cycpass'}->{$packid} || 0;
    if (@blocked && $cycpass == 3) {
      # cycpass == 2 means that packages of this cycle are building
      # because of source changes
      print "      - $packid ($buildtype)\n";
      print "        blocked by cycle builds ($blocked[0]...)\n";
      return ('blocked', join(', ', @blocked));
    }
    my %cycs = map {$_ => 1} @{$ctx->{'cychash'}->{$packid}};
    # prune building cycle packages from blocked
    my $building = $ctx->{'building'};
    @blocked = grep {!$cycs{$dep2src->{$_}} || !$building->{$dep2src->{$_}}} @blocked;
    if (@blocked) {
      print "      - $packid ($buildtype)\n";
      print "        blocked ($blocked[0]...)\n";
    }
  }
  if (@blocked) {
    # print "      - $packid ($buildtype)\n";
    # print "        blocked\n";
    return ('blocked', join(', ', @blocked));
  }
  my $reason;
  my @meta_s = stat("$gdst/:meta/$packid");
  # we store the lastcheck data in one string instead of an array
  # with 4 elements to save precious memory
  # srcmd5.metamd5.hdrmetamd5.statdata (32+32+32+x)
  my $lastcheck = $ctx->{'lastcheck'};
  my $mylastcheck = $lastcheck->{$packid};
  my @meta;
  if (!@meta_s || !$mylastcheck || substr($mylastcheck, 96) ne "$meta_s[9]/$meta_s[7]/$meta_s[1]") {
    if (open(F, '<', "$gdst/:meta/$packid")) {
      @meta_s = stat F;
      @meta = <F>;
      close F;
      chomp @meta;
      $mylastcheck = substr($meta[0], 0, 32);
      if (@meta == 2 && $meta[1] =~ /^fake/) {
        $mylastcheck .= 'fakefakefakefakefakefakefakefake';
      } else {
        $mylastcheck .= Digest::MD5::md5_hex(join("\n", @meta));
      }
      $mylastcheck .= 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
      $mylastcheck .= "$meta_s[9]/$meta_s[7]/$meta_s[1]";
      $lastcheck->{$packid} = $mylastcheck;
    } else {
      delete $lastcheck->{$packid};
      undef $mylastcheck;
    }
  }
  if (!$mylastcheck) {
    print "      - $packid ($buildtype)\n";
    print "        no meta, start build\n";
    return ('scheduled', [ { 'explain' => 'new build' } ]);
  } elsif (substr($mylastcheck, 0, 32) ne ($pdata->{'verifymd5'} || $pdata->{'srcmd5'})) {
    print "      - $packid ($buildtype)\n";
    print "        src change, start build\n";
    return ('scheduled', [ { 'explain' => 'source change', 'oldsource' => substr($mylastcheck, 0, 32) } ]);
  } elsif (substr($mylastcheck, 32, 32) eq 'fakefakefakefakefakefakefakefake') {
    my @s = stat("$gdst/:meta/$packid");
    if (!@s || $s[9] + 14400 > time()) {
      print "      - $packid ($buildtype)\n";
      print "        buildsystem setup failure\n";
      return ('failed')
    }
    print "      - $packid ($buildtype)\n";
    print "        retrying bad build\n";
    return ('scheduled', [ { 'explain' => 'retrying bad build' } ]);
  } else {
    my $rebuildmethod = $repo->{'rebuild'} || 'transitive';
    if ($rebuildmethod eq 'local' || $pdata->{'hasbuildenv'}) {
      # rebuild on src changes only
      goto relsynccheck;
    }
    # more work, check if dep rpm changed
    if ($ctx->{'incycle'}) {
      # print "      - $packid ($buildtype)\n";
      # print "        in cycle, no source change...\n";
      return ('done');
    }
    my $check = substr($mylastcheck, 32, 32);
    my $pool = $ctx->{'pool'};
    my $dep2pkg = $ctx->{'dep2pkg'};
    $check .= $rebuildmethod;
    $check .= $pool->pkg2pkgid($dep2pkg->{$_}) for sort @$edeps;
    $check = Digest::MD5::md5_hex($check);
    if ($check eq substr($mylastcheck, 64, 32)) {
      # print "      - $packid ($buildtype)\n";
      # print "        nothing changed\n";
      goto relsynccheck;
    }
    substr($mylastcheck, 64, 32) = $check;
    # even more work, generate new meta, check if it changed
    my @new_meta;
    my $repodatas = $gctx->{'repodatas'};
    my $dep2meta = $repodatas->{"$prp/$myarch"}->{'meta'};
    $repodatas->{"$prp/$myarch"}->{'meta'} = $dep2meta = {} unless $dep2meta;
    for my $bpack (@$edeps) {
      my $pkg = $dep2pkg->{$bpack};
      my $path = $pool->pkg2fullpath($pkg, $myarch);
      if ($depislocal->{$bpack} && $path) {
        if (!exists $dep2meta->{$bpack}) {
          my @m;
          # the next line works for deb and rpm
          my $mf = substr("$reporoot/$path", 0, -4);
          #print "        reading meta for $path\n";
          if (! -e "$mf.meta") {
            # the generic version
            $mf = "$reporoot/$path";
            $mf =~ s/\.(?:$binsufsre)$//;
          }
          if (open(F, '<', "$mf.meta") || open(F, '<', "$mf-MD5SUMS.meta")) {
            @m = <F>;
            close F;
            chomp @m;
            s/  /  $bpack\// for @m;
          }
          @m = ($pool->pkg2pkgid($pkg)."  $bpack") unless @m;
          $dep2meta->{$bpack} = join("\n", @m);
          # do not include our own build results
          next if $m[0] =~ /\/\Q$packid\E$/s;
          # fixup first line
          $m[0] =~ s/  .*/  $bpack/;
          push @new_meta, @m;
        } else {
          my $oldlen = @new_meta;
          push @new_meta, split("\n", $dep2meta->{$bpack});
          next if $oldlen == @new_meta;         # hmm?
          # do not include our own build results
          if ($new_meta[$oldlen] =~ /\/\Q$packid\E$/) {
            splice(@new_meta, $oldlen);
            next;
          }
          # fixup first line
          $new_meta[$oldlen] =~ s/  .*/  $bpack/;
        }
      } else {
        my $pkgid = $pool->pkg2pkgid($pkg);
        push @new_meta, "$pkgid  $bpack";
      }
    }
    @new_meta = BSSolv::gen_meta($ctx->{'subpacks'}->{$info->{'name'}} || [], @new_meta);
    unshift @new_meta, ($pdata->{'verifymd5'} || $pdata->{'srcmd5'})."  $packid";
    if (Digest::MD5::md5_hex(join("\n", @new_meta)) eq substr($mylastcheck, 32, 32)) {
      # print "      - $packid ($buildtype)\n";
      # print "        nothing changed (looked harder)\n";
      $ctx->{'nharder'}++;
      $lastcheck->{$packid} = $mylastcheck;
      goto relsynccheck;
    }
    # something changed, read in old meta (if not already done)
    if (!@meta && open(F, '<', "$gdst/:meta/$packid")) {
      @meta = <F>;
      close F;
      chomp @meta;
    }
    if ($rebuildmethod eq 'direct') {
      @meta = grep {!/\//} @meta;
      @new_meta = grep {!/\//} @new_meta;
    }
    if (@meta == @new_meta && join('\n', @meta) eq join('\n', @new_meta)) {
      # print "      - $packid ($buildtype)\n";
      # print "        nothing changed (looked harder)\n";
      $ctx->{'nharder'}++;
      if ($rebuildmethod eq 'direct') {
        $lastcheck->{$packid} = $mylastcheck;
      } else {
        # should not happen, delete lastcheck cache
        delete $lastcheck->{$packid};
      }
      goto relsynccheck;
    }
    my @diff = BSSched::BuildJob::diffsortedmd5(\@meta, \@new_meta);
    my $reason = BSSched::BuildJob::sortedmd5toreason(@diff);
    print "      - $packid ($buildtype)\n";
    print "        $_\n" for @diff;
    print "        meta change, start build\n";
    return ('scheduled', [ { 'explain' => 'meta change', 'packagechange' => $reason } ] );
  }
relsynccheck:
  if ($ctx->{'relsynctrigger'}->{$packid}) {
    print "      - $packid ($buildtype)\n";
    print "        rebuild counter sync, start build\n";
    return ('scheduled', [ { 'explain' => 'rebuild counter sync' } ] );
  }
  return ('done');
}

=head2 build - create a package build job

 TODO: add description

=cut

sub build {
  my ($self, $ctx, $packid, $pdata, $info, $data) = @_;

  my $reason = $data->[0];
  my $needed = $ctx->{'rebuildpackage_needed'};
  if (!$needed) {
    $needed = $ctx->{'rebuildpackage_needed'} = {};
    my $edeps = $ctx->{'edeps'};
    my $dep2src = $ctx->{'dep2src'};
    for my $p (keys %$edeps) {
      $needed->{$_}++ for map { $dep2src->{$_} || $_ } @{$edeps->{$p}};
    }
  }
  $info->{'nounchanged'} = 1 if $ctx->{'cychash'}->{$packid};
  my ($state, $job) = BSSched::BuildJob::create($ctx, $packid, $pdata, $info, $ctx->{'subpacks'}->{$info->{'name'}} || [], $ctx->{'edeps'}->{$packid} || [], $reason, $needed->{$packid} || 0);
  delete $info->{'nounchanged'};
  return ($state, $job);
}

1;
