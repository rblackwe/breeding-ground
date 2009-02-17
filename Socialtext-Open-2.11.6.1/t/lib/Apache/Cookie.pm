package Apache::Cookie;
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
use strict;
use warnings;

our $DATA = {};

sub new {
    my ($class, %opts) = @_;
    my $self = { %opts };
    bless $self, $class;
}

sub value {
    my $self = shift;
    return %{ $self->{value} };
}

sub fetch {
    return $DATA;
}

1;
