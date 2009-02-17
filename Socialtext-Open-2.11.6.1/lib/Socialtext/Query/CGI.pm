#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::Query::CGI;
use strict;
use warnings;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'direction';
cgi 'search_term';
cgi 'sortby';
cgi 'page_name';

1;
