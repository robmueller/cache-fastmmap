
#########################

use Test::More;
use strict;

my $fs;
BEGIN {
    my @fs = map { { /(\w+)="([^"]*)"/g } } split /\n/, `findmnt -t tmpfs -P -b -o TARGET,AVAIL | grep /tmp`;
    ($fs) = grep { $_->{AVAIL} > 2**33 } @fs;
    if (!$fs) {
      plan skip_all => 'Large file tests need tmpfs with at least 8G';
    }
}

BEGIN {
  plan tests => 6;
  use_ok('Cache::FastMmap')
};


#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $cache_file = $fs->{TARGET} . "/largecachetest.cache";

my %WrittenItems;
my $FC = Cache::FastMmap->new(
  share_file => $cache_file,
  serializer => '',
  init_file => 1,
  num_pages => 8,
  page_size => 2**30,
);

ok( defined $FC );

srand(6543);

# Put 1000 items in the cache - should be big enough :)
for (1 .. 1000) {
  my ($Key, $Val) = (RandStr(100), RandStr(1000));
  $FC->set($Key, $Val);
  $WrittenItems{$Key} = $Val;
}

# Get values in cache should be 1000
my %CacheItems = map { $_->{key} => $_->{value} } $FC->get_keys(2);
ok( scalar(keys %CacheItems) == 1000, "1000 items in cache");

# Should be able to read all items
my ($Failed, $GetFailed) = (0, 0);
for (keys %WrittenItems) {
  $Failed++ if $FC->get($_) ne $WrittenItems{$_};
  $GetFailed++ if $FC->get($_) ne $CacheItems{$_};
}

ok( $Failed == 0, "got all written items" );
ok( $GetFailed == 0, "got all get_keys items" );

# Now there should be nothing left
$FC->clear();

%CacheItems = map { $_->{key} => $_->{value} } $FC->get_keys(2);
ok( scalar(keys %CacheItems) == 0, "empty cache 2");

sub RandStr {
  return join '', map { chr(ord('a') + rand(26)) } (1 .. $_[0]);
}

