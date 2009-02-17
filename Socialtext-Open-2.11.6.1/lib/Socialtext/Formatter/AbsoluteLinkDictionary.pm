#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::Formatter::AbsoluteLinkDictionary;
use base 'Socialtext::Formatter::LinkDictionary';

use strict;
use warnings;
use Class::Field qw'field';

BEGIN {
    # make some code

    my @methods
        = qw(interwiki search_query category_query recent_changes_query
        category weblog file image);
    no strict 'refs';
    foreach my $method (@methods) {
        my $super = "SUPER::$method";
        *{__PACKAGE__ . "::$method"} = sub {
            my $self = shift;
            return '%{url_prefix}' . $self->$super;
        }
    }
}

field free => -init => '$self->interwiki';

sub special_http {
    my $self = shift;
    return '%{url_prefix}' . '/%{workspace}/' . $self->SUPER::special_http();
}

1;
