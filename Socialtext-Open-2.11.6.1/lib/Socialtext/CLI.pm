#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::CLI;

use strict;
use warnings;

our $VERSION = '0.01';

use Encode;
use File::Basename ();
use File::Spec;
use Getopt::Long qw( :config pass_through );
use Socialtext::AppConfig;
use Pod::Usage;
use Readonly;
use Socialtext::Validate qw( validate SCALAR_TYPE ARRAYREF_TYPE );
use Socialtext::l10n qw( loc loc_lang valid_code );


my %CommandAliases = (
    '--help' => 'help',
    '-h'     => 'help',
    '-?'     => 'help',
);

{
    Readonly my $spec => { argv => ARRAYREF_TYPE( default => [] ) };
    sub new {
        my $class = shift;
        my %p = validate( @_, $spec );

        local @ARGV = @{ $p{argv} };

        my %opts;
        GetOptions(
            'ceqlotron' => \$opts{ceqlotron},
        ) or exit 1;

        my $self = {
            argv      => [ @ARGV ],
            command   => '',
            ceqlotron => $opts{ceqlotron},
        };

        return bless $self, $class
    }
}

sub run {
    my $self = shift;

    my $command = shift @{ $self->{argv} };

    my $script_name = File::Basename::basename($0);

    $self->_help_as_error(
        "You must provide a command as the first argument to this script.\n"
        . "Please run '$script_name help' for more details.")
        unless defined $command and length $command;

    $command = $CommandAliases{$command}
        if $CommandAliases{$command};
    $command =~ s/-/_/g;

    unless ( $self->can($command) ) {
        $self->_help_as_error(
            "The command you specified, $command, was not valid.\n"
            . "Please run '$script_name help' for more details.");
    }

    if ( $command ne 'help' ) {
        if ($>) {
            $self->_check_privs();
        }
        else {
            $self->_drop_privs();
        }
    }

    $self->{command} = $command;
    $self->$command();
}

sub _check_privs {
    my $self = shift;

    my $data_root = Socialtext::AppConfig->data_root_dir();
    return if -w $data_root;

    my $uid = (stat $data_root)[4];
    my $username = getpwuid $uid;

    warn <<"EOF";

 The data root dir at $data_root is not writeable by this process.

 It is owned by $username.

 You can either run this process as $username or root in order to run
 this command.

EOF

    _exit(1);
}

sub _drop_privs {
    my ( $uid, $gid ) = (stat Socialtext::AppConfig->data_root_dir())[4, 5];

    require POSIX;
    POSIX::setgid($gid);
    POSIX::setuid($uid);
}

sub help {
    $_[0]->_print_help( exitval => 0, verbose => 1 );
}

sub _help_as_error {
    $_[0]->_print_help( message => $_[1], exitval => 2 );
}

{
    Readonly my $spec => {
        message => SCALAR_TYPE( default => undef ),
        exitval => SCALAR_TYPE( default => 0 ),
        verbose => SCALAR_TYPE( default => 0 ),
    };
    sub _print_help {
        my $self = shift;
        my %p = validate( @_, $spec );

        if ( $p{message} ) {
            $p{message} = _clean_msg( $p{message} );
        }

        pod2usage({
            -message => $p{message},
            -input   => $INC{'Socialtext/CLI.pm'},
            -section => 'NAME|SYNOPSIS|COMMANDS',
            -verbose => ( $p{verbose} ? 2 : 0 ),
            -exitval => $p{exitval},
        });
    }
}

sub give_system_admin {
    my $self = shift;
    my $user = $self->_require_user();

    $user->update_metadata( is_technical_admin => 1 );

    my $username = $user->username();
    $self->_success( "$username now has system admin access." );
}

sub give_accounts_admin {
    my $self = shift;
    my $user = $self->_require_user();

    $user->update_metadata( is_business_admin => 1 );

    my $username = $user->username();
    $self->_success( "$username now has accounts admin access." );
}

sub remove_system_admin {
    my $self = shift;
    my $user = $self->_require_user();

    $user->update_metadata( is_technical_admin => 0 );

    my $username = $user->username();
    $self->_success( "$username no longer has system admin access." );
}

sub remove_accounts_admin {
    my $self = shift;
    my $user = $self->_require_user();

    $user->update_metadata( is_business_admin => 0 );

    my $username = $user->username();
    $self->_success( "$username no longer has accounts admin access." );
}

sub list_workspaces {
    require Socialtext::Workspace;

    my $self = shift;

    my $meth = $self->_determine_workspace_output(shift);

    my $workspaces = Socialtext::Workspace->All();

    while ( my $ws = $workspaces->next() ) {
        print $ws->$meth(), "\n";
    }

    $self->_success();
}

sub _determine_workspace_output {
    my $self = shift;

    my %opts = $self->_get_options( 'ids' );

    return $opts{ids}
        ? 'workspace_id'
        : 'name';
}

sub create_user {
    my $self = shift;
    my %user = $self->_require_create_user_params(shift);

    require Socialtext::User;

    if ( $user{username} and Socialtext::User->new( username => $user{username} ) ) {
        $self->_error(
            qq|The username you provided, "$user{username}", is already in use.|);
    }

    if ( $user{email_address}
         and Socialtext::User->new( email_address => $user{email_address} ) ) {
        $self->_error(
            qq|The email address you provided, "$user{email_address}", is already in use.|);
    }

    $user{username} ||= $user{email_address};

    my $user = eval { Socialtext::User->create( %user, require_password => 1 ) };
    if ( my $e = Exception::Class->caught('Socialtext::Exception::DataValidation') ) {
        my $msg = "The following errors occurred when creating the new user:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $self->_success( 'A new user with the username "' . $user->username()
                      . '" was created.' );
}

