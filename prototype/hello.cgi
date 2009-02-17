#!/usr/local/bin/perl -w
use strict;
use CGI;                             
use Data::Dumper;
use CGI::Carp 'fatalsToBrowser';
my $q = new CGI;                    
print $q->header;                    
#print $q->start_html('hello world');
#print $q->h1( localtime() );
#print $q->h1('hi 2');
#print $q->param('zip');
#print $q->img( { src=> "http://robertblackwell.com/robert/icons/icons/add.png" });
print $q->img( { src=> "http://robertblackwell.com/robert/icons/icons/anchor.png" });

print '<a href="http://pairlite.com"><img src="http://robertblackwell.com/robert/icons/icons/anchor.png"> </img></a>';
print '<a href="http://pairlite.com"><img src="http://robertblackwell.com/robert/icons/icons/add.png"> </img></a>';


print '<a href="http://localhost:8090/select?number=1">1</a>';
print '<a href="http://localhost:8090/select?number=2">2</a>';
print '<a href="http://localhost:8090/select?number=3">3</a>';
print "-(17:00)->";
print '<a href="http://localhost:8090/select?number=4">4</a>';
print '<a href="http://localhost:8090/select?number=5">5</a>';
print '<a href="http://localhost:8090/select?number=6">6</a>';
print '<a href="http://localhost:8090/select?number=7">7</a>';
print '<a href="http://localhost:8090/select?number=8">8</a>';
print '<a href="http://localhost:8090/select?number=9">9</a>';
print '<a href="http://localhost:8090/select?number=10">10</a>';
print '<a href="http://localhost:8090/select?number=39">39</a>';

#print Dumper \%ENV;
#print $q->Dump;
print $q->end_html;


