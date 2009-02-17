#!perl
# -*- coding: utf-8 -*- vim:fileencoding=utf-8:
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

binmode (STDOUT, ":utf8");
binmode (STDERR, ":utf8");
use Test::Socialtext tests => 2;
fixtures( 'admin' );
use Encode qw(decode);

my $hub = new_hub('admin');

# When we pass in Latin-1 the parser does the right thing.  Everything works
# okay without any magic.  This test confirms that.
FREELINK_SINGLE_LATIN1:{
    my $a_acute_u = chr(0x00E1); # this works right
    my $html = $hub->viewer->text_to_html("\n[x]\n[$a_acute_u]\n");
    is($html, qq{<div class="wiki">
<br /><p>
<a href="index.cgi?x" title="[click to create page]" class="incipient">x</a><br />
<a href="index.cgi?%C3%A1" title="[click to create page]" class="incipient">$a_acute_u</a></p>
</div>
}, 'Fix bug {rt 19458} using Latin-1 (this passing may not be Right)');
}

# When we pass in UTF-8 the parser does the WRONG thing. The titles are
# calculated wrong.  Seems substr() is not behaving right.
FREELINK_SINGLE_UTF8:{
    my $a_acute_u = chr(0x00E1); # this works right
    $a_acute_u = decode("iso-8859-1", $a_acute_u);
    my $html = $hub->viewer->text_to_html("\n[x]\n[$a_acute_u]\n");
    is($html, qq{<div class="wiki">
<br /><p>
<a href="index.cgi?x" title="[click to create page]" class="incipient">x</a><br />
<a href="index.cgi?%C3%A1" title="[click to create page]" class="incipient">$a_acute_u</a></p>
</div>
}, 'Fix bug {rt 19458} using utf-8');
}
