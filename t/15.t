
#########################

use Test::More tests => 9;
BEGIN { use_ok('Cache::FastMmap') };
use strict;

#########################

# Test writeback and cache_not_found option

# Test a backing store just made of a local hash
my %BackingStore = (
  foo => { key1 => '123abc' },
  bar => undef
);

my %OrigBackingStore = %BackingStore;

my $RCBCalled = 0;

my $FC = Cache::FastMmap->new(
  cache_not_found => 1,
  init_file => 1,
  num_pages => 89,
  page_size => 2048,
  context => \%BackingStore,
  read_cb => sub { $RCBCalled++; return $_[0]->{$_[1]}; },
  write_cb => sub { $_[0]->{$_[1]} = $_[2]; },
  delete_cb => sub { delete $_[0]->{$_[1]} },
  write_action => 'write_back'
);

ok( defined $FC );

# Should pull from the backing store
ok( eq_hash( $FC->get('foo'), { key1 => '123abc' } ),  "cb get foo is hash");
is( $FC->get('bar'), undef,  "cb get bar is undef");
is( $RCBCalled, 2,  "cb get read callback called twice");

# Should be in the cache now
ok( eq_hash( $FC->get('foo'), { key1 => '123abc' } ),  "cb get foo is hash");
is( $FC->get('bar'), undef,  "cb get bar is undef");
is( $RCBCalled, 2,  "cb get read callback still only called twice");

# Need to make them dirty
$FC->set('foo', { key1 => '123abc' });
$FC->set('bar', undef);

# Should force cache data back to backing store
%BackingStore = ();
$FC->empty();

ok( eq_hash(\%BackingStore, \%OrigBackingStore), "items match in store")
  or diag explain [ \%BackingStore, \%OrigBackingStore ];

