#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Test::Socialtext::Fixture;

# Inspired by Ruby on Rails' fixtures.
# See http://api.rubyonrails.com/classes/Fixtures.html

use strict;
use warnings;
use Carp qw( confess );
use DateTime;
use File::Basename ();
use File::chdir;
use File::Slurp qw(slurp write_file);
use File::Spec;
use Socialtext::ApacheDaemon;
use Socialtext::Build qw( get_build_setting );

my $DefaultUsername = 'devnull1@socialtext.com';


sub new {
    my $class = shift;
    my $self = {@_};

    croak("Need to specify an environment") unless exists $self->{env};
    croak("Need to specify a name") unless exists $self->{name};
    bless $self, $class;

    $self->_init;

    return $self;
}

sub _init {
    my $self = shift;
    $self->{fixtures} = [];

    my $dir = $self->dir;

    $self->_generate_base_config();

    require Socialtext::Account;
    require Socialtext::Paths;
    require Socialtext::User;
    require Socialtext::Workspace;

    if (-f "$dir/fixture.yaml") {
        require YAML;

        $self->set_config(YAML::LoadFile("$dir/fixture.yaml"))
            or die "Could not load " . $self->name . "/fixture.yaml: $!";
        foreach my $sub_name (@{$self->config->{fixtures}}) {
            push @{ $self->fixtures },
                Test::Socialtext::Fixture->new( name => $sub_name, env => $self->env );
        }

        if ( $self->config->{clear_alzabo_cache} ) {
            Socialtext::AlzaboWrapper->ClearCache();
        }
    }
    else {
        $self->set_config({});
    }
}

# XXX - this is a bit gross and unlike the other fixture bits, but
# it's a prereq for all other fixtures, though not necessarily for all
# tests.
my $BaseConfigGenerated;
sub _generate_base_config {
    return if $BaseConfigGenerated;
    my $self = shift;

    my $env               = $self->env;

    _system_or_die(
        $env->nlw_dir . '/configure',
        '--quiet',
    );

    my $testing = $ENV{HARNESS_ACTIVE} ? '--testing' : '';

    my $gen_config = $env->nlw_dir . '/dev-bin/gen-config';
    my $st_db      = $env->nlw_dir . '/bin/st-db';

    my $apache_proxy    = get_build_setting('apache-proxy')    || 1;
    my $socialtext_open = get_build_setting('socialtext-open') || 0;

    _system_or_die(
        $gen_config,
        '--quiet',
        '--root',           $env->root_dir,
        '--ports-start-at', $env->ports_start_at,
        '--apache-proxy=' . $apache_proxy,
        '--socialtext-open=' . $socialtext_open,
        '--dev=0',    # Don't create the files in ~/.nlw
        $testing,
    );

    _system_or_die( $st_db, '--recreate',      '--quiet' );
    _system_or_die( $st_db, '--required-data', '--quiet' );

    $BaseConfigGenerated = 1;
}

sub make_cache_current {
    my $self = shift;

    unless ($self->is_current) {
        $self->generate;
        $self->encache;
    }
}

sub is_current {
    my $self = shift;
    my $dir = $self->dir;

    if (-f $self->fs_cache_file) {
        if (-M $dir < -M $self->fs_cache_file) {
            warn "mtimedir ", $self->name, "\n";
            return 0;
        }
    }

    if (-x "$dir/is-current") {
        return ! (system "$dir/is-current");
    }

    return 0;
}

sub encache {
    my $self = shift;

    $self->_encache_database;
    $self->_encache_filesystem;
}

sub _encache_filesystem {
    my $self = shift;

    my @contents = $self->_cache_contents
        or return;

    local $CWD = $self->env->root_dir or die;
    _system_or_die( 'tar czf '
          . $self->fs_cache_file . ' '
          . join ' ', @contents );
}

sub _encache_database {
    my $self = shift;

    foreach my $cache_item (@{$self->config->{cache}}) {
        if ($cache_item eq 'USERS') {
            my $file = $self->db_cache_file;

            require Socialtext::AppConfig;
            _system_or_die(
                'pg_dump -c ' . Socialtext::AppConfig->db_schema_name . " > $file" );
        }
    }
}

sub decache {
    my $self = shift;

    # Note that order is important here.  We'll need AppConfig to be able to
    # decache the database.
    $self->_decache_filesystem;
    $self->_decache_database;
}

sub _decache_filesystem {
    my $self = shift;

    return unless $self->_cache_contents;

    local $CWD = $self->env->root_dir or die;
    _system_or_die('tar xzf ' . $self->fs_cache_file);
}

sub _decache_database {
    my $self = shift;

    my $file = $self->db_cache_file;
    if (-f $file) {
        require Socialtext::AppConfig;
        _system_or_die( "psql -q -o /tmp/psql.out.$> "
              . Socialtext::AppConfig->db_schema_name
              . " -f $file > /tmp/psql.notice.$> 2>&1 " );
    }
}

