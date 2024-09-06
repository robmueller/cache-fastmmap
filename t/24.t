
#########################

use Test::More tests => 27;
use Test::Deep;
BEGIN { use_ok('Cache::FastMmap') };
use Data::Dumper;
use strict;

#########################

# Test version numbers

my $FC = Cache::FastMmap->new(
  init_file => 1,
  num_pages => 1,
  page_size => 65536,
  expire_time => 3,
);
ok( defined $FC );

my $only_newer_cb = sub ($k, $v, $o) {
};

ok( $FC->set('foo', '123abc', { version => 3 }), 'store item 1, version 3');

ok( $FC->set('baz', '789ghi'),    'store item 3');
is( $FC->get('foo'), '123abc',  "get item 1");
is( $FC->get('bar'), '456def',  "get item 2");
is( $FC->get('baz'), '789ghi',  "get item 3");

$now = $epoch+1;
Cache::FastMmap::_set_time_override($now);

sub cb { return ( (defined $_[1] ? $_[1] : 'boo') . 'a', { expire_on => $_[2]->{expire_on} }); };
sub cb2 { return ($_[1] . 'a'); };
is( $FC->get_and_set('foo', \&cb),  '123abca',  "get_and_set item 1 after sleep 1");
is( $FC->get_and_set('bar', \&cb),  '456defa',  "get_and_set item 2 after sleep 1");
is( $FC->get_and_set('baz', \&cb2), '789ghia',  "get_and_set item 3 after sleep 1");
is( $FC->get_and_set('gah', \&cb),  'booa',     "get_and_set item 4 after sleep 1");

my @e = $FC->get_keys(2);
cmp_deeply(
  \@e,
  bag(
    superhashof({ key => 'foo', value => '123abca', last_access => num($now, 1), expire_on => num($now+1, 1) }),
    superhashof({ key => 'bar', value => '456defa', last_access => num($now, 1), expire_on => num($now+2, 1) }),
    superhashof({ key => 'baz', value => '789ghia', last_access => num($now, 1), expire_on => num($now+3, 1) }),
    superhashof({ key => 'gah', value => 'booa',    last_access => num($now, 1), expire_on => num($now+3, 1) }),
  ),
  "got expected keys"
) || diag explain [ $now, \@e ];

$now = $epoch+2;
Cache::FastMmap::_set_time_override($now);

is( $FC->get('foo'), undef,      "get item 1 after sleep 2");
is( $FC->get('bar'), '456defa',  "get item 2 after sleep 2");
is( $FC->get('baz'), '789ghia',  "get item 3 after sleep 2");

is( $FC->get_and_set('bar', \&cb), '456defaa',  "get_and_set item 2 after sleep 2");

@e = $FC->get_keys(2);
cmp_deeply(
  \@e,
  bag(
    superhashof({ key => 'bar', value => '456defaa', last_access => num($now, 1), expire_on => num($now+1, 1) }),
    superhashof({ key => 'baz', value => '789ghia',  last_access => num($now, 1), expire_on => num($now+2, 1) }),
    superhashof({ key => 'gah', value => 'booa',     last_access => num($now-1, 1), expire_on => num($now+2, 1) }),
  ),
  "got expected keys"
) || diag explain [ $now, \@e ];

$now = $epoch+3;
Cache::FastMmap::_set_time_override($now);

is( $FC->get('foo'), undef,      "get item 1 after sleep 3");
is( $FC->get('bar'), undef,      "get item 2 after sleep 3");
is( $FC->get('baz'), '789ghia',  "get item 3 after sleep 3");

@e = $FC->get_keys(2);
cmp_deeply(
  \@e,
  bag(
    superhashof({ key => 'baz', value => '789ghia',  last_access => num($now, 1), expire_on => num($now+1, 1) }),
    superhashof({ key => 'gah', value => 'booa',     last_access => num($now-2, 1), expire_on => num($now+1, 1) }),
  ),
  "got expected keys"
) || diag explain [ $now, \@e ];

$now = $epoch+4;
Cache::FastMmap::_set_time_override($now);

is( $FC->get('foo'), undef,      "get item 1 after sleep 4");
is( $FC->get('bar'), undef,      "get item 2 after sleep 4");
is( $FC->get('baz'), undef,      "get item 3 after sleep 4");

@e = $FC->get_keys(2);
cmp_deeply(
  \@e,
  bag(),
  "got expected keys (empty)"
) || diag explain [ $now, \@e ];

$FC->empty(1);

ok( eq_hash(\%BackingStore, { foo => '123abca', bar => '456defaa', baz => '789ghia', gah => 'booa' }), "items match expire 2");


