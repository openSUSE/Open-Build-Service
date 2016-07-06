use strict;
use warnings;


use FindBin;
use lib "$FindBin::Bin/lib/";

use Test::Mock::BSRPC;
use Test::Mock::BSConfig;
use Test::OBS::Utils;
use Test::OBS;
use Test::Mock::BSRepServer::Checker;

use Test::More tests => 2;                      # last test to print

use BSUtil;
use BSXML;
use Data::Dumper;
use XML::Structured;


no warnings 'once';
# preparing data directory for testcase 1
$BSConfig::bsdir = "$FindBin::Bin/data/0380";


$Test::Mock::BSRPC::fixtures_map = {
  # rpc call to fixture map
    "srcserver/getprojpack?withsrcmd5&withdeps&withrepos&expandedrepos&withremotemap&ignoredisable&project=home:Admin:branches:openSUSE.org:OBS:Server:2.7&repository=images&arch=x86_64&parseremote=1&package=_product:OBS-Addon-cd-cd-x86_64" => "srcserver/fixture_00001.xz"
};
use warnings;

use_ok("BSRepServer::BuildInfo");

my ($got,$expected);

# Test Case 01
{
  ($got) = BSRepServer::BuildInfo->new(projid=>'home:Admin:branches:openSUSE.org:OBS:Server:2.7', repoid=>'images', arch=>'x86_64', packid=>'_product:OBS-Addon-cd-cd-x86_64')->getbuildinfo();

  $expected = Test::OBS::Utils::readxmlxz("$BSConfig::bsdir/result/tc01", $BSXML::buildinfo);
}
cmp_buildinfo($got, $expected, 'buildinfo for Kiwi Product with remotemap');

exit 0;

