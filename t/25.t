
#########################

# Tombstone and modseq support: conditional stores, tombstoned removes,
# and the stale write-back race they exist to close

use Test::More tests => 56;
BEGIN { use_ok('Cache::FastMmap') };
use strict;

#########################

my $FC = Cache::FastMmap->new(
  serializer => '',
  init_file => 1,
  num_pages => 89,
  page_size => 8192,
  tombstone_expire_time => 60,
);
ok(defined $FC, "created cache");

# Basic modseq store and retrieval

ok($FC->set("k1", "v1", { modseq => 5 }), "stored with modseq 5");
my $ModSeq;
is($FC->get("k1", { modseq => \$ModSeq }), "v1", "got value back");
is($ModSeq, 5, "got modseq back");

# Conditional store ordering against a live value

ok(!$FC->set("k1", "old", { modseq => 4 }), "older modseq store refused");
is($FC->get("k1"), "v1", "value unchanged after refusal");
ok($FC->set("k1", "v1b", { modseq => 5 }), "equal modseq store allowed");
ok($FC->set("k1", "v2", { modseq => 7 }), "newer modseq store allowed");
$FC->get("k1", { modseq => \$ModSeq });
is($ModSeq, 7, "modseq updated to 7");

# A plain set (no modseq) still overwrites a live modseq'd value, and
# clears its modseq

ok($FC->set("k1", "plain"), "plain set over live value allowed");
is($FC->get("k1", { modseq => \$ModSeq }), "plain", "plain value stored");
is($ModSeq, undef, "plain value has no modseq");

# Tombstoned remove: reads miss, older stores refused, newer allowed

ok($FC->set("k2", "v1", { modseq => 10 }), "stored k2 at modseq 10");
ok($FC->remove("k2", { modseq => 12 }), "tombstoned k2 at modseq 12");
is($FC->get("k2"), undef, "tombstoned key reads as miss");
ok(!$FC->exists("k2"), "tombstoned key doesn't exist");

ok(!$FC->set("k2", "stale", { modseq => 11 }), "store below tombstone refused");
ok(!$FC->set("k2", "stale"), "plain store on tombstone refused");
is($FC->get("k2"), undef, "still a miss after refused stores");

ok($FC->set("k2", "fresh", { modseq => 12 }), "store at tombstone modseq allowed");
is($FC->get("k2", { modseq => \$ModSeq }), "fresh", "fresh value stored");
is($ModSeq, 12, "fresh modseq stored");

# Tombstones never lower their modseq

ok($FC->remove("k2", { modseq => 20 }), "tombstoned k2 at modseq 20");
$FC->remove("k2", { modseq => 15 });
ok(!$FC->set("k2", "v", { modseq => 16 }),
  "older re-tombstone didn't lower the modseq");
ok($FC->set("k2", "v", { modseq => 20 }), "store at kept modseq allowed");

# get_keys hides tombstones, exposes modseqs

$FC->remove("k2", { modseq => 21 });
my @Keys = sort $FC->get_keys(0);
is_deeply(\@Keys, [ "k1" ], "get_keys(0) hides tombstones");
my @Details = grep { $_->{key} eq "k1" } $FC->get_keys(2);
is($Details[0]->{value}, "plain", "get_keys(2) value");
is($Details[0]->{modseq}, undef, "get_keys(2) no modseq on plain value");
$FC->set("k1", "ms", { modseq => 30 });
(@Details) = grep { $_->{key} eq "k1" } $FC->get_keys(2);
is($Details[0]->{value}, "ms", "get_keys(2) strips modseq prefix");
is($Details[0]->{modseq}, 30, "get_keys(2) exposes modseq");

# Plain remove deletes a tombstone entirely

ok($FC->remove("k2"), "plain remove deletes the tombstone entry");
ok($FC->set("k2", "back"), "plain set works after tombstone removed");
is($FC->get("k2"), "back", "value back");

# Tombstones expire

my $now = time;
$FC->set("k3", "v", { modseq => 5 });
$FC->remove("k3", { modseq => 6, expire_time => 30 });
ok(!$FC->set("k3", "z"), "plain store refused before tombstone expiry");
Cache::FastMmap::_set_time_override($now + 31);
ok($FC->set("k3", "z"), "plain store allowed after tombstone expiry");
Cache::FastMmap::_set_time_override();

# The write-back race this is all for: reader gets value, invalidation
# lands, reader tries to store its stale copy back

$FC->set("user", "old-user", { modseq => 100 });
my $Thawed;
$FC->get("user", { modseq => \$Thawed });
$FC->remove("user", { modseq => 101 });
ok(!$FC->set("user", "old-user", { modseq => $Thawed }),
  "stale write-back refused by tombstone");
ok($FC->set("user", "new-user", { modseq => 101 }),
  "recompute at the invalidating modseq stored");

# read_cb results are served but not cached over a tombstone

my $Reads = 0;
my $FC2 = Cache::FastMmap->new(
  serializer => '',
  init_file => 1,
  num_pages => 89,
  page_size => 8192,
  read_cb => sub { $Reads++; return "computed" },
);
$FC2->remove("r1", { modseq => 5, expire_time => 60 });
is($FC2->get("r1"), "computed", "read_cb value served over tombstone");
is($FC2->get("r1"), "computed", "read_cb value served again");
is($Reads, 2, "read_cb called each time - tombstone blocked caching");
$FC2->remove("r1");
is($FC2->get("r1"), "computed", "read_cb value served after tombstone gone");
is($Reads, 3, "read_cb called after tombstone removed");
is($FC2->get("r1"), "computed", "cached value served");
is($Reads, 3, "read_cb not called - value now cached");

# Serialized values round-trip with modseqs

my $FC3 = Cache::FastMmap->new(
  init_file => 1,
  num_pages => 89,
  page_size => 8192,
);
ok($FC3->set("s1", { a => 1, b => [ 2, 3 ] }, { modseq => 9 }), "stored ref with modseq");
is_deeply($FC3->get("s1", { modseq => \$ModSeq }), { a => 1, b => [ 2, 3 ] },
  "ref round-tripped");
is($ModSeq, 9, "ref modseq round-tripped");

# Undef values round-trip with modseqs

ok($FC->set("un1", undef, { modseq => 4 }), "stored undef with modseq");
is($FC->get("un1", { modseq => \$ModSeq }), undef, "undef round-tripped");
is($ModSeq, 4, "undef value modseq round-tripped");

# Raw utf8 values round-trip with modseqs

my $Wide = "caf\x{e9} \x{263A}";
ok($FC->set("u1", $Wide, { modseq => 3 }), "stored utf8 value with modseq");
is($FC->get("u1", { modseq => \$ModSeq }), $Wide, "utf8 value round-tripped");
is($ModSeq, 3, "utf8 value modseq round-tripped");

# get_and_set can do conditional stores via returned options

$FC->set("g1", "a", { modseq => 5 });
my ($GV, $GDidStore) = $FC->get_and_set("g1", sub { ($_[1] . "x", { modseq => 4 }) });
ok(!$GDidStore, "get_and_set with older modseq refused");
is($FC->get("g1"), "a", "get_and_set refusal left value alone");
