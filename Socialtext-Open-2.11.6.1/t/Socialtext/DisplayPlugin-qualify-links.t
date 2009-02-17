#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

# This test makes sure that Socialtext::DisplayPlugin::qualify_links 
# properly processes links from unqualified to fully qualified.

use strict;
use warnings;

use Test::Socialtext tests => 6;

BEGIN {
    use_ok( 'Socialtext::DisplayPlugin' );
}

run {
    my $case          = shift;
    my $original_html = $case->original;
    my $expected_html = $case->expected;

    is(
        Socialtext::DisplayPlugin->qualify_links(
            $original_html, 'HOST/foobar/'
        ),
        $expected_html,
        'Original html is qualified to expected html'
    );
};

__DATA__
=== basic qualifaction
--- original
<a href="index.cgi?formatting_todo"
--- expected
<a href="HOST/foobar/index.cgi?formatting_todo"

=== already-qualified
--- original
<a href="http://foo.com/index.cgi?formatting_todo"
--- expected
<a href="http://foo.com/index.cgi?formatting_todo"

=== utf-8
--- original
<a href="index.cgi?%D0%9F%D1%80%D0%BE%D0%B5%D0%BA%D1%82%D1%8B%20-%20%D0%9B%D0%A6"
--- expected
<a href="HOST/foobar/index.cgi?%D0%9F%D1%80%D0%BE%D0%B5%D0%BA%D1%82%D1%8B%20-%20%D0%9B%D0%A6"

=== weblog
--- original
<a href="/foobar/index.cgi?action=weblog_display"
--- expected
<a href="HOST/foobar/index.cgi?action=weblog_display"

=== attachment
--- original
<a href="/foobar/index.cgi/Robot.txt?action=attachments_download;page_name=formatting_test;id=20051117173632-112"
--- expected
<a href="HOST/foobar/index.cgi/Robot.txt?action=attachments_download;page_name=formatting_test;id=20051117173632-112"

