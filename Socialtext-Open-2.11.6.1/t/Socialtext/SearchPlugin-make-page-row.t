#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext tests => 5;
fixtures( 'admin' );
use Socialtext::SearchPlugin;
use Socialtext::Page;

my $hub = new_hub('admin');

my $Singapore = join '', map { chr($_) } 26032, 21152, 22369;

my $utf8_page = Socialtext::Page->new(hub=>$hub)->create(
    title => $Singapore,
    content => 'hello',
    creator => $hub->current_user,
);

my $page_uri = $utf8_page->uri;

ok( keys(%{make_page_row($page_uri)}),
    'passing an encoded utf8 page uri returns hash with keys' );
ok( !keys(%{make_page_row($Singapore)}),
    'passing utf8 string returns empty hash' );
ok( !keys(%{make_page_row('this page does not exist')}),
    'non existent page returns empty hash' );
ok( keys(%{make_page_row('start_here')}),
    'normal existing page returns hash with keys' );
# sigh, osx doesn't care about case in filenames as much as we might like...
ok( !keys(%{make_page_row('Start Here')}) || $^O =~ /darwin/,
    'existing page as name not uri returns empty or this is a mac' );

sub make_page_row {
    my $uri_candidate = shift;
    my $output = $hub->search->_make_page_row($uri_candidate);
    return $output;
}
