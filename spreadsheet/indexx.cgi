#!/usr/bin/perl
use CGI;
use HTML::Table;

use DBM::Deep;
use YAML::Syck;
use Data::Dumper;

my $cgi = CGI->new();

my $db = DBM::Deep->new( "foo.db" );
$db->{key} = 'value';
$db->{localtim} = localtime();
$db->{myhash}->{subkey} = "subvalue";

#  print $db->{myhash}->{subkey} . "\n";
 my $struct = $db->export();


print $cgi->header();
print $cgi->start_html();
print "hi";
my @array_of_stuff = ( [ ['1:1', '1:2a'], ['2:1', '2:2'] ] );
$db->{array_of_stuff} =[ @array_of_stuff ]; 
my $table1 = new HTML::Table( @array_of_stuff );
$table1->setCell(1, 1, 'This is Cell 1');
$table1->setCellBGColor(1,1,'blue');

#Sets the cell style attribute.
$table1->setCellStyle (1, 1, 'css style');
$table1->setCellAttr (1, 1, "'onClick=javasscript:alert('bob') ");

#Sets the cell class attribute.
$table1->setCellClass (1, 1, 'css class');


$table1->print;
print "<hr>";
print $cgi->Dump(); 
print "<hr>";
print "<pre>xxxx<hr>";
print Dumper $struct;
print "</pre>";
print $cgi->end_html();
__END__
  use HTML::Table;

  $table1 = new HTML::Table($rows, $cols);
    or
  $table1 = new HTML::Table(-rows=>26,
                            -cols=>2,
                            -align=>'center',
                            -rules=>'rows',
                            -border=>0,
                            -bgcolor=>'blue',
                            -width=>'50%',
                            -spacing=>0,
                            -padding=>0,
                            -style=>'color: blue',
                            -class=>'myclass',
                            -evenrowclass=>'even',
                            -oddrowclass=>'odd',
                            -head=> ['head1', 'head2'],
                            -data=> [ ['1:1', '1:2'], ['2:1', '2:2'] ] );
   or
  $table1 = new HTML::Table( [ ['1:1', '1:2'], ['2:1', '2:2'] ] );

  $table1->setCell($cellrow, $cellcol, 'This is Cell 1');
  $table1->setCellBGColor('blue');
  $table1->setCellColSpan(1, 1, 2);
  $table1->setRowHead(1);
  $table1->setColHead(1);

  $table1->print;

  $table2 = new HTML::Table;
  $table2->addRow(@cell_values);
  $table2->addCol(@cell_values2);

  $table1->setCell(1,1, "$table2->getTable");
  $table1->print;
