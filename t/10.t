
#########################

use Test::More tests => 9;
BEGIN { use_ok('Cache::FastMmap') };
use Data::Dumper;
use strict;

#########################

# Test writeback and cache_not_found option

# Test a backing store just made of a local hash
my %BackingStore = (
  foo => '123abc',
  bar => undef
);

my %OrigBackingStore = %BackingStore;

my $RCBCalled = 0;

my $FC = Cache::FastMmap->new(
  cache_not_found => 1,
  raw_values => 1,
  init_file => 1,
  num_pages => 89,
  page_size => 1024,
  context => \%BackingStore,
  read_cb => sub { $RCBCalled++; return $_[0]->{$_[1]}; },
  write_cb => sub { $_[0]->{$_[1]} = $_[2]; },
  delete_cb => sub { delete $_[0]->{$_[1]} },
  write_action => 'write_back'
);

ok( defined $FC );

# Should pull from the backing store
is( $FC->get('foo'), '123abc',  "cb get 1");
is( $FC->get('bar'), undef,  "cb get 2");
is( $RCBCalled, 2,  "cb get 2");

# Should be in the cache now
is( $FC->get('foo'), '123abc',  "cb get 3");
is( $FC->get('bar'), undef,  "cb get 4");
is( $RCBCalled, 2,  "cb get 2");

$FC->set('foo', '123abc');
$FC->set('bar', undef);

# Should force cache data back to backing store
%BackingStore = ();
$FC->empty();

ok( eq_hash(\%BackingStore, \%OrigBackingStore), "items match 1" . Dumper(\%BackingStore, \%OrigBackingStore));

