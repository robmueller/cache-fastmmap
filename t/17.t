
#########################

use Test::More tests => 206;
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

# Store 56000 bytes in cache
ok($FC->set("foo", "a" x 28000), "set foo");
ok($FC->set("bar", "b" x 28000), "set bar");

# Store 100 items (> 89 slots), but immediately delete. Each item uses
#  a slot + about (8*6 + 8) = 56 bytes * 100 slots = 5600 bytes,
#  make sure 56000 + 5600 < 65536
for (1 .. 100) {
  ok($FC->set("a", "$_"), "set $_");
  ok($FC->get("a") eq "$_", "get $_");
  $FC->remove("a");
}

# Since each item we added above was immediately deleted, our
#  original items should still be cached, check that
ok($FC->get("foo") eq "a" x 28000, "get foo");
ok($FC->get("bar") eq "b" x 28000, "get bar");
