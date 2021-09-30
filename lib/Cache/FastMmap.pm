package Cache::FastMmap;

=head1 NAME

Cache::FastMmap - Uses an mmap'ed file to act as a shared memory interprocess cache

=head1 SYNOPSIS

  use Cache::FastMmap;

  # Uses vaguely sane defaults
  $Cache = Cache::FastMmap->new();

  # Uses Storable to serialize $Value to bytes for storage
  $Cache->set($Key, $Value);
  $Value = $Cache->get($Key);

  $Cache = Cache::FastMmap->new(serializer => '');

  # Stores stringified bytes of $Value directly
  $Cache->set($Key, $Value);
  $Value = $Cache->get($Key);

=head1 ABSTRACT

A shared memory cache through an mmap'ed file. It's core is written
in C for performance. It uses fcntl locking to ensure multiple
processes can safely access the cache at the same time. It uses
a basic LRU algorithm to keep the most used entries in the cache.

=head1 DESCRIPTION

In multi-process environments (eg mod_perl, forking daemons, etc),
it's common to want to cache information, but have that cache
shared between processes. Many solutions already exist, and may
suit your situation better:

=over 4

=item *

L<MLDBM::Sync> - acts as a database, data is not automatically
expired, slow

=item *

L<IPC::MM> - hash implementation is broken, data is not automatically
expired, slow

=item *

L<Cache::FileCache> - lots of features, slow

=item *

L<Cache::SharedMemoryCache> - lots of features, VERY slow. Uses
IPC::ShareLite which freeze/thaws ALL data at each read/write

=item *

L<DBI> - use your favourite RDBMS. can perform well, need a
DB server running. very global. socket connection latency

=item *

L<Cache::Mmap> - similar to this module, in pure perl. slows down
with larger pages

=item *

L<BerkeleyDB> - very fast (data ends up mostly in shared memory
cache) but acts as a database overall, so data is not automatically
expired

=back

In the case I was working on, I needed:

=over 4

=item *

Automatic expiry and space management

=item *

Very fast access to lots of small items

=item *

The ability to fetch/store many items in one go

=back

Which is why I developed this module. It tries to be quite
efficient through a number of means:

=over 4

=item *

Core code is written in C for performance

=item *

It uses multiple pages within a file, and uses Fcntl to only lock
a page at a time to reduce contention when multiple processes access
the cache.

=item *

It uses a dual level hashing system (hash to find page, then hash
within each page to find a slot) to make most C<get()> calls O(1) and
fast

=item *

On each C<set()>, if there are slots and page space available, only
the slot has to be updated and the data written at the end of the used
data space. If either runs out, a re-organisation of the page is
performed to create new slots/space which is done in an efficient way

=back

The class also supports read-through, and write-back or write-through
callbacks to access the real data if it's not in the cache, meaning that
code like this:

  my $Value = $Cache->get($Key);
  if (!defined $Value) {
    $Value = $RealDataSource->get($Key);
    $Cache->set($Key, $Value)
  }

Isn't required, you instead specify in the constructor:

  Cache::FastMmap->new(
    ...
    context => $RealDataSourceHandle,
    read_cb => sub { $_[0]->get($_[1]) },
    write_cb => sub { $_[0]->set($_[1], $_[2]) },
  );

And then:

  my $Value = $Cache->get($Key);

  $Cache->set($Key, $NewValue);

Will just work and will be read/written to the underlying data source as
needed automatically.

=head1 PERFORMANCE

If you're storing relatively large and complex structures into
the cache, then you're limited by the speed of the Storable module.
If you're storing simple structures, or raw data, then
Cache::FastMmap has noticeable performance improvements.

See L<http://cpan.robm.fastmail.fm/cache_perf.html> for some
comparisons to other modules.

=head1 COMPATIBILITY

Cache::FastMmap uses mmap to map a file as the shared cache space,
and fcntl to do page locking. This means it should work on most
UNIX like operating systems.

Ash Berlin has written a Win32 layer using MapViewOfFile et al. to 
provide support for Win32 platform.

=head1 MEMORY SIZE

Because Cache::FastMmap mmap's a shared file into your processes memory
space, this can make each process look quite large, even though it's just
mmap'd memory that's shared between all processes that use the cache,
and may even be swapped out if the cache is getting low usage.

However, the OS will think your process is quite large, which might
mean you hit some BSD::Resource or 'ulimits' you set previously that you
thought were sane, but aren't anymore, so be aware.

=head1 CACHE FILES AND OS ISSUES

Because Cache::FastMmap uses an mmap'ed file, when you put values into
the cache, you are actually "dirtying" pages in memory that belong to
the cache file. Your OS will want to write those dirty pages back to
the file on the actual physical disk, but the rate it does that at is
very OS dependent.

In Linux, you have some control over how the OS writes those pages
back using a number of parameters in /proc/sys/vm

  dirty_background_ratio
  dirty_expire_centisecs
  dirty_ratio
  dirty_writeback_centisecs

How you tune these depends heavily on your setup.

As an interesting point, if you use a highmem linux kernel, a change
between 2.6.16 and 2.6.20 made the kernel flush memory a LOT more.
There's details in this kernel mailing list thread:
L<http://www.uwsg.iu.edu/hypermail/linux/kernel/0711.3/0804.html>

In most cases, people are not actually concerned about the persistence
of data in the cache, and so are happy to disable writing of any cache
data back to disk at all. Baically what they want is an in memory only
shared cache. The best way to do that is to use a "tmpfs" filesystem
and put all cache files on there.

For instance, all our machines have a /tmpfs mount point that we
create in /etc/fstab as:

  none /tmpfs tmpfs defaults,noatime,size=1000M 0 0

And we put all our cache files on there. The tmpfs filesystem is smart
enough to only use memory as required by files actually on the tmpfs,
so making it 1G in size doesn't actually use 1G of memory, it only uses
as much as the cache files we put on it. In all cases, we ensure that
we never run out of real memory, so the cache files effectively act 
just as named access points to shared memory.

