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
