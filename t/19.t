
#########################

use Test::More;

BEGIN {
  eval "use JSON (); use Sereal ();";
  if ($@) {
    plan skip_all => 'No JSON/Sereal, no json/sereal storage tests';
  } else {
    plan tests => 7;
  }
  use_ok('Cache::FastMmap');
}

use Time::HiRes qw(time);
use Data::Dumper;
use strict;

#########################

my $FCStorable = Cache::FastMmap->new(serializer => 'storable', init_file => 1);
ok( defined $FCStorable );
my $FCJson = Cache::FastMmap->new(serializer => 'json', init_file => 1);
ok( defined $FCJson );
my $FCSereal = Cache::FastMmap->new(serializer => 'sereal', init_file => 1);
ok( defined $FCSereal );

eval { $FCJson->set("foo2", { key1 => '123abc', key2 => \"bar" }); };
ok( $@ =~ /cannot encode reference to scalar/ );

my $StorableTime = DoTests($FCStorable);
my $JsonTime = DoTests($FCJson);
my $SerealTime = DoTests($FCSereal);

ok ($StorableTime > $SerealTime, "Sereal faster than storable");
ok ($StorableTime > $JsonTime, "Json faster than storable");

sub DoTests {
  my $FC = shift;

  for (1..10000) {
    $FC->set("foo$_", { key1 => 'boom', key2 => "woot$_" });
  }

  my $Start = time;
  for (1..10000) {
    $FC->set("foo$_", { key1 => '123abc', key2 => "bar$_" });
    my $H = $FC->get("foo$_");
    keys %$H == 2 || die;
    $H->{key1} eq '123abc' || die;
    $H->{key2} eq "bar$_" || die;
  }
  my $End = time;
  return $End-$Start;
}

