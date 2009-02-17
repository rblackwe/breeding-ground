#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::Challenger;
use strict;
use warnings;

use Socialtext::AppConfig;
use base qw( Socialtext::MultiPlugin );

sub base_package {
    return __PACKAGE__;
}

sub _drivers {
    my $class = shift;
    my $driver = Socialtext::AppConfig->challenger();
    return $driver;
}

sub Challenge {
    my $class = shift;

    my $return = $class->_first('challenge', @_);
}

1;

__END__

=head1 NAME

Socialtext::Challenger
- a pluggable mechanism for challenging the user who can't authenticate 

=head1 SYNOPSIS

  use Socialtext::Challenger;
  Socialtext::Challenger->Challenge(
      request => $r,
      hub     => $hub,                  # Optional
  );

=head1 DESCRIPTION

This class provides a hook point for registering new means of challenging a
user or system for credentials.

=head1 METHODS

=head2 Socialtext::Challenger->Challenge(ARGS)

Activates the first credentials challenger it can.  Generally this will cause
an HTTP reponse of some kind.  Examples include 401 to request HTTP Basic
authentication, 302 to redirect to a login page, or 200 plus the content of a
login page.  The default setting in L<Socialtext::AppConfig> is to use
L<Socialtext::Challenger:STLogin> but this can be configured in
C<socialtext.conf>.

The caller should realize that in most cases a challenger will cause a
redirect through an abort exception, and not return in a traditional sense.
Similarly, the callee can expect that no HTTP response code or headers have
been written to the client yet.

Individual plugin classes are expected to implement a class method called
C<challenge> (note case distinction).  If it returns false, the system did not
activate (for whatever reason) and the next challenger will be tried.

=head3 ARGUMENTS

C<challenge> accepts a hash of arguments.  C<request> is required and is the
web request object.  C<hub> is often passed when a L<Socialtext::Hub> has
already been created.  Implementors need to handle the case when a hub is
present and the case when a hub is not.  If there is a hub, it indicates the
the URI being requested corresponds to some workspace.  So the user B<may> be
authenticated but not authorized.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2007 Socialtext, Inc., All Rights Reserved.

=cut
