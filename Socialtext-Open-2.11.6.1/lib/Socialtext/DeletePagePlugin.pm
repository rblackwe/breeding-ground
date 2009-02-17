#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::DeletePagePlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';
use URI::Escape;
use Encode;

use Class::Field qw( const );


sub class_id { 'delete_page' }
const cgi_class => 'Socialtext::DeletePage::CGI';

sub register {
    my $self = shift;
    $self->hub->registry->add(action => 'delete_page');
    $self->hub->registry->add(action => 'delete_epilogue');
    $self->hub->registry->add(action => 'undelete_page');
}

# XXX dependency on current is a smell, or at least we
# should allow some way to do arguments here
sub delete_page {
    my $self = shift;
    return $self->redirect( $self->hub->pages->current->uri )
        unless $self->hub->checker->check_permission('delete');

    $self->hub->pages->current->delete( user => $self->hub->current_user );
    $self->finish;
}

sub undelete_page {
    my $self = shift;
    my $page = $self->hub->pages->new_from_name(  
        Encode::decode("utf8", URI::Escape::uri_unescape($self->cgi->page_id )));

    return $self->redirect( $page->uri )
        unless $self->hub->checker->check_permission('edit');

    my @rev_ids = $page->all_revision_ids;
    if ( @rev_ids < 2 ) {
        my $msg = 'Cannot undelete a page with only one revision. '
            . 'Returning to front page.';
        return $self->hub->fail_home_with_warning( $msg );
    }
    $page->restore_revision(
        revision_id => $rev_ids[-2],
        user        => $self->hub->current_user,
    );
    $self->redirect( $page->uri );
}

sub finish {
    my $self = shift;
    my $id =  $self->hub->pages->current->uri;
    $self->redirect("action=delete_epilogue&page_id=$id");
}

sub delete_epilogue {
    my $self = shift;
    my $id = $self->cgi->page_id;
    my $page = $self->hub->pages->new_from_name($id);

    $self->screen_template('view/page/delete_epilogue');
    $self->render_screen(
        display_title => 'Deleted "' . $page->metadata->Subject . '"',
        page_id => $page->uri,
        backlinks_description =>
            $self->hub->backlinks->past_tense_description_for_page($page),
    );
}

package Socialtext::DeletePage::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'page_id';

1;

