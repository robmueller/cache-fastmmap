
#########################

use Test::More tests => 3;
BEGIN { use_ok('Cache::FastMmap') };
use strict;

#########################

# Mixed set / remove / overwrite churn against a single page: every
# subsequent get must return the value last written for that key
# (slot ordering invariant).

my $FC = Cache::FastMmap->new(
  init_file => 1,
  num_pages => 1,
  page_size => 2 ** 15,
);
ok( defined $FC );

my @d;

for (1 .. 20) {

  $FC->set($_, $d[$_]=$_) for 1 .. 100;

  for (1 .. 50) {
    $FC->remove($_*2);
    $d[$_*2] = undef;

    $FC->set($_, $_*2);
    $d[$_] = $_*2;

    for my $c (1 .. 100) {
      my $v = $FC->get($c);
      ($v || 0) == ($d[$c] || 0)
        || die "at offset $c, got $v expected $d[$c]";
    }
  }

}
ok(1, "ordering santity tests complete");
