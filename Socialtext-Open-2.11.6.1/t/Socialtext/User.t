#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext tests => 12;
fixtures( 'rdbms_clean' );

use Socialtext::User;

my $user;

# Since the Postgres plugin is always available, these are duplicated here
is( Socialtext::User->Count(), 2, 'base users are registered' );
ok( Socialtext::User->SystemUser, 'a system user exists' );
ok( Socialtext::User->Guest, 'a guest user exists' );

$user = Socialtext::User->new( username => 'devnull9@socialtext.net', );
is( $user, undef, 'no non-special users exist yet' );

$user = Socialtext::User->SystemUser;

is( $user->driver_name, 'Default',
    'System User is stored in Postgres (Default).'
);

is( $user->creator->username, 'system-user',
    'System User sprang from suigenesis.'
);

my $new_user = Socialtext::User->create(
    username      => 'devnull1@socialtext.com',
    first_name    => 'Dev',
    last_name     => 'Null',
    email_address => 'devnull1@socialtext.com',
    password      => 'd3vnu11l'
);

is( $new_user->creator->username, 'system-user',
    'Unidentified creators default to system-user.'
);

my $newer_user = Socialtext::User->create(
    username           => 'devnull2@socialtext.com',
    first_name         => 'Dev',
    last_name          => 'Null 2',
    email_address      => 'devnull2@socialtext.com',
    password           => 'password',
    created_by_user_id => $new_user->user_id
);

is( $newer_user->creator->username, 'devnull1@socialtext.com',
    'Tracking creator.'
);

ok( $newer_user->password_is_correct( 'password' ),
    'Password checks out.'
);

ok( $newer_user->update_store( last_name => 'Nullius' ),
    'Can update certain data (like last name).'
);

eval { $newer_user->update_metadata( is_system_created => 1 ) };
like( $@, qr/cannot change/,
        'But not others (like is system created).'
);

my $user3 = Socialtext::User->create(
    username      => 'nonauth@socialtext.net',
    email_address => 'nonauth@socialtext.net',
    password      => 'unencrypted',
    no_crypt      => 1,
    created_by_user_id => $user->user_id,
);

$user3->set_confirmation_info(is_password_change => 0);

is( $user3->requires_confirmation, 1, 'user requires confirmation' );
