
#########################

use Test::More tests => 186;
BEGIN { use_ok('Cache::FastMmap') };
use Storable qw(freeze thaw);
use strict;

#########################

# Test that we actually re-use deleted slots in a cache

my $FC = Cache::FastMmap->new(
  page_size => 65536,
  num_pages => 1,
  init_file => 1,
  serializer => '',
  start_slots => 89,
);
ok( defined $FC );

ok($FC->set("foo", "a" x 31000), "set foo");
ok($FC->set("bar", "b" x 31000), "set bar");

for (1 .. 90) {
  ok($FC->set("a", "$_"), "set $_");
  ok($FC->get("a") eq "$_", "get $_");
  $FC->remove("a");
}

ok($FC->get("foo") eq "a" x 31000, "get foo");
ok($FC->get("bar") eq "b" x 31000, "get bar");
