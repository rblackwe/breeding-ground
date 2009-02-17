#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::SyndicatePlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const );
use Socialtext::AppConfig;
use Socialtext::Exceptions qw( no_such_page_error );
use Socialtext::Search::AbstractFactory;
use Socialtext::Syndicate::Feed;
use Socialtext::Watchlist;
use Socialtext::User;

=head1 NAME

Socialtext::SyndicatePlugin - A plugin for managing syndicated feeds of sets of pages

=head1 SYNOPSIS

    my $feed = $hub->syndicate->syndicate;

=head1 DESCRIPTION

Socialtext::SyndicatePlugin uses L<Socialtext::Syndicate::Feed> to create
RSS20 and Atom format feeds of one or more L<Socialtext::Page> objects.

Feeds may be created based on a variety of CGI parameter inputs. See
L</METHODS>.

Socialtext::SyndicatePlugin is primarly used by L<Socialtext::Handler::Syndicate>
and uses L<Socialtext::Syndicate::Feed> for most of the hard work.
Socialtext::SyndicatePlugin acts as a bridge between the two: inspecting
CGI parameters and choosing the proper set of pages based on those
parameters.

=cut

sub class_id { 'syndicate' }
const class_title => 'Syndicate';
const cgi_class => 'Socialtext::Syndicate::CGI';
const default_category => 'Recent Changes';
const default_type => 'RSS20';
const feed_redirect_path => '/feed/workspace/';

=head1 METHODS

=head2 register($registry)

(This method is called automatically by the plugin management system.)

Establish the existence of the 'syndication depth' preference and
'rss20' action, described elsewhere.

=cut
sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add(preference => $self->syndication_depth);
    $registry->add(action => 'rss20');
}

=head2 syndicate()

Entry point to create syndication feed (RSS 2.0 or Atom) of one
or more L<Socialtext::Page> objects. The CGI parameter 'type' chooses
RSS20 or Atom, RSS20 by default.

Feeds are returned as an object of the appropriate
C<Socialtext::Syndicate::Feed>. The pages shown are based on provided
CGI parameters.

If 'search_term' is defined in the CGI paramters, a search is
performed and the pages in the results are returned in the feed.

If 'page' is defined and it is the name of an existing L<Socialtext::Page>
a feed containing the contents of that one page is returned.

If 'category' is defined a feed for all pages in that category
is returned.

Finally, if none of search_term, page or category are defined,
a feed for the default category, 'recent changes', is returned.

=cut
sub syndicate {
    my $self = shift;
    my $type = $self->cgi->type || $self->default_type;

    if ( my $search = $self->cgi->search_term ) {
        return $self->_syndicate_search( $type, $search );
    }
    elsif ( my $page_name = $self->cgi->page ) {
        return $self->_syndicate_page_named( $type, $page_name );
    }
    elsif ( $self->cgi->watchlist ) {
        return $self->_syndicate_watchlist( $type, $self->cgi->watchlist );
    }
    else {
        my $category = $self->cgi->category || $self->default_category;
        my $count = $self->cgi->count || $self->preference('syndication_depth');
        return $self->_syndicate_category( $type, $category, $count );
    }
}

=head2 rss20()

Provided as a backwards compatibility action for legacy URLs
for providing RSS feeds. If the system receives 'action=rss20'
in the CGI parameters, this method is called, causing a redirect
to contemporary URIs.

=cut
sub rss20 {
    my $self = shift;
    my $query_string = '';
    my $auth         = '';

    $query_string = '?category=' . $self->uri_escape( $self->cgi->category )
        if $self->cgi->category;

    $auth = '/noauth' if $self->hub->current_workspace->is_public;

    $self->redirect( $auth
            . $self->feed_redirect_path
            . $self->hub->current_workspace->name
            . $query_string );
}

=head2 syndication_depth()

An L<Socialtext::Preference> controlling the maximum number of pages to
show in a syndication feed for the current user. If the preference
is unset for the user, the default, 10, is used.

=cut
sub syndication_depth {
    my $self = shift;
    my $p = $self->new_preference('syndication_depth');
    $p->query('How many posts should be displayed in outgoing feeds?');
    $p->type('pulldown');
    my $choices = [
        5   => '5',
        10  => '10',
        15  => '15',
        20  => '20',
        25  => '25',
        50  => '50',
        100 => '100',
    ];
    $p->choices($choices);
    $p->default(10);
    return $p;
}

sub _syndicate_search {
    my $self = shift;
    my $type  = shift;
    my $query = shift;

    return $self->_syndicate(
        title => $self->_search_feed_title($query),
        link  => $self->_search_html_link($query),
        pages => $self->_search_get_items($query),
        type  => $type,
    );
}

