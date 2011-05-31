#!/usr/local/bin/perl -w

use lib '/home/mod_perl/hm/modules';
use ExtUtils::testlib;
use Cache::FastMmap;
use Data::Dumper;
use POSIX ":sys_wait_h";
use strict;

#EdgeTests();

my $FC = Cache::FastMmap->new(
  init_file => 1,
  raw_values => 1
) || die "Could not create file cache";

BasicTests($FC);
$FC->clear();

my @Keys;
RepeatMixTest($FC, 0.0, \@Keys);
RepeatMixTest($FC, 0.5, \@Keys);
RepeatMixTest($FC, 0.8, \@Keys);

ForkTests($FC);

$FC = Cache::FastMmap->new(
  init_file => 1,
  page_size => 8192,
  raw_values => 1
) || die "Could not create file cache";

BasicTests($FC);
$FC->clear();

@Keys = ();
RepeatMixTest($FC, 0.0, \@Keys);
RepeatMixTest($FC, 0.5, \@Keys);
RepeatMixTest($FC, 0.8, \@Keys);

ForkTests($FC);

print "All done\n";

exit(0);

sub BasicTests {
  my $FC = shift;

  printf "Basic tests\n";

  # Test empty
  !defined $FC->get('')
    || die "Not undef on empty get";

  !defined $FC->get(' ')
    || die "Not undef on empty get";

  !defined $FC->get(' ' x 1024)
    || die "Not undef on empty get";

  !defined $FC->get(' ' x 65536)
    || die "Not undef on empty get";

  # Test basic store/get on key sizes
  $FC->set('', 'abc');
  $FC->get('') eq 'abc'
    || die "Get mismatch";

  $FC->set(' ', 'def');
  $FC->get(' ') eq 'def'
    || die "Get mismatch";

  $FC->set(' ' x 1024, 'ghi');
  $FC->get(' ' x 1024) eq 'ghi'
    || die "Get mismatch";

  # Bigger than the page size - shouldn't work
  $FC->set(' ' x 65536, 'jkl');
  !defined $FC->get(' ' x 65536)
    || die "Get mismatch";

  # Test basic store/get on value sizes
  $FC->set('abc', '');
  $FC->get('abc') eq ''
    || die "Get mismatch";

  $FC->set('def', 'x');
  $FC->get('def') eq 'x'
    || die "Get mismatch";

  $FC->set('ghi', 'x' . ('y' x 1024) . 'z');
  $FC->get('ghi') eq 'x' . ('y' x 1024) . 'z' 
    || die "Get mismatch";

  # Bigger than the page size - shouldn't work
  $FC->set('jkl', 'x' . ('y' x 65536) . 'z');
  !defined $FC->get('jkl')
    || die "Get mismatch";

  # Ref key should use 'stringy' version
  my $Ref = [ ];
  $FC->set($Ref, 'abcd');
  $FC->get($Ref) eq 'abcd'
    || die "Get mismatch";
  $FC->get("$Ref") eq 'abcd'
    || die "Get mismatch";


  # Check utf8
#	  eval { $FC->set("\x{263A}", "blah\x{263A}"); };
#	  $@ || die "Set utf8 succeeded, but should have failed: $@";
#	  eval { $FC->set("blah", "\x{263A}"); };
#	  $@ || die "Set utf8 succeeded, but should have failed: $@";
#	  eval { $FC->get("\x{263A}"); };
#	  $@ || die "Set utf8 succeeded, but should have failed: $@";

  $FC->set("\x{263A}", "blah\x{263A}");
  $FC->get("\x{263A}") eq "blah\x{263A}"
    || die "Get mismatch";

  $FC->clear();

  $FC->set("abc", "123");
  $FC->set("bcd", "234");
  $FC->set("cde", "345");
  $FC->set("def", "456");

  join(",", sort $FC->get_keys) eq "abc,bcd,cde,def"
    || die "get_keys mismatch";

  $FC->set("efg\x{263A}", "567\x{263A}");

  join(",", sort $FC->get_keys) eq "abc,bcd,cde,def,efg\x{263A}"
    || die "get_keys mismatch";

  my %keys = map { $_->{key} => $_ } $FC->get_keys(2);
  $keys{abc}->{value} eq "123"
    || die "get_keys missing";
  $keys{"efg\x{263A}"}->{value} eq "567\x{263A}"
    || die "get_keys missing";

}

