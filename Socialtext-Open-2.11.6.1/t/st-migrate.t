#!/usr/bin/perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
use strict;
use warnings;
use Test::More qw/no_plan/;
use Socialtext::AppConfig;

my $st_migrate = "bin/st-migrate";
ok -x $st_migrate;
my $perl = "$^X -Ilib";
my $prog = "$perl $st_migrate";

Compiles: {
    like qx($perl -c $st_migrate 2>&1), qr/syntax OK/;
}

Usage: {
    like qx($prog -? 2>&1),     qr/USAGE: /;
    like qx($prog --help 2>&1), qr/USAGE: /;
}
