use 5.006;
use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'          => 'Cache::FastMmap',
    'VERSION_FROM'  => 'lib/Cache/FastMmap.pm',
    'ABSTRACT_FROM' => 'lib/Cache/FastMmap.pm',
    'AUTHOR'        => 'Rob Mueller <cpan@robm.fastmail.fm>',
    'PREREQ_PM'     => {
      'Storable' => 0,
    },
    'LIBS'          => [''],
    'INC'           => '-I.',
    'OBJECT'        => 'CImpl.o mmap_cache.o ' . ($^O eq 'MSWin32' ? 'win32.o' : 'unix.o'),
#	    'OPTIMIZE' => '-g -DDEBUG -ansi -pedantic',
);

package MY;

sub constants {
  $_[0]->{DLBASE} = "CImpl";
  $_[0]->{FULLEXT} = "Cache/FastMmap/CImpl";
  return shift->SUPER::constants();
}