sub EdgeTests {
  my $FC = Cache::FastMmap->new(
    init_file => 1,
    num_pages => 1,
    raw_values => 1
  ) || die "Could not create file cache";

  printf "Edge tests. Assume implementation\n";

  $FC->clear();

  # bytes for kv data
  # 65536 - 8*4 - 4*4*89 = 64080

  # adds 4*2 + 1 + 1 = 10 bytes, 64070 rem
  $FC->set('a', 'a');
  $FC->get('a') eq 'a'
    || die "Get mismatch";

  # Ensure oldest timestamp
  sleep 2;

  # adds 4*2 + 1 + 64051 = 64060, 10 rem
  $FC->set('b', 'b' x 64051);
  $FC->get('b') eq 'b' x 64051
    || die "Get mismatch";

  sleep 2;

  # adds 4*2 + 1 + 1 = 10 bytes, 0 rem
  $FC->set('c', 'c');
  $FC->get('c') eq 'c'
    || die "Get mismatch";
  $FC->get('b') eq 'b' x 64051
    || die "Get mismatch";
  $FC->get('a') eq 'a'
    || die "Get mismatch";

  # adds 4*2 + 1 + 1 = 10 bytes, force expunge
  $FC->set('d', 'd');
  !defined $FC->get('a')
    || die "Get mismatch";
  !defined $FC->get('b')
    || die "Get mismatch";
  $FC->get('d') eq 'd'
    || die "Get mismatch";
  $FC->get('c') eq 'c'
    || die "Get mismatch";

  # Try again
  $FC->clear();

  # adds 4*2 + 1 + 1 = 10 bytes, 64070 rem
  $FC->set('a', 'a');
  $FC->get('a') eq 'a'
    || die "Get mismatch";

  # Ensure oldest timestamp
  sleep 2;

  # adds 4*2 + 1 + 64052 = 64061, 9 rem
  $FC->set('b', 'b' x 64052);
  $FC->get('b') eq 'b' x 64052
    || die "Get mismatch";

  sleep 2;

  # adds 4*2 + 1 + 1 = 10 bytes, -1 rem, force expunge
  $FC->set('c', 'c');
  $FC->get('c') eq 'c'
    || die "Get mismatch";

  !defined $FC->get('b')
    || die "Get mismatch";
  !defined $FC->get('a')
    || die "Get mismatch";

  # adds 4*2 + 1 + 1 = 10 bytes
  $FC->set('d', 'd');
  $FC->get('d') eq 'd'
    || die "Get mismatch";
  $FC->get('c') eq 'c'
    || die "Get mismatch";

}

sub ForkTests {

  # Now fork several children to test cache concurrency
  my ($Pid, %Kids);
  for (my $j = 0; $j < 8; $j++) {
    if (!($Pid = fork())) {
      RepeatMixTest($FC, 0.4, \@Keys);
      exit;
    }
    $Kids{$Pid} = 1;
    select(undef, undef, undef, 0.001);
  }

  # Wait for children to finish
  my $Kid;
  do {
    $Kid = waitpid(-1, WNOHANG);
    delete $Kids{$Kid};
  } until $Kid > 0 && !%Kids;

}

sub RepeatMixTest {
  my ($FC, $Ratio, $WroteKeys) = @_;

  print "Repeat mix tests\n";

  my ($Read, $ReadHit);

  # Lots of random tests
  for (1 .. 10000) {

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

  printf "Read hit pct: %5.3f\n", ($ReadHit/$Read) if $Read;

  return;
}

sub RandStr {
  my $Len = shift;

  if (!$::URandom) {
    open($::URandom, '/dev/urandom')
      || die "Could not open /dev/urandom: $!";
  }

  sysread($::URandom, my $D, $Len);
  $D =~ s/(.)/chr(ord($1) % 26 + ord('a'))/ge;
  return $D;
}

