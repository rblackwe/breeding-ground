package Socialtext::HomepagePlugin;
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use base 'Socialtext::Plugin';

use Socialtext::TT2::Renderer;
use Socialtext::Watchlist;
use Socialtext::l10n qw/loc_lang/;

# XXX This code has no documentation

sub class_id    () { 'homepage' }
sub class_title () { 'Home Link' }

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add( action     => 'homepage' );
    $registry->add( action     => 'dashboard' );
}

sub homepage {
    my $self = shift;

    if ( $self->hub->current_workspace->homepage_is_dashboard ) {
        return $self->dashboard;
    }

    my $title = $self->hub->current_workspace->title;
    my $uri = $self->hub->pages->new_from_name($title)->uri;

    return $self->redirect($uri);
}


sub dashboard {
    my $self = shift;

    my $locale = $self->preferences->locale->value;
    loc_lang($locale);

    my $renderer = Socialtext::TT2::Renderer->instance;

    return $renderer->render(
        template => 'view/homepage',
        vars     => {
            $self->hub->helpers->global_template_vars,
            title          => 'Dashboard',
            group_notes    => $self->_get_group_notes_info,
            personal_notes => $self->_get_personal_notes_info,
            whats_new      => $self->_get_whats_new_info,
            watchlist      => $self->_get_watchlist_info,
            wikis          => $self->_get_wikis_info,
            hub            => $self->hub,
            feeds          => $self->_feeds( $self->hub->current_workspace ),
            unplug_uri     => "?action=unplug",
            unplug_phrase  => 'Click this button to save the '
                . $self->hub->tiddly->default_count
                . ' most recent pages to your computer for offline use.',
        },
    );
}

sub _get_group_notes_info {
    my ($self) = @_;
    my $page_title = 'Announcements and Links';
    return {
        html      => $self->hub->pages->new_from_name($page_title)->to_html_or_default,
        edit_path => $self->hub->helpers->page_edit_path($page_title),
        view_path => $self->hub->helpers->page_display_path($page_title),
    };
}

sub _get_personal_notes_info {
    my ($self) = @_;
    my $page_title = $self->hub->favorites->preferences->which_page->value;
    if ($page_title) {
        return {
            html      => $self->hub->pages->new_from_name($page_title)->to_html_or_default,
            edit_path => $self->hub->favorites->favorites_edit_path . ';caller_action=homepage',
            view_path => $self->hub->helpers->page_display_path($page_title),
        };
    }
    return {
        html      => '',
        edit_path => $self->hub->helpers->preference_path('favorites'),
    };
}

sub _get_whats_new_info {
    my ($self) = @_;
    return {
        pages => [
            map $self->_get_whats_new_page_info($_),
            $self->hub->category->get_pages_for_category(
                'recent changes',
                $self->hub->recent_changes->preferences->sidebox_changes_depth->value,
            )
        ],
    };
}

sub _get_whats_new_page_info {
    my $self = shift;
    my $page = shift;

    my $updated_author = $page->last_edited_by || $self->hub->current_user;
    # This should really be a user object or user-pref object method,
    # but this is what we've got.
    my $show_preview = $self->hub->pages->show_mouseover;

    return {
        link    => $self->hub->helpers->page_display_path($page->id),
        title   => $self->hub->helpers->html_escape($page->title),
        date    => $page->datetime_for_user,
        author  => (  $updated_author
                    ? $updated_author->best_full_name(workspace => $self->hub->current_workspace)
                    : undef),
        preview => (  $show_preview
                    ? $page->preview_text
                    : '' ),
    }
}


sub _get_watchlist_info {
    my ($self) = @_;

    my $watchlist = Socialtext::Watchlist->new(
        user        => $self->hub->current_user,
        workspace   => $self->hub->current_workspace,
    );

    my $show_preview = $self->hub->pages->show_mouseover;

    my @pages = ();
    # If the page has been purged take it out of the watchlist.
    # For the sake of performance, don't go through all
    # items in the watchlist, just collect first 5 active pages.
    # Because we only want 5 in the homepage dashboard.
    # Leave the rest of purging to display_watchlist action.
    # (Or further invocations to this function.)
    foreach ( $watchlist->pages() ) {
        my $page = $self->hub->pages->new_from_name($_);
        if ( !$page->active ) {
            $watchlist ||= Socialtext::Watchlist->new(
                user      => $self->hub->current_user,
                workspace => $self->hub->current_workspace
            );
            $watchlist->remove_page( page => $page );
            next;
        } 
        my $updated_author = $page->last_edited_by || $page->hub->current_user;
        push @pages, {
            title   => $self->hub->helpers->html_escape($page->metadata->Subject),
            link    => $self->hub->helpers->page_display_path($_),
            date    => $page->datetime_for_user,
            author  => (  $updated_author
                        ? $updated_author->best_full_name(workspace => $self->hub->current_workspace)
                        : undef),
            preview => (  $show_preview
                        ? $page->preview_text
                        : '' ),
        };
        last if @pages >= $self->hub->favorites->preferences->watchlist_dashboard_length->value;
     }
    return {
        pages => \@pages,
    };
}

sub _get_wikis_info {
    my $self = shift;
    return [
        map {{
            title   => $self->hub->helpers->html_escape($_->title),
            name    => $self->hub->helpers->uri_escape($_->name),
            changes => $self->_get_changes_count_for_wiki($_),
        }} 
        $self->hub->current_workspace->read_breadcrumbs(
            $self->hub->current_user 
        )
    ];
}

sub _get_changes_count_for_wiki {
    my ($self, $wiki) = @_;
    my $current = $self->hub->current_workspace;
    $self->hub->current_workspace($wiki);
    my $seconds = $self->hub->recent_changes->preferences->changes_depth->value * 1440 * 60;
    my $count   = @{$self->hub->category->get_pages_by_seconds_limit('recent changes', $seconds)};
    $self->hub->current_workspace($current);
    return $count;
}

1;

