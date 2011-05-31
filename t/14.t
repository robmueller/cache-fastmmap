
#########################

use Test::More tests => 110;
BEGIN { use_ok('Cache::FastMmap') };
use strict;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $FC = Cache::FastMmap->new(
  enable_stats => 1
);

ok( defined $FC );

ok( !defined $FC->get("a") );
$FC->set("a", "b");
ok( $FC->get("a") eq "b" );

# Get 100 times
for (1 .. 100) {
  ok( $FC->get("a") eq "b" );
}

my ($nreads, $nreadhits) = $FC->get_statistics();

cmp_ok( $nreads, '==', 102 );
cmp_ok( $nreadhits, '==', 101 );

($nreads, $nreadhits) = $FC->get_statistics(1);

cmp_ok( $nreads, '==', 102 );
cmp_ok( $nreadhits, '==', 101 );

($nreads, $nreadhits) = $FC->get_statistics(1);

cmp_ok( $nreads, '==', 0 );
cmp_ok( $nreadhits, '==', 0 );

