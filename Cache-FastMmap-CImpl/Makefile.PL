use 5.006;
use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'          => 'Cache::FastMmap::CImpl',
    'AUTHOR'        => 'Rob Mueller <cpan@robm.fastmail.fm>',
    'VERSION_FROM'  => 'CImpl.pm',
    'LIBS'          => [''],
    'INC'           => '-I.',
    'OBJECT'        => 'CImpl.o mmap_cache.o ' . ($^O eq 'MSWin32' ? 'win32.o' : 'unix.o'),
#	    'DEFINE'        => '-DDEBUG',
);
