#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use warnings;
use strict;

use Test::Socialtext;
fixtures( 'admin_no_pages' );

BEGIN {
    unless ( eval { require Email::Send::Test; 1 } ) {
        plan skip_all => 'These tests require Email::Send::Test to run.';
    }
}

plan tests => 7;


Socialtext::EmailSender->TestModeOn();

my $hub    = new_hub('admin');
my $bugs   = $hub->bugs;

{
    Email::Send::Test->clear;

    {
        local $SIG{__WARN__} = sub {};
        $bugs->save_report('test error');
    }

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'One email was sent' );
    is( $emails[0]->header('To'), Socialtext::AppConfig->email_errors_to,
        'Email is addressed to proper recipient' );
    is( $emails[0]->header('From'), 'noreply@socialtext.com',
        'Email is from proper sender' );
    like( $emails[0]->header('Subject'),
          qr/Application error in admin for devnull1\@socialtext.com on/,
          'Subject is correct' );
    like( $emails[0]->body,
          qr/_15_workspace:\s+admin/, 'workspace is correct' );
    like( $emails[0]->body,
          qr/_30_user_id:\s+devnull1\@socialtext.com/, 'workspace is correct' );
    like( $emails[0]->body,
          qr{_35_url:\s+http://localhost}, "a url is listed" );
}
