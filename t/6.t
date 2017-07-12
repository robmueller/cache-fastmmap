
#########################

use Test::More;

my $GetMem;

BEGIN {
  eval "use GTop ();";
  if (!$@) {
    my $GTop = GTop->new;
    $GetMem = sub { return $GTop->proc_mem($$)->size };
  } elsif (-f "/proc/$$/status") {
    $GetMem = sub { open(my $Sh, "/proc/$$/status"); my ($S) = map { /(\d+) kB/ && $1*1024 } grep { /^VmSize:/ } <$Sh>; close($Sh); return $S; }
  }
  if ($GetMem) {
    plan tests => 10;
  } else {
    plan skip_all => 'No GTop or /proc/, no memory leak tests';
  }
  use_ok('Cache::FastMmap');
}

use strict;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

our ($DidRead, $DidWrite, $DidDelete, $HitCount);

our $FC;
$FC = Cache::FastMmap->new(init_file => 0, serializer => '');
$FC = undef;

TestLeak(\&NewLeak, "new - 1");
TestLeak(\&NewLeak, "new - 2");
TestLeak(\&NewLeak2, "new2 - 1");
TestLeak(\&NewLeak2, "new2 - 2");

$FC = Cache::FastMmap->new(
  init_file => 1,
  serializer => '',
  num_pages => 17,
  page_size => 65536,
  read_cb => sub { $DidRead++; return undef; },
  write_cb => sub { $DidWrite++; },
  delete_cb => sub { $DidDelete++; },
  write_action => 'write_back'
);

ok( defined $FC );

# Prefill cache to make sure all pages mapped
for (1 .. 10000) {
  $FC->set(RandStr(20), RandStr(20));
}
$FC->get('foo');

our $Key = "blah" x 100;
our $Val = "\x{263A}" . RandStr(1000);

our $IterCount = 100;

our $StartKey = 1;
SetLeak();
$StartKey = 1;
GetLeak();

our $IterCount = 20000;

$StartKey = 1;
TestLeak(\&SetLeak, "set");

$StartKey = 1;
TestLeak(\&GetLeak, "get");

$FC->clear();

$StartKey = 1;
TestLeak(\&SetLeak, "set2");

our (@a, @b, @c);
@a = $FC->get_keys(0);
@b = $FC->get_keys(1);
@c = $FC->get_keys(2);
@a = @b = @c = ();

ListLeak();
TestLeak(\&ListLeak, "list");

sub RandStr {
  return join '', map { chr(ord('a') + rand(26)) } (1 .. $_[0]);
}

sub TestLeak {
  my $Sub = shift;
  my $Test = shift;

  my $Before = $GetMem->();
  eval {
    $Sub->();
  };
  if ($@) {
    ok(0, "leak test died: $@");
  }
  my $After = $GetMem->();

  my $Extra = ($After - $Before)/1024;
  ok( $Extra <= 500, "leak test $Extra > 500k - for $Test");
}

sub NewLeak {

  for (1 .. 2000) {
    $FC = Cache::FastMmap->new(
      init_file => 0,
      serializer => '',
      num_pages => 17,
      page_size => 8192,
      read_cb => sub { $DidRead++; return undef; },
      write_cb => sub { $DidWrite++; },
      delete_cb => sub { $DidDelete++; },
      write_action => 'write_back'
    );
  }
  $FC = undef;

}

sub NewLeak2 {

  for (1 .. 2000) {
    $FC = Cache::FastMmap->new(
      init_file => 1,
      serializer => '',
      num_pages => 17,
      page_size => 8192,
      read_cb => sub { $DidRead++; return undef; },
      write_cb => sub { $DidWrite++; },
      delete_cb => sub { $DidDelete++; },
      write_action => 'write_back'
    );
  }
  $FC = undef;

}

sub SetLeak {
  for (1 .. $IterCount) {
    $Key = "blah" . $StartKey++ . "blah";
    if ($_ % 10 < 6) { $Val = RandStr(int(rand(20))+2); }
    elsif ($_ % 10 < 8) { $Val = "\x{263A}" . RandStr(int(rand(20))+2); }
    else { $Val = undef; }

    $FC->set($Key, $Val);
  }
}

sub GetLeak {
  for (1 .. $IterCount) {
    $Key = "blah" . $StartKey++ . "blah";
    $HitCount++ if $FC->get($Key);
  }
}

sub WBLeak {
  for (1 .. $IterCount) {
    $Key = "blah" . $StartKey++ . "blah";
    if ($_ % 10 < 6) { $Val = RandStr(int(rand(20))+2); }
    elsif ($_ % 10 < 8) { $Val = "\x{263A}" . RandStr(int(rand(20))+2); }
    else { $Val = undef; }
    $FC->set($Key, $Val);
    my $PreDidWrite = $DidWrite;
    $FC->empty() if $_ % 10 == 0;
    $PreDidWrite + 1 == $DidWrite
      || die "write count mismatch";
    $FC->get($Key)
      && die "get success";
  }
}

sub ListLeak {
  for (1 .. 100) {
    @a = $FC->get_keys(0);
    @b = $FC->get_keys(1);
    @c = $FC->get_keys(2);
    @a = @b = @c = ();
  }
}
