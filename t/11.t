
#########################

use Test::More tests => 7;
BEGIN { use_ok('Cache::FastMmap') };
use strict;

#########################

# Test recursive cache use

sub get_fc {
my $FC;
$FC = Cache::FastMmap->new(
  cache_not_found => 1,
  raw_values => 1,
  init_file => 1,
  num_pages => 89,
  page_size => 1024,
  read_cb => sub { $FC->get($_[1] . "1"); },
  write_cb => sub { $FC->set($_[1] . "1", $_[2]); },
  delete_cb => sub { $FC->delete($_[1]); },
  write_action => 'write_back',
  @_
);
return $FC;
}

my $FC = get_fc();
ok( defined $FC );

$FC->set("foo1", "bar");
my $V = eval { $FC->get("foo"); };
ok(!$V, "no return");
like($@, qr/already locked/, "recurse fail");

$FC = undef;

$FC = get_fc(allow_recursive => 1);
ok( defined $FC );

$FC->set("foo1", "bar");
$V = eval { $FC->get("foo"); };
ok(!$@, "recurse success 1");
is($V, "bar", "recurse success 2");

