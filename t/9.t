
#########################

use Test::More tests => 5;
BEGIN { use_ok('Cache::FastMmap') };
use Storable qw(freeze thaw);
use strict;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $FC = Cache::FastMmap->new(
  page_size => 8192,
  num_pages => 3,
  init_file => 1,
  raw_values => 1
);
ok( defined $FC );

sub rand_str {
  return join '', map { chr(rand(26) + ord('a')) } 1 .. int($_[0]);
}

srand(123);

my $Bad = 0;

my @LastEntries;
foreach my $i (1 .. 500) {
  my $K = rand_str(rand(10) + 10);
  my $V = rand_str(rand(20) + 20);

  $FC->set($K, $V);
  push @LastEntries, [ $K, $V ];
  shift @LastEntries if @LastEntries > 25;

  foreach my $e (0 .. @LastEntries-1) {
    local $_ = $LastEntries[$e];
    if ($_->[1] ne ($FC->get($_->[0]) || '')) {
      $Bad = 1;
      last;
    }
  }
  last if $Bad;
  select(undef, undef, undef, 0.01);
}

ok( !$Bad );

$FC = Cache::FastMmap->new(
  page_size => 8192,
  num_pages => 3,
  init_file => 1
);

ok( defined $FC );

$Bad = 0;
@LastEntries = ();

foreach my $i (1 .. 500) {
  my $K = rand_str(rand(10) + 10);
  my $V = [ rand_str(rand(20) + 20) ];

  $FC->set($K, $V);
  push @LastEntries, [ $K, freeze($V) ];
  shift @LastEntries if @LastEntries > 25;

  foreach my $e (0 .. @LastEntries-1) {
    local $_ = $LastEntries[$e];
    if ($_->[1] ne freeze($FC->get($_->[0]) || [])) {
      $Bad = 1;
      last;
    }
  }
  last if $Bad;
  select(undef, undef, undef, 0.01);
}

ok( !$Bad );
