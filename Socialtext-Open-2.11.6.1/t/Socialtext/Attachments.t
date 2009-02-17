#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use warnings;
use strict;

use Test::Socialtext tests => 15;
fixtures( 'admin_no_pages' );
use Socialtext::Attachments;
use Socialtext::User;

sub new_attachment {
    bless {}, 'Socialtext::Attachment'; # "new" does stuff this test doesn't need (now)
}

sub booleanize { $_[0] ? 1 : '' } # could be a filter

my $hub = new_hub('admin');
my $creator = Socialtext::User->new( username => 'devnull1@socialtext.com' );

run {
    my $case = shift;
    my $a = new_attachment;
    $a->filename('t/attachments/' . $case->in);
    is
        $a->mime_type,
        $case->mime_type,
        $case->in . " = " . $case->mime_type;
    is
        booleanize($a->should_popup),
        booleanize($case->should_popup),
        $case->in.' should '.($case->should_popup ? '' : 'not ').'pop-up';
    open my $fh, '<', $a->filename or die $a->filename . ": $!";
    $hub->attachments->create(
        filename => $case->in,
        fh => $fh,
        creator => $creator,
    );
    my $name = Socialtext::Encode::ensure_is_utf8($case->in);
    my $actually_attached =
      grep { $name eq $_->Subject } @{$hub->attachments->all};
    ok($actually_attached, $case->in . ' should actually attach');
};

# TODO (Maybe): Detect if content looks like application/binary or text/plain.

__DATA__
===
--- in: foo.txt
--- mime_type: text/plain
--- should_popup: 0

===
--- in: foo.htm
--- mime_type: text/html
--- should_popup: 0

===
--- in: foo.html
--- mime_type: text/html
--- should_popup: 0

===
--- in: foo
--- mime_type: application/binary
--- should_popup: 1

===
--- in: Internationalization.txt
--- mime_type: text/plain
--- should_popup: 0
