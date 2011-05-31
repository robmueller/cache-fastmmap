
#########################

use Test::More;

BEGIN {
  eval "use GTop ();";
  if ($@) {
    plan skip_all => 'No GTop installed, no memory leak tests';
  } else {
    plan tests => 10;
  }
  use_ok('Cache::FastMmap');
}

use strict;

my $GTop = GTop->new;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

our ($DidRead, $DidWrite, $DidDelete, $HitCount);

our $FC;
$FC = Cache::FastMmap->new(init_file => 0, raw_values => 1);
$FC = undef;

TestLeak(\&NewLeak, "new - 1");
TestLeak(\&NewLeak, "new - 2");
TestLeak(\&NewLeak2, "new2 - 1");
TestLeak(\&NewLeak2, "new2 - 2");

$FC = Cache::FastMmap->new(
  init_file => 1,
  raw_values => 1,
  num_pages => 17,
  page_size => 8192,
  read_cb => sub { $DidRead++; return undef; },
  write_cb => sub { $DidWrite++; },
  delete_cb => sub { $DidDelete++; },
  write_action => 'write_back'
);

ok( defined $FC );

# Prefill cache to make sure all pages mapped
for (1 .. 2000) {
  $FC->set(RandStr(15), RandStr(10));
}
$FC->get('foo');

our $Key = "blah100000blah";
our $Val = "\x{263A}" . RandStr(17);

our $StartKey = 1;
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

  my $Before = $GTop->proc_mem($$)->size;
  eval {
    $Sub->();
  };
  if ($@) {
    ok(0, "leak test died: $@");
  }
  my $After = $GTop->proc_mem($$)->size;

  my $Extra = ($After - $Before)/1024;
  ok( $Extra < 30, "leak test $Extra > 30k - $Test");
}

sub NewLeak {

  for (1 .. 1000) {
    $FC = Cache::FastMmap->new(
      init_file => 0,
      raw_values => 1,
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

  for (1 .. 100) {
    $FC = Cache::FastMmap->new(
      init_file => 1,
      raw_values => 1,
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
  for (1 .. 10000) {
    $Key = "blah" . $StartKey++ . "blah";
    if ($_ < 9000) { $Val = RandStr(int(rand(15))+2); }
    elsif ($_ < 9500) { $Val = "\x{263A}" . RandStr(int(rand(15))+2); }
    else { $Val = undef; }

    $FC->set($Key, $Val);
  }
}

sub GetLeak {
  for (1 .. 20000) {
    $Key = "blah" . $StartKey++ . "blah";
    $HitCount++ if $FC->get($Key);
  }
}

sub WBLeak {
  for (1 .. 5000) {
    $Key = "blah" . $StartKey++ . "blah";
    if ($_ < 4000) { $Val = RandStr(int(rand(15))+2); }
    elsif ($_ < 4500) { $Val = "\x{263A}" . RandStr(int(rand(15))+2); }
    else { $Val = undef; }
    $FC->set($Key, $Val);
    my $PreDidWrite = $DidWrite;
    $FC->empty();
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
