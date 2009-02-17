#!/usr/local/bin/perl
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use DBI;
# Connect to the database.
my $dbh = DBI->connect("DBI:mysql:database=pl129_testdb;host=www2.pairlite.com",
		 "pl129_2", "Test1234",
		 {'RaiseError' => 1}) or die "$!";
my $cgi = CGI->new();
print $cgi->header();
print $cgi->start_html();
print <<'END';
  After database connect<p>
  If no errors show, connection attempt was successful.
END
print $cgi->end_html();
__END__
<?php
  define("DBTYPE", "mysql");              //Database type
  define("DBHOST", "www2.pairlite.com");     //Database host addrsss
  define("DBUSER", "pl129_2");              //Database username
  define("DBPASS", "Test1234");           //Database password
  define("DBNAME", "pl129_testdb");        //Database name
  mysql_connect(DBHOST,DBUSER,DBPASS);
  mysql_selectdb(DBNAME);
?>
  After database connect<p>
  If no errors show, connection attempt was successful.
