use 5.006;
use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'          => 'Cache::FastMmap',
    'VERSION_FROM'  => 'FastMmap.pm',
    'ABSTRACT_FROM' => 'FastMmap.pm',
    'AUTHOR'        => 'Rob Mueller <cpan@robm.fastmail.fm>',
    'PREREQ_PM'     => {
      'Storable' => 0,
    },
    'DIR'           => [
      'Cache-FastMmap-CImpl'
    ],
#	    'OPTIMIZE' => '-g -DDEBUG -ansi -pedantic',
);
