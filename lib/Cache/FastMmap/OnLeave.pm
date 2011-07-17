#!/usr/bin/perl -w
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