sub _require_create_user_params {
    my $self = shift;

    my %opts = $self->_get_options(
        'username:s',
        'email:s',
        'password:s',
        'first-name:s',
        'last-name:s'
    );

    for my $key ( grep { defined $opts{$_} } 'first-name', 'last-name' ) {
        my $val = $opts{$key};

        unless ( Encode::is_utf8($val) or $val =~ /^[\0x00-\xff]*$/ ) {
            $self->_error( "The value you provided for the $key option is not a valid UTF8 string." );
        }
    }

    $opts{email_address} = delete $opts{email};
    $opts{first_name}    = delete $opts{'first-name'};
    $opts{last_name}     = delete $opts{'last-name'};

    return %opts;
}

sub add_member {
    my $self = shift;

    my $user = $self->_require_user();
    my $ws   = $self->_require_workspace();

    if ( $ws->has_user( user => $user ) ) {
        $self->_error( $user->username . ' is already a member of the '
                        . $ws->name . ' workspace.' );
    }

    $ws->add_user( user => $user );

    $self->_success( $user->username . ' is now a member of the '
                      . $ws->name . ' workspace.' );
}

sub remove_member {
    my $self = shift;

    my $user = $self->_require_user();
    my $ws   = $self->_require_workspace();

    unless ( $ws->has_user( user => $user ) ) {
        $self->_error( $user->username . ' is not a member of the '
                        . $ws->name . ' workspace.' );
    }

    $ws->remove_user( user => $user );

    $self->_success( $user->username . ' is no longer a member of the '
                      . $ws->name . ' workspace.' );

}

sub _make_role_toggler {
    my $rolename = shift;
    my $add_p = shift;
    my $pre_failure = $add_p ? 'already' : 'not';
    my $success = $add_p ? 'now' : 'no longer';
    my $article = $rolename =~ /^[aeiou]/ ? 'an' : 'a';

    return sub {
        my $self = shift;

        my $user = $self->_require_user();
        my $ws   = $self->_require_workspace();

        require Socialtext::Role;
        my $role = Socialtext::Role->new( name => $rolename );
        my $display_name = $role->display_name();

        if ( $add_p == $ws->user_has_role( user => $user, role => $role ) ) {
            $self->_error( $user->username
                    . " is $pre_failure $article $display_name for the "
                    . $ws->name
                    . ' workspace.' );
        }

        my $is_selected = $user->workspace_is_selected( workspace => $ws );
        $ws->assign_role_to_user(
            user        => $user,
            role        => $add_p ? $role : Socialtext::Role->Member,
            is_selected => $is_selected,
        );

        $self->_success( $user->username . " is $success $article $display_name for the "
                          . $ws->name . ' workspace.' );
    }
}

{
    no warnings 'once';
    *add_workspace_admin    = _make_role_toggler( 'workspace_admin', 1 );
    *remove_workspace_admin = _make_role_toggler( 'workspace_admin', 0 );
    *add_impersonator       = _make_role_toggler( 'impersonator',    1 );
    *remove_impersonator    = _make_role_toggler( 'impersonator',    0 );
}

sub change_password {
    my $self = shift;

    my $user = $self->_require_user();
    my $pw   = $self->_require_string('password');

    eval { $user->update_store( password => $pw ) };

    if ( my $e = Exception::Class->caught('Socialtext::Exception::DataValidation') ) {
        my $msg = "The following errors occurred when changing the password:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $self->_success( 'The password for ' . $user->username
                      . ' has been changed.' );
}

sub disable_email_notify {
    my $self = shift;

    my $user = $self->_require_user();
    my ( $hub, $main )  = $self->_require_hub($user);

    my $ws = $hub->current_workspace();

    unless ( $ws->has_user( user => $user ) ) {
        $self->_error( $user->username . ' is not a member of the '
                        . $ws->name . ' workspace.' );
    }

    # XXX - this wipes out other email-related prefs, but that's
    # probably ok for now
    $hub->preferences()->store( $user->email_address(),
                                email_notify => { notify_frequency => 0 } );

    $self->_success( 'Email notify has been disabled for ' . $user->username()
                      . ' in the ' . $ws->name() . " workspace.\n" );
}

sub set_locale {
    my $self = shift;

    my $user = $self->_require_user();
    my ( $hub, $main )  = $self->_require_hub($user);

    my $email = $user->email_address;
    my $prefs = $hub->preferences->_load_all($email);
    my $display_prefs = $prefs->{display};
    loc_lang( $display_prefs->{locale} || 'en' );

    my $new_locale = $self->_require_string('locale');
    if (not valid_code($new_locale)) {
        $self->_error(loc("'[_1]' is not a valid locale", $new_locale));
    }

    $display_prefs->{locale} = $new_locale;
    $hub->preferences->store( $email, display => $display_prefs );
    loc_lang($new_locale);
    $self->_success(loc('Locale for [_1] is now [_2]', 
                        $user->username, $new_locale));
}

sub delete_category {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my @categories = $self->_require_categories($hub)
        or return;

    for my $cat (@categories) {
        $hub->category()->delete(
            category => $cat,
            user     => $hub->current_user(),
        );
    }

    my $msg = 'The following categories were deleted from the ';
    $msg .= $hub->current_workspace()->name() . " workspace:\n";
    $msg .= "  * $_\n" for @categories;

    $self->_success($msg);
}
{
    no warnings 'once';
    *delete_categories = \&delete_category;
}

sub search_categories {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my @categories = $self->_require_categories($hub)
        or return;

    my $msg = "Matched the following categories:\n";
    $msg .= "  * $_\n" for @categories;

    $self->_success($msg);
}

