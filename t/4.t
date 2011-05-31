
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
  num_pages => 3,
  page_size => 32768,
  context => \%BackingStore,
  read_cb => sub { return $_[0]->{$_[1]}; },
  write_cb => sub { $_[0]->{$_[1]} = $_[2]; },
  delete_cb => sub { delete $_[0]->{$_[1]} },
  write_action => 'write_back'
);

ok( defined $FC );

srand(6543);

# Put 100 items in the cache (should be big enough)
for (1 .. 100) {
  my ($Key, $Val) = (RandStr(10), RandStr(100));
  $FC->set($Key, $Val);
  $WrittenItems{$Key} = $Val;
}

# Should only be 2 items in the backing store
ok( scalar(keys %BackingStore) == 2, "items match 1");

# Should flush back all the items to backing store
$FC->empty();

# Get values in cache should be empty
my %CacheItems = map { $_->{key} => $_->{value} } $FC->get_keys(2);
ok( scalar(keys %CacheItems) == 0, "empty cache");

# Backing store should be equal to all items we wrote
ok( eq_hash(\%WrittenItems, \%BackingStore), "items match 1");

# Should be able to read all items
my $Failed = 0;
for (keys %WrittenItems) {
  $Failed++ if $FC->get($_) ne $WrittenItems{$_};
}

ok( $Failed == 0, "got all written items 1" );

# Empty backing store
%BackingStore = ();

# Should still be able to read all items
$Failed = 0;
for (keys %WrittenItems) {
  $Failed++ if $FC->get($_) ne $WrittenItems{$_};
}

ok( $Failed == 0, "got all written items 2" );

# Now there should be nothing left
$FC->clear();

%CacheItems = map { $_->{key} => $_->{value} } $FC->get_keys(2);
ok( scalar(keys %CacheItems) == 0, "empty cache 2");
ok( scalar(keys %BackingStore) == 0, "empty backing store 1");

sub RandStr {
  return join '', map { chr(ord('a') + rand(26)) } (1 .. $_[0]);
}