Some people have suggested using anonymous mmaped memory. Unfortunately
we need a file descriptor to do the fcntl locking on, so we'd have
to create a separate file on a filesystem somewhere anyway. It seems
easier to just create an explicit "tmpfs" filesystem.

=head1 PAGE SIZE AND KEY/VALUE LIMITS

To reduce lock contention, Cache::FastMmap breaks up the file
into pages. When you get/set a value, it hashes the key to get a page,
then locks that page, and uses a hash table within the page to
get/store the actual key/value pair.

One consequence of this is that you cannot store values larger than
a page in the cache at all. Attempting to store values larger than
a page size will fail (the set() function will return false).

Also keep in mind that each page has it's own hash table, and that we
store the key and value data of each item. So if you are expecting to
store large values and/or keys in the cache, you should use page sizes
that are definitely larger than your largest key + value size + a few
kbytes for the overhead.

=head1 USAGE

Because the cache uses shared memory through an mmap'd file, you have
to make sure each process connects up to the file. There's probably
two main ways to do this:

=over 4

=item *

Create the cache in the parent process, and then when it forks, each
child will inherit the same file descriptor, mmap'ed memory, etc and
just work. This is the recommended way. (BEWARE: This only works under
UNIX as Win32 has no concept of forking)

=item *

Explicitly connect up in each forked child to the share file. In this
case, make sure the file already exists and the children connect with
init_file => 0 to avoid deleting the cache contents and possible
race corruption conditions. Also be careful that multiple children
may race to create the file at the same time, each overwriting and
corrupting content. Use a separate lock file if you must to ensure
only one child creates the file. (This is the only possible way under
Win32)

=back

The first way is usually the easiest. If you're using the cache in a
Net::Server based module, you'll want to open the cache in the
C<pre_loop_hook>, because that's executed before the fork, but after
the process ownership has changed and any chroot has been done.

In mod_perl, just open the cache at the global level in the appropriate
module, which is executed as the server is starting and before it
starts forking children, but you'll probably want to chmod or chown
the file to the permissions of the apache process.

=head1 RELIABILITY

Cache::FastMmap is being used in an extensive number of systems at
L<www.fastmail.com> and is regarded as extremely stable and reliable.
Development has in general slowed because there are currently no
known bugs and no additional needed features at this time.

=head1 METHODS

=over 4

=cut

# Modules/Export/XSLoader {{{
use 5.006;
use strict;
use warnings;
use bytes;

our $VERSION = '1.57';

require XSLoader;
XSLoader::load('Cache::FastMmap', $VERSION);

# Track currently live caches so we can cleanup in END {}
#  if we have empty_on_exit set
our %LiveCaches;

# Global time override for testing
my $time_override;

use constant FC_ISDIRTY => 1;

use File::Spec;

# }}}

=item I<new(%Opts)>

Create a new Cache::FastMmap object.

Basic global parameters are:

=over 4

=item * B<share_file>

File to mmap for sharing of data.
default on unix: /tmp/sharefile-$pid-$time-$random
default on windows: %TEMP%\sharefile-$pid-$time-$random

=item * B<init_file>

Clear any existing values and re-initialise file. Useful to do in a
parent that forks off children to ensure that file is empty at the start
(default: 0)

B<Note:> This is quite important to do in the parent to ensure a
consistent file structure. The shared file is not perfectly transaction
safe, and so if a child is killed at the wrong instant, it might leave
the cache file in an inconsistent state.

=item * B<serializer>

Use a serialization library to serialize perl data structures before
storing in the cache. If not set, the raw value in the variable passed
to set() is stored as a string. You must set this if you want to store
anything other than basic scalar values. Supported values are:

  ''         for none
  'storable' for 'Storable'
  'sereal'   for 'Sereal'
  'json'     for 'JSON'
  [ $s, $d ] for custom serializer/de-serializer

If this parameter has a value the module will attempt to load the
associated package and then use the API of that package to serialize data
before storing in the cache, and deserialize it upon retrieval from the
cache. (default: 'storable')

You can use a custom serializer/de-serializer by passing an array-ref
with two values. The first should be a subroutine reference that takes
the data to serialize as a single argument and returns an octet stream
to store. The second should be a subroutine reference that takes the
octet stream as a single argument and returns the original data structure.

One thing to note, the data structure passed to the serializer is always
a *scalar* reference to the original data passed in to the ->set(...)
call. If your serializer doesn't support that, you might need to
dereference it first before storing, but rembember to return a reference
again in the de-serializer.

(Note: Historically this module only supported a boolean value for the
`raw_values` parameter and defaulted to 0, which meant it used Storable
to serialze all values.)

=item * B<raw_values>

Deprecated. Use B<serializer> above

=item * B<compressor>

Compress the value (but not the key) before storing into the cache, using
the compression package identified by the value of the parameter. Supported
values are:

  'zlib'     for 'Compress::Zlib'
  'lz4'      for 'Compress::LZ4'
  'snappy'   for 'Compress::Snappy'
  [ $c, $d ] for custom compressor/de-compressor

If this parameter has a value the module will attempt to load the
associated package and then use the API of that package to compress data
before storing in the cache, and uncompress it upon retrieval from the
cache. (default: undef)

You can use a custom compressor/de-compressor by passing an array-ref
with two values. The first should be a subroutine reference that takes
the data to compress as a single octet stream argument and returns an
octet stream to store. The second should be a subroutine reference that
takes the compressed octet stream as a single argument and returns the
original uncompressed data.

