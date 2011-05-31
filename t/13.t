
#########################

use Test::More;

BEGIN {
  eval "use Compress::Zlib ();";
  if ($@) {
    plan skip_all => 'No Compress::Zlib installed, no compress tests';
  } else {
    plan tests => 11;
  }
  use_ok('Cache::FastMmap');
}

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $FC = Cache::FastMmap->new(
  page_size => 8192,
  num_pages => 1,
  init_file => 1,
  raw_values => 1,
  compress => 1
);
ok( defined $FC );

my $FCNC = Cache::FastMmap->new(
  page_size => 8192,
  num_pages => 1,
  init_file => 1,
  raw_values => 1,
);
ok( defined $FCNC );

sub rand_str {
  return join '', map { chr(rand(26) + ord('a')) } 1 .. int($_[0]);
}

my $K1 = rand_str(10);
my $K2 = rand_str(10);
my $V = rand_str(10) x 1000;

ok( $FC->set($K1, $V) );
ok( $FC->set($K2, $V) );
ok( !$FCNC->set($K1, $V) );
ok( !$FCNC->set($K2, $V) );

my $CV1 = $FC->get($K1);
my $CV2 = $FC->get($K2);

ok( $CV1 eq $V );
ok( $CV2 eq $V );

$CV1 = $FCNC->get($K1);
$CV2 = $FCNC->get($K2);

ok( !defined $CV1 );
ok( !defined $CV2 );
