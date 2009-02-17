#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext;
fixtures( 'admin_no_pages' );

BEGIN {
    unless ( eval { require Email::Send::Test; 1 } ) {
        plan skip_all => 'These tests require Email::Send::Test to run.';
    }
}

plan tests => 4;


use Socialtext::EmailNotifier;
use Socialtext::EmailReceiver;

Socialtext::EmailSender->TestModeOn();

my $hub = new_hub('admin');

my $pages = $hub->pages;
my $notify = $hub->email_notify;
my $notifier = Socialtext::EmailNotifier->new(
    plugin           => $notify,
    notify_frequency => 'notify_frequency',
);

# used when setting mtime on varous files to force notify runs
my $ten_days_ago = time - (86400 * 10);
my $user = Socialtext::User->new( username => 'devnull1@socialtext.com' );

{
    Email::Send::Test->clear;

    Socialtext::File::update_mtime( $notifier->run_stamp_file, $ten_days_ago );
    Socialtext::File::update_mtime( $notifier->_stamp_file_for_user($user), $ten_days_ago );

    # send an email to make sure email-in causes notifications
    deliver_email('simple');

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'One email was sent' );
    is( $emails[0]->header('To'), 'devnull1@socialtext.com',
        'Email is addressed to proper recipient' );
    like( $emails[0]->header('Subject'),
          qr/\Qrecent changes in Admin Wiki workspace\E/i,
          'Subject is correct' );

    my @parts = $emails[0]->parts;
    like( $parts[0]->body, qr/this is a test message again/i,
          'Recent changes includes URI of page that was just created' );
}

# XXX - we should also test other things that should generate
# notifications, like a new page, edit page, duplicate page, send page
# to workspace, etc.

sub deliver_email {
    my $name = shift;

    my $file = "t/test-data/email/$name";
    die "No such email $name" unless -f $file;

    open my $fh, '<', $file or die $!;

    Socialtext::EmailReceiver->receive_handle(
        handle    => $fh,
        workspace => $hub->current_workspace(),
    );

    # XXX due to decoupling of postprocess email notify need to call
    # this by hand
    $notify->maybe_send_notifications;
}

