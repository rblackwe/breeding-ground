#!/usr/bin/perl
use CGI;

use DBM::Deep;
#use YAML::Syck;
use Data::Dumper;


my $db = DBM::Deep->new( "foo.db" );

#  print $db->{myhash}->{subkey} . "\n";
my $struct = $db->export();
print Dumper $struct;
