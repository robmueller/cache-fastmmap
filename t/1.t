
#########################

use Test::More tests => 56;
BEGIN { use_ok('Cache::FastMmap') };
use strict;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $FC = Cache::FastMmap->new(init_file => 1, raw_values => 1);
ok( defined $FC );

# Test empty cache
ok( !defined $FC->get(''),          "empty get('')" );
ok( !defined $FC->get(' '),         "empty get(' ')" );
ok( !defined $FC->get(' ' x 1024),  "empty get(' ' x 1024)" );
ok( !defined $FC->get(' ' x 65536), "empty get(' ' x 65536)" );

# Test basic store/get on key sizes
ok( $FC->set('', 'abc'),          "set('', 'abc')" );
is( $FC->get(''), 'abc',          "get('') eq 'abc'");

ok( $FC->set(' ', 'def'),         "set(' ', 'def')" );
is( $FC->get(' '), 'def',         "get(' ') eq 'def'");

ok( $FC->set(' ' x 1024, 'ghi'),  "set(' ' x 1024, 'ghi')");
is( $FC->get(' ' x 1024), 'ghi',  "get(' ' x 1024) eq 'ghi'");

# Bigger than the page size - should not work
ok( !$FC->set(' ' x 65536, 'jkl'),  "set(' ' x 65536, 'jkl')");
ok( !defined $FC->get(' ' x 65536), "empty get(' ' x 65536)");

# Test basic store/get on value sizes
ok( $FC->set('abc', ''),          "set('abc', '')");
is( $FC->get('abc'), '',          "get('abc') eq ''");

ok( $FC->set('def', 'x'),         "set('def', 'x')");
is( $FC->get('def'), 'x',         "get('def') eq 'x'");

ok( $FC->set('ghi', 'x' . ('y' x 1024) . 'z'), "set('ghi', ...)");
is( $FC->get('ghi'), 'x' . ('y' x 1024) . 'z', "get('ghi') eq ...");

# Bigger than the page size - should not work
ok( !$FC->set('jkl', 'x' . ('y' x 65536) . 'z'), "set('jkl', ...)");
ok( !defined $FC->get('jkl'), "empty get('jkl')" );

# Ref key should use 'stringy' version
my $Ref = [ ];
ok( $FC->set($Ref, 'abcd'),   "set($Ref)" );
is( $FC->get($Ref), 'abcd',   "get($Ref)" );
is( $FC->get("$Ref"), 'abcd', "get(\"$Ref\")" );

# Check UTF8
ok( $FC->set("key\x{263A}", "val"), "set utf8 key" );
is( $FC->get("key\x{263A}"), "val", "get utf8 key" );

ok( $FC->set("key", "val\x{263A}"), "set utf8 val" );
is( $FC->get("key"), "val\x{263A}", "get utf8 val" );

ok( $FC->set("key2\x{263A}", "val2\x{263A}"), "set utf8 key/val" );
is( $FC->get("key2\x{263A}"), "val2\x{263A}", "get utf8 key/val" );

# Check clearing actually works
$FC->clear();

ok( !defined $FC->get('abc'), "post clear 1" );
ok( !defined $FC->get('def'), "post clear 2" );
ok( !defined $FC->get('ghi'), "post clear 3" );
ok( !defined $FC->get('jkl'), "post clear 4" );
ok( !defined $FC->get("key"), "post clear 5" );
ok( !defined $FC->get("key\x{263A}"), "post clear 6" );
ok( !defined $FC->get("key2\x{263A}"), "post clear 7" );

# Check getting key/value lists
ok( $FC->set("abc", "123"), "get_keys set 1" );
ok( $FC->set("bcd", "234"), "get_keys set 2" );
ok( $FC->set("cde", "345"), "get_keys set 3" );

is( join(",", sort $FC->get_keys), "abc,bcd,cde", "get_keys 1");

my %keys = map { $_->{key} => $_ } $FC->get_keys(2);
is( scalar(keys %keys), 3, "get_keys 2" );
is($keys{abc}->{value}, "123", "get_keys 3");
is($keys{bcd}->{value}, "234", "get_keys 4");
is($keys{cde}->{value}, "345", "get_keys 5");

# Test getting key/value lists with UTF8
$FC->set("def\x{263A}", "456\x{263A}");

is( join(",", sort $FC->get_keys), "abc,bcd,cde,def\x{263A}", "get_keys 6");

%keys = map { $_->{key} => $_ } $FC->get_keys(2);
is( scalar(keys %keys), 4 , "get_keys 7");
is($keys{abc}->{value}, "123", "get_keys 8");
is($keys{bcd}->{value}, "234", "get_keys 9");
is($keys{cde}->{value}, "345", "get_keys 10");
is($keys{"def\x{263A}"}->{value}, "456\x{263A}", "get_keys 11");

# basic multi_* tests

$FC->multi_set("page1", { k1 => 1, k2 => 2 });
$FC->multi_set("page2", { k3 => 1, k4 => 2 });
my $R = $FC->multi_get("page1", [ qw(k1 k2) ]);
is($R->{k1}, 1, "multi_get 1");
is($R->{k2}, 2, "multi_get 2");
$R = $FC->multi_get("page2", [ qw(k3 k4) ]);
is($R->{k3}, 1, "multi_get 3");
is($R->{k4}, 2, "multi_get 4");
