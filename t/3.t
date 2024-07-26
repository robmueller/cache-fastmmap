
#########################

use Test::More tests => 8;
BEGIN { use_ok('Cache::FastMmap') };
use strict;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

# Default cache should be large enough to fit everything with our initial run of writes/reads
my $FC = Cache::FastMmap->new(init_file => 1, serializer => '');
ok( defined $FC );

my (@Keys, $HitRate);

# read ratio = 0.0 means only writes, so no hits at all, but we add to the cache
$HitRate = RepeatMixTest($FC, 1000, 0.0, \@Keys);
ok( $HitRate == 0.0, "hit rate should be 0.0 with ratio 0.0");

# read ratio = 0.5, we should find everything in the cache that's already there or that we add
$HitRate = RepeatMixTest($FC, 1000, 0.5, \@Keys);
ok( $HitRate == 1.0, "hit rate should be 1.0 with ratio 0.5");

# read ratio = 0.8, we should find everything in the cache that's already there or that we add
$HitRate = RepeatMixTest($FC, 1000, 0.8, \@Keys);
ok( $HitRate == 1.0, "hit rate should be 1.0 with ration 0.8");

$FC = undef;
@Keys = ();

# Should be repeatable
srand(123456);

# Have a specific size limited cache, and we'll check a hit ratio around what we expect
$FC = Cache::FastMmap->new(
  init_file => 1,
  page_size => 16384,
  num_pages => 61,
  serializer => ''
);
ok( defined $FC );

$HitRate = RepeatMixTest($FC, 1000, 0.0, \@Keys);
ok( $HitRate == 0.0, "hit rate should be 0.0 with ratio 0.0");
# Heuristic from measurement
$HitRate = RepeatMixTest($FC, 10000, 0.5, \@Keys);
ok( $HitRate > 0.8 && $HitRate < 0.95, "hit rate with ratio 0.5 should be > 0.8 and < 0.95 - $HitRate");


sub RepeatMixTest {
  my ($FC, $NItems, $Ratio, $WroteKeys) = @_;

  my ($Read, $ReadHit);

  # Lots of random tests
  for (1 .. $NItems) {

    # Read/write ratio
    if (rand() < $Ratio) {

      # Pick a key from known written ones
      my $K = $WroteKeys->[ rand(@$WroteKeys) ];
      my $V = $FC->get($K);
      $Read++;

      # Skip if not found in cache
      next if !defined $V;
      $ReadHit++;

      # Offset of 10 past first chars of value are key
      substr($V, 10, length($K)) eq $K
        || die "Cache/key not equal: $K, $V";

    } else {

      my $K = RandStr(16);
      my $V = RandStr(10) . $K . RandStr(int(rand(200)));
      push @$WroteKeys, $K;
      $FC->set($K, $V);

    }
  }

  return $Read ? ($ReadHit/$Read) : 0.0;
}

sub RandStr {
  return join '', map { chr(ord('a') + rand(26)) } (1 .. $_[0]);
}

