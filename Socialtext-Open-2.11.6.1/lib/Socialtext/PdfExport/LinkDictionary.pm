#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::PdfExport::LinkDictionary;
use warnings;
use strict;

use base 'Socialtext::Formatter::AbsoluteLinkDictionary';

sub image {'%{full_path}'}

1;
