
#########################

use Test::More tests => 46;
BEGIN { use_ok('Cache::FastMmap') };
use strict;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $FC = Cache::FastMmap->new(init_file => 1, expire_time => 3, raw_values => 1);
ok( defined $FC );
my $FC2 = Cache::FastMmap->new(init_file => 1, expire_time => 5, raw_values => 1);
ok( defined $FC2 );


ok( $FC->set('abc', '123'),    "expire set 1");
is( $FC->get('abc'), '123',    "expire get 2");

ok( $FC2->set('abc', '123'),    "expire set 3");
ok( $FC2->set('def', '123', 3), "expire set 4");
ok( $FC2->set('ghi', '123', 'now'), "expire set 5");
ok( $FC2->set('jkl', '123', 'never'), "expire set 6");
is( $FC2->get('abc'), '123',    "expire get 7");
is( $FC2->get('def'), '123',    "expire get 8");
is( $FC2->get('ghi'), '123',    "expire get 9");
is( $FC2->get('jkl'), '123',    "expire get 10");

sleep(2);

ok( $FC->set('def', '456'),    "expire set 11");
is( $FC->get('abc'), '123',    "expire get 12");
is( $FC->get('def'), '456',    "expire get 13");

is( $FC2->get('abc'), '123',    "expire get 14");
is( $FC2->get('def'), '123',    "expire get 15");
ok( !defined $FC2->get('ghi'),  "expire get 16");
is( $FC2->get('jkl'), '123',    "expire get 17");

sleep(2);

ok( !defined $FC->get('abc'),  "expire get 18");
is( $FC->get('def'), '456',    "expire get 19");

is( $FC2->get('abc'), '123',    "expire get 20");
ok( !defined $FC2->get('def'),  "expire get 21");
ok( !defined $FC2->get('ghi'),  "expire get 22");
is( $FC2->get('jkl'), '123',    "expire get 23");

sleep(2);

ok( !defined $FC->get('abc'),  "expire get 24");
ok( !defined $FC->get('def'),  "expire get 25");

ok( !defined $FC2->get('abc'),  "expire get 26");
ok( !defined $FC2->get('def'),  "expire get 27");
ok( !defined $FC2->get('ghi'),  "expire get 28");
is( $FC2->get('jkl'), '123',    "expire get 29");

ok( $FC->set('abc', '123', '1s'),  "expire set 31");
ok( $FC->set('abc', '123', '1m'),  "expire set 32");
ok( $FC->set('abc', '123', '1d'),  "expire set 33");
ok( $FC->set('abc', '123', '1w'),  "expire set 34");

ok( $FC->set('abc', '123', '1 second'),  "expire set 41");
ok( $FC->set('abc', '123', '1 minute'),  "expire set 42");
ok( $FC->set('abc', '123', '1 day'),     "expire set 43");
ok( $FC->set('abc', '123', '1 week'),    "expire set 44");

ok( $FC->set('abc', '123', 'now'),       "expire set 45");
ok( $FC->set('abc', '123', 'never'),     "expire set 46");

ok( $FC->set('abc', '123', 's'),         "expire set 47");
ok( $FC->set('abc', '123', ''),          "expire set 48");
ok( $FC->set('abc', '123', -1),          "expire set 49");
ok( $FC->set('abc', '123', 'garbage'),   "expire set 50");
