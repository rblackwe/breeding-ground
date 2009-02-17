#!perl -Tw
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::More;

BEGIN {
    plan skip_all => 'Not meaningful unless we are under mod_perl' unless $ENV{MOD_PERL};
    plan tests => 1;
    use_ok( 'Socialtext::Handler::Cleanup' );
}
