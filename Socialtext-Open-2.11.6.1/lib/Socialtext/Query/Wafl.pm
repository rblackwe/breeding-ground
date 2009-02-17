#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::Query::Wafl;
use strict;
use warnings;

use Socialtext::Formatter::WaflPhrase;
use base 'Socialtext::Formatter::WaflPhraseDiv';

use Class::Field qw( field );
use Socialtext::Permission 'ST_READ_PERM';

field target_workspace =>
    -init => '$self->current_workspace_name';
field wafl_query_title => 'no title defined';
field wafl_query_link  => '';

# XXX Should figure some way to get workspace argument in here
sub html {
    my $self = shift;
    my $arguments = $self->arguments;
    my $workspace_name;
    ($workspace_name, $arguments) = $self->_parse_arguments($arguments);
    my $results = $self->_get_results($workspace_name, $arguments);
    $self->_set_titles($arguments);
    $self->_present_results($results);
}

sub _parse_arguments {
    my $self = shift;
    my $arguments = shift;

    my ( $workspace_name, $other_args )
        = ( $arguments =~ /\s*(?:<([\w-]+)>)?\s*(.*)$/ );
    $workspace_name = $self->current_workspace_name unless $workspace_name;
    return ( $workspace_name, $other_args );
}

sub _set_titles { }

sub _get_results {
    my $self = shift;
    my $workspace_name = shift;
    my $arguments = shift;

    $self->target_workspace($workspace_name);

    my $results;

    my $ws = Socialtext::Workspace->new( name => $workspace_name );
    return +{error => 'no access to workspace'}
        unless $ws && $self->authz->user_has_permission_for_workspace(
            user       => $self->current_user,
            permission => ST_READ_PERM,
            workspace  => $ws,
        );

    eval {
        local $SIG{__DIE__};    # don't want stacktrace
        $results
            = $self->_get_wafl_data( $self->hub, $arguments, $workspace_name );
    };
    undef($@); # just to be careful of bad evals

    return $results;
}

sub _present_results {
    my $self = shift;
    my $results = shift;
    my $link_html;
    if ($self->method =~ /[-_]full$/ and not $results->{error}) {
        $link_html = $self->_full_page_results($results);
    }
    else {
        $link_html = $self->_title_results($results);
    }

    return $self->template->process(
        'query_wafl.html',
        wafl_query_title => $self->wafl_query_title,
        wafl_query_link  => $self->wafl_query_link,
        error            => $results->{error},
        link_html        => $link_html,
        workspace_name   => $self->target_workspace,
    );
}

sub _full_page_results {
    my $self = shift;
    my $results = shift;
    $self->_format_results($results, "\n\n", 'include');
}

sub _title_results {
    my $self = shift;
    my $results = shift;
    $self->_format_results($results, "\n* ", 'link');
}

sub _format_results {
    my $self = shift;
    my $results = shift;
    my $separator = shift;
    my $wafl = shift;
    my $rows = $results->{rows};

    my $workspace_name = '';
    $workspace_name = $self->target_workspace
        unless $self->target_workspace eq $self->current_workspace_name;

    my $wikitext = $separator . join($separator,
        map {
            "{$wafl $workspace_name [" . $_->{Subject} . ']}'
        } @$rows
    );
    return $self->hub->viewer->text_to_html($wikitext. "\n\n");
}

1;
