
#########################

use Test::More tests => 19;
BEGIN { use_ok('Cache::FastMmap') };
use Data::Dumper;
use strict;

#########################

# Test maintaining write back of expired items after get

# Test a backing store just made of a local hash
my %BackingStore = ();

my $FC = Cache::FastMmap->new(
  serializer => '',
  init_file => 1,
  num_pages => 1,
  page_size => 8192,
  context => \%BackingStore,
  write_cb => sub { $_[0]->{$_[1]} = $_[2]; },
  delete_cb => sub { delete $_[0]->{$_[1]} },
  write_action => 'write_back'
);

my $epoch = time;
my $now = $epoch;
Cache::FastMmap::_set_time_override($now);

ok( defined $FC );

ok( $FC->set('foo', '123abc', 1), 'store item 1');
ok( $FC->set('bar', '456def', 2), 'store item 2');
ok( $FC->set('baz', '789ghi', 3), 'store item 3');
is( $FC->get('foo'), '123abc',  "get item 1");
is( $FC->get('bar'), '456def',  "get item 2");
is( $FC->get('baz'), '789ghi',  "get item 3");

$now = $epoch+1;
Cache::FastMmap::_set_time_override($now);

is( $FC->get('foo'), undef,     "get item 1 after sleep 1");
is( $FC->get('bar'), '456def',  "get item 2 after sleep 1");
is( $FC->get('baz'), '789ghi',  "get item 3 after sleep 1");

$FC->empty(1);

ok( eq_hash(\%BackingStore, { foo => '123abc' }), "items match expire 1" );

$FC->expire('baz');
$FC->expire('dummy');

ok( eq_hash(\%BackingStore, { foo => '123abc', baz => '789ghi' }), "items match explicit expire" );

is( $FC->get('baz'), undef,  "get item 3 after explicit expire");

$now = $epoch+2;
Cache::FastMmap::_set_time_override($now);

is( $FC->get('foo'), undef,  "get item 1 after sleep 2");
is( $FC->get('bar'), undef,  "get item 2 after sleep 2");
is( $FC->get('baz'), undef,  "get item 3 after sleep 2");

$FC->empty(1);

ok( eq_hash(\%BackingStore, { foo => '123abc', bar => '456def', baz => '789ghi' }), "items match expire 2");

$FC->remove('foo');

ok( eq_hash(\%BackingStore, { bar => '456def', baz => '789ghi' }), "items match remove 1");