sub create_workspace {
    my $self = shift;
    my %ws = $self->_require_create_workspace_params(shift);

    require Socialtext::Hostname;
    require Socialtext::User;
    require Socialtext::Workspace;

    if ( $ws{name} and Socialtext::Workspace->new( name => $ws{name} ) ) {
        $self->_error(
            qq|The workspace name you provided, "$ws{name}", is already in use.|);
    }

    my $account_name = delete $ws{account} || Socialtext::Hostname::domain();
    # Special case hack for ST production systems
    $account_name = 'Socialtext' if $account_name =~ /socialtext/;

    my $account = Socialtext::Account->new( name => $account_name );
    unless ($account) {
        $self->_error(
            qq|There is no account named "$account_name".|);
    }

    $ws{account_id} = $account->account_id();

    my $ws = eval {
        my @skip = delete( $ws{empty} ) ? ( skip_default_pages => 1 ) : ();
        Socialtext::Workspace->create( %ws, @skip );
    };

    if ( my $e = Exception::Class->caught('Socialtext::Exception::DataValidation') ) {
        my $msg = "The following errors occurred when creating the new workspace:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $self->_success( 'A new workspace named "' . $ws->name()
                      . '" was created.' );
}

sub _require_create_workspace_params {
    my $self = shift;

    return $self->_get_options(
        'name:s',
        'title:s',
        'account:s',
        'empty',
    );
}

sub create_account {
    my $self = shift;

    my $name = $self->_require_string('name');

    require Socialtext::Account;

    if ( $name and Socialtext::Account->new( name => $name ) ) {
        $self->_error(
            qq|The account name you provided, "$name", is already in use.|);
    }

    my $account = eval { Socialtext::Account->create( name => $name ) };

    if ( my $e = Exception::Class->caught('Socialtext::Exception::DataValidation') ) {
        my $msg = "The following errors occurred when creating the new account:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $self->_success( 'A new account named "' . $account->name()
                      . '" was created.' );
}

sub set_permissions {
    my $self = shift;

    my $ws       = $self->_require_workspace();
    my $set_name = $self->_require_string('permissions');

    $ws->set_permissions( set_name => $set_name );

    $self->_success( 'The permissions for the ' . $ws->name()
                      . " workspace have been changed to $set_name.\n" );
}

sub add_permission {
    my $self = shift;

    my $ws   = $self->_require_workspace();
    my $perm = $self->_require_permission();
    my $role = $self->_require_role();

    $ws->add_permission(
        permission => $perm,
        role       => $role,
    );

    $self->_success( 'The ' . $perm->name() . ' permission has been granted to the '
                      . $role->display_name() . ' role in the ' . $ws->name() . " workspace.\n" );
}

sub remove_permission {
    my $self = shift;

    my $ws   = $self->_require_workspace();
    my $perm = $self->_require_permission();
    my $role = $self->_require_role();

    $ws->remove_permission(
        permission => $perm,
        role       => $role,
    );

    $self->_success( 'The ' . $perm->name() . ' permission has been revoked from the '
                      . $role->display_name() . ' role in the ' . $ws->name() . " workspace.\n" );
}

sub show_workspace_config {
    my $self = shift;

    my $ws = $self->_require_workspace();

    my $msg = 'Config for ' . $ws->name . " workspace\n\n";

    my $fmt = '%-32s:  %s';
    for my $c ( sort grep { $_ ne 'name' } map { $_->name } $ws->columns ) {
        my $val = $ws->$c();
        $val = 'NULL' unless defined $val;
        $val = q{''} if $val eq '';

        $msg .= sprintf( $fmt, $c, $val );
        $msg .= "\n";
    }

    $msg .= sprintf( $fmt, 'ping URIs', join ' - ', $ws->ping_uris );
    $msg .= "\n";
    $msg .= sprintf( $fmt, 'custom comment form fields', join ' - ', $ws->comment_form_custom_fields );
    $msg .= "\n";

    $self->_success($msg);
}

sub set_workspace_config {
    my $self = shift;

    my $ws = $self->_require_workspace();

    # XXX - these checks belong in Socialtext::Workspace->update()
    my %unsettable = map { $_ => 1 } qw( name creation_datetime );
    my %update;
    while ( my ( $key, $value ) = splice @{ $self->{argv} }, 0, 2 ) {
        next if $key =~ /_id$/;

        if ( $unsettable{$key} ) {
            $self->_error( "Cannot change $key after workspace creation." );
        }

        unless ( $ws->can($key) ) {
            $self->_error( "$key is not a valid workspace config key." );
        }

        $value = undef if $value eq '-null-';

        $update{$key} = $value;
    }

    eval { $ws->update(%update) };

    if ( my $e = Exception::Class->caught('Socialtext::Exception::DataValidation') ) {
        my $msg = "The following errors occurred when setting the workspace config:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $self->_success( 'The workspace config for '
                     . $ws->name() . ' has been updated.' );
}

sub set_logo_from_file {
    my $self = shift;

    my $ws = $self->_require_workspace();
    my $filename = $self->_require_string('file');

    open my $fh, '<', $filename
        or $self->_error( "Cannot read $filename: $!" );

    eval {
        $ws->set_logo_from_filehandle(
            filename   => $filename,
            filehandle => $fh,
        );
    };

    if ( my $e = Exception::Class->caught('Socialtext::Exception::DataValidation') ) {
        my $msg = "The following errors occurred when trying to use this logo:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $self->_success( 'The logo file was imported as the new logo for the '
                     . $ws->name() . ' workspace.' );
}

sub set_comment_form_custom_fields {
    my $self = shift;

    my $ws = $self->_require_workspace();

    $ws->set_comment_form_custom_fields( fields => $self->{argv} );

    $self->_success( 'The custom comment form fields for the '
                     . $ws->name() . ' workspace have been updated.' );
}

