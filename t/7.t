
#########################

use Test::More tests => 13;
BEGIN { use_ok('Cache::FastMmap') };
use strict;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

# Test a backing store just made of a local hash
my %BackingStore = (
  foo => '123abc',
  bar => '456def'
);

my %WrittenItems = %BackingStore;

my $FC = Cache::FastMmap->new(
  raw_values => 1,
  init_file => 1,
  num_pages => 89,
  page_size => 1024,
  context => \%BackingStore,
  read_cb => sub { return $_[0]->{$_[1]}; },
  write_cb => sub { $_[0]->{$_[1]} = $_[2]; },
  delete_cb => sub { delete $_[0]->{$_[1]} },
  write_action => 'write_back',
  empty_on_exit => 1
);

ok( defined $FC );

srand(6543);

# Put 3000 items in the cache
for (1 .. 3000) {
  my ($Key, $Val) = (RandStr(10), RandStr(100));
  $FC->set($Key, $Val);
  $WrittenItems{$Key} = $Val;
}

# Get values in cache
my %CacheItems = map { $_->{key} => $_->{value} } $FC->get_keys(2);

# Reality check approximate number of items in each
ok( scalar(keys %BackingStore) < 2700, "backing store size 1" );
ok( scalar(keys %CacheItems) > 300, "backing store size 2" );

# Merge with backing store items
my %AllItems = (%BackingStore, %CacheItems);

# Should be equal to all items we wrote
ok( eq_hash(\%AllItems, \%WrittenItems), "items match 1");

# Check we can get the items we wrote
is( $FC->get('foo'), '123abc',  "cb get 1");
is( $FC->get('bar'), '456def',  "cb get 2");

# Read them forward and backward, which should force
#  complete flush and read from backing store
my $Failed = 0;
for (keys %WrittenItems, reverse keys %WrittenItems) {
  $Failed++ if $FC->get($_) ne $WrittenItems{$_};
}

ok( $Failed == 0, "got all written items 1" );

# Delete some items (should be random from cache/backing store)
my @DelKeys = (keys %WrittenItems)[0 .. 300];
for (@DelKeys) {
  $FC->remove($_);
  delete $WrittenItems{$_};
}

# Check it all matches again
%CacheItems = map { $_->{key} => $_->{value} } $FC->get_keys(2);
%AllItems = (%BackingStore, %CacheItems);
ok( eq_hash(\%AllItems, \%WrittenItems), "items match 2");

$Failed = 0;
for (keys %WrittenItems) {
  $Failed++ if $FC->get($_) ne $WrittenItems{$_};
}

ok( $Failed == 0, "got all written items 2" );

# Force flushing of cache
$FC->empty();

# So all written items should be in backing store
ok( eq_hash(\%WrittenItems, \%BackingStore), "items match 3");

my @Keys = $FC->get_keys(0);
ok( scalar(@Keys) == 0, "no items left in cache" );

%WrittenItems = %BackingStore = ();

# Put 3000 items in the cache
for (1 .. 3000) {
  my ($Key, $Val) = (RandStr(10), RandStr(100));
  $FC->set($Key, $Val);
  $WrittenItems{$Key} = $Val;
}

# empty_on_exit is set, so this should push to backing store
$FC = undef;

ok( eq_hash(\%WrittenItems, \%BackingStore), "items match 4");

sub RandStr {
  return join '', map { chr(ord('a') + rand(26)) } (1 .. $_[0]);
}

