package Socialtext::Rest::WorkspaceTags;
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Socialtext::String;

use base 'Socialtext::Rest::Tags';

=head1 NAME

Socialtext::Rest::WorkspaceTags - A class for exposing collections of Tags associated with a Workspace

=head1 SYNOPSIS

    GET  /data/workspaces/:ws/tags
    POST /data/workspaces/:ws/tags

=head1 DESCRIPTION

Every workspace has a collection of zero or more tags (aka categories) that
may be used to describe pages and as navigational aids. At the URIs listed
above it is possible to get a list of those tags, or add a new tag 
to those available for use.

See L<Socialtext::Rest::Tags> for information on representations.

=cut
sub collection_name { "Tags for " . $_[0]->workspace->title . "\n" }

sub _entities_for_query {
    my $self = shift;

    return $self->hub->category->all_visible_categories();
}

sub add_text_element {
    my ( $self, $tag ) = @_;

    chomp $tag;
    $self->hub->category->save($tag);

    return $self->_uri_for_tag($tag);
}

1;
=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
