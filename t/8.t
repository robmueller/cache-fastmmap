
#########################

use Test::More tests => 17;
BEGIN { use_ok('Cache::FastMmap') };
use strict;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $FC = Cache::FastMmap->new(init_file => 1, raw_values => 0);
ok( defined $FC );

# Test empty cache
ok( !defined $FC->get(''),          "empty get('')" );

ok( $FC->set('123', 'abc'),          "set('123', 'abc')" );
ok( $FC->get('123') eq 'abc',        "get('123') eq 'abc'");

ok( $FC->set('123', undef),          "set('123', undef)" );
ok( !defined $FC->get('123'),        "!defined get('123')");

ok( $FC->set('123', [ 'abc' ]),          "set('123', [ 'abc' ])" );
ok( eq_array($FC->get('123'), [ 'abc' ]),    "get('123') eq [ 'abc' ]");

# Check UTF8
ok( $FC->set("key\x{263A}", [ "val\x{263A}" ]), "set utf8 key/val" );
ok( eq_array($FC->get("key\x{263A}"), [ "val\x{263A}" ]), "get utf8 key/val" );

is( join(",", sort $FC->get_keys), "123,key\x{263A}", "get_keys 1");

my %keys = map { $_->{key} => $_ } $FC->get_keys(2);
is( scalar(keys %keys), 2, "get_keys 2" );
ok( eq_array($keys{123}->{value}, [ "abc" ]), "get_keys 3");
ok( eq_array($keys{"key\x{263A}"}->{value}, [ "val\x{263A}" ]), "get_keys 4");

# Check clearing actually works
$FC->clear();

ok( !defined $FC->get('123'), "post clear 1" );
ok( !defined $FC->get("key\x{263A}"), "post clear 6" );

