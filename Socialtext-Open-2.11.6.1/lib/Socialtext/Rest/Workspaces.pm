package Socialtext::Rest::Workspaces;
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use warnings;
use strict;

use base 'Socialtext::Rest::Collection';

use JSON;
use Socialtext::HTTP ':codes';
use Socialtext::Permission;
use Socialtext::Workspace;
use Socialtext::User;

$JSON::UTF8 = 1;

# Anybody can see these, since they are just the list of workspaces the user
# has 'selected'.
sub permission { +{} }

sub collection_name {
    'Workspaces';
}

sub _entities_for_query {
    my $self = shift;

    my $query = $self->rest->query->param('q');
    my $user  = $self->rest->user();

    # REVIEW: Alzabo Cursors lurk in here. Make sure we get
    # the whole list.
    # REVIEW: 'all' should only work for some super authenticate user,
    # but which one? business admin seems right
    if ( defined $query and $query eq 'all' and $user->is_business_admin() )
    {
        return ( Socialtext::Workspace->All()->all() );
    }
    elsif ( defined $query and $query eq 'selected' ) {
        return ( $self->rest->user->workspaces( selected_only => 1 )->all() );
    }
    else {
        return ( $self->rest->user->workspaces()->all() );
    }
}

sub _entity_hash {
    my $self      = shift;
    my $workspace = shift;

    return +{
        name  => $workspace->name,
        uri   => '/data/workspaces/' . $workspace->name,
        title => $workspace->title,
        # not really modified time, but it is the time we have
        modified_time => $workspace->creation_datetime,

        # REVIEW: more?
    };
}

sub POST {
    my $self = shift;
    my $rest = shift;

    unless ($self->_user_is_business_admin_p( ) ) {
        $rest->header(
                      -status => HTTP_401_Unauthorized,
                     );
        return '';
    }

    my $create_request_hash = jsonToObj( $rest->getContent() );

    unless ( $create_request_hash->{name} and
             $create_request_hash->{title} and
             $create_request_hash->{account_id} ) {
        $rest->header(
            -status => HTTP_400_Bad_Request,
            -type  => 'text/plain', );
        return "name, title, account_id required";
    }

    my $new_workspace_name = $create_request_hash->{name};

    if ( Socialtext::Workspace->new( name => $new_workspace_name ) ) {
        $rest->header(
            -status => HTTP_409_Conflict,
            -type   => 'text/plain', );
        return "$new_workspace_name is not a valid selection\n";
    }

    my ( $new_workspace ) = eval {
        $self->_create_workspace(
            creator          => $self->rest->user(),
            %$create_request_hash );
    };

    if ( my $e = Exception::Class->caught('Socialtext::Exception::DataValidation') ) {
        $rest->header(
                      -status => HTTP_400_Bad_Request,
                      -type   => 'text/plain' );
        return join( "\n", $e->messages );
    } elsif ( $@ ) {
        $rest->header(
            -status => HTTP_400_Bad_Request,
            -type   => 'text/plain' );
        # REVIEW: what kind of system logging should we be doing here?
        return "$@";
    }

    $rest->header(
        -status => HTTP_201_Created,
        -type   => 'application/json',
        -Location => $self->full_url('/', $new_workspace_name),
    );

    return '';

}

sub _admin_in_workspace_p {
    my $self = shift;
    my %p    = @_;

    return $p{workspace}->user_has_permission(
        user       => $p{user},
        permission =>
            Socialtext::Permission->new( name => 'admin_workspace' ), );
}

# REVIEW: Extract to Socialtext::*? Almost certainly
# The question is "what".  JJP thinks we want a "Socialtext::Provisioner" class
# that handles the various intricacies of business logic involved.
sub _create_workspace {
    my $self = shift;
    my %p    = @_;

    my $new_workspace = Socialtext::Workspace->create(
        name       => $p{name},
        title      => $p{title},
        account_id => $p{account_id},

        skin_name                       => $p{skin_name},
        show_welcome_message_below_logo =>
            $p{show_welcome_message_below_logo},
        show_title_below_logo => $p{show_title_below_logo},
        header_logo_link_uri  => $p{header_logo_link_uri},
    );
    # $new_workspace->set_logo_from_uri( uri => $p{logo_uri} );

    return ($new_workspace);
}

1;

