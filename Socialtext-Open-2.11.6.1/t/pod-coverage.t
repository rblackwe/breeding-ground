#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
use warnings;
use strict;
use Test::More;

BEGIN {
    unless ( eval { require Test::Pod::Coverage; 1 } ) {
        plan skip_all => 'These tests require Test::Pod::Coverage to run.';
    }
}

my %Modules = (
    'Socialtext::Account' => { trustme => [ qr/DefaultOrderByColumn/ ] },
    'Socialtext::AlzaboWrapper' => {},
    'Socialtext::Data' => {},
    'Socialtext::Permission' => {},
    'Socialtext::Role' => {},
    'Socialtext::Schema' => {},
    'Socialtext::User' => {},
    'Socialtext::User::Default' => { trustme => [ qr/DefaultOrderByColumn/ ] },
    'Socialtext::UserId' => {},
    'Socialtext::UserMetadata' => {},
    'Socialtext::UserWorkspaceRole' => {},
    'Socialtext::Workspace' => { trustme => [ qr/DefaultOrderByColumn/ ] },

    'Socialtext::ArchiveExtractor' => {},
    'Socialtext::Authz' => {},
    'Socialtext::Authz::SimpleChecker' => {},
    'Socialtext::EmailAlias' => {},
    'Socialtext::EmailReceiver' => {},
    'Socialtext::EmailSender' => {},
    'Socialtext::Hostname' => {},
    'Socialtext::MultiCursor' => {},
    'Socialtext::Session' => {},
    'Socialtext::TT2::Renderer' => {},
    'Socialtext::UI' => {},
    'Socialtext::URI' => { trustme => [ qr/^uri(?:_object)?$/ ] },

    'Socialtext::AppConfig' => {},
    'Socialtext::Ceqlotron' => {},
    'Socialtext::ChangeEvent' => {},
    'Socialtext::ChangeEvent::Page' => {},
    'Socialtext::ChangeEvent::Attachment' => {},
    'Socialtext::ChangeEvent::Workspace' => {},
    'Socialtext::Lite' => {},

    'Socialtext::Search::AbstractFactory' => {},
    'Socialtext::Search::Indexer' => {},
    'Socialtext::Search::Searcher' => {},
    'Socialtext::Search::Hit' => {},
    'Socialtext::Search::AttachmentHit' => {},
    'Socialtext::Search::PageHit' => {},
    'Socialtext::Search::SimplePageHit' => { trustme => [ qr/^page_uri$/ ] },
    'Socialtext::Search::SimpleAttachmentHit' => {
        trustme => [ qr/^page_uri|attachment_id$/ ]
    },
);

plan tests => scalar keys %Modules;

Test::Pod::Coverage::pod_coverage_ok( $_, $Modules{$_} ) for sort keys %Modules;