sub set_ping_uris {
    my $self = shift;

    my $ws = $self->_require_workspace();

    $ws->set_ping_uris( uris => $self->{argv} );

    $self->_success( 'The ping uris for the '
                     . $ws->name() . ' workspace have been updated.' );
}

sub rename_workspace {
    my $self = shift;

    my $ws = $self->_require_workspace();

    my $name = $self->_require_string('name');

    my $old_name = $ws->name();
    $ws->rename( name => $name );

    $self->_success( "The $old_name workspace has been renamed to $name." );
}

sub show_acls {
    my $self = shift;

    my $ws = $self->_require_workspace();

    require List::Util;
    require Socialtext::Permission;
    require Socialtext::Role;

    my %roles = map { $_->name() => $_ } Socialtext::Role->All()->all();

    my @perms = Socialtext::Permission->All()->all();

    my $msg = "ACLs for " . $ws->name . " workspace\n\n";
    $msg .= "  permission set name: " . $ws->current_permission_set_name() . "\n\n";

    my $first_col = '<' x List::Util::max( map { length $_->name } @perms );

    my $format = "| \@$first_col| ";

    # We want the roles in a specific order, but if we add new ones
    # and no one updates this code, at least they'll all be shown in
    # _some_ order.
    my @roles = map { delete $roles{$_} }
        qw( guest authenticated_user member workspace_admin impersonator );
    push @roles, sort { $a->name() cmp $b->name() } values %roles;

    for my $role (@roles) {
        my $col = '|' x length $role->display_name();
        $format .= "\@$col\@|";
    }
    $format .= "\n";

    # Holy crap, a (more or less) legitimate use for Perl's formats
    # feature! I'd prefer Text::Reform but it seems silly to add a
    # dependency for this one command.
    #
    # See the end of "perldoc perlform" for an explanation of formline
    # and $^A;
    formline $format, q{ }, map { $_->display_name() => '|' } @roles;

    for my $perm (@perms) {
        my @marks;
        for my $role (@roles) {
            push @marks,
                $ws->role_has_permission( role => $role, permission => $perm ) ? 'X' : ' ';
        }

        formline $format, $perm->name(), map { $_ => '|'} @marks
    }

    $msg .= $^A;
    $self->_success($msg, "no indent");
}

sub purge_page {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $page = $self->_require_page($hub);

    my $title = $page->metadata()->Subject();
    $page->purge();

    $self->_success( "The $title page was purged from the "
                      . $hub->current_workspace()->name() . " workspace.\n" );
}

sub html_archive {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $file = Cwd::abs_path( $self->_require_string('file') );

    require Socialtext::HTMLArchive;
    $file = Socialtext::HTMLArchive->new( hub => $hub )->create_zip($file);

    $self->_success( 'An HTML archive of the ' . $hub->current_workspace()->name()
                      . " workspace has been created in $file.\n" );
}

sub export_workspace {
    my $self = shift;

    my $ws = $self->_require_workspace();

    my $file = $self->_export_workspace($ws);

    $self->_success( 'The ' . $ws->name()
                      . " workspace has been exported to $file." );
}

sub _export_workspace {
    my $self = shift;
    my $ws    = shift;

    my $dir = $self->_optional_string('dir');
    $dir ||= $ENV{ST_EXPORT_DIR};
    $dir ||= File::Spec->tmpdir();

    return $ws->export_to_tarball( dir => $dir );
}

sub delete_workspace {
    my $self = shift;

    my $ws = $self->_require_workspace();

    my $skip_export = $self->_boolean_flag('no-export');

    my $file = $self->_export_workspace($ws)
        unless $skip_export;

    my $name = $ws->name();
    $ws->delete();

    my $msg = "The $name workspace has been ";
    $msg .= "exported to $file and " unless $skip_export;
    $msg .= 'deleted.';

    $self->_success($msg);
}

sub index_page {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $page = $self->_require_page($hub);

    my $ws_name = $hub->current_workspace()->name();

    require Socialtext::Search::AbstractFactory;
    Socialtext::Search::AbstractFactory->GetFactory->create_indexer($ws_name)
        ->index_page( $page->id() );

    $self->_success( 'The ' . $page->metadata()->Subject()
                      . " page in the $ws_name workspace has been indexed." );
}

sub index_attachment {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $page = $self->_require_page($hub);
    my $attachment = $self->_require_attachment($page);

    my $ws_name = $hub->current_workspace()->name();

    require Socialtext::Search::AbstractFactory;
    Socialtext::Search::AbstractFactory->GetFactory->create_indexer(
        $hub->current_workspace->name
    )->index_attachment( $page->id(), $attachment->id() );

    Socialtext::Search::AbstractFactory->GetFactory->create_indexer($ws_name)
        ->index_page( $page->id() );

    $self->_success( 'The ' . $attachment->filename()
                      . " attachment in the $ws_name workspace has been indexed." );
}

sub index_workspace {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    if ( $self->_get_options("sync") ) {
        my $ws_name = $hub->current_workspace()->name();
        my $factory = Socialtext::Search::AbstractFactory->GetFactory();
        my $indexer = $factory->create_indexer($ws_name);
        $indexer->index_workspace($ws_name);
        $self->_success("The $ws_name workspace has been indexed.");
    }

    # Rather than call index_workspace on the indexer object (which is
    # synchronous), we create ChangeEvents to trigger the appropriate
    # indexer activity.
    require Socialtext::ChangeEvent;

    for my $page_id ( $hub->pages()->all_ids() ) {
        my $page = $hub->pages()->new_page($page_id);

        next if $page->deleted();

        Socialtext::ChangeEvent->Record($page);

        $self->_index_attachments_for_page($page);
    }

    $self->_success( 'The ' . $hub->current_workspace()->name()
                      . ' workspace has been indexed.' );
}

