#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext tests => 4;
fixtures( 'admin_no_pages' );
use Socialtext::Pages;

# XXX sigh, cgi->changes is checked to see if we should get the data
$ENV{GATEWAY_INTERFACE} = 1;
$ENV{QUERY_STRING} = 'action=recent_changes;changes=recent';
$ENV{REQUEST_METHOD} = 'GET';

my $hub = new_hub('admin');
$hub->preload;

# make a change
{
    my $page = Socialtext::Page->new(hub => $hub)->create(
        title => 'this is a new page',
        content => 'hello',
        creator => $hub->current_user,
    );
}

{
    my $output = $hub->recent_changes->recent_changes;

    ok($output ne '', 'output exists');
    like($output, qr/index.cgi\?this_is_a_new_page" title/,
        'output is somewhat reasonable');
    unlike($output, qr/called at lib\/.*line\s\d+/,
        'does not have error output');
    like($output, qr/this is a new page/i, 'expected title is present');
}
