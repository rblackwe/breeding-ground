#!perl -Tw
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::More tests => 7;
use FindBin;

BEGIN {
    use_ok( 'Socialtext::File', 'set_contents', 'get_contents' );
}

my @files;
my @files_and_dirs;

FILES_UNDER: {
    my $start = $FindBin::Bin;
    @files = Socialtext::File::files_under( $start );

    cmp_ok( scalar @files, '>', 0, 'Found at least one file' );

    my @nonfiles = grep { !-f } @files;
    is( scalar @nonfiles, 0, 'No non-file files found' );
}


FILES_AND_DIRS_UNDER: {
    my $start = $FindBin::Bin;
    my @files_and_dirs = Socialtext::File::files_and_dirs_under( $start );

    cmp_ok( scalar @files_and_dirs, '>', scalar @files, 'There better be more files than dirs' );

    my %files_and_dirs = map { ($_,1) } @files_and_dirs;
    delete @files_and_dirs{ @files };

    cmp_ok( scalar keys %files_and_dirs, '>', 1, 'Still better be some dirs left' );

    my @nondirs = grep { !-d } keys %files_and_dirs;
    is( scalar @nondirs, 0, 'All the rest of the files_and_dirs, minus files, better be dirs' );
}

Set_and_get_contents: {
    my $file = 't/contents.$$';
    unlink $file;
    set_contents($file, $$);
    is get_contents($file), $$;
    unlink $file;
}