# Helper for index_workspace
sub _index_attachments_for_page {
    my $self = shift;
    my $page  = shift;

    my $attachments = $page->hub()->attachments()->all( page_id => $page->id() );

    foreach my $attachment (@$attachments) {
        next if $attachment->deleted();

        Socialtext::ChangeEvent->Record($attachment);
    }
}

sub delete_search_index {
    my $self = shift;

    my $ws = $self->_require_workspace();

    require Socialtext::Search::AbstractFactory;
    Socialtext::Search::AbstractFactory->GetFactory->create_indexer(
        $ws->name()
    )->delete_workspace();

    $self->_success( 'The search index for the '
                      . $ws->name() . ' workspace has been deleted.' );
}

sub send_email_notifications {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    unless ( $hub->current_workspace()->email_notify_is_enabled() ) {
        $self->_error( 'Email notifications are disabled for the '.
                        $hub->current_workspace()->name() . ' workspace.' );
    }

    my $page = $self->_require_page($hub);

    $hub->email_notify()->maybe_send_notifications( $page->id() );

    $self->_success( 'Email notifications were sent for the '.
                      $page->metadata()->Subject() . ' page.' );
}

sub send_watchlist_emails {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $page = $self->_require_page($hub);

    $hub->watchlist()->maybe_send_notifications( $page->id() );

    $self->_success( 'Watchlist emails were sent for the '.
                      $page->metadata()->Subject() . ' page.' );
}

sub send_weblog_pings {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    unless ( $hub->current_workspace()->ping_uris() ) {
        $self->_error( 'The ' . $hub->current_workspace()->name()
                        . ' workspace has no ping uris.' );
    }

    my $page = $self->_require_page($hub);

    require Socialtext::WeblogUpdates;
    Socialtext::WeblogUpdates->new( hub => $hub )->send_ping($page);

    $self->_success( 'Pings were sent for the '
                      . $page->metadata()->Subject() . ' page.' );
}

sub mass_copy_pages {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $target_ws = $self->_require_target_workspace();
    my $prefix = $self->_optional_string('prefix');
    $prefix ||= '';

    $hub->duplicate_page()->mass_copy_to( $target_ws->name(), $prefix, $hub->current_user() );

    my $msg =
        'All of the pages in the ' . $hub->current_workspace()->name()
        . ' workspace have been copied to the ' . $target_ws->name() . ' workspace';
    $msg .= qq|, prefixed with "$prefix"| if $prefix;
    $msg .= '.';

    $self->_success($msg);
}

sub add_users_from {
    my $self = shift;

    my $ws        = $self->_require_workspace();
    my $target_ws = $self->_require_target_workspace();

    my $users = $ws->users();

    my @added;
    while ( my $user = $users->next() ) {
        next if $target_ws->has_user( user => $user );

        $target_ws->add_user( user => $user );
        push @added, $user->username();
    }

    if (@added) {
        my $msg = 'The following users from the '
            . $ws->name()
            . ' workspace were added to the '
            . $target_ws->name()
            . " workspace:\n\n";

        $msg .= " - $_\n" for sort @added;

        $self->_success($msg);
    }
    else {
        $self->_success( 'There were no users in the '
                . $ws->name()
                . ' workspace not already in the '
                . $target_ws->name()
                . ' workspace.' );
    }
}

sub update_page {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $user  = $self->_require_user();
    my $title = $self->_require_string('page');

    $hub->current_user($user);

    my $page = $hub->pages()->new_from_name($title);

    $page->load();

    my $content = do { local $/; <STDIN> };
    unless ( defined $content and length $content ) {
        $self->_error( 'update-page requires that you provide page content on stdin.' );
        return;
    }

    my $revision = $page->metadata()->Revision() || 0;

    $page->update(
        subject          => $title,
        content          => $content,
        revision         => $revision,
        original_page_id => $page->id(),
        user             => $hub->current_user,
    );

    my $verb = $revision == 0 ? 'created' : 'updated';
    $self->_success( qq|The "$title" page has been $verb.| );
}

# This command is quiet since it's really only designed to be run by
# an MTA, and should be quiet on success.
sub deliver_email {
    my $self = shift;

    my $ws = $self->_require_workspace();

    require Socialtext::EmailReceiver;

    eval {
        Socialtext::EmailReceiver->receive_handle(
            handle    => \*STDIN,
            workspace => $ws,
        );
    };

    if ( my $e = Exception::Class->caught('Socialtext::Exception::Auth') ) {
        die $e->error();
    }
    elsif ( $e = $@ ) {
        die $e;
    }
}


sub customjs {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    if ($hub->current_workspace()->customjs_uri()) {
        $self->_success(
            'Custom JS URI for ' .
            $hub->current_workspace()->name .
            ' workspace is ' .
            $hub->current_workspace()->customjs_uri() .
            '.'
        );
    } else {
        $self->_success(
            'The ' .
            $hub->current_workspace()->name .
            ' workspace has not custom Javascript set.'
        );
    }
}

sub clear_customjs {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    $hub->current_workspace()->update('customjs_uri', '');
    $self->_success(
        'Custom JS URI cleared for ' .
        $hub->current_workspace()->name .
        ' workspace.'
    );
}

sub set_customjs {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    my %opts = $self->_get_options( 'uri:s' );
    $hub->current_workspace()->update('customjs_uri', $opts{uri});
    $self->_success(
        'Custom JS URI for ' .
        $hub->current_workspace()->name .
        ' workspace set to ' .
        $opts{uri} .
        '.'
    );
}


# Called by Socialtext::Ceqlotron
sub from_input {
    my $self = shift;
    my $class = ref $self;

    {
        no warnings 'redefine';
        *_exit = sub {};
        *_help_as_error = sub { die $_[1] };
    }

    my $errors;
    while ( my $input = <STDIN> ) {
        chomp $input;

        eval {
            my @argv = split( chr(0), $input );
            $class->new( argv => \@argv )->run();
        };
        $errors .= $@ if $@;
    }

    die $errors if $errors;
}