(Note: Historically this module only supported a boolean value for the
`compress` parameter and defaulted to use Compress::Zlib. The note for the
old `compress` parameter stated: "Some initial testing shows that the
uncompressing tends to be very fast, though the compressing can be quite
slow, so it's probably best to use this option only if you know values in
the cache are long-lived and have a high hit rate."

Comparable test results for the other compression tools are not yet available;
submission of benchmarks welcome. However, the documentation for the 'Snappy'
library (http://google.github.io/snappy/) states: For instance, compared to
the fastest mode of zlib, Snappy is an order of magnitude faster for most
inputs, but the resulting compressed files are anywhere from 20% to 100%
bigger. )

=item * B<compress>

Deprecated. Please use B<compressor>, see above.

=item * B<enable_stats>

Enable some basic statistics capturing. When enabled, every read to
the cache is counted, and every read to the cache that finds a value
in the cache is also counted. You can then retrieve these values
via the get_statistics() call. This causes every read action to
do a write on a page, which can cause some more IO, so it's
disabled by default. (default: 0)

=item * B<expire_time>

Maximum time to hold values in the cache in seconds. A value of 0
means does no explicit expiry time, and values are expired only based
on LRU usage. Can be expressed as 1m, 1h, 1d for minutes/hours/days
respectively. (default: 0)

=back

You may specify the cache size as:

=over 4

=item * B<cache_size>

Size of cache. Can be expresses as 1k, 1m for kilobytes or megabytes
respectively. Automatically guesses page size/page count values.

=back

Or specify explicit page size/page count values. If none of these are
specified, the values page_size = 64k and num_pages = 89 are used.

=over 4

=item * B<page_size>

Size of each page. Must be a power of 2 between 4k and 1024k. If not,
is rounded to the nearest value.

=item * B<num_pages>

Number of pages. Should be a prime number for best hashing

=back

The cache allows the use of callbacks for reading/writing data to an
underlying data store.

=over 4

=item * B<context>

Opaque reference passed as the first parameter to any callback function
if specified

=item * B<read_cb>

Callback to read data from the underlying data store.  Called as:

  $read_cb->($context, $Key)
  
Should return the value to use. This value will be saved in the cache
for future retrievals. Return undef if there is no value for the
given key

=item * B<write_cb>

Callback to write data to the underlying data store.
Called as:

  $write_cb->($context, $Key, $Value, $ExpiryTime)
  
In 'write_through' mode, it's always called as soon as a I<set(...)>
is called on the Cache::FastMmap class. In 'write_back' mode, it's
called when a value is expunged from the cache if it's been changed
by a I<set(...)> rather than read from the underlying store with the
I<read_cb> above.

Note: Expired items do result in the I<write_cb> being
called if 'write_back' caching is enabled and the item has been
changed. You can check the $ExpiryTime against C<time()> if you only
want to write back values which aren't expired.

Also remember that I<write_cb> may be called in a different process
to the one that placed the data in the cache in the first place

=item * B<delete_cb>

Callback to delete data from the underlying data store.  Called as:

  $delete_cb->($context, $Key)

Called as soon as I<remove(...)> is called on the Cache::FastMmap class

=item * B<cache_not_found>

If set to true, then if the I<read_cb> is called and it returns
undef to say nothing was found, then that information is stored
in the cache, so that next time a I<get(...)> is called on that
key, undef is returned immediately rather than again calling
the I<read_cb>

=item * B<write_action>

Either 'write_back' or 'write_through'. (default: write_through)

=item * B<allow_recursive>

If you're using a callback function, then normally the cache is not
re-enterable, and attempting to call a get/set on the cache will
cause an error. By setting this to one, the cache will unlock any
pages before calling the callback. During the unlock time, other
processes may change data in current cache page, causing possible
unexpected effects. You shouldn't set this unless you know you
want to be able to recall to the cache within a callback.
(default: 0)

=item * B<empty_on_exit>

When you have 'write_back' mode enabled, then
you really want to make sure all values from the cache are expunged
when your program exits so any changes are written back.

The trick is that we only want to do this in the parent process,
we don't want any child processes to empty the cache when they exit.
So if you set this, it takes the PID via $$, and only calls
empty in the DESTROY method if $$ matches the pid we captured
at the start. (default: 0)

=item * B<unlink_on_exit>

Unlink the share file when the cache is destroyed.

As with empty_on_exit, this will only unlink the file if the
DESTROY occurs in the same PID that the cache was created in
so that any forked children don't unlink the file.

This value defaults to 1 if the share_file specified does
not already exist. If the share_file specified does already
exist, it defaults to 0.

=item * B<catch_deadlocks>

Sets an alarm(10) before each page is locked via fcntl(F_SETLKW) to catch
any deadlock. This used to be the default behaviour, but it's not really
needed in the default case and could clobber sub-second Time::HiRes
alarms setup by other code. Defaults to 0.

=back

=cut
sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  # If first item is a hash ref, use it as arguments
  my %Args = ref($_[0]) eq 'HASH' ? %{shift()} : @_;

  my $Self = {};
  bless ($Self, $Class);

  # Work out cache file and whether to init
  my $share_file = $Args{share_file};
  if (!$share_file) {
    my $tmp_dir = File::Spec->tmpdir;
    $share_file = File::Spec->catfile($tmp_dir, "sharefile");
    $share_file .= "-" . $$ . "-" . time . "-" . int(rand(100000));
  }
  !ref($share_file) || die "share_file argument was a reference";
  $Self->{share_file} = $share_file;
  my $permissions = $Args{permissions};

  my $init_file = $Args{init_file} ? 1 : 0;
  my $test_file = $Args{test_file} ? 1 : 0;
  my $enable_stats = $Args{enable_stats} ? 1 : 0;
  my $catch_deadlocks = $Args{catch_deadlocks} ? 1 : 0;

  # Worth out unlink default if not specified
  if (!exists $Args{unlink_on_exit}) {
    $Args{unlink_on_exit} = -f($share_file) ? 0 : 1;
  }

  # Serialise stored values?
  my $serializer = $Args{serializer};
  $serializer = ($Args{raw_values} ? '' : 'storable') if !defined $serializer;

  if ($serializer) {
    if (ref $serializer eq 'ARRAY') {
      $Self->{serialize}   = $serializer->[0];
      $Self->{deserialize} = $serializer->[1];
    } elsif ($serializer eq 'storable') {
      eval "require Storable;"
        || die "Could not load serialization package: Storable : $@";
      $Self->{serialize}   = Storable->can("freeze");
      $Self->{deserialize} = Storable->can("thaw");
    } elsif ($serializer eq 'sereal') {
      eval "require Sereal::Encoder; require Sereal::Decoder;"
        || die "Could not load serialization package: Sereal : $@";
      my $SerealEnc = Sereal::Encoder->new();
      my $SerealDec = Sereal::Decoder->new();
      $Self->{serialize} = sub { $SerealEnc->encode(@_); };
      $Self->{deserialize} = sub { $SerealDec->decode(@_); };
    } elsif ($serializer eq 'json') {
      eval "require JSON;"
        || die "Could not load serialization package: JSON : $@";
      my $JSON = JSON->new->utf8->allow_nonref;
      $Self->{serialize}   = sub { $JSON->encode(${$_[0]}); };
      $Self->{deserialize} = sub { \$JSON->decode($_[0]); };
    } else {
      die "Unrecognized value >$serializer< for `serializer` parameter";
    }
  }

  # Compress stored values?
  my $compressor = $Args{compressor};
  $compressor = ($Args{compress} ? 'zlib' : 0) if !defined $compressor;

  my %known_compressors = (
    zlib   => 'Compress::Zlib',
    lz4    => 'Compress::LZ4',
    snappy => 'Compress::Snappy',
  );

  if ( $compressor ) {
    if (ref $compressor eq 'ARRAY') {
      $Self->{compress}   = $compressor->[0];
      $Self->{uncompress} = $compressor->[1];
    } elsif (my $compressor_module = $known_compressors{$compressor}) {
      eval "require $compressor_module;"
        || die "Could not load compression package: $compressor_module : $@";

      # LZ4 and Snappy use same API
      if ($compressor_module eq 'Compress::LZ4' || $compressor_module eq 'Compress::Snappy') {
        $Self->{compress}   = $compressor_module->can("compress");
        $Self->{uncompress} = $compressor_module->can("uncompress");
      } elsif ($compressor_module eq 'Compress::Zlib') {
        $Self->{compress}   = $compressor_module->can("memGzip");
        # (gunzip from tmp var: https://rt.cpan.org/Ticket/Display.html?id=72945)
        my $uncompress = $compressor_module->can("memGunzip");
        $Self->{uncompress} = sub { &$uncompress(my $Tmp = shift) };
      }
    } else {
      die "Unrecognized value >$compressor< for `compressor` parameter";
    }
  }

  # If using empty_on_exit, need to track used caches
  my $empty_on_exit = $Self->{empty_on_exit} = int($Args{empty_on_exit} || 0);

  # Need Scalar::Util::weaken to track open caches
  if ($empty_on_exit) {
    eval "use Scalar::Util qw(weaken); 1;"
      || die "Could not load Scalar::Util module: $@";
  }

  # Work out expiry time in seconds
  my $expire_time = $Self->{expire_time} = parse_expire_time($Args{expire_time});

  # Function rounds to the nearest power of 2
  sub RoundPow2 { return int(2 ** int(log($_[0])/log(2)) + 0.1); }

  # Work out cache size
  my ($cache_size, $num_pages, $page_size);

  my %Sizes = (k => 1024, m => 1024*1024);
  if ($cache_size = $Args{cache_size}) {
    $cache_size *= $Sizes{lc($1)} if $cache_size =~ s/([km])$//i;

    if ($num_pages = $Args{num_pages}) {
      $page_size = RoundPow2($cache_size / $num_pages);
      $page_size = 4096 if $page_size < 4096;

    } else {
      $page_size = $Args{page_size} || 65536;
      $page_size *= $Sizes{lc($1)} if $page_size =~ s/([km])$//i;
      $page_size = 4096 if $page_size < 4096;

      # Increase num_pages till we exceed 
      $num_pages = 89;
      if ($num_pages * $page_size <= $cache_size) {
        while ($num_pages * $page_size <= $cache_size) {
          $num_pages = $num_pages * 2 + 1;
        }
      } else {
        while ($num_pages * $page_size > $cache_size) {
          $num_pages = int(($num_pages-1) / 2);
        }
        $num_pages = $num_pages * 2 + 1;
      }

    }

  } else {
    ($num_pages, $page_size) = @Args{qw(num_pages page_size)};
    $num_pages ||= 89;
    $page_size ||= 65536;
    $page_size *= $Sizes{lc($1)} if $page_size =~ s/([km])$//i;
    $page_size = RoundPow2($page_size);
  }

  $cache_size = $num_pages * $page_size;
  @$Self{qw(cache_size num_pages page_size)}
    = ($cache_size, $num_pages, $page_size);

  # Number of slots to start in each page
  my $start_slots = int($Args{start_slots} || 0) || 89;

  # Save read through/write back/write through details
  my $write_back = ($Args{write_action} || 'write_through') eq 'write_back';
  @$Self{qw(context read_cb write_cb delete_cb)}
    = @Args{qw(context read_cb write_cb delete_cb)};
  @$Self{qw(cache_not_found allow_recursive write_back)}
    = (@Args{qw(cache_not_found allow_recursive)}, $write_back);
  @$Self{qw(unlink_on_exit enable_stats)}
    = (@Args{qw(unlink_on_exit)}, $enable_stats);

  # Save pid
  $Self->{pid} = $$;

  # Initialise C cache code
  my $Cache = fc_new();

  $Self->{Cache} = $Cache;

  # Setup cache parameters
  fc_set_param($Cache, 'init_file', $init_file);
  fc_set_param($Cache, 'test_file', $test_file);
  fc_set_param($Cache, 'page_size', $page_size);
  fc_set_param($Cache, 'num_pages', $num_pages);
  fc_set_param($Cache, 'expire_time', $expire_time);
  fc_set_param($Cache, 'share_file', $share_file);
  fc_set_param($Cache, 'permissions', $permissions) if defined $permissions;
  fc_set_param($Cache, 'start_slots', $start_slots);
  fc_set_param($Cache, 'catch_deadlocks', $catch_deadlocks);
  fc_set_param($Cache, 'enable_stats', $enable_stats);

  # And initialise it
  fc_init($Cache);

  # Track cache if need to empty on exit
  weaken($LiveCaches{ref($Self)} = $Self)
    if $empty_on_exit;

  # All done, return PERL hash ref as class
  return $Self;
}

