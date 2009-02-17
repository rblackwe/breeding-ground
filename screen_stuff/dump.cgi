#!/usr/bin/perl -w
use strict;
use CGI;                             
use CGI::Carp 'fatalsToBrowser';
my $q = new CGI;                    
print $q->header;                    
print $q->start_html('hello world');
print $q->h1('hi');
#print $q->param('zip');

print $q->Dump;
print $q->end_html;


