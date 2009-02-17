package Socialtext::User;
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;
    my $self = \%opts;
    bless $self, $class;
    return $self;
}

sub confirm_email_address {}

sub confirmation_uri { 'blah/nlw/submit/confirm/foo' }

1;
