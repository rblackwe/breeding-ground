#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext tests => 20;
fixtures( 'admin' );

use File::Basename ();
use File::Temp ();
use YAML ();

my $hub = new_hub('admin');
my $admin = $hub->current_workspace;

{
    ok( scalar ( grep { m{data/admin} } $admin->_data_dir_paths() ),
        '_data_dir_paths() includes pages' );
    ok( scalar ( grep { m{plugin/admin} } $admin->_data_dir_paths() ),
        '_data_dir_paths() includes plugin' );
    ok( scalar ( grep { m{user/admin} } $admin->_data_dir_paths() ),
        '_data_dir_paths() includes user' );
}

{
    my $image ='t/attachments/socialtext-logo-30.gif';
    open my $fh, '<', $image
        or die "Cannot read $image: $!";
    $admin->set_logo_from_filehandle(
        filehandle => $fh,
        filename   => $image,
    );

    $admin->_dump_to_yaml_file( 't/tmp' );

    my $ws_file = 't/tmp/admin-info.yaml';
    ok( -f $ws_file, 'workspace data yaml dump exists' );

    my $ws_dump = YAML::LoadFile($ws_file);
    is( $ws_dump->{account_name}, 'Socialtext', 'account_name is Socialtext in workspace dump' );
    is( $ws_dump->{creator_username}, 'devnull1@socialtext.com',
        'check creator name in workspace dump' );
    is( $ws_dump->{logo_filename}, File::Basename::basename( $admin->logo_filename() ),
        'check logo filename' );
}

{
    $admin->_dump_users_to_yaml_file( 't/tmp' );

    my $users_file = 't/tmp/admin-users.yaml';
    ok( -f $users_file, 'users data yaml dump exists' );

    my $users_dump = YAML::LoadFile($users_file);
    is( $users_dump->[0]{email_address}, 'devnull1@socialtext.com',
        'check email address for first user in user dump' );
    is( $users_dump->[0]{creator_username}, 'system-user',
        'check creator name for first user in user dump' );
}

{
    $admin->_dump_permissions_to_yaml_file( 't/tmp' );

    my $users_file = 't/tmp/admin-permissions.yaml';
    ok( -f $users_file, 'permissions data yaml dump exists' );

    my $perm_dump = YAML::LoadFile($users_file);
    ok( Socialtext::Role->new( name => $perm_dump->[0]{role_name} ),
        'valid role name in first dumped perm' );
    ok( Socialtext::Permission->new( name => $perm_dump->[0]{permission_name} ),
        'valid permission name in first dumped perm' );
}

{
    my $tarball = $admin->export_to_tarball();
    ok( -f $tarball, 'tarball exists' );

    my $dir = File::Temp::tempdir( CLEANUP => 1 );
    system( 'tar', 'xzf', $tarball, '-C', $dir )
        and die "Cannot untar $tarball: $!";

    for my $data_dir ( qw( data plugin user ) ) {
        ok( -d "$dir/$data_dir", "$data_dir is in tarball" );
    }

    ok( -f "$dir/admin-info.yaml", 'workspace yaml dump file is in tarball' );
    ok( -f "$dir/admin-users.yaml", 'users yaml dump file is in tarball' );
    ok( -f "$dir/admin-permissions.yaml", 'permissions yaml dump file is in tarball' );
}
