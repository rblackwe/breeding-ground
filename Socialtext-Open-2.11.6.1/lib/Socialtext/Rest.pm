package Socialtext::Rest;
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use warnings;
use strict;

# A base class in which to group code common to all 'Socialtext::Rest::*'
# classes.

use Class::Field 'field';
use DateTime;
use DateTime::Format::HTTP;
use Carp 'croak';

use Socialtext::Workspace;
use Socialtext::HTTP ':codes';

our $AUTOLOAD;

field 'hub',  -init => '$self->main->hub';
field 'main', -init => '$self->_new_main';
field 'page', -init => '$self->hub->pages->new_from_uri($self->pname)';
field 'params';
field 'rest';
field 'workspace', -init => '$self->_new_workspace';

sub new {
    my $class = shift;
    my $new_object = bless {}, $class;
    $new_object->_initialize(@_);
    return $new_object;
}

sub error {
    my ( $self, $code, $msg, $body ) = @_;
    $self->rest->header(
        -status => "$code $msg",
        -type   => 'text/plain',
    );
    return $body;
}

sub bad_method {
    my ( $self, $rest ) = @_;
    my $allowed = $self->allowed_methods;
    $rest->header(
        -allow  => $allowed,
        -status => HTTP_405_Method_Not_Allowed,
        -type   => 'text/plain' );
    return HTTP_405_Method_Not_Allowed . "\n\nOnly $allowed are supported.\n";
}

=head2 bad_type

The request sent a content-type that's not useful for the current URI.

=cut
# REVIEW: Ideally this would wire back to the uri_map to tell us
# what types are acceptable.
sub bad_type {
    my ( $self, $rest ) = @_;
    $rest->header(
        -status => HTTP_415_Unsupported_Media_Type,
    );
    return '';
}

sub _initialize {
    my ( $self, $rest, $params ) = @_;

    $self->rest($rest);
    $self->params($params);
}

sub _new_workspace {
    my $self = shift;

    return $self->ws
        ? Socialtext::Workspace->new( name => $self->ws )
        : undef;
}

sub _new_main {
    my $self = shift;
    my $main = Socialtext->new;

    $main->load_hub(
        current_user      => $self->rest->user,
        current_workspace => $self->workspace,
    );
    $main->hub->registry->load;
    $main->debug;

    return $main;
}

=head2 make_http_date

Given an epoch time, returns a properly formatted RFC 1123 date
string.

=cut
sub make_http_date {
    my $self = shift;
    my $epoch = shift;
    my $dt = DateTime->from_epoch( epoch => $epoch );
    return DateTime::Format::HTTP->format_datetime($dt);
}

=head2 make_date_time_date

Given an HTTP (rfc 1123) date, return a DateTime object.

=cut
sub make_date_time_date {
    my $self = shift;
    my $timestring = shift;
    return DateTime::Format::HTTP->parse_datetime($timestring);
}

=head2 user_can($permission_name)

C<$permission_name> can either be the name of a L<Socialtext::Permission> or
the name of a L<Socialtext::User> method.  If C<$permission_name> begins with
C<is_>, then it is assumed to be the latter.  E.g, C<is_business_admin>.

=cut
sub user_can {
    my $self = shift;
    my $permission_name = shift;
    return $permission_name =~ /^is_/
        ? $self->rest->user->$permission_name
        : $self->hub->checker->check_permission($permission_name);
}

=head2 if_authorized($http_method, $perl_method, @args)

Checks the hash returned by C<< $self->permission >> to see if the user is
authorized to perform C<< $http_method >> using C<< $self->user_can >>. If so,
executes C<< $self->$perl_method(@args) >>, and if not returns
C<< $self->not_authorized >>.

The default implementation of C<permission> requires C<read> for C<GET> and
C<edit> for C<PUT>, C<POST>, and C<DELETE>.

=cut
sub if_authorized {
    my ( $self, $method, $perl_method, @args ) = @_;
    my $perm_name = $self->permission->{$method};

    return !$perm_name
        ? $self->$perl_method(@args)
        : $perm_name !~ /^is/ && !defined $self->workspace
            ? $self->no_workspace
            : ( !$perm_name ) || $self->user_can($perm_name)
                ? $self->$perl_method(@args)
                : $self->not_authorized;
}

sub permission {
    +{ GET => 'read', PUT => 'edit', POST => 'edit', DELETE => 'delete' };
}

=head2 not_authorized()

Tells the client the current user is not authorized for the
requested method on the resource.

=cut
sub not_authorized {
    my $self = shift;
    $self->rest->header(
        -status => HTTP_403_Forbidden,
        -type   => 'text/plain',
    );
    return 'User not authorized';
}

=head2 _user_is_business_admin_p()

_Protected_

Yet another way to check for a role, though this one works a bit better for checking
if the current user is a business admin.

=cut
sub _user_is_business_admin_p {
    my $self = shift;
    return $self->user_can( 'is_business_admin' );
}

=head2 no_workspace()

Informs the client that we can't operate because no valid workspace
was created from the provided URI.

=cut
sub no_workspace {
    my $self = shift;
    $self->rest->header(
        -status => HTTP_404_Not_Found,
        -type   => 'text/plain',
    );
    return $self->ws . ' not found';
}

# REVIEW: making use of CGI.pm here
sub full_url {
    my $self = shift;

    return join '', $self->rest->query->url( -full => 1, -path_info => 1 ), @_;
}

# Automatic getters for query parameters.
sub AUTOLOAD {
    my $self = shift;
    my $type = ref $self or die "$self is not an object.\n";

    $AUTOLOAD =~ s/.*://;
    return if $AUTOLOAD eq 'DESTROY';

    if (exists $self->params->{$AUTOLOAD}) {
        croak("Cannot set the value of '$AUTOLOAD'") if @_;
        return $self->params->{$AUTOLOAD};
    }
    croak("No such method '$AUTOLOAD' for type '$type'.");
}


1;