sub version {
    my $self = shift;

    require Socialtext;

    $self->_success( Socialtext->version_paragraph() );
}

sub _require_user {
    require Socialtext::User;

    my $self = shift;

    my %opts = $self->_get_options( 'username:s', 'email:s' );

    unless ( grep { defined and length } @opts{ 'username', 'email' } ) {
        $self->_help_as_error(
            "The command you called ($self->{command}) requires a user to be specified.\n"
            . "A user can be identified by username (--username) or email address (--email).\n" );
    }

    my $user;
    if ( $opts{username} ) {
        $user = Socialtext::User->new( username => $opts{username} )
            or $self->_error(qq|No user with the username "$opts{username}" could be found.|);
    }
    elsif ( $opts{email} ) {
        $user = Socialtext::User->new( email_address => $opts{email} )
            or $self->_error(qq|No user with the email address "$opts{email}" could be found.|);
    }

    return $user;
}

sub _require_workspace {
    require Socialtext::Workspace;

    my $self = shift;
    my $key = shift || 'workspace';

    my %opts = $self->_get_options( "$key:s" );

    unless ( $opts{$key} ) {
        $self->_help_as_error(
            "The command you called ($self->{command}) requires a workspace to be specified.\n"
            . "A workspace is identified by name with the --$key option.\n" );
        return;
    }

    my $ws = Socialtext::Workspace->new( name => $opts{$key} );

    unless ($ws) {
        $self->_error(qq|No workspace named "$opts{$key}" could be found.| );
    }

    return $ws;
}

sub _require_target_workspace {
    my $self = shift;

    return $self->_require_workspace('target');
}

sub _require_hub {
    my $self = shift;

    require Socialtext::User;
    my $user = shift || Socialtext::User->SystemUser();

    my $ws = $self->_require_workspace();

    require Socialtext;
    my $main = Socialtext->new();
    $main->load_hub(
        current_workspace => $ws,
        current_user      => $user,
    );
    $main->hub()->registry()->load();

    return ( $main->hub(), $main );
}

sub _require_categories {
    my $self = shift;
    my $hub  = shift;

    my %opts = $self->_get_options( 'category:s', 'search:s' );

    unless ( grep { defined and length } @opts{ 'category', 'search' } ) {
        $self->_help_as_error(
            "The command you called ($self->{command}) requires one or more categories to be specified.\n"
            . "You can specify a category by name (--category) or by a search string (--search)." );
    }

    if ( $opts{category} ) {
        unless ( $hub->category()->exists( $opts{category} ) ) {
            $self->_error( qq|There is no category "$opts{category}" in the |
                            . $hub->current_workspace()->name() . ' workspace.' );
        }

        return $opts{category};
    }
    else {
        my @matches =
            $hub->category->match_categories( $opts{search} );

        unless (@matches) {
            $self->_error( qq|No categories matching "$opts{search}" were found in the |
                            . $hub->current_workspace()->name() . ' workspace.' );
        }

        return @matches;
    }
}

sub _require_page {
    my $self = shift;
    my $hub  = shift;

    my %opts = $self->_get_options('page:s');

    unless ( $opts{page} ) {
        $self->_help_as_error(
            "The command you called ($self->{command}) requires a page to be specified.\n"
            . "You can specify a page by id with the --page option." );
    }

    my $page = $hub->pages()->new_page( $opts{page} );
    unless ( $page and $page->exists() ) {
        $self->_error( qq|There is no page with the id "$opts{page}" in the |
                        . $hub->current_workspace()->name() . " workspace.\n" );
    }

    return $page;
}

sub _require_attachment {
    my $self = shift;
    my $page = shift;

    my %opts = $self->_get_options('attachment:s');

    unless ( $opts{attachment} ) {
        $self->_help_as_error(
            "The command you called ($self->{command}) requires an attachment to be specified.\n"
            . "You can specify an attachment by id with the --attachment option." );
    }

    my $attachment = $page->hub()->attachments()->new_attachment(
        id      => $opts{attachment},
        page_id => $page->id(),
    );

    unless ( $attachment->exists() ) {
        $self->_error( qq|There is no attachment with the id "$opts{attachment}" in the |
                        . $page->hub()->current_workspace()->name() . " workspace.\n" );
    }

    $attachment->load();

    return $attachment
}

sub _require_permission {
    require Socialtext::Permission;

    my $self = shift;

    my %opts = $self->_get_options('permission:s');

    unless ( $opts{permission} ) {
        $self->_help_as_error(
            "The command you called ($self->{command}) requires a permission to be specified.\n"
            . "A permission is identified by name with the --permission option.\n" );
        return;
    }

    my $perm = Socialtext::Permission->new( name => $opts{permission} );

    unless ($perm) {
        $self->_error(qq|There is no permission named "$opts{permission}".| );
    }

    return $perm;
}

sub _require_role {
    require Socialtext::Role;

    my $self = shift;

    my %opts = $self->_get_options('role:s');

    unless ( $opts{role} ) {
        $self->_help_as_error(
            "The command you called ($self->{command}) requires a role to be specified.\n"
            . "A role is identified by name with the --role option.\n" );
        return;
    }

    my $role = Socialtext::Role->new( name => $opts{role} );

    unless ($role) {
        $self->_error(qq|There is no role named "$opts{role}".| );
    }

    return $role;
}

sub _require_string {
    my $self = shift;
    my $name = shift;

    my %opts = $self->_get_options( "$name:s" );

    unless ( defined $opts{$name} and length $opts{$name} ) {
        $self->_help_as_error(
            "The command you called ($self->{command}) requires a $name to be specified with the --$name option.\n");
    }

    return $opts{$name};
}

