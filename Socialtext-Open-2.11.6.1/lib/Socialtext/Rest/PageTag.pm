package Socialtext::Rest::PageTag;
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

=head1 NAME

Socialtext::Rest::PageTag - Manage tags on a page via REST

=head1 SYNOPSIS

    GET    /data/workspaces/:ws/pages/:pname/tags/:tag
    PUT    /data/workspaces/:ws/pages/:pname/tags/:tag
    DELETE /data/workspaces/:ws/pages/:pname/tags/:tag

=head1 DESCRIPTION

Provide a way to determine existince, add or remove one single tag
from one single page. When a tag is added, if it does not exist
in the tag system it is created. When a tag is removed from a page,
the tag remains in the system.

=cut

use base 'Socialtext::Rest::Tag';

sub _find_tag {
    my $self = shift;
    my $tag  = shift;

    return $self->page->has_tag($tag);
}

sub _add_tag {
    my $self = shift;
    my $tag  = shift;

    $self->_clean_tag(\$tag);

    $self->page->add_tags($tag);
}

# REVIEW: this sure looks a lot like _add_tag
sub _delete_tag {
    my $self = shift;
    my $tag  = shift;

    $self->_clean_tag(\$tag);

    $self->page->delete_tag($tag);
    $self->page->store(user => $self->page->hub->current_user );
}

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=cut

1;