=item I<get($Key, [ \%Options ])>

Search cache for given Key. Returns undef if not found. If
I<read_cb> specified and not found, calls the callback to try
and find the value for the key, and if found (or 'cache_not_found'
is set), stores it into the cache and returns the found value.

I<%Options> is optional, and is used by get_and_set() to control
the locking behaviour. For now, you should probably ignore it
unless you read the code to understand how it works

=cut
sub get {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # Hash value, lock page, read result
  my ($HashPage, $HashSlot) = fc_hash($Cache, $_[1]);
  my $Unlock = $Self->_lock_page($HashPage);
  my ($Val, $Flags, $Found, $ExpireOn) = fc_read($Cache, $HashSlot, $_[1]);

  # Value not found, check underlying data store
  if (!$Found && (my $read_cb = $Self->{read_cb})) {

    # Callback to read from underlying data store
    # (unlock page first if we allow recursive calls
    $Unlock = undef if $Self->{allow_recursive};
    $Val = eval { $read_cb->($Self->{context}, $_[1]); };
    my $Err = $@;
    $Unlock = $Self->_lock_page($HashPage) if $Self->{allow_recursive};

    # Pass on any error
    die $Err if $Err;

    # If we found it, or want to cache not-found, store back into our cache
    if (defined $Val || $Self->{cache_not_found}) {

      # Are we doing writeback's? If so, need to mark as dirty in cache
      my $write_back = $Self->{write_back};

      $Val = $Self->{serialize}(\$Val) if $Self->{serialize};
      $Val = $Self->{compress}($Val) if $Self->{compress};

      # Get key/value len (we've got 'use bytes'), and do expunge check to
      #  create space if needed
      my $KVLen = length($_[1]) + (defined($Val) ? length($Val) : 0);
      $Self->_expunge_page(2, 1, $KVLen);

      fc_write($Cache, $HashSlot, $_[1], $Val, -1, 0);
    }
  }

  # Unlock page and return any found value
  # Unlock is done only if we're not in the middle of a get_set() operation.
  my $SkipUnlock = $_[2] && $_[2]->{skip_unlock};
  $Unlock = undef unless $SkipUnlock;

  # If not using raw values, use thaw() to turn data back into object
  $Val = $Self->{uncompress}($Val) if defined($Val) && $Self->{compress};
  $Val = ${$Self->{deserialize}($Val)} if defined($Val) && $Self->{deserialize};

  # If explicitly asked to skip unlocking, we return the reference to the unlocker
  return ($Val, $Unlock, { $Found ? (expire_on => $ExpireOn) : () }) if $SkipUnlock;

  return $Val;
}

