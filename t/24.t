
#########################

# Lock-release contract: every code path that acquires a page lock must
# release it before returning, including paths where user-supplied code
# (sub passed to get_and_set, read_cb, custom serialize/deserialize) dies.
#
# pod for get_and_set explicitly promises: "If your sub does a die/throws
# an exception, the page will correctly be unlocked". The other paths
# aren't documented but were preserved by the refactor that removed
# Cache::FastMmap::OnLeave in favour of explicit fc_lock/fc_unlock.
#
# Detection: each test triggers the failure path, then performs a second
# operation on the same page. If the lock leaked, that second op blocks
# forever — alarm() turns the hang into a test failure.

use Test::More;
use strict;

BEGIN {
  if ($^O eq "MSWin32") {
    plan skip_all => "alarm() unreliable on $^O";
  } else {
    plan tests => 26;
  }
}
BEGIN { use_ok('Cache::FastMmap') };

#########################

sub run_with_deadlock_guard {
  my ($timeout, $code) = @_;
  my $deadlocked = 0;
  my $result = eval {
    local $SIG{ALRM} = sub { $deadlocked = 1; die "deadlock\n"; };
    alarm($timeout);
    my $r = $code->();
    alarm(0);
    $r;
  };
  alarm(0);
  return ($deadlocked, $result, $@);
}

#########################
# get_and_set: user sub dies

{
  my $FC = Cache::FastMmap->new(init_file => 1, serializer => '');
  ok( $FC->set("k", "initial"), "[get_and_set die] set initial" );

  eval { $FC->get_and_set("k", sub { die "boom\n" }); };
  is( $@, "boom\n", "[get_and_set die] re-throws" );

  my ($dead, $r) = run_with_deadlock_guard(5, sub { $FC->set("k", "after") });
  is( $dead, 0, "[get_and_set die] no deadlock on follow-up set" );
  is( $FC->get("k"), "after", "[get_and_set die] follow-up value visible" );
}

#########################
# get_and_set: user sub returns empty list (no store, must still unlock)

{
  my $FC = Cache::FastMmap->new(init_file => 1, serializer => '');
  ok( $FC->set("k", "keep"), "[get_and_set empty] set initial" );

  my $r = $FC->get_and_set("k", sub { return () });
  # Empty-return path: no store, original value preserved.
  is( $FC->get("k"), "keep", "[get_and_set empty] original value preserved" );

  my ($dead) = run_with_deadlock_guard(5, sub { $FC->set("k", "after") });
  is( $dead, 0, "[get_and_set empty] no deadlock on follow-up set" );
}

#########################
# get: read_cb dies (non-recursive). Lock is held during read_cb in this
# mode; outer eval in get() must catch and unlock before re-throwing.

{
  my $FC = Cache::FastMmap->new(
    init_file => 1,
    serializer => '',
    read_cb => sub { die "rcb-boom\n" },
  );

  eval { $FC->get("missing") };
  like( $@, qr/rcb-boom/, "[get read_cb die] re-throws" );

  my ($dead) = run_with_deadlock_guard(5, sub { $FC->set("missing", "v") });
  is( $dead, 0, "[get read_cb die] no deadlock on follow-up set" );
}

#########################
# get: read_cb dies with allow_recursive. This is the trickiest path:
# get() unlocks before calling read_cb, the inner eval catches the die,
# re-locks the page, then re-throws — outer eval catches and unlocks.

{
  my $FC = Cache::FastMmap->new(
    init_file => 1,
    serializer => '',
    allow_recursive => 1,
    read_cb => sub { die "rcb-rec-boom\n" },
  );

  eval { $FC->get("missing") };
  like( $@, qr/rcb-rec-boom/, "[get read_cb die recursive] re-throws" );

  my ($dead) = run_with_deadlock_guard(5, sub { $FC->set("missing", "v") });
  is( $dead, 0, "[get read_cb die recursive] no deadlock on follow-up set" );
}

