#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use warnings;
use strict;

use Test::Socialtext tests => 5;
fixtures( 'admin' );

=head1 DESCRIPTION

Test that orphans are correctly discovered and correctly not
displayed when they are deleted.

=cut

my $hub = new_hub('admin');
my $backlinks = $hub->backlinks;
my $pages = $hub->pages;

my $page_one = Socialtext::Page->new( hub => $hub )->create(
    title   => 'backlink sampler',
    content =>
        "Hello\nthis is a [smartass5] page to [admin wiki]\nyou\n\nHello ",
    creator => $hub->current_user,
);

{
    my $orphan_pages = $backlinks->get_orphaned_pages;

    my @backlinks = $backlinks->_get_backlink_page_ids_for_page(
        $pages->new_from_name( 'backlink sampler' )
    );

    ok(scalar(@backlinks) == 0, 'no backlinks for backlink sampler');
    ok(scalar @$orphan_pages, 'there are some orphans');
    ok(grep(/^backlink_sampler$/, map {$_->id} @$orphan_pages),
        "The orphan pages contains backlink sampler");
}

{
    my @calling_pages = $backlinks->_get_backlink_page_ids_for_page(
        $pages->new_from_name( 'smartass5' )
    );
    
    ok(grep(/^backlink_sampler$/, @calling_pages),
        "The smartass5 page has a caller of backlink sampler");
}

{
    $page_one->delete( user => $hub->current_user );
    my $orphan_pages = $backlinks->get_orphaned_pages;
    ok(! grep(/^backlink_sampler$/, map {$_->id} @$orphan_pages),
        "The orphan pages does not contain backlink sampler");
}
