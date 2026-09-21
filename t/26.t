
#########################

# Page repair: a writer killed while holding a page lock leaves the
# page's dirty marker set, and the next process to lock the page
# reinitialises it instead of trusting it. Bad slot offsets and entry
# lengths are caught and repaired too, rather than crashing.

use Test::More;
BEGIN {
  # The killed-writer cases fork, and perl's fork on Windows is thread
  # emulation, which Cache::FastMmap refuses
  if ($^O eq 'MSWin32') {
    plan skip_all => 'fork tests not supported on Windows';
  }
  require Cache::FastMmap;
  # A -DDEBUG build asserts on any structural inconsistency, which is
  # what this test deliberately creates
  if (Cache::FastMmap::fc_get_param(Cache::FastMmap::fc_new(), 'debug')) {
    plan skip_all => 'DEBUG build aborts on the corruption this test creates';
  }
  plan tests => 30;
  use_ok('Cache::FastMmap');
}
use strict;
use POSIX qw(_exit);
use File::Temp qw(tempdir);

#########################

my $Dir = tempdir(CLEANUP => 1);
my $File = "$Dir/repair.cache";

my %Args = (
  share_file => $File,
  serializer => '',
  num_pages  => 7,
  page_size  => 8192,
  unlink_on_exit => 0,
);

my $FC = Cache::FastMmap->new(%Args, init_file => 1);
ok(defined $FC, "created cache");
is($FC->repaired_pages, 0, "no repairs on a fresh cache");

my @Warns;
local $SIG{__WARN__} = sub { push @Warns, $_[0] };

# Fill every page with something so a repair is visible as lost entries
my %Page;
for my $i (1 .. 200) {
  $FC->set("key$i", "value$i");
  my ($p) = Cache::FastMmap::fc_hash($FC->{Cache}, "key$i");
  push @{$Page{$p}}, "key$i";
}
is(scalar(keys %Page), 7, "entries spread over every page");

# --- A writer killed mid-update

# The child locks a page, starts a store (which sets the dirty marker)
# and dies without unlocking, exactly as a SIGKILL mid-set would leave
# things. fc_unlock never runs, so the marker stays set; the kernel
# drops the fcntl lock with the process.
my ($DirtyPage) = Cache::FastMmap::fc_hash($FC->{Cache}, "dirtykey");
my $pid = fork();
die "fork: $!" unless defined $pid;
if ($pid == 0) {
  my $Child = Cache::FastMmap->new(%Args);
  my ($HashPage, $HashSlot) = Cache::FastMmap::fc_hash($Child->{Cache}, "dirtykey");
  Cache::FastMmap::fc_lock($Child->{Cache}, $HashPage);
  Cache::FastMmap::fc_write($Child->{Cache}, $HashSlot, "dirtykey", "v", -1, 0);
  _exit(0);
}
waitpid($pid, 0);
is($?, 0, "child exited holding the page lock");

# Other pages are untouched
my ($OtherPage) = grep { $_ != $DirtyPage } keys %Page;
is($FC->get($Page{$OtherPage}[0]), "value" . substr($Page{$OtherPage}[0], 3),
  "entry on an untouched page still readable");
is(scalar(@Warns), 0, "no warning for a clean page");

# First access to the dirty page repairs it
ok(!defined $FC->get($Page{$DirtyPage}[0]), "entry on the dirty page is gone");
is(scalar(@Warns), 1, "repair was reported");
like($Warns[0], qr/page $DirtyPage of \Q$File\E reinitialised: left dirty by a killed writer/,
  "warning names the page, file and reason");
is($FC->repaired_pages, 1, "repaired_pages counts it");
ok(!defined $FC->get("dirtykey"), "the half-written key is gone too");

# And the page is usable again
ok($FC->set("after", "repair"), "can store on the repaired page after");
is($FC->get("after"), "repair", "and read it back");
is(scalar(@Warns), 1, "no further warnings");
@Warns = ();

# --- A slot pointing outside the page

# Damage is done through the cache's own mapping (fc_peek/fc_poke) rather
# than by writing the file: not every platform keeps mmap and file I/O
# coherent without msync, and this test isn't about that.
sub peek { Cache::FastMmap::fc_peek($FC->{Cache}, $_[0]) }
sub poke { Cache::FastMmap::fc_poke($FC->{Cache}, $_[0], $_[1]) }

