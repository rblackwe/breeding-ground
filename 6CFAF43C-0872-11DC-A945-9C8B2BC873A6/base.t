#!/usr/local/bin/perl
use Test::More qw( no_plan );
ok 1;
my $xdata = 'GXXX';
$xdata =~ s/^[GH]+//;
diag $xdata;
