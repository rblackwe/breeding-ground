#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::RevisionPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const );
use Socialtext::String;

sub class_id { 'revision' }
const cgi_class => 'Socialtext::Revision::CGI';

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add( action => 'revision_list' );
    $registry->add( action => 'revision_view' );
    $registry->add( action => 'revision_compare' );
    $registry->add( action => 'revision_restore' );
}

# XXX this method may not have test coverage
sub revision_list {
    my $self = shift;
    my $rows                  = [];
    my $page                  = $self->hub->pages->current;

    for my $revision_id ( sort { $b cmp $a } $page->all_revision_ids ) {
        my $revision = $self->hub->pages->new_page( $page->id );
        $revision->revision_id($revision_id);
        my $row = {};
        $row->{id}     = $revision_id;
        $row->{number} = $revision->metadata->Revision;
        $row->{date}   = $revision->datetime_for_user;
        $row->{from}   =
            $revision->last_edited_by->best_full_name( workspace => $self->hub->current_workspace );
        $row->{class} = @$rows % 2 ? 'trbg-odd' : 'trbg-even';

        $rows->[-1]{next} = $row
          if @$rows;
        push @$rows, $row;
    }

    $self->screen_template('view/page_revision_list');
    $self->render_screen(
        revision_count => scalar $page->all_revision_ids,
        $page->all,
        page           => $page,
        display_title  => $self->html_escape( $page->title ),
        rows           => $rows,
    );
}

sub revision_view {
    my $self = shift;
    my $page = $self->hub->pages->current;
    unless ( -f $page->revision_file( $self->cgi->revision_id ) ) {
        return $self->redirect( $page->uri );
    }
    $page->revision_id( $self->cgi->revision_id );
    $page->load();

    my $output = $self->cgi->mode eq 'source'
      ? do { local $_ = $self->html_escape( $page->content ); s/$/<br \/>/gm; $_ }
      : $page->to_html;

    my $revision = $page->metadata->Revision;

    $self->screen_template('view/page/revision');
    $self->render_screen(
        $page->all,
        human_readable_revision => $revision,
        display_title    => $self->html_escape( $page->title ),
        display_title_decorator  => "Revision $revision",
        print                   => $output,
    );
}

sub revision_compare {
    my $self = shift;
    my $page     = $self->hub->pages->current;
    my $page_id  = $page->id;
    my $before_page = $self->hub->pages->new_page($page_id);
    $before_page->revision_id( $self->cgi->old_revision_id );
    $before_page->load();
    my $new_page = $self->hub->pages->new_page($page_id);
    $new_page->revision_id( $self->cgi->new_revision_id );
    $new_page->load();

    my $class = (defined $self->cgi->mode and $self->cgi->mode ne 'source')
        ? 'Socialtext::RenderedSideBySideDiff'
        : 'Socialtext::WikitextSideBySideDiff';

    my $differ = $class->new(
        before_page => $before_page,
        after_page => $new_page,
        hub => $self->hub,
    );

    my $old_revision = $before_page->metadata->Revision;
    my $new_revision = $new_page->metadata->Revision;

    $self->screen_template('view/page/revision_compare');
    $self->render_screen(
        $page->all,
        print => $differ->framed_comparison,
        display_title    => $self->html_escape( $page->title ),
        display_title_decorator  => "Compare Revisions $old_revision and $new_revision",
    );
}

# XXX have an error here if the request method is not POST
sub revision_restore {
    my $self = shift;
    my $page = $self->hub->pages->current;
    if ( $self->hub->checker->check_permission('edit') ) {
        $page->restore_revision(
            revision_id => $self->cgi->revision_id,
            user => $self->hub->current_user
        );
    }
    $self->redirect($page->uri);
}

package Socialtext::SideBySideDiff;

use base 'Socialtext::Base';

use Class::Field qw( field );
use Socialtext::Helpers;

field 'before_page';
field 'after_page';
field 'hub';

sub framed_comparison {
    my $self = shift;
    return join '',
        $self->header,
        $self->from_wikitext_to_html,
        $self->footer;
}

sub header {
    my $self = shift;
    my @headings = map {
        my $pretty_revision = $_->metadata->Revision;
        my $link            = Socialtext::Helpers->script_link(
            "<strong>Revision $pretty_revision</strong></a>",
            action      => 'revision_view',
            page_id     => $_->id,
            revision_id => $_->revision_id,
        );
        my $tags = join ', ', grep $_ ne 'Recent Changes', $_->html_escaped_categories;
        my $editor = $_->last_edited_by->best_full_name(
            workspace => $self->hub->current_workspace );
        qq{
      <td width="50%" bgcolor="#ffffff">
        <h3 class="st-revision-view-link">$link</h3>
        <div class="st-revision-tags">Tags: $tags</div>
        <div class="st-revision-attribution">by $editor</div>
      </td>\n};
    } ( $self->before_page, $self->after_page );

    return qq{
<table id="st-revision-compare-table" cellpadding="2" cellspacing="2">
 <tr>
 @headings
 </tr>
};
}

