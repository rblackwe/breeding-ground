#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext tests => 66;
fixtures( 'admin_with_extra_pages' );

BEGIN {
    use_ok( 'Socialtext::Syndicate::Atom' );
    use_ok( 'XML::Atom' );
    use_ok( 'Socialtext::Page' );
}

my $hub = new_hub('admin');

ATOM_1_0_XHTML: {
    my $page = _make_page( 'xhtml', "Pure xhtml\n" );
    my $feed = _get_feed([$page]);
    is(
        _content_type($feed), 'xhtml',
        'xhtml content gets xhtml type'
    );
}

ATOM_1_0_HTML: {
    my $page = _use_page('formattingtodo');
    my $feed = _get_feed([$page]);
    is(
        _content_type($feed), 'html',
        'formattingtodo becomes escaped html'
    );
}


# these next two blocks test that content which should
# be impossible in our system result in content that
# is unusable in aggregators.
# XXX: We need to decide if that's what we want.
ATOM_1_0_CRAP: {
    my $page = _make_page(
        'html',
        "* hello\n** \xdamn\n* goodbye\n\n.html\n<h1>Hello\n.html\n\n"
    );
   my $feed = _get_feed([$page]);
    is(
        _content_type($feed), 'base64',
        'bad content becomes unusable base64'
    );
}

ATOM_1_0_KNOWN_BAD: {
    my $page = _use_page('internationalization');
    my $feed = _get_feed([$page]);
    is(
        _content_type($feed), 'base64',
        'internationalization comes out as unusable base64'
    );
}

ATOM_1_0_UTF8: {
    my $page = _use_page('babel');
    my $feed = _get_feed([$page]);
    is(
        _content_type($feed), 'xhtml',
        'babel makes good xhtml utf8'
    );
}

ATOM_1_0_FULL: {
    my $feed = _get_feed(
        [
            grep { ($_->id !~ /^in%C5/) && ($_->id ne 'html') }
                Socialtext::Pages->new( hub => $hub )->all()
        ]
    );
    _check_all_entries_for_type($feed);
}

# to create our own
sub _make_page {
    my $name = shift;
    my $content = shift;

    my $page = Socialtext::Page->new(hub=>$hub)->create(
        title => $name,
        content => $content,
        creator => $hub->current_user,
    );

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    isa_ok( $page, 'Socialtext::Page', "Created our own page called $name" );

    return $page;
}

# for babel
sub _use_page {
    my $id = shift;

    my $page = Socialtext::Page->new(
        hub => $hub,
        id  => $id,
    );

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    isa_ok( $page, 'Socialtext::Page', "Created our own page with ID $id" );

    return $page;
}

# to generate a feed
sub _get_feed {
    my $pages = shift;

    my $feed = Socialtext::Syndicate::Feed->New(
        title     => 'a test title',
        html_link => 'http://example.com',
        type      => 'Atom',
        pages     => $pages,
        feed_id   => $hub->current_workspace->uri,
        contact   => 'test@example.com',
        generator => 'Socialtext Workspace v' . $hub->main->product_version,
        feed_link => 'http://example.com/link',
    );

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    isa_ok( $feed, 'Socialtext::Syndicate::Feed', "Created our own feed" );

    my $foo = $feed->as_xml;
    return $foo;
}

# to get the type attribute on the content element
sub _content_type {
    my $xml = shift;

    my $feed = eval { XML::Atom::Feed->new(\$xml); };
    if ($@) {
        die "getting feed: $@\n";
    }
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    isa_ok( $feed, 'XML::Atom::Feed', 'Created a new XML::Atom::Feed' );

    my @entries = $feed->entries();
    is( scalar @entries, 1, 'Should be only one entry in the feed...' );

    # should only be one
    my $entry = shift @entries;
    isa_ok( $entry, 'XML::Atom::Entry', '... and it is the right type' );

    return _one_entry_type($entry);
}

sub _check_all_entries_for_type {
    my $xml = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $feed = eval { XML::Atom::Feed->new(\$xml); };
    if ($@) {
        die "getting feed: $@\n";
    }
    my @entries = $feed->entries();

    foreach my $entry (@entries) {
        if ($entry->title eq 'Internationalization') {
            is( _one_entry_type($entry), 'base64',
                '"Internationalization" comes though, as base64');
        }
        else {
            isnt( _one_entry_type($entry), 'base64',
                'full feed entry no base64 ' . $entry->title() );
        }
    }

    return;
}

sub _one_entry_type {
    my $entry = shift;

    my $content = $entry->content();
    my $content_type = $content->type();
    $content_type ||= 'base64';

    return $content_type;
}
