#!perl -w
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext tests => 1;
fixtures( 'admin_no_pages', 'foobar' );

filters {
    wiki => 'format',
};

my $hub = new_hub('admin');
my $viewer = $hub->viewer;

run_is wiki => 'match';

sub format {
    $viewer->text_to_html(shift)
}

__DATA__
=== Empty paragraph must be a <br> due to crufty IE bug (17911)
--- wiki
{link: foobar [Quick Start]}

----
--- match
<div class="wiki">
<span class="nlw_phrase"><a title="inter-workspace link: foobar" href="/foobar/index.cgi?quick_start">Quick Start</a><!-- wiki: {link: foobar [Quick Start]} --></span><br /><br /><hr />
</div>
