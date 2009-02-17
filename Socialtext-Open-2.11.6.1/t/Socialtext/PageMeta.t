#!perl -Tw
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use warnings;
use strict;
use Test::More tests => 4;

BEGIN {
    use_ok( 'Socialtext::PageMeta' );
}

my $meta = Socialtext::PageMeta->new;
eval { $meta->from_hash( { DoesNotExist => 1 } ) };
is( $@, '', 'no error when bogus keys are passed to from_has()' );

eval { $meta->from_hash( { From => 'Joe', Revision => 10 } ) };
is( $meta->From, 'Joe', 'valid key in from_hash sets attribute (From)' );
is( $meta->Revision, 10, 'valid key in from_hash sets attribute (Revision)' );
