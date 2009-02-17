#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext tests => 9;
fixtures( 'admin', 'foobar' );
use Socialtext::Pages;

my $hub = new_hub('admin');
my $content_one;
my $content_two;
my $content_three;

my $page_one = Socialtext::Page->new( hub => $hub )->create(
    title   => "page one",
    content =>
        "Page One\n\n{include [page two]}\n\n{include foobar [not here]}",
    creator => $hub->current_user,
);


$content_one = $page_one->to_html_or_default;

like $content_one, qr{Page One.*href="/admin/index.cgi\?page%20two"}sm,
    'page one should contain a link to incipient page two';
like $content_one, qr{Replace this text with your own}sm,
    'page one should contain default text for page two';
like $content_one, qr{href="/foobar/index.cgi\?not%20here"}sm,
    'page one should contain a link to incipient not here page in foobar';

my $page_two = Socialtext::Page->new( hub => $hub )->create(
    title   => "page two",
    content =>
        "Page Two\n\n{include [page one]}\n\n{include foobar [People]}\n\n", creator => $hub->current_user, );

$content_one = $page_one->to_html_or_default;
$content_two = $page_two->to_html_or_default;

like $content_one, qr{Page One.*Page Two.*include: \[page one\]}sm,
    'page one should have page two but not recurse';

like $content_two, qr{Page Two.*Page One.*include: \[page two\]}sm,
    'page two should have page one but not recurse';

like $content_two, qr{foobar/index.cgi\?people},
    'page two should include welcome from foobar with links to people';


my $page_three = Socialtext::Page->new( hub => $hub )->create(
    title   => "page three",
    content =>
        "Page Three\n\n{include [page two]}\n\nincludes page two\n\n",
    creator => $hub->current_user,
);

$content_three = $page_three->to_html_or_default;

like $content_three,
    qr{Page Three.*Page Two.*Page One.*include: \[page two\]}sm,
    'page three gets page two gets page one but stop for page two';

unlike $content_three,
    qr{<div class="wiki">.*<div class="wiki">}ms,
    'included page does not have multiple div class="wiki"';

like $content_one,
    qr{<div class="wiki-include-page">.*<div class="wiki-include-title">.*<div class="wiki-include-content">}sm,
    'included page is wrapped in the properly classed divs';