=item I<set($Key, $Value, [ \%Options ])>

Store specified key/value pair into cache

I<%Options> is optional. If it's not a hash reference, it's
assumed to be an explicit expiry time for the key being set,
this is to make set() compatible with the Cache::Cache interface

If a hash is passed, the only useful entries right now are expire_on to
set an explicit expiry time for this entry (epoch seconds), or expire_time
to set an explicit relative future expiry time for this entry in
seconds/minutes/days in the same format as passed to the new constructor.

Some other options are used internally, such as by get_and_set()
to control the locking behaviour. For now, you should probably ignore
it unless you read the code to understand how it works

This method returns true if the value was stored in the cache,
false otherwise. See the PAGE SIZE AND KEY/VALUE LIMITS section
for more details.

=cut
sub set {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  my $Val = $Self->{serialize} ? $Self->{serialize}(\$_[2]) : $_[2];
  $Val = $Self->{compress}($Val) if $Self->{compress};

  # Get opts, make compatible with Cache::Cache interface
  my $Opts = defined($_[3]) ? (ref($_[3]) ? $_[3] : { expire_time => $_[3] }) : undef;
  # expire_on takes precedence, otherwise use expire_time if present
  my $expire_on = defined($Opts) ? (
    defined $Opts->{expire_on} ? $Opts->{expire_on} :
      (defined $Opts->{expire_time} ? parse_expire_time($Opts->{expire_time}, _time()): -1)
  ) : -1;

  # Hash value, lock page
  my ($HashPage, $HashSlot) = fc_hash($Cache, $_[1]);

  # If skip_lock is passed, it's a *reference* to an existing lock we
  #  have to take and delete so we can cleanup below before calling
  #  the callback
  my $Unlock = $Opts && $Opts->{skip_lock};
  if ($Unlock) {
    ($Unlock, $$Unlock) = ($$Unlock, undef);
  } else {
    $Unlock = $Self->_lock_page($HashPage);
  }

  # Are we doing writeback's? If so, need to mark as dirty in cache
  my $write_back = $Self->{write_back};

  # Get key/value len (we've got 'use bytes'), and do expunge check to
  #  create space if needed
  my $KVLen = length($_[1]) + (defined($Val) ? length($Val) : 0);
  $Self->_expunge_page(2, 1, $KVLen);

  # Now store into cache
  my $DidStore = fc_write($Cache, $HashSlot, $_[1], $Val, $expire_on, $write_back ? FC_ISDIRTY : 0);

  # Unlock page
  $Unlock = undef;

  # If we're doing write-through, or write-back and didn't get into cache,
  #  write back to the underlying store
  if ((!$write_back || !$DidStore) && (my $write_cb = $Self->{write_cb})) {
    eval { $write_cb->($Self->{context}, $_[1], $_[2]); };
  }

  return $DidStore;
}

=item I<get_and_set($Key, $AtomicSub)>

Atomically retrieve and set the value of a Key.

The page is locked while retrieving the $Key and is unlocked only after
the value is set, thus guaranteeing the value does not change between
the get and set operations.

$AtomicSub is a reference to a subroutine that is called to calculate the
new value to store. $AtomicSub gets $Key, the current value from the
cache, and an options hash as paramaters. Currently the only option
passed is the expire_on of the item.

It should return the new value to set in the cache for the given $Key,
and an optional hash of arguments in the same format as would be passed
to a C<set()> call.