sub generate {
    my $self = shift;

    $self->_generate_subfixtures;
    $self->_generate_workspaces;
    $self->_run_custom_generator;
}

sub _run_custom_generator {
    my $self = shift;
    my $dir = $self->dir;
    my $env = $self->env;

    if (-r "$dir/generate") {
        local $ENV{NLW_DIR} = $env->nlw_dir;
        local $ENV{NLW_ROOT_DIR} = $env->root_dir;
        local $ENV{NLW_STARTING_PORT} = $env->ports_start_at;

        (system "$dir/generate") == 0
            or die $self->name . "/generate exit ", $? >> 8;
    }
}

sub _create_user {
    my $self = shift;
    my %p = @_;

    my $user = Socialtext::User->new( username => $p{username} );
    $user ||= Socialtext::User->create(
        username        => $p{username},
        email_address   => $p{username},
        password        => 'd3vnu11l',
        is_business_admin  => $p{is_business_admin},
        is_technical_admin => $p{is_technical_admin},
    );

    return $user;
}

sub _generate_subfixtures {
    my $self = shift;

    foreach my $name (@{$self->config->{fixtures}}) {
        Test::Socialtext::Fixture->new(name => $name, env => $self->env)->generate();
    }
}

my %PermsForName = (
    public          => 'public',
    'auth-to-edit'  => 'public-authenticate-to-edit',
);
sub _generate_workspaces {
    my $self = shift;

    return unless $self->config->{workspaces};

    my $creator = $self->_create_user(
        username           => $DefaultUsername,
        is_business_admin  => 1,
        is_technical_admin => 1,
    );
    my $account_id = Socialtext::Account->Socialtext()->account_id();

    print STDERR "# workspaces: " if $self->env->verbose;
    while ( my ( $name, $spec ) = each %{ $self->config->{workspaces} } ) {
        print STDERR "$name... " if $self->env->verbose;

        if ( $name eq 'help' ) {
            $self->_generate_help_workspace($creator);
            next;
        }
	my $title = ucfirst($name) . ' Wiki';

	if( defined $spec->{title} ) {
	    $title = $spec->{title};
	}

        my $ws = Socialtext::Workspace->create(
            name               => $name,
            title              => $title,
            account_id         => $account_id,
            created_by_user_id => $creator->user_id(),
            account_id         => Socialtext::Account->Socialtext()->account_id,
        );

        my $perms = $PermsForName{ $ws->name } || 'member-only';
	if( defined( $spec->{permission_set_name} )) {
	    $perms = $spec->{permission_set_name};
	}

        $ws->set_permissions( set_name => $perms );

        # Add extra users in the roles specified.
        while ( my ( $role, $users ) = each %{ $spec->{extra_users} } ) {
            $self->_add_user( $ws, $_, $role ) for @$users;
        }

        $self->_create_extra_pages($ws) if $spec->{extra_pages};
        $self->_create_ordered_pages($ws) if $spec->{ordered_pages};
        $self->_activate_impersonate_permission($ws)
            if $spec->{admin_can_impersonate};
    }

    print STDERR "done!\n" if $self->env->verbose;
}

sub _add_user {
    my $self = shift;
    my $ws = shift;
    my $username = shift;
    my $rolename = shift;

    $ws->add_user(
        user => $self->_create_user( username => $username ),
        role => Socialtext::Role->new( name => $rolename ),
    );
}

sub _activate_impersonate_permission {
    my $self = shift;
    my $workspace = shift;

    $workspace->add_permission(
        permission => Socialtext::Permission->new( name => 'impersonate' ),
        role => Socialtext::Role->WorkspaceAdmin(),
    );
}

sub _generate_help_workspace {
    my $self = shift;
    my $user = shift;


    _system_or_die( 'bin/st-create-help-workspace' );
    my $ws = Socialtext::Workspace->new( name => 'help' );
    $ws->add_user(
        user => $user,
        role => Socialtext::Role->WorkspaceAdmin(),
    );
}

sub _unlink_existing_pages {
    my $self = shift;
    my $ws = shift;
    my $workspace_name = $ws->name;

    my $data_dir = Socialtext::Paths::page_data_directory($workspace_name);

    # clean out the pages we don't want
    File::Path::rmtree($data_dir);
    $self->_clean_workspace_ceqlotron_tasks($workspace_name);
}

# remove the ceqlotron jobs we don't want
sub _clean_workspace_ceqlotron_tasks {
    my $self           = shift;
    my $workspace_name = shift;

    require Socialtext::Ceqlotron;
    Socialtext::Ceqlotron::ensure_queue_directory();
    Socialtext::Ceqlotron::ensure_lock_file();

    my $program = 'bin/ceq-rm';
    system($program, $workspace_name) and die "$program failed: $!";
}

