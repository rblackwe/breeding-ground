#!perl -w
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext tests => 3;
fixtures( 'admin_no_pages' );

filters {
    wiki => ['format'],
};

my $hub = new_hub('admin');
my $viewer = $hub->viewer;

run_is wiki => 'match';

sub format {
    $viewer->text_to_html(shift)
}

__DATA__
=== simple table, no spaces
--- wiki
||||
||||
||||
--- match
<div class="wiki">
<table style="border-collapse: collapse;" class="formatter_table">
<tr>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
</tr>
<tr>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
</tr>
<tr>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
</tr>
</table>
</div>

=== simple table, spaces
--- wiki
| | | |
| | | |
| | | |
--- match
<div class="wiki">
<table style="border-collapse: collapse;" class="formatter_table">
<tr>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
</tr>
<tr>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
</tr>
<tr>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
<td style="border: 1px solid black;padding: .2em;"></td>
</tr>
</table>
</div>

=== simple table, words
--- wiki
| foo | bar | baz |
| bar | baz | foo |
| baz | foo | bar |
--- match
<div class="wiki">
<table style="border-collapse: collapse;" class="formatter_table">
<tr>
<td style="border: 1px solid black;padding: .2em;">foo</td>
<td style="border: 1px solid black;padding: .2em;">bar</td>
<td style="border: 1px solid black;padding: .2em;">baz</td>
</tr>
<tr>
<td style="border: 1px solid black;padding: .2em;">bar</td>
<td style="border: 1px solid black;padding: .2em;">baz</td>
<td style="border: 1px solid black;padding: .2em;">foo</td>
</tr>
<tr>
<td style="border: 1px solid black;padding: .2em;">baz</td>
<td style="border: 1px solid black;padding: .2em;">foo</td>
<td style="border: 1px solid black;padding: .2em;">bar</td>
</tr>
</table>
</div>