If $AtomicSub returns an empty list, no value is stored back
in the cache. This avoids updating the expiry time on an entry
if you want to do a "get if in cache, store if not present" type
callback.

For example:

=over 4

=item *

To atomically increment a value in the cache

  $Cache->get_and_set($Key, sub { return $_[1]+1; });

=item *

To add an item to a cached list and set the expiry time
depending on the size of the list

  $Cache->get_and_set($Key, sub ($, $v) {
    push @$v, $item;
    return ($v, { expire_time => @$v > 2 ? '10s' : '2m' });
  });

=item *

To update a counter, but maintain the original expiry time

  $Cache->get_and_set($Key, sub {
    return ($_[1]+1, { expire_on => $_[2]->{expire_on} );
  });


=back

In scalar context the return value from C<get_and_set()>, is the
*new* value stored back into the cache.

In list context, a two item array is returned; the new value stored
back into the cache and a boolean that's true if the value was stored
in the cache, false otherwise. See the PAGE SIZE AND KEY/VALUE LIMITS
section for more details.

Notes:

=over 4

=item *

Do not perform any get/set operations from the callback sub, as these
operations lock the page and you may end up with a dead lock!

=item *

If your sub does a die/throws an exception, the page will correctly
be unlocked (1.15 onwards)

=back

=cut
sub get_and_set {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  my ($Value, $Unlock, $Opts) = $Self->get($_[1], { skip_unlock => 1 });

  # If this throws an error, $Unlock ref will still unlock page
  my @NewValue = $_[2]->($_[1], $Value, $Opts);

  my $DidStore = 0;
  if (@NewValue) {
    ($Value, my $Opts) = @NewValue;
    $DidStore = $Self->set($_[1], $Value, { skip_lock => \$Unlock, %{$Opts || {}} });
  }

  return wantarray ? ($Value, $DidStore) : $Value;
}

=item I<remove($Key, [ \%Options ])>

Delete the given key from the cache

I<%Options> is optional, and is used by get_and_remove() to control
the locking behaviour. For now, you should probably ignore it
unless you read the code to understand how it works

=cut
sub remove {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # Hash value, lock page, read result
  my ($HashPage, $HashSlot) = fc_hash($Cache, $_[1]);

  # If skip_lock is passed, it's a *reference* to an existing lock we
  #  have to take and delete so we can cleanup below before calling
  #  the callback
  my $Unlock = $_[2] && $_[2]->{skip_lock};
  if ($Unlock) {
    ($Unlock, $$Unlock) = ($$Unlock, undef);
  } else {
    $Unlock = $Self->_lock_page($HashPage);
  }

  my ($DidDel, $Flags) = fc_delete($Cache, $HashSlot, $_[1]);
  $Unlock = undef;

  # If we deleted from the cache, and it's not dirty, also delete
  #  from underlying store
  if ((!$DidDel || ($DidDel && !($Flags & FC_ISDIRTY)))
     && (my $delete_cb = $Self->{delete_cb})) {
    eval { $delete_cb->($Self->{context}, $_[1]); };
  }
  
  return $DidDel;
}

=item I<get_and_remove($Key)>

Atomically retrieve value of a Key while removing it from the cache.

The page is locked while retrieving the $Key and is unlocked only after
the value is removed, thus guaranteeing the value stored by someone else
isn't removed by us.

=cut
sub get_and_remove {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  my ($Value, $Unlock) = $Self->get($_[1], { skip_unlock => 1 });
  my $DidDel = $Self->remove($_[1], { skip_lock => \$Unlock });
  return wantarray ? ($Value, $DidDel) : $Value;
}

=item I<expire($Key)>

Explicitly expire the given $Key. For a cache in write-back mode, this
will cause the item to be written back to the underlying store if dirty,
otherwise it's the same as removing the item. 

=cut
sub expire {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # Hash value, lock page, read result
  my ($HashPage, $HashSlot) = fc_hash($Cache, $_[1]);
  my $Unlock = $Self->_lock_page($HashPage);
  my ($Val, $Flags, $Found) = fc_read($Cache, $HashSlot, $_[1]);

  # If we found it, remove it
  if ($Found) {
    (undef, $Flags) = fc_delete($Cache, $HashSlot, $_[1]);
  }
  $Unlock = undef;

  # If it's dirty, write it back
  if (($Flags & FC_ISDIRTY) && (my $write_cb = $Self->{write_cb})) {
    eval { $write_cb->($Self->{context}, $_[1], $Val); };
  }

  return $Found;
}

=item I<clear()>

Clear all items from the cache

Note: If you're using callbacks, this has no effect
on items in the underlying data store. No delete
callbacks are made

=cut
sub clear {
  my $Self = shift;
  $Self->_expunge_all(1, 0);
}

=item I<purge()>

Clear all expired items from the cache

Note: If you're using callbacks, this has no effect
on items in the underlying data store. No delete
callbacks are made, and no write callbacks are made
for the expired data

=cut
sub purge {
  my $Self = shift;
  $Self->_expunge_all(0, 0);
}

=item I<empty($OnlyExpired)>

Empty all items from the cache, or if $OnlyExpired is
true, only expired items.

Note: If 'write_back' mode is enabled, any changed items
are written back to the underlying store. Expired items are
written back to the underlying store as well.

=cut
sub empty {
  my $Self = shift;
  $Self->_expunge_all($_[0] ? 0 : 1, 1);
}

=item I<get_keys($Mode)>

Get a list of keys/values held in the cache. May immediately be out of
date because of the shared access nature of the cache

If $Mode == 0, an array of keys is returned

If $Mode == 1, then an array of hashrefs, with 'key',
'last_access', 'expire_on' and 'flags' keys is returned

If $Mode == 2, then hashrefs also contain 'value' key

=cut
sub get_keys {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  my $Mode = $_[1] || 0;
  my ($Uncompress, $Deserialize) = @$Self{qw(uncompress deserialize)};

  return fc_get_keys($Cache, $Mode)
    if $Mode <= 1 || ($Mode == 2 && !$Uncompress && !$Deserialize);

  # If we're getting values as well, and they're not raw, unfreeze them
  my @Details = fc_get_keys($Cache, 2);

  for (@Details) {
    my $Val = $_->{value};
    if (defined $Val) {
      $Val = $Uncompress->($Val) if $Uncompress;
      $Val = ${$Deserialize->($Val)} if $Deserialize;
      $_->{value} = $Val;
    }
  }
  return @Details;
}

=item I<get_statistics($Clear)>

Returns a two value list of (nreads, nreadhits). This
only works if you passed enable_stats in the constructor

nreads is the total number of read attempts done on the
cache since it was created

nreadhits is the total number of read attempts done on
the cache since it was created that found the key/value
in the cache

If $Clear is true, the values are reset immediately after
they are retrieved

=cut
sub get_statistics {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});
  my $Clear = $_[1];

  my ($NReads, $NReadHits) = (0, 0);
  for (0 .. $Self->{num_pages}-1) {
    my $Unlock = $Self->_lock_page($_);
    my ($PNReads, $PNReadHits) = fc_get_page_details($Cache);
    $NReads += $PNReads;
    $NReadHits += $PNReadHits;
    fc_reset_page_details($Cache) if $Clear;
    $Unlock = undef;
  }
  return ($NReads, $NReadHits);
}

