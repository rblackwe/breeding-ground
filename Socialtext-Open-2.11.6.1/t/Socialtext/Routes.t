#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::More tests => 17;

BEGIN { use_ok('Socialtext::Routes') }

# TEST: instantiate
{
    my $obj = Socialtext::Routes->new();
    isa_ok($obj, 'Socialtext::Routes');
}

# TEST: get routes map returns what you put in
{
    my $obj = Socialtext::Routes->new(map {$_ => $_*$_} (1 .. 1000));
    isa_ok($obj, 'Socialtext::Routes');
    is_deeply([$obj->routes_map->Keys], [(1 .. 1000)],
              'routes_map(): contains ordered keys');
    is_deeply([$obj->routes_map->Values], [map {$_*$_} (1 .. 1000)],
              'routes_map(): contains ordered values');
}

# TEST: append_routes
{
    my $obj = Socialtext::Routes->new();
    isa_ok($obj, 'Socialtext::Routes');
    eval { $obj->append_routes('odd number of stuff') };
    like($@, qr/Odd number of elements given to append_routes/);
    $obj->append_routes(map {$_ => $_*$_} (1 .. 1000));
    is_deeply([$obj->routes_map->Keys], [(1 .. 1000)],
              'append_routes() returns keys in right order');
    is_deeply([$obj->routes_map->Values], [map {$_*$_} (1 .. 1000)],
              'append_routes() returns values in right order');
}

# TEST: run, simple usage.  
{
    my $obj = Socialtext::Routes->new('/foo/:var/bar', => sub {+{@_}});
    isa_ok($obj, 'Socialtext::Routes');
    is_deeply($obj->run("/foo/42/bar"), {var => 42},
              "Testing parsing action");
    eval { $obj->run("/cows/are/:good") };
    like($@, qr/No route matched/, "Testing parsing action");
}

# TEST: run, more advanced usage.
{
    my $obj = Socialtext::Routes->new(
        '/data/tags/:tag', => sub {+{@_}},
        '/data/tags', => sub {+{@_}},
        '/data/pages/:page/sections/:section', => sub {+{@_}},
        '/data/workspaces/:ws/pages/:page', => sub {+{@_}},
        '/data/workspaces/:ws', => sub {+{@_}},
    );
    isa_ok($obj, 'Socialtext::Routes');

    is_deeply($obj->run("/data/tags"), {}, '/data/tags matches');
    is_deeply($obj->run("/data/tags/foo"), {tag => 'foo'}, 
              '/data/tags/foo matches');
    is_deeply($obj->run("/data/pages/cows/sections/udder/love/cakes"),
                        {page => 'cows', section => 'udder'},
                        '/data/pages/cows/sections/udder/love/cakes matches');
    is_deeply($obj->run("/data/workspaces/cows"), {ws => 'cows'},
              '/data/workspaces/cows matches');
}
