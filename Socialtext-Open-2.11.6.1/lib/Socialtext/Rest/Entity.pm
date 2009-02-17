package Socialtext::Rest::Entity;
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use warnings;
use strict;

=head1 NAME

Socialtext::Rest::Entity - Superclass for representations of a single object.

=head1 SEE ALSO

L<Socialtext::Rest::Collection>

=cut

use JSON;
$JSON::UTF8 = 1;

use base 'Socialtext::Rest';

use Socialtext::HTTP ':codes';

$JSON::UTF8 = 1;

sub allowed_methods {'GET, HEAD, PUT'}

sub attribute_table_row {
    my ( $self, $name, $value ) = @_;

    $value = "<a href='$value'>$value</a>" if $name =~ /uri$/;

    return "<tr><td>$name</td><td>$value</td></tr>\n";
}

{
    no warnings 'once';
    *GET_text = _make_getter(\&resource_to_text, 'text/plain');
    *GET_html = _make_getter(\&resource_to_html, 'text/html');
    *GET_json = _make_getter(\&resource_to_json, 'application/json');
    *PUT_json = _make_putter(\&json_to_resource);
}

# REVIEW: This is cut-paste from Socialtext::Rest::Collection.
sub _make_getter {
    my ( $sub, $content_type ) = @_;
    return sub {
        my ( $self, $rest ) = @_;

        $self->if_authorized(
            'GET',
            sub {
                if ( defined( my $resource = $self->get_resource($rest) ) ) {
                    $rest->header(
                        -type          => $content_type . '; charset=UTF-8',
                        -Last_Modified => $self->make_http_date(
                            $self->last_modified($resource)
                        )
                    );
                    return $self->$sub($resource);
                }
                return $self->http_404($rest);
            }
        );
    };
}

# REVIEW: This is cut-paste from Socialtext::Rest::Collection.
sub nonexistence_message { 'The requested resource does not exist.' }

# REVIEW: This is cut-paste from Socialtext::Rest::Collection.
sub last_modified { time }

# REVIEW: This is cut-paste from Socialtext::Rest::Collection.
sub http_404 {
    my ( $self, $rest ) = @_;

    $rest->header( -type   => 'text/plain',
                   -status => HTTP_404_Not_Found, );
    return $self->nonexistence_message;
}

sub http_400 {
   my ( $self, $rest, $content ) = @_;

    $rest->header( -type   => 'text/plain',
                   -status => HTTP_400_Bad_Request, );
    return $content || ""; 
}

# FIXME: No permissions checking here YET as its not used
# and what permission to check may need to be passed in as
# an argument.
sub _make_putter {
    my ( $sub ) = @_;
    return sub {
        my ( $self, $rest ) = @_;
        my $content = eval {
            my ( $location, $type, $content )
                = $self->put_generic( $self->$sub( $rest->getContent ) );
            my $status =
                  $location ? HTTP_201_Created
                : $content  ? HTTP_200_OK
                : HTTP_204_No_Content;
            $rest->header(
                -status => $status,
                $type     ? ( -type     => $type )     : (),
                $location ? ( -Location => $location ) : () );
            return $content;
        };
        if ($@) {
            $rest->header(
                -status => HTTP_400_Bad_Request
                -type   => 'text/plain' );
            return $@;
        }
        return $content;
    }
}

sub resource_to_text {
    my ( $self, $resource ) = @_;

    my $name = $self->entity_name;

    return $name . ': '
        . join( ', ', map {"$_:$resource->{$_}"} keys %$resource );
}

sub resource_to_html {
    my ( $self, $resource ) = @_;

    my $name = $self->entity_name;
    my $body = join '',
        map { $self->attribute_table_row( $_, $resource->{$_} ) }
            keys %$resource;
    return ( << "END_OF_HEADER" . $body . << "END_OF_TRAILER" );
<html>
<head>
<title>$name</title>
</head>
<body>
<h1>$name</h1>
<table>
END_OF_HEADER
</table>
</body>
</html>
END_OF_TRAILER
}

sub resource_to_json { objToJson($_[1]) }
sub json_to_resource { jsonToObj($_[1]) }

1;