=item I<multi_get($PageKey, [ $Key1, $Key2, ... ])>

The two multi_xxx routines act a bit differently to the
other routines. With the multi_get, you pass a separate
PageKey value and then multiple keys. The PageKey value
is hashed, and that page locked. Then that page is
searched for each key. It returns a hash ref of
Key => Value items found in that page in the cache.

The main advantage of this is just a speed one, if you
happen to need to search for a lot of items on each call.

For instance, say you have users and a bunch of pieces
of separate information for each user. On a particular
run, you need to retrieve a sub-set of that information
for a user. You could do lots of get() calls, or you
could use the 'username' as the page key, and just
use one multi_get() and multi_set() call instead.

A couple of things to note:

=over 4

=item 1.

This makes multi_get()/multi_set() and get()/set()
incompatible. Don't mix calls to the two, because
you won't find the data you're expecting

=item 2.

The writeback and callback modes of operation do
not work with multi_get()/multi_set(). Don't attempt
to use them together.

=back

=cut
sub multi_get {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # Hash value page key, lock page
  my ($HashPage, $HashSlot) = fc_hash($Cache, $_[1]);
  my $Unlock = $Self->_lock_page($HashPage);

  # For each key to find
  my ($Keys, %KVs) = ($_[2]);
  for (@$Keys) {

    # Hash key to get slot in this page and read
    my $FinalKey = "$_[1]-$_";
    (undef, $HashSlot) = fc_hash($Cache, $FinalKey);
    my ($Val, $Flags, $Found, $ExpireOn) = fc_read($Cache, $HashSlot, $FinalKey);
    next unless $Found;

    # If not using raw values, use thaw() to turn data back into object
    $Val = $Self->{uncompress}($Val) if defined($Val) && $Self->{compress};
    $Val = ${$Self->{deserialize}($Val)} if defined($Val) && $Self->{deserialize};

    # Save to return
    $KVs{$_} = $Val;
  }

  # Unlock page and return any found value
  $Unlock = undef;

  return \%KVs;
}

=item I<multi_set($PageKey, { $Key1 => $Value1, $Key2 => $Value2, ... }, [ \%Options ])>

Store specified key/value pair into cache

=cut
sub multi_set {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # Get opts, make compatible with Cache::Cache interface
  my $Opts = defined($_[3]) ? (ref($_[3]) ? $_[3] : { expire_time => $_[3] }) : undef;
  # expire_on takes precedence, otherwise use expire_time if present
  my $expire_on = defined($Opts) ? (
    defined $Opts->{expire_on} ? $Opts->{expire_on} :
      (defined $Opts->{expire_time} ? parse_expire_time($Opts->{expire_time}, _time()): -1)
  ) : -1;

  # Hash page key value, lock page
  my ($HashPage, $HashSlot) = fc_hash($Cache, $_[1]);
  my $Unlock = $Self->_lock_page($HashPage);

  # Loop over each key/value storing into this page
  my $KVs = $_[2];
  while (my ($Key, $Val) = each %$KVs) {

    $Val = $Self->{serialize}(\$Val) if $Self->{serialize};
    $Val = $Self->{compress}($Val) if $Self->{compress};

    # Get key/value len (we've got 'use bytes'), and do expunge check to
    #  create space if needed
    my $FinalKey = "$_[1]-$Key";
    my $KVLen = length($FinalKey) + length($Val);
    $Self->_expunge_page(2, 1, $KVLen);

    # Now hash key and store into page
    (undef, $HashSlot) = fc_hash($Cache, $FinalKey);
    my $DidStore = fc_write($Cache, $HashSlot, $FinalKey, $Val, $expire_on, 0);
  }

  # Unlock page
  $Unlock = undef;

  return 1;
}

=back

=cut

=head1 INTERNAL METHODS

=over 4

=cut

=item I<_expunge_all($Mode, $WB)>

Expunge all items from the cache

Expunged items (that have not expired) are written
back to the underlying store if write_back is enabled

=cut
sub _expunge_all {
  my ($Self, $Cache, $Mode, $WB) = ($_[0], $_[0]->{Cache}, $_[1], $_[2]);

  # Repeat expunge for each page
  for (0 .. $Self->{num_pages}-1) {
    my $Unlock = $Self->_lock_page($_);
    $Self->_expunge_page($Mode, $WB, -1);
    $Unlock = undef;
  }

}

=item I<_expunge_page($Mode, $WB, $Len)>

Expunge items from the current page to make space for
$Len bytes key/value items

Expunged items (that have not expired) are written
back to the underlying store if write_back is enabled

