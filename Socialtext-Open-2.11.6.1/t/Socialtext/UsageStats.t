#!/usr/bin/env perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;
use Test::More tests => 19; 
use Socialtext::UsageStats;

# test pulling workspace out of a url path
{
    my %workspace_urls = (
        '/dev-tasks/index.cgi?help_me'            => 'dev-tasks',
        '/public/index.cgi?action=destroy'        => 'public',
        '/public/index.cgi?the_hippies'           => 'public',
        '/arti/index.cgi'                         => 'arti',
    );
    my @other_urls = qw(
        /feed/workspace/dev-tasks
        /nlw/login.html
        /johnson/and/johnson/baby/shampoo
    );

    for my $url ( keys %workspace_urls ) {
        my $found_workspace
            = Socialtext::UsageStats::get_workspace_from_url($url);
        is( $found_workspace, $workspace_urls{$url},
            "$url should find $found_workspace" );
    }

    for my $url (@other_urls) {
        my $found_workspace
            = Socialtext::UsageStats::get_workspace_from_url($url);
        is($found_workspace, undef, "$url should have no workspace" );
    }

}

# test edit requests
{
    my @data = (
        [ 'POST', '/dev-tasks/index.cgi',         302, 1   ],
        [ 'POST', '/dev-tasks/index.cgi',         200, q{} ],
        [ 'POST', '/dev-tasks/index.cgi?help_me', 302, q{} ],
        [ 'GET',  '/dev-tasks/index.cgi',         302, q{} ],
    );

    for my $request (@data) {
        my $is_edit = Socialtext::UsageStats::is_edit_action(
            $request->[0],
            $request->[1],
            $request->[2],
        );
        is( $is_edit && 1, $request->[3] && 1, 'edit action evaluated' );
    }
}

# test get_user_last_login
# XXX need test environment for public method, so do private method
{
    my $file_name = "/tmp/functions.t.$$";
    system( 'touch', $file_name ) == 0
        or die "unable to touch a file in tmp";
    my $mtime = ( stat($file_name) )[9];

    my $calculated_mtime
        = Socialtext::UsageStats::_get_file_mtime($file_name);

    is( $mtime, $calculated_mtime, "$file_name should have correct mtime" );
    unlink($file_name);
}

# test parse_apache_log_line
{
    my $log_line =<<'...';
127.0.0.1 - devnull1@socialtext.com [12/Oct/2005:13:18:02 -0700] "GET /admin/index.cgi?workspace_navigation HTTP/1.1" 200 23287 "http://www.example.com/" "Mozilla/5.0 (Macintosh; U; PPC Mac OS X Mach-O; en-US; rv:1.7.10) Gecko/20050716 Firefox/1.0.6" 12918 3
...

    my $log = Socialtext::UsageStats::parse_apache_log_line($log_line);

    # host, user, timestamp, method, url, status, referer
    is( $log->{host}, '127.0.0.1', 'correct host' );
    is( $log->{user}, 'devnull1@socialtext.com', 'correct user' );
    is( $log->{timestamp}, '12/Oct/2005:13:18:02', 'correct timestamp' );
    is( $log->{method}, 'GET', 'correct method' );
    is( $log->{url}, '/admin/index.cgi?workspace_navigation', 'correct url' );
    is( $log->{status}, '200', 'correct status' );
    is( $log->{referer}, 'http://www.example.com/', 'correct referer' );

}
