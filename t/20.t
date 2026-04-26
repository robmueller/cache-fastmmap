
#########################

use Test::More;
use strict;

#########################

# share_file file-mode handling: default permissions are 0640, an
# explicit `permissions` parameter overrides that, and the value is
# applied regardless of process umask.


if( $^O eq 'MSWin32' ) {
    plan skip_all => "permissions parameter is not supported on Windows";
}
else {
    plan tests => 7;
}

require_ok('Cache::FastMmap');

my $old_umask = umask 0000;
note( 'umask returns undef on this system, test results may not be reliable')
    unless defined $old_umask;

my $FC = Cache::FastMmap->new(init_file => 1);
ok( defined $FC );
my (undef, undef, $Mode) = stat($FC->{share_file});
$Mode = $Mode & 0777;
is($Mode, 0640, "default persmissions 0640");
undef $FC;

my $FC = Cache::FastMmap->new(init_file => 1, permissions => 0600);
ok( defined $FC );
my (undef, undef, $Mode) = stat($FC->{share_file});
$Mode = $Mode & 0777;
is($Mode, 0600, "can set to 0600");
undef $FC;

my $FC = Cache::FastMmap->new(init_file => 1, permissions => 0666);
ok( defined $FC );
my (undef, undef, $Mode) = stat($FC->{share_file});
$Mode = $Mode & 0777;
is($Mode, 0666, "can set to 0666");
undef $FC;
