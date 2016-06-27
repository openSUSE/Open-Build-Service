use strict;
use warnings;


use FindBin;
use lib "$FindBin::Bin/lib/";

use Test::Mock::BSRPC;
use Test::Mock::BSConfig;
use Test::OBS;

use Test::More tests => 3;                      # last test to print

use BSUtil;
use BSXML;
use Data::Dumper;

no warnings 'once';
# preparing data directory for testcase 1
$BSConfig::bsdir = "$FindBin::Bin/data/0360/";
$BSConfig::srcserver = 'srcserver';
$BSConfig::repodownload = 'http://download.opensuse.org/repositories';
use warnings;

use_ok("BSRepServer::BuildInfo");

$Test::Mock::BSRPC::fixtures_map = {
  %{$Test::Mock::BSRPC::fixtures_map},
#  'srcserver/getprojpack?withsrcmd5&withdeps&withrepos&expandedrepos&withremotemap&ignoredisable&project=openSUSE:13.2&repository=standard&arch=i586&parseremote=1&package=screen' => '../shared/srcserver/fixtures_00001',
  'srcserver/getprojpack?withsrcmd5&withdeps&withrepos&expandedrepos&withremotemap&ignoredisable&project=home:Admin:branches:openSUSE.org:OBS:Server:Unstable&repository=openSUSE_Leap_42.1&arch=x86_64&parseremote=1&package=_product:OBS-Addon-release'
        => 'srcserver/fixture_003_000',
  'srcserver/getconfig?project=home:Admin:branches:openSUSE.org:OBS:Server:Unstable&repository=openSUSE_Leap_42.1'
        => 'srcserver/fixture_003_001',
};


my ($got,$expected);

### Test Case 01
($got) = BSRepServer::BuildInfo->new(projid=>'openSUSE:13.2', repoid=>'standard', arch=>'i586', packid=>'screen')->getbuildinfo();
$expected = BSUtil::readxml("$BSConfig::bsdir/result/tc01", $BSXML::buildinfo);

cmp_buildinfo($got, $expected, 'buildinfo for screen');

# Test Case 02
{
  local *STDOUT;
  my $out;
  if ( ! $ENV{DEBUG} ) {
    open(STDOUT,">",\$out);
  }

  ($got) = BSRepServer::BuildInfo->new(projid=>'home:Admin:branches:openSUSE.org:OBS:Server:Unstable', repoid=>'openSUSE_Leap_42.1', arch=>'x86_64', packid=>'_product:OBS-Addon-release')->getbuildinfo();

  $expected = Test::OBS::Utils::readxmlxz("$BSConfig::bsdir/result/tc02", $BSXML::buildinfo);
}

cmp_buildinfo($got, $expected, 'buildinfo for regular Package with remotemap');

exit 0;
