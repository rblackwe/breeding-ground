#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use warnings;
use strict;

use Test::Socialtext tests => 1;
fixtures( 'admin_no_pages' ); # need appconfig

use Socialtext::Log;

my $logger_one = Socialtext::Log->new;
my $logger_two = Socialtext::Log->new;

is($logger_one, $logger_two, 'the two loggers are the same');