sub _create_ordered_pages {
    my $self = shift;
    my $ws = shift;

    $self->_unlink_existing_pages($ws);

    my $workspace_name = $ws->name;

    my $hub = $self->env->hub_for_workspace($ws);

    my $category_count = 1;

    # prepare the recent changes data
    my $date = DateTime->now;
    $date->subtract( seconds => 120 );
    for my $number (qw(one two three four five six)) {
        my $category = $category_count++ % 2;
        $category = "category $category";

        # We set the dates to ensure a repeatable sort order
        my $page = Socialtext::Page->new( hub => $hub )->create(
            title      => "$workspace_name page $number",
            content    => "$number content",
            date       => $date,
            categories => [$category],
            creator    => $hub->current_user,
        );
        $date->add( seconds => 5 );
    }
}

sub _create_extra_pages {
    my $self = shift;
    my $ws = shift;

    my $hub = $self->env->hub_for_workspace($ws);

    for my $file ( grep { -f && ! /(?:\.sw.|~)$/ } glob "t/extra-pages/*" ) {
        my $name = Encode::decode( 'utf8', File::Basename::basename( $file ) );
        $name =~ s{_SLASH_}{/}g;

        open my $fh, '<:utf8', $file
            or die "Cannot read $file: $!";
        my $content = File::Slurp::read_file($fh);

        Socialtext::Page->new( hub => $hub )->create(
            title   => $name,
            content => $content,
            date    => $self->_get_deterministic_date_for_page($name),
            creator => Socialtext::User->SystemUser(),
        );
    }

    $self->_create_extra_attachments($ws);
}

sub _get_deterministic_date_for_page {
    my $self = shift;
    my $name  = shift;
    my $epoch = DateTime->now->epoch;

    $epoch -= $self->_hash_name_for_seconds_in_the_past($name);

    return DateTime->from_epoch( epoch => $epoch )
}

sub _hash_name_for_seconds_in_the_past {
    my $self = shift;
    my $name = shift;

    # We want some pages to stay at the top of RecentChanges for quick access:
    my @very_recents = split /\n/, <<'EOT';
FormattingTest
FormattingToDo
WikiwygFormattingToDo
WikiwygFormattingTest
Babel
Internationalization
<script>alert("pathological")</script>
EOT
    return 0 if grep { $_ eq $name } @very_recents;

    my $NUM_BUCKETS = 1000;
    my $x = 33;
    $x *= ord for split //, $name;
    $x %= $NUM_BUCKETS;

    my $OFFSET_TO_ACCOUNT_FOR_VERY_RECENTS = 60;
    my $SECONDS_CURVE_ROOT = exp(log(60*60*24)/$NUM_BUCKETS);
    return
        $OFFSET_TO_ACCOUNT_FOR_VERY_RECENTS
        + int(($SECONDS_CURVE_ROOT**$x)*$x);
}

sub _create_extra_attachments {
    my $self = shift;
    my $ws = shift;

    my $hub = $self->env->hub_for_workspace($ws);

    local $CWD = 't/extra-attachments';
    for my $dir ( grep { -d && ! /\.svn/ } glob '*' ) {
        $hub->pages->current( $hub->pages->new_from_name( $dir ) );

        for my $file ( grep { -f } glob "$dir/*" ) {
            open my $fh, '<', $file
                or die "Cannot read $file: $!";

            $hub->attachments->from_file_handle(
                fh     => $fh,
                embed  => 0,
                unpack => 0,
                filename => $file,
                creator  => Socialtext::User->SystemUser(),
            );
        }
    }
}

sub fs_cache_file {
    my $self = shift;

    return $self->env->root_dir . '-' . $self->name . '.tgz';
}

sub db_cache_file {
    my $self = shift;

    return $self->env->root_dir . '-' . $self->name . '.sql';
}

sub _cache_contents {
    my $self = shift;
    my %file;

    # XXX: these keyword explosions probably belong somewhere else
    foreach my $cache_item (@{$self->config->{cache}}) {
        if ($cache_item =~ /^WORKSPACES/) {
            $file{$_} = 1 foreach qw(
                root/aliases.deliver
                root/data
                root/user
                root/plugin
            );
        } elsif ($cache_item eq 'USERS') {
            # ignore
        } else {
            $file{$cache_item} = 1;
        }
    }
    foreach my $fixture (@{$self->fixtures}) {
        $file{$_} = 1 foreach $fixture->_cache_contents;
    }

    my @contents = keys %file;
    return @contents;
}

sub _system_or_die {
    (system @_) == 0 or confess("Cannot execute @_: $!");
}

sub env { $_[0]->{env} }
sub name { $_[0]->{name} }
sub dir { $_[0]->env->nlw_dir . "/t/Fixtures/" . $_[0]->name }
sub config { $_[0]->{config} }
sub set_config { $_[0]->{config} = $_[1] }
sub fixtures { $_[0]->{fixtures} }

1;

__END__
