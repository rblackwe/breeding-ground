#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext tests => 19;
fixtures( 'ALL' );

# Confirm that we can create tables of contents of 
# the current page, of another page in the same workspace,
# of a page not in this workspace, but not of a page
# in which we aren't a member.

use Socialtext::Pages;

my $admin  = new_hub('admin');
my $foobar = new_hub('foobar');
my $public = new_hub('public');

my $page_one = Socialtext::Page->new( hub => $admin )->create(
    title   => 'target one',
    content => <<'EOF',
^ Structured Wikitext

Folding [is fun].

^^ Has Benefits

> Now is the time for all good wikitext to come to the aid of its user.

^^^ And Consequences

The bees are in the what?

* this is a list
* and so is this

^ In Summary

We conclude ipsum lorem is nonsense.

^^ Header with {link in summary}

stuff

^^ Header with [Free Link]

EOF
    creator => $admin->current_user,
);

for my $hub ( $admin, $foobar ) {
    Socialtext::Page->new( hub => $hub )->create(
        title   => 'NoHeaders',
        content => <<'EOF',
This page has no headers.

None, not a one.
EOF
        creator => $hub->current_user,
    );
}

# confirm content of first page
$admin->pages->current($page_one);
my $html_one = $page_one->to_html_or_default();
like $html_one, qr{<h1 id="structured_wikitext">Structured Wikitext</h1>},
    'page one should start with an h1';

my $page_two = Socialtext::Page->new( hub => $admin )->create(
    title   => 'source two',
    content => <<'EOF',

^ Witness the Fitness

{toc}

^ Recant the cant

{toc [target one]}

{toc [target infinity]}

{toc [noheaders]}

{toc foobar [noheaders]}
EOF
    creator => $admin->current_user,
);

$admin->pages->current($page_two);
my $html_two = $page_two->to_html_or_default();
like $html_two,
    qr{<p>Table of Contents: source two</p>},
    'page two has a title for the first table of contents';
like $html_two,
    qr{<p>Table of Contents: target one</p>},
    'page two has a title for the remote table of contents';
like $html_two,
    qr{<li><span.*<a.* href="#witness_the_fitness">Witness the Fitness</a>.*</li>},
    'page two has a section link to witness the fitness';
like $html_two,
    qr{<li><span.*<a.* href="/admin/index.cgi\?target_one#structured_wikitext">target one \(Structured Wikitext\)</a>.*</li>},
    'page two has a section link to structured wikitext on target one';
like $html_two,
    qr{<li><span.*<a.* href="/admin/index.cgi\?target_one#header_with_in_summary">target one \(Header with in summary\)</a>.*</li>},
    'page two has a section link to complex header on target one';
like $html_two,
    qr{<li><span.*<a.* href="/admin/index.cgi\?target_one#header_with_free_link">target one \(Header with Free Link\)</a>.*</li>},
    'page two has a section link to complex header on target one';
like $html_two,
    qr{class="wafl_syntax_error">\[target infinity\]},
    'page two does not link to non-existent target infinity';
like $html_two,
    qr{href="/admin/index.cgi\?noheaders">NoHeaders</a>.*does not have any headers.},
    'a page with no headers reports that information and links to page';
like $html_two,
    qr{href="/foobar/index.cgi\?noheaders">NoHeaders</a>.*does not have any headers.},
    'a page with no headers in a different workspace links to page only';
unlike $html_two, qr{this is a list},
    'html two does not include list content from one';
unlike $html_two, qr{The bees are in the what},
    'html two does not paragraph ontent from one';

# Test under conditions similar to RSS and Atom
$admin->pages->current(undef);
$html_two = $page_two->to_absolute_html();
like $html_two,
    qr{<li><span.*<a.* href="#witness_the_fitness">Witness the Fitness</a>.*</li>},
    'page two has a section link to witness the fitness';
like $html_two,
    qr{<li><span.*<a.* href="http://.*/admin/index.cgi\?target_one#structured_wikitext">target one \(Structured Wikitext\)</a>.*</li>},
    'page two has a section link to structured wikitext on target one';
like $html_two,
    qr{class="wafl_syntax_error">\[target infinity\]},
    'page two does not link to non-existent target infinity';


my $page_foobar = Socialtext::Page->new( hub => $foobar )->create(
    title   => 'foobar',
    content => <<'EOF',

^ Crazy Man

{toc admin [target one]}

^ Extra wacky

{toc admin [source two]}

{toc admin [target infinity]}

EOF
    creator => $foobar->current_user,
);

$foobar->pages->current($page_foobar);
my $html_foobar = $page_foobar->to_html_or_default();
like $html_foobar,
    qr{<li><span.*<a.*href="/admin/index.cgi\?target_one#structured_wikitext">target one \(Structured Wikitext\)</a>.*</span></li>},
    'page foobar links to structured wikitext on target one';
like $html_foobar,
    qr{<li><span.*<a.*href="/admin/index.cgi\?source_two#witness_the_fitness">source two \(Witness the Fitness\)</a>.*</span></li>},
    'page foobar links to witness the fitness on source two';
like $html_foobar,
    qr{syntax_error.*admin \[target infinity\]},
    'page foobar does not link to non-existent target infinity';

my $page_public = Socialtext::Page->new( hub => $public )->create(
    title   => 'public',
    content => <<'EOF',

^ Denied!

{toc admin [target one]}

EOF
    creator => $public->current_user,
);

$public->pages->current($page_public);
$public->current_user( Socialtext::User->Guest() );
my $html_public = $page_public->to_html_or_default();
like $html_public,
    qr{permission_error.*admin \[target one\]},
    'guest user viewing page public does not have access to admin target one';
