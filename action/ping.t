#!/usr/local/bin/perl
use Test::More ( tests => 1 );

my $command           = '/sbin/ping -c 2 robertblackwell.com';
my $command_response  = `$command`;

diag $command;
diag $command_response;

like  ($command_response, qr/216.146.203.240/ ), "ip is 216.146.203.240";
