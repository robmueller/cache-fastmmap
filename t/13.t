use strict;
use warnings;

use Test::More;
use Data::Dumper;
$Data::Dumper::Deparse = 1;

BEGIN {
  note 'Compression testing';
  use_ok('Cache::FastMmap');
}

my %compressors = (
  lz4    => 'Compress::LZ4',
  snappy => 'Compress::Snappy',
  zlib   => 'Compress::Zlib',
);

for my $compressor ( keys %compressors ) {
  note "  Testing with $compressors{$compressor}";
  # Avoid prototype mismatch warnings
  if ( ! eval "require $compressors{$compressor};" ) {
    note "  Cannot load $compressors{$compressor}: skipping tests: reason: $@";
    next;
  }

  my $FC = Cache::FastMmap->new(
    page_size  => 8192,
    num_pages  => 1,
    init_file  => 1,
    serializer => '',
    compressor => $compressor
  );
  ok( defined $FC,          'create compressing cache' );

  my $FCNC = Cache::FastMmap->new(
    page_size  => 8192,
    num_pages  => 1,
    init_file  => 1,
    serializer => '',
  );
  ok( defined $FCNC,        'create non-compressing cache of same size' );

  my $K1 = rand_str(10);
  my $K2 = rand_str(10);
  my $V = rand_str(10) x 1000;

  ok( $FC->set($K1, $V),    'set() with large value in compressing cache' );
  ok( $FC->set($K2, $V),    'also set() same value with different key' );
  ok( !$FCNC->set($K1, $V), 'cannot set() same value in non-compressing cache' );
  ok( !$FCNC->set($K2, $V), 'also fail to set() with different key' );

  my $CV1 = $FC->get($K1);
  my $CV2 = $FC->get($K2);

  is( $CV1, $V,             'get() same large value from compressing cache' );
  is( $CV2, $V,             'also get() same value with second key used' );

  $CV1 = $FCNC->get($K1);
  $CV2 = $FCNC->get($K2);

  ok( !defined $CV1,        'cannot get() anything from non-compressing cache' );
  ok( !defined $CV2,        'also fail to get() with second key used' );
}

note '  Check support for deprecated `compress` param';
for ( 1, 'Compress::NonExistent', 'Compress::LZ4' ) {
  my $DCNC = Cache::FastMmap->new(
    page_size  => 8192,
    num_pages  => 1,
    init_file  => 1,
    serializer => '',
    compress   => $_,
  );

  ok( defined $DCNC,        'create cache with `compress` param: ' . $_ );

  my $wanted = quotemeta('&$uncompress(my $Tmp = shift())');
  $wanted = qr/$wanted/;
  my $got = Dumper $DCNC->{uncompress};
  like( $got, $wanted,      'using `Compress::Zlib` as compressor' );
}


done_testing;

sub rand_str {
    return join '', map { chr(rand(26) + ord('a')) } 1 .. int($_[0]);
}

__END__
