#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext tests => 24;
fixtures( 'populated_rdbms' );
#use Test::Socialtext tests => 24, fixtures => ['admin_no_pages'];

use DateTime::Format::Pg;
use Socialtext::Workspace;

{
    my $workspaces = Socialtext::Workspace->All();
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ map { ("workspace$_") } 0..9 ],
        'All() returns workspaces sorted by name by default',
    );

    $workspaces = Socialtext::Workspace->All( limit => 2 );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( workspace0 workspace1 ) ],
        'All() limit of 2',
    );

    $workspaces = Socialtext::Workspace->All( limit => 2, offset => 2 );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( workspace2 workspace3 ) ],
        'All() limit of 2, offset of 2',
    );

    $workspaces = Socialtext::Workspace->All( sort_order => 'DESC' );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ reverse map { ("workspace$_") } 0..9 ],
        'All() in DESC order',
    );

    # Since ws 7-10 have the same number of users each, they come out
    # first, but sorted by name in ascending order.
    $workspaces = Socialtext::Workspace->All( order_by => 'user_count', sort_order => 'DESC' );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ map { ("workspace$_") } 6, 7, 8, 9, 5, 4, 2, 3, 1, 0 ],
        'All() sorted by DESC user_count',
    );

    $workspaces = Socialtext::Workspace->All( order_by => 'account_name' );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ map { ("workspace$_") } 1, 4, 7, 2, 5, 8, 0, 3, 6, 9 ],
        'All() sorted by account_name',
    );

    $workspaces = Socialtext::Workspace->All( order_by => 'creation_datetime' );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ map { ("workspace$_") } 0..9 ],
        'All() sorted by creation_datetime',
    );

    $workspaces = Socialtext::Workspace->All( order_by => 'creator' );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ map { ("workspace$_") } 6, 5, 4, 3, 2, 9, 1, 8, 0, 7  ],
        'All() sorted by creator',
    );
}

{
    my $account_id = Socialtext::Account->Socialtext()->account_id;

    my $workspaces = Socialtext::Workspace->ByAccountId( account_id => $account_id );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ map { ("workspace$_") } 0, 3, 6, 9 ],
        'ByAccountId() returns workspaces sorted by name by default',
    );

    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        limit      => 2,
    );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( workspace0 workspace3 ) ],
        'ByAccountId() limit of 2',
    );

    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        limit      => 2,
        offset     => 1,
    );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( workspace3 workspace6 ) ],
        'ByAccountId() limit of 2, offset of 2',
    );

    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        sort_order => 'DESC',
    );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ map { ("workspace$_") } 9, 6, 3, 0 ],
        'ByAccountId() in DESC order',
    );

    # Since ws 7-10 have the same number of users each, they come out
    # first, but sorted by name in ascending order.
    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        order_by   => 'user_count',
        sort_order => 'DESC',
    );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ map { ("workspace$_") } 6, 9, 3, 0 ],
        'ByAccountId() sorted by DESC user_count',
    );

    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        order_by   => 'creation_datetime',
    );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ map { ("workspace$_") } 0, 3, 6, 9 ],
        'ByAccountId() sorted by creation_datetime',
    );

    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        order_by   => 'creator',
    );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ map { ("workspace$_") } 6, 3, 9, 0, ],
        'ByAccountId() sorted by creator',
    );
}

{
    # We want to make sure that these workspaces have a known
    # creation_datetime, just for simplicity when testing ordering by
    # creation_datetime.
    my $now = DateTime->now();
    Socialtext::Workspace->create(
        name              => 'workspace10',
        title             => 'Workspace 10',
        account_id        =>
            Socialtext::Account->new( name => 'Other 1')->account_id,
        creation_datetime =>
            DateTime::Format::Pg->format_timestamptz($now),
    );

    my $ws = Socialtext::Workspace->create(
        name       => 'number-111',
        title      => 'Number 111',
        account_id =>
            Socialtext::Account->new( name => 'Other 2')->account_id,
        creation_datetime =>
            DateTime::Format::Pg->format_timestamptz($now),
    );

    for my $username ( qw( devnull6@urth.org devnull7@urth.org ) ) {
        my $user = Socialtext::User->new( username => $username );
        $ws->add_user( user => $user );
    }

    is( Socialtext::Workspace->CountByName( name => '1' ), 3,
        'Three workspaces match "%1%"' );

    my $workspaces = Socialtext::Workspace->ByName( name => '1' );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( number-111 workspace1 workspace10 ) ],
        'ByName() returns workspaces sorted by name by default',
    );

    $workspaces = Socialtext::Workspace->ByName( name => '1', limit => 2  );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( number-111 workspace1 ) ],
        'ByName() limit of 2',
    );

    $workspaces = Socialtext::Workspace->ByName( name => '1', limit => 2, offset => 1 );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( workspace1 workspace10 ) ],
        'ByName() limit of 2, offset of 1',
    );

    $workspaces = Socialtext::Workspace->ByName( name => '1', sort_order => 'DESC' );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( workspace10 workspace1 number-111 ) ],
        'ByName() in DESC order',
    );

    # Since ws 7-10 have the same number of users each, they come out
    # first, but sorted by name in ascending order.
    $workspaces = Socialtext::Workspace->ByName(
        name     => '1',
        order_by => 'user_count',
        sort_order => 'DESC',
    );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( workspace1 number-111 workspace10 ) ],
        'ByName() sorted by DESC user_count',
    );

    $workspaces = Socialtext::Workspace->ByName( name => '1', order_by => 'account_name' );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( workspace1 workspace10 number-111  ) ],
        'ByName() sorted by account_name',
    );

    $workspaces = Socialtext::Workspace->ByName( name => '1', order_by => 'creation_datetime' );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( number-111  workspace10 workspace1 ) ],
        'ByName() sorted by creation_datetime',
    );

    $workspaces = Socialtext::Workspace->ByName( name => '1', order_by => 'creator' );
    is_deeply(
        [ map { $_->name } $workspaces->all() ],
        [ qw( workspace1 number-111 workspace10 ) ],
        'ByName() sorted by creator',
    );
}