sub _optional_string {
    my $self = shift;
    my $name = shift;

    my %opts = $self->_get_options( "$name:s" );

    return $opts{$name};
}

sub _boolean_flag {
    my $self = shift;
    my $name = shift;

    my %opts = $self->_get_options( "$name" );

    return $opts{$name};
}

sub _get_options {
    my $self = shift;

    local @ARGV = @{ $self->{argv} };

    my %opts;
    GetOptions( \%opts, @_ ) or exit 1;

    $self->{argv} = [ @ARGV ];

    return %opts;
}

sub _success {
    my $self = shift;
    my $msg  = _clean_msg(shift, shift);

    print $msg
        if defined $msg and not $self->{ceqlotron};

    _exit(0);
}

sub _error {
    my $self = shift;
    my $msg  = _clean_msg(shift);

    print STDERR $msg
        if defined $msg and not $self->{ceqlotron};

    _exit( $self->{ceqlotron} ? 0 : 1 );
}

# This exists so it can be overridden by tests and from_input.
sub _exit { exit shift; }

sub _clean_msg {
    my $msg = shift;
    my $no_indent = shift || 0;

    return unless defined $msg;

    # adds NL at beginning and two at the end
    $msg =~ s/^\n*/\n/;
    $msg =~ s/\n*$/\n\n/;

    # Indent every non-empty line by one space
    $msg =~ s/^(.*\S.*)/ $1/gm unless $no_indent;

    return $msg;
}


1;

__END__

=head1 NAME

Socialtext::CLI - Provides the implementation for the st-admin CLI script

=head1 USAGE

  st-admin <command> <options> [--ceqlotron]

=head1 SYNOPSIS

  USERS

  create-user --email [--username] --password [--first-name --last-name]
  change-password [--username or --email] --password
  add-member [--username or --email] --workspace
  remove-member [--username or --email] --workspace
  add-workspace-admin [--username or --email] --workspace
  remove-workspace-admin [--username or --email] --workspace
  add-impersonator [--username or --email] --workspace
  remove-impersonator [--username or --email] --workspace
  disable-email-notify [--username or --email] --workspace

  WORKSPACES

  set-permissions --workspace --permissions
    [public | member-only | authenticated-user-only | public-read-only
    | public-comment-only | public-authenticate-to-edit | intranet]

  add-permission --workspace --role --permission
  remove-permission --workspace --role --permission
  show-acls --workspace
  set-workspace-config --workspace <key> <value>
  show-workspace-config --workspace
  create-workspace --name --title --account
  delete-workspace --workspace [--dir]
  list-workspaces [--ids]
  export-workspace --workspace [--dir]
  html-archive --workspace --file
  mass-copy-pages --workspace --target [--prefix]
  purge-page --workspace --page
  search-categories --workspace --search
  delete-category --workspace [--category or --search]
  rename-workspace --workspace --name
  add-users-from --workspace --target
  customjs --workspace
  set-customjs --workspace --uri
  clear-customjs --workspace

  INDEXING

  index-workspace --workspace [--sync]
  delete-search-index --workspace
  index-page --workspace --page
  index-attachment --workspace --page --attachment

  ACCOUNTS

  create-account --name
  give-accounts-admin [--username or --email]
  remove-accounts-admin [--username or --email]
  give-system-admin [--username or --email]
  remove-system-admin [--username or --email]

  EMAIL

  send_email_notifications --workspace --page
  send_watchlist_emails --workspace --page
  deliver-email --workspace

  OTHER

  set-logo-from-file --workspace --file /path/to/file.jpg
  set-comment-form-custom-fields --workspace <field> <field>
  set-ping-uris --workspace <uri> <uri>
  send-weblog-pings --workspace --page
  update-page --workspace --page [--username or --email] < page-body.txt
  from-input < <list of commands>
  version
  help

=head1 COMMANDS

The following commands are provided:

=head2 create-user --email [--username] --password [--first-name --last-name]

Creates a new user. An email address and password are required. If no
username is specified, then the email address will also be used as the
username.

=head2 change-password [--username or --email] --password

Change the given user's password.

=head2 add-member --username --workspace

Given a user and a workspace, this command adds the specified user to
the given workspace.

=head2 remove-member --username --workspace

Given a user and a workspace, this command removes the specified user
from the given workspace.

=head2 add-workspace-admin --username --workspace

Given a user and a workspace, this command makes the specified user an
admin for the given workspace.

=head2 remove-workspace-admin --username --workspace

Given a user and a workspace, this command remove admin privileges for
the specified user in the given workspace, and makes them a normal
workspace member.

=head2 add-impersonator --username --workspace

Given a user and a workspace, this command makes the specified user an
impersonator for the given workspace.

=head2 remove-impersonator --username --workspace

Given a user and a workspace, this command remove impersonate privileges for
the specified user in the given workspace, and makes them a normal workspace
member.

=head2 disable-email-notify --username --workspace

Turns off email notifications from the specified workspace for the
given user.

=head2 set-permissions --workspace --permissions

Sets the permission for the specified workspace to the given named
permission set. Valid set names are:

=over 8

=item * public

=item * member-only

=item * authenticated-user-only

=item * public-read-only

=item * public-comment-only

=item * public-authenticate-to-edit

=item * intranet

=back

See the C<Socialtext::Workspace> documentation for more details on
permission sets.

=head2 add-permission --workspace --role -permission

Grants the specified permission to the given role in the named
workspace.

=head2 remove-permission --workspace --role -permission

Revokes the specified permission from the given role in the named
workspace.

=head2 show-acls --workspace

Prints a table of the workspace's role/permissions matrix to standard
output.

=head2 set-workspace-config --workspace <key> <value>

