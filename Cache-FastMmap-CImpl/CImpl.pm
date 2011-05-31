package Cache::FastMmap::CImpl;

=head1 NAME

Cache::FastMmap::CImpl - C code implementation for Cache::FastMmap

=head1 SYNOPSIS

Do not use this directly. Cache::FastMmap uses this

=cut

# Modules/Export/XSLoader {{{
use 5.006;
use strict;
use warnings;

our $VERSION = '1.36';

require XSLoader;
XSLoader::load('Cache::FastMmap::CImpl', $VERSION);
# }}}

sub DESTROY {
  my $Self = shift;

  # Close any file before destruction
  $Self->fc_close();
}

1;

__END__

=head1 AUTHOR

Rob Mueller E<lt>cpan@robm.fastmail.fmE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2003-2010 by The FastMail Partnership

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
