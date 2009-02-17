#!perl -Tw
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use Test::More skip_all => 'FIXME';

use warnings;
use strict;
use Test::More tests => 1;

BEGIN {
    use_ok( 'Socialtext::Handler::Changes::Full' );
}
