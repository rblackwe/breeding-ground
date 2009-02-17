#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::RefcardPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

sub class_id { 'refcard' }

sub register {
    my $self = shift;
    $self->hub->registry->add(action => 'refcard');
}

sub refcard {
    my $self = shift;
    $self->template_process('view/refcard');
}

1;

