package Socialtext::Rest::WorkspaceAttachments;
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use warnings;
use strict;

use base 'Socialtext::Rest::Attachments';

sub allowed_methods { 'GET, HEAD' }

sub _entities_for_query {
    my $self = shift;
    return $self->hub->attachments->all_attachments_in_workspace()
}

1;