#########################
# multi_get: deserialize dies inside the locked loop body.

{
  my $FC = Cache::FastMmap->new(
    init_file => 1,
    serializer => [
      sub { ${ $_[0] } },                                    # serialize
      sub { die "deser-boom\n" if $_[0] eq 'POISON'; \$_[0] }, # deserialize
    ],
  );
  ok( $FC->multi_set("page", { good => 'ok', bad => 'POISON' }),
      "[multi_get deser die] multi_set seed" );

  eval { $FC->multi_get("page", [ qw(good bad) ]) };
  like( $@, qr/deser-boom/, "[multi_get deser die] re-throws" );

  my ($dead) = run_with_deadlock_guard(5,
    sub { $FC->multi_set("page", { good => 'still-ok' }) });
  is( $dead, 0, "[multi_get deser die] no deadlock on follow-up multi_set" );
}

#########################
# multi_set: serialize dies inside the locked loop body.

{
  my $FC = Cache::FastMmap->new(
    init_file => 1,
    serializer => [
      sub { die "ser-boom\n" if ${ $_[0] } eq 'POISON'; ${ $_[0] } }, # serialize
      sub { \$_[0] },                                                  # deserialize
    ],
  );

  eval { $FC->multi_set("page", { ok => 'fine', bad => 'POISON' }) };
  like( $@, qr/ser-boom/, "[multi_set ser die] re-throws" );

  my ($dead) = run_with_deadlock_guard(5,
    sub { $FC->multi_set("page", { ok => 'still-fine' }) });
  is( $dead, 0, "[multi_set ser die] no deadlock on follow-up multi_set" );
}

#########################
# get_and_set: deserializer dies while get() is returning with skip_unlock.

{
  my $FC = Cache::FastMmap->new(
    init_file => 1,
    serializer => [
      sub { ${ $_[0] } },
      sub { die "locked-deser-boom\n" if $_[0] eq 'POISON'; \$_[0] },
    ],
  );
  ok( $FC->set("k", "POISON"), "[get_and_set locked deser die] seed poison" );

  eval { $FC->get_and_set("k", sub { return "unused" }) };
  like( $@, qr/locked-deser-boom/, "[get_and_set locked deser die] re-throws" );

  my ($dead) = run_with_deadlock_guard(5, sub { $FC->set("k", "after") });
  is( $dead, 0, "[get_and_set locked deser die] no deadlock on follow-up set" );
}

#########################
# get_and_set: serializer dies inside set() while it owns the existing lock.

{
  my $FC = Cache::FastMmap->new(
    init_file => 1,
    serializer => [
      sub { die "locked-ser-boom\n" if ${ $_[0] } eq 'POISON'; ${ $_[0] } },
      sub { \$_[0] },
    ],
  );
  ok( $FC->set("k", "initial"), "[get_and_set locked ser die] seed initial" );

  eval { $FC->get_and_set("k", sub { return "POISON" }) };
  like( $@, qr/locked-ser-boom/, "[get_and_set locked ser die] re-throws" );

  my ($dead) = run_with_deadlock_guard(5, sub { $FC->set("k", "after") });
  is( $dead, 0, "[get_and_set locked ser die] no deadlock on follow-up set" );
}

#########################
# get_and_set: non-hash set options from callback must not strand the lock.

{
  my $FC = Cache::FastMmap->new(init_file => 1, serializer => '');
  ok( $FC->set("k", "initial"), "[get_and_set bad opts] seed initial" );

  eval { $FC->get_and_set("k", sub { return ("after", "bad-options") }) };
  like( $@, qr/options must be a hash reference/, "[get_and_set bad opts] re-throws" );

  my ($dead) = run_with_deadlock_guard(5, sub { $FC->set("k", "after") });
  is( $dead, 0, "[get_and_set bad opts] no deadlock on follow-up set" );
}