sub footer {
    my $self = shift;
    return '</table>';
}

# XXX this doesn't actually do any comparison. =(
package Socialtext::RenderedSideBySideDiff;

use base 'Socialtext::SideBySideDiff';

sub from_wikitext_to_html {
    my $self = shift;
    return
        '<tr>'
        . '<td valign="top">' . $self->before_page->to_html . '</td>'
        . '<td valign="top">' . $self->after_page->to_html .  '</td>'
        . '</tr>';
}

package Socialtext::WikitextSideBySideDiff;

use base 'Socialtext::SideBySideDiff';
use Algorithm::Diff;

sub from_wikitext_to_html {
    my $self = shift;
    return $self->compare(
        $self->before_page->content,
        $self->after_page->content
    );
}

sub compare {
    my $self = shift;
    my $before = shift;
    my $after = shift;

    my $html = '';
    my @chunks = $self->split_into_diffable_divs($before, $after);

    for my $ii (0 .. $#chunks) {
        $html .= "<tr>\n";
        for my $desired_output (qw(before after)) {
            my $contents = $self->compare_chunk(
                $chunks[$ii][0], $chunks[$ii][1], $desired_output
            );
            $html .= "  <td>\n$contents\n  </td>\n";
        }
        $html .= "</tr>\n";
    }
    return $html
}

sub split_into_diffable_divs {
    my $self = shift;
    my @sdiffs = Algorithm::Diff::sdiff(
        [ $self->split_into_escaped_lines(shift) ],
        [ $self->split_into_escaped_lines(shift) ],
    );
    my @divs;
    my @accumulation = ('','');
    for (0..$#sdiffs) {
        my $row = $sdiffs[$_];
        my $flag = $row->[0];
        my ($left, $right) = @{$row}[1,2];
        $accumulation[0] .= $left;
        $accumulation[1] .= $right;
        if ('u' eq $flag or $_ == $#sdiffs) {
            push @divs, [ @accumulation ];
            @accumulation = ('','');
        }
    }
    return @divs
}

sub split_into_escaped_lines {
    my $self = shift;
    return split /$/m, Socialtext::String::html_escape($_[0]);
}

sub compare_chunk {
    my $self = shift;
    my $before = shift;
    my $after = shift;
    my $desired_output = shift;

    my @before = $self->split_into_words($before);
    my @after = $self->split_into_words($after);

    my @cdiffs = Algorithm::Diff::compact_diff(\@before, \@after);
    my $html   = '';

    # some roughness to deal with the terse structure returned by compact_diff:
    for ( my $ii = 0; $ii + 3 <= $#cdiffs; $ii += 2 ) {
        if ($ii % 4) {
            if ('before' eq $desired_output) {
                my @slice = $cdiffs[$ii] .. $cdiffs[ $ii + 2 ] - 1;
                $html .= enspan_old( @before[ @slice ] );
            }
            elsif ('after' eq $desired_output) {
                my @slice = $cdiffs[ $ii + 1 ] .. $cdiffs[ $ii + 3 ] - 1;
                $html .= enspan_new( @after[ @slice ] );
            }
            else {
                warn "Uhh.... something's super wrong.";
            }
        }
        else {
            $html .= join '', @before[ $cdiffs[$ii] .. $cdiffs[ $ii + 2 ] - 1 ];
        }
    }

    # XXX need to refactor this (and add a unit test - not necessarily in that
    # order)
    if ($html =~ /^\s+$/m) {
        $html =~ s/\n/<br\/>\n/gsm;
    } else {
        $html =~ s/(.)\n/$1<br\/>\n/gsm;
    }
    return Socialtext::String::double_space_harden($html);
}

sub split_into_words { split /\b/, $_[1] }

sub enspan_old {
    return @_
      ? join '', "<span class='st-revision-compare-old'>", @_, "</span>"
      : '';
}

sub enspan_new {
    return @_
      ? join '', "<span class='st-revision-compare-new'>", @_, "</span>"
      : '';
}


package Socialtext::Revision::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'mode';
cgi new_revision_id => '-clean_path';
cgi old_revision_id => '-clean_path';
cgi revision_id     => '-clean_path';

1;