Given a valid workspace configuration key, this sets the value of the
key for the specified workspace. Use "-null-" as the value to set the
value to NULL in the DBMS. You can pass multiple key value pairs on
the command line.

=head2 show-workspace-config --workspace

Prints all of the specified workspace's configuration values to
standard output.

=head2 search-categories --workspace --search

Lists all categories matching the specified string.

=head2 delete-category --workspace [--category or --search]

Deletes the specified categories from the given workspace. You can
specify a single category by name with C<--category> or all categories
matching a string with C<--search>.

=head2 create-workspace --name --title --account [--empty]

Creates a new workspace with the given settings.  The usual account is
Socialtext. Accounts are used for billing.  If --empty is given then no pages
are inserted into the workspace, it is completely empty.

=head2 delete-workspace --workspace [--dir]

Deletes the specified workspace. Before the workspace is deleted, it
will first be exported to a tarball. See the L<export-workspace>
command documentation for details on where the exported tarball is
created.

=head2 list-workspaces [--ids]

Provides a newline separated list of all the workspace names in the
system. If you pass "--ids", it lists workspace ids instead.

=head2 export-workspace --workspace [--dir]

Exports the specified workspace as a tarball suitable for importing
via the import-workspace command. If no directory is provided, it
checks for an env var named C<ST_EXPORT_DIR>, and finally defaults to
saving the tarball in the directory returned by C<<
File::Spec->tmpdir() >>.

=head2 delete-workspace --workspace [--dir] [--no-export]

Deletes the specified workspace. Before the workspace is deleted, it
will first be exported to a tarball. To skip this step pass the
"--no-export" flag. See the L<export-workspace> command documentation
for details on where the exported tarball is created.

=head2 rename-workspace --workspace --name

Renames the specified workspace with the given name.

=head2 clear-customjs --workspace

Remove the custom Javascript for a workspace.

=head2 set-customjs --workspace --uri

Set the URI for the custom Javascript for a workspace.

=head2 customjs --workspace

Show the URI for the custom Javascript assigned to a workspace.

=head2 html-archive --workspace --file

Creates an archive of HTML pages containing the pages and attachments
to the specified file. The filename given must end in ".zip".

=head2 add-users-from --workspace --target

Adds all in the users who are a member of one workspace to the target
workspace I<as workspace members>. If a user is already a member of
the target workspace they are skipped.

=head2 mass-copy-pages --workspace --target [--prefix]

This command copies I<every> page in the specified workspace to the
target workspace. If a prefix is provided, this is prepended to the
page names in the target workspace.

=head2 purge-page --workspace --page

Purges the specified page from the given workspace. The page must be
specified by its I<page id>, which is the name used in URIs.

=head2 index-workspace --workspace [--sync]

(Re-)indexes all the pages and attachments in the specified workspace.  If
--sync is given the indexing is done syncronously, otherwise change events are
created and indexing is done asyncronously.

=head2 delete-search-index --workspace

Deletes the search index for the specified workspace.

=head2 index-page --workspace --page

(Re-)indexes the specified page in the given workspace.

=head2 index-attachment --workspace --page --attachment

(Re-)indexes the specified attachment in the given workspace. The
attachment must be specified by its id and its page's id.

=head2 set-logo-from-file --workspace --file /path/to/file.jpg

Given a path to an image file, makes that file the specified
workspace's logo.

=head2 set-comment-form-custom-fields --workspace <field> <field>

This sets the workspace's comment form custom fields to the given
field names, replacing any that already exist. If called without any
field names, it will simply remove all existing custom fields.

=head2 set-ping-uris --workspace <uri> <uri>

Given a set of URIs, this sets the workspace's ping URIs to the given
URIs, replacing any that already exist. If called without any URIs, it
will simply remove all the existing ping URIs.

=head2 send-weblog-pings --workspace --page

Given a page, this command send weblog pings for that page. It pings
the URIs defined for the workspace. If the workspace has no ping URIs,
it does nothing.

=head2 send_email_notifications --workspace --page

Sends and pending emali notifications for the specified page.

=head2 send_watchlist_emails --workspace --page

Sends any pending watchlist change notifications for the specified
page.

=head2 update-page --workspace --page --username < page-body.txt

Update (or create) a page with the given title in the specified
workspace. The user argument sets the author of the page.

=head2 deliver-email --workspace

Deliver an email to the specified workspace. The email message should
be provided on STDIN.

=head2 create-account --name

Creates a new account with the given name.

=head2 give-accounts-admin [--username or --email]

Gives the specified user accounts admin privileges.

=head2 remove-accounts-admin [--username or --email]

Remove the specified user's accounts admin privileges.

=head2 give-system-admin [--username or --email]

Gives the specified user system admin privileges.

=head2 remove-system-admin [--username or --email]

Remove the specified user's system admin privileges.

=head2 from-input < <list of commands>

Reads a list of commands from STDIN and executes them. Each line must
contain a list of arguments separated by a null character (\0). The
first argument should be the command to be run.

=head2 version

Displays the product version information.

=head2 help

What you're reading now.

=head1 EXIT CODES

If a command completes successfully, the exit code of the process will
be 0. If it cannot complete for some non-fatal reason, the exit code
is 1. An example of this would be if the "send-email-notifications"
command is called for a workspace which has email notifications
disabled. Another example would be passing a "--workspace" argument
and specifying a non-existent workspace.

Fatal errors cause an exit code of 2 or higher. Not passing required
arguments is a fatal error.

=head1 BEHAVIOR UNDER --ceqlotron

All the commands accept an additional "--ceqlotron" argument which tells
them they are running under the ceqlotron. When this is passed,
commands to do not generate any success or failure output, and unless
there is a fatal error, the exit code of the process will always be 0.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2006 Socialtext, Inc., All Rights Reserved.

=cut