=cut
sub _expunge_page {
  my ($Self, $Cache, $Mode, $WB, $Len) = ($_[0], $_[0]->{Cache}, @_[1 .. 3]);

  # If writeback mode, need to get expunged items to write back
  my $write_cb = $Self->{write_back} && $WB ? $Self->{write_cb} : undef;

  my @WBItems = fc_expunge($Cache, $Mode, $write_cb ? 1 : 0, $Len);

  my ($Uncompress, $Deserialize) = @$Self{qw(uncompress deserialize)};

  for (@WBItems) {
    next if !($_->{flags} & FC_ISDIRTY);

    my $Val = $_->{value};
    if (defined $Val) {
      $Val = $Uncompress->($Val) if $Uncompress;
      $Val = ${$Deserialize->($Val)} if $Deserialize;
    }
    eval { $write_cb->($Self->{context}, $_->{key}, $Val, $_->{expire_on}); };
  }
}

=item I<_lock_page($Page)>

Lock a given page in the cache, and return an object
reference that when DESTROYed, unlocks the page

=cut
sub _lock_page {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});
  my $Unlock = Cache::FastMmap::OnLeave->new(sub {
    fc_unlock($Cache) if fc_is_locked($Cache);
  });
  fc_lock($Cache, $_[1]);
  return $Unlock;
}

sub _time {
  $time_override ? $time_override : time;
}

sub _set_time_override {
  my $Time = shift;
  $time_override = $Time;
  fc_set_time_override($Time || 0);
}

my %Times = ('' => 1, s => 1, m => 60, h => 60*60, d => 24*60*60, w => 7*24*60*60);

sub parse_expire_time {
  my $expire_time = shift || '';
  return 0 if $expire_time eq 'never';
  return @_ ? shift : 1 if $expire_time eq 'now';
  my $offset = $expire_time =~ /^(\d+)\s*([mhdws]?)/i ? $1 * $Times{lc($2)} : 0;
  return $offset + (@_ ? shift : 0);
}

sub cleanup {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # Avoid potential double cleanup
  return if $Self->{cleaned};
  $Self->{cleaned} = 1;

  # Expunge all entries on exit if requested and in parent process
  if ($Self->{empty_on_exit} && $Cache && $Self->{pid} == $$) {
    $Self->empty();
  }

  if ($Cache) {
    fc_close($Cache);
    $Cache = undef;
    delete $Self->{Cache};
  }

  unlink($Self->{share_file})
    if $Self->{unlink_on_exit} && $Self->{pid} == $$;

}

sub DESTROY {
  my $Self = shift;
  $Self->cleanup();
  delete $LiveCaches{ref($Self)} if $Self->{empty_on_exit};
}

sub END {
  while (my (undef, $Self) = each %LiveCaches) {
    # Weak reference, might be undef already
    $Self->cleanup() if $Self;
  }
  %LiveCaches = ();
}

sub CLONE {
  die "Cache::FastMmap does not support threads sorry";
}

1;

package Cache::FastMmap::OnLeave;
use strict;

sub new {
  my $Class = shift;
  my $Ref = \$_[0];
  bless $Ref, $Class;
  return $Ref;
}

sub disable {
  ${$_[0]} = undef;
}

sub DESTROY {
  my $e = $@;  # Save errors from code calling us
  eval {

  my $Ref = shift;
  $$Ref->() if $$Ref;

  };
  # $e .= "        (in cleanup) $@" if $@;
  $@ = $e;
}

1;

__END__

=back

=cut

=head1 INCOMPATIBLE CHANGES

=over 4

=item * From 1.15

=over 4

=item *

Default share_file name is no-longer /tmp/sharefile, but /tmp/sharefile-$pid-$time.
This ensures that different runs/processes don't interfere with each other, but
means you may not connect up to the file you expect. You should be choosing an
explicit name in most cases.

On Unix systems, you can pass in the environment variable TMPDIR to
override the default directory of /tmp

=item *

The new option unlink_on_exit defaults to true if you pass a filename for the
share_file which doesn't already exist. This means if you have one process that
creates the file, and another that expects the file to be there, by default it
won't be.

Otherwise the defaults seem sensible to cleanup unneeded share files rather than
leaving them around to accumulate.

=back

=item * From 1.29

=over 4

=item *

Default share_file name is no longer /tmp/sharefile-$pid-$time 
but /tmp/sharefile-$pid-$time-$random.

=back

=item * From 1.31

=over 4

=item *

Before 1.31, if you were using raw_values => 0 mode, then the write_cb
would be called with raw frozen data, rather than the thawed object.
From 1.31 onwards, it correctly calls write_cb with the thawed object
value (eg what was passed to the ->set() call in the first place)

=back

=item * From 1.36

=over 4

=item *

Before 1.36, an alarm(10) would be set before each attempt to lock
a page. The only purpose of this was to detect deadlocks, which
should only happen if the Cache::FastMmap code was buggy, or a
callback function in get_and_set() made another call into
Cache::FastMmap.

However this added unnecessary extra system calls for every lookup,
and for users using Time::HiRes, it could clobber any existing
alarms that had been set with sub-second resolution.

So this has now been made an optional feature via the catch_deadlocks
option passed to new.

=back

=item * From 1.52

=over 4

=item *

The term expire_time was overloaded in the code to sometimes mean
a relative future time (e.g. as passed to new constructor) or an
absolute unix epoch (e.g. as returned from get_keys(2)).

To avoid this confusion, the code now uses expire_time to always
means a relative future time, and expire_on to mean an absolute
epoch time. You can use either as an optional argument to a
set() call.

Since expire_time was used in the constructor and is likely more
commonly used, I changed the result of get_keys(2) so it now
returns expire_on rather than expire_time.

=back

=back

=cut

=head1 SEE ALSO

L<MLDBM::Sync>, L<IPC::MM>, L<Cache::FileCache>, L<Cache::SharedMemoryCache>,
L<DBI>, L<Cache::Mmap>, L<BerkeleyDB>

Latest news/details can also be found at:

L<http://cpan.robm.fastmail.fm/cachefastmmap/>

Available on github at:

L<https://github.com/robmueller/cache-fastmmap/>

=cut

=head1 AUTHOR

Rob Mueller L<mailto:cpan@robm.fastmail.fm>

=cut

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2003-2017 by FastMail Pty Ltd

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

