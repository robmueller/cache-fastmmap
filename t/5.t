
#########################

use Test::More tests => 9;
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
  page_size => 2048,
  context => \%BackingStore,
  read_cb => sub { return $_[0]->{$_[1]}; },
  write_cb => sub { $_[0]->{$_[1]} = $_[2]; },
  delete_cb => sub { delete $_[0]->{$_[1]} },
  write_action => 'write_through'
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
ok( scalar(keys %BackingStore) == 3002, "backing store size 1" );
ok( scalar(keys %CacheItems) > 500, "backing store size 2" );

# Should be equal to all items we wrote
ok( eq_hash(\%BackingStore, \%WrittenItems), "items match 1");

# Check we can get the items we wrote
is( $FC->get('foo'), '123abc',  "cb get 1");
is( $FC->get('bar'), '456def',  "cb get 2");

# Read them forward and backward
my $Failed = 0;
for (keys %WrittenItems, reverse keys %WrittenItems) {
  $Failed++ if $FC->get($_) ne $WrittenItems{$_};
}

ok( $Failed == 0, "got all written items" );

ok( eq_hash(\%WrittenItems, \%BackingStore), "items match 2");

sub RandStr {
  return join '', map { chr(ord('a') + rand(26)) } (1 .. $_[0]);
}

