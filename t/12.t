
#########################
our ($IsWin, $Tests);

BEGIN {
  $IsWin = 0;
  $Tests = 7;

  if ($^O eq "MSWin32") {
    $IsWin = 1;
    $Tests -= 2;
  }
}

use Test::More tests => $Tests;
BEGIN { use_ok('Cache::FastMmap') };
use strict;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $FC = Cache::FastMmap->new(init_file => 1, raw_values => 1);
ok( defined $FC );

# Check get_and_set()

ok( $FC->set("cnt", 1), "set counter" );
is( $FC->get_and_set("cnt", sub { return ++$_[1]; }), 2, "get_and_set 1" );
is( $FC->get_and_set("cnt", sub { return ++$_[1]; }), 3, "get_and_set 2" );

# Basic atomicness test

my $loops = 5000;
if (!$IsWin) {

$FC->set("cnt", 0);
if (my $pid = fork()) {
  for (1 .. $loops) {
    $FC->get_and_set("cnt", sub { return ++$_[1]; });
  }
  waitpid($pid, 0);
  is( $FC->get("cnt"), $loops*2, "get_and_set 1");

} else {
  for (1 .. $loops) {
    $FC->get_and_set("cnt", sub { return ++$_[1]; });
  }
  CORE::exit(0);
}

}

# Check get_and_remove()

if (!$IsWin) {

my $got_but_didnt_remove = 0;
if (my $pid = fork()) {
  for (1..$loops) {
    $FC->set("cnt", "data");
    my ($got, $did_remove) = $FC->get_and_remove("cnt");
    # With atomicity, we should never get something out, but fail to remove something:
    $got_but_didnt_remove++ if $got && !$did_remove;
  }
  waitpid($pid, 0);
  is( $got_but_didnt_remove, 0, "get_and_remove 1" );
} else {
  for (1..$loops) {
    $FC->remove("cnt");
  }
  CORE::exit(0);
}

}
