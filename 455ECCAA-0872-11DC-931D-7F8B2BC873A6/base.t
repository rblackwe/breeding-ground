#!/usr/local/bin/perl
use Test::More qw( no_plan );
use Data::Dumper;
use CGI;
use YAML::Syck;

#foreach (0..0) {
   open (my $out ,">", "test.out") || die;
   my $q = new CGI;
   $q->param(-name=>'counter',-value=>$_);
   $q->param(-name=>'counter2',-value=>$_);
   $q->save($out);
   close $out;

   my  $yaml = Dump(\%ENV);
 #  my %params = $q->Vars;
 #  warn Dumper %params;
   DumpFile('env.yaml', $yaml);
   #DumpFile('env.yaml', $params);
  # diag Dumper \%ENV;
#}
ok 1;
