#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use MIME::Base64;
use Test::Socialtext;
use mocked 'Apache::Request';
use mocked 'Apache::Cookie';

BEGIN {
    plan tests => 4;
    fixtures('admin_no_pages');
    use_ok( 'Socialtext::Handler' );
}

GUEST: {
    my $guest_request = Apache::Request->new( uri => '/nowhere' );
    my $user = Socialtext::Handler->authenticate($guest_request);
    is $user, undef, "Guest user isn't set";
}

AUTHENTICATED: {
    my $fake_request = Apache::Request->new(
        Authorization => 'Basic ' . MIME::Base64::encode('devnull1@socialtext.com:d3vnu11l'),
        uri => '/nowhere'
    );
    my $user = Socialtext::Handler->authenticate($fake_request);
    is $user->username, 'devnull1@socialtext.com', "Retrieved user from headers";
    is $fake_request->connection->user, 'devnull1@socialtext.com', "Propogated username back up to the Request.";
}