# Offsets of the used slots on a page, and each slot's data offset
sub used_slots {
  my ($Page) = @_;
  my $PageStart = $Page * $Args{page_size};
  my $Magic = peek($PageStart);
  die sprintf("bad magic %x", $Magic) unless $Magic == 0x92f7e3b1;
  my $NumSlots = peek($PageStart + 4);
  my @Used;
  for my $i (0 .. $NumSlots - 1) {
    my $Off = peek($PageStart + 32 + $i * 4);
    push @Used, [ $PageStart + 32 + $i * 4, $Off ] if $Off > 1;
  }
  return @Used;
}

# Point every used slot on a page at the given offset. Lookups only
# follow the slots they probe, so one bad slot might never be seen;
# all of them means the first probe finds it.
sub corrupt_slot {
  my ($Page, $NewOffset) = @_;
  poke($_->[0], $NewOffset) for used_slots($Page);
}

my $BadPage = $OtherPage;
corrupt_slot($BadPage, $Args{page_size} + 64);
$FC->get($Page{$BadPage}[0]);   # a lookup on that page
is(scalar(@Warns), 1, "bad offset reported");
like($Warns[0], qr/page $BadPage of .* reinitialised: slot data offset \d+ outside page/,
  "warning gives the reason");
is($FC->repaired_pages, 2, "second repair counted");
ok(!defined $FC->get($Page{$BadPage}[0]), "page emptied by the repair");
ok($FC->set("after2", "repair2") && $FC->get("after2") eq "repair2",
  "repaired page usable");
@Warns = ();

# --- An entry whose lengths run past the page, found by expunge/empty

my ($LenPage) = grep { $_ != $DirtyPage && $_ != $BadPage } keys %Page;
$FC->set("lenkey", "x" x 100);   # make sure there's an entry
# Point the slots at the last few words of the page: the offset is in
# range but an entry header can't fit there. get_keys walks every slot,
# so it finds the problem; it repairs inside its iterator and reports
# once at the end
corrupt_slot($LenPage, $Args{page_size} - 8);
my @Keys = $FC->get_keys(0);
ok(scalar(@Keys) > 0, "get_keys still returns the other pages");
is(scalar(@Warns), 1, "bad entry reported by the walk");
like($Warns[0], qr/page $LenPage of .* reinitialised: slot data offset \d+ outside page/,
  "with a bounds reason");
is($FC->repaired_pages, 3, "third repair counted");
@Warns = ();

# An entry header whose lengths run past the page end
$FC->set("lenkey2", "y" x 100);
my ($LenPage2) = Cache::FastMmap::fc_hash($FC->{Cache}, "lenkey2");
{
  # Overwrite the value length of lenkey2's entry with something huge.
  # Entry layout: 4 words of metadata, key len, value len, then the key.
  my $PageStart = $LenPage2 * $Args{page_size};
  my $Found = 0;
  for my $Slot (used_slots($LenPage2)) {
    my $Entry = $PageStart + $Slot->[1];
    my $KeyLen = peek($Entry + 16);
    next unless $KeyLen == length("lenkey2");
    my $Key = substr(pack("L*", map { peek($Entry + 24 + $_ * 4) } 0 .. 1), 0, $KeyLen);
    next unless $Key eq "lenkey2";
    poke($Entry + 20, 0x7fffffff);
    $Found = 1;
  }
  die "lenkey2 not found on its page" unless $Found;
}
ok(!defined $FC->get("lenkey2"), "entry with a bad length is a miss");
is(scalar(@Warns), 1, "and is reported");
like($Warns[0], qr/entry at offset \d+ runs past end of page/, "with the length reason");
@Warns = ();

# --- A dirty page is repaired at open too, with a summary warning

$pid = fork();
die "fork: $!" unless defined $pid;
if ($pid == 0) {
  my $Child = Cache::FastMmap->new(%Args);
  my ($HashPage, $HashSlot) = Cache::FastMmap::fc_hash($Child->{Cache}, "k2");
  Cache::FastMmap::fc_lock($Child->{Cache}, $HashPage);
  Cache::FastMmap::fc_write($Child->{Cache}, $HashSlot, "k2", "v", -1, 0);
  _exit(0);
}
waitpid($pid, 0);
my $FC2 = Cache::FastMmap->new(%Args, test_file => 1);
is($FC2->repaired_pages, 1, "test_file repaired the dirty page on open");
is(scalar(@Warns), 1, "reported once, as an open summary");
like($Warns[0], qr/1 page\(s\) reinitialised on open, last: page \d+ of .* left dirty by a killed writer/,
  "open summary warning");