sub _syndicate_watchlist {
    my $self = shift;
    my $type  = shift;
    my $watchlist  = shift;
    my $user;
    if ($watchlist =~ /default/) {
        $user = $self->hub->current_user;
    } else {
        $user = Socialtext::User->new (username => $watchlist);
    }

    return $self->_syndicate(
        title => $self->_watchlist_feed_title($user),
        link  => $self->_watchlist_html_link($user),
        pages => $self->_watchlist_get_items($user),
        type  => $type,
    );
}

sub _syndicate_page_named {
    my $self = shift;
    my $type = shift;
    my $name = shift;

    my $page = $self->hub->pages->new_from_name($name);

    no_such_page_error name => $name, error => "$name does not exist"
        unless $page->active;

    return $self->_syndicate(
        title => $self->_page_feed_title($page),
        link  => $page->full_uri,
        pages => [$page],
        type  => $type,
    );
}

sub _syndicate_category {
    my $self = shift;
    my $type = shift;
    my $category = shift;
    my $count = shift;

    return $self->_syndicate(
        title => $self->_category_feed_title($category),
        link  => $self->_category_html_link($category),
        pages => $self->_category_get_items($category, $count),
        type  => $type,
    );
}

sub _syndicate {
    my $self = shift;
    # XXX validate me
    my %p = @_;

    my $type = $self->_canonicalize_type( $p{type} );

    my $feed = Socialtext::Syndicate::Feed->New(
        title     => $p{title},
        html_link => $p{link},
        type      => $p{type},
        pages     => $p{pages},
        feed_id   => $self->hub->current_workspace->uri,
        contact   => Socialtext::AppConfig->support_address,
        generator => "Socialtext Workspace v"
            . $self->hub->main->product_version,
        feed_link => $self->hub->cgi->full_uri_with_query,

        # post_link
    );

    return $feed;
}

sub _canonicalize_type {
    my $self = shift;
    my $type = shift;

    $type =~ s/rss20/RSS20/i;
    $type =~ s/atom/Atom/i;

    return $type;
}

sub _category_get_items {
    my $self = shift;
    my $category = shift;
    my $count = shift;

    my @pages = $self->hub->category->get_pages_for_category(
        $category,
        $count,
    );

    return \@pages;
}

sub _watchlist_get_items {
    my $self = shift;
    my $user = shift;
    my $watchlist = Socialtext::Watchlist->new(
        user      => $user,
        workspace => $self->hub->current_workspace
    );
    my @pages = map { $self->hub->pages->new_from_name( $_ ) } $watchlist->pages;
    return \@pages;
}

sub _search_get_items {
    my $self = shift;
    my $query = shift;
    my $searcher = Socialtext::Search::AbstractFactory->GetFactory->create_searcher(
        $self->hub->current_workspace->name
    );

    my @pages = map { $self->hub->pages->new_from_name( $_->page_uri ) }
        grep { $_->isa('Socialtext::Search::PageHit') }
        $searcher->search($query);

    return \@pages;
}

sub _category_feed_title {
    my $self = shift;
    my $category = shift;

    return $self->hub->current_workspace->title . ': ' . $category;
}

sub _search_feed_title {
    my $self = shift;
    my $query = shift;

    return $self->hub->current_workspace->title . ": search for $query";
}

sub _watchlist_feed_title {
    my $self = shift;
    my $user = shift;

    return $self->hub->current_workspace->title . ": watchlist for " . $user->best_full_name;
}

sub _page_feed_title {
    my $self = shift;
    my $page = shift;

    return $self->hub->current_workspace->title . ': '
        . $page->metadata->Subject;
}

sub _category_html_link {
    my $self = shift;
    my $category = shift;

    return $self->hub->current_workspace->uri .
           Socialtext::AppConfig->script_name .
           '?action=weblog_display;category=' .
           $self->uri_escape($category);
}

sub _watchlist_html_link {
    my $self = shift;
    my $page = shift;

    return $self->hub->current_workspace->uri
        . Socialtext::AppConfig->script_name
        . '?$page';
}

sub _search_html_link {
    my $self = shift;
    my $query = shift;

    return $self->hub->current_workspace->uri .
           Socialtext::AppConfig->script_name .
           '?action=search;search_term=' .
           $self->uri_escape($query);
}

sub feed_uri_root {
    my $self = shift;
    my $workspace = shift;

    my $uri = $workspace->is_public ? '/noauth/feed/workspace/' : '/feed/workspace/';
    return $uri . $workspace->name;
}

package Socialtext::Syndicate::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'category';
cgi 'search_term';
cgi 'type';
cgi 'page';
cgi 'watchlist';
cgi 'count';

1;

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

