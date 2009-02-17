#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::Hub;
use strict;
use warnings;

use base 'Socialtext::Base';

use Class::Field qw( const field );
use Socialtext::Registry;
use Readonly;
use Socialtext::Authz;
use Socialtext::Authz::SimpleChecker;
use Socialtext::Validate qw( validate SCALAR_TYPE );
use Socialtext::BrowserDetect ();
use Socialtext::Challenger;

sub class_id { 'hub' }

field action => -init => '$self->cgi->action';
field main => -weak;
field hub => -weak,
      -init => '$self';
const registry_class => 'Socialtext::Registry';
field registry =>
      -init => '$self->_load_class("registry")';
field 'authz' =>
      -init => 'Socialtext::Authz->new';
field 'checker' =>
      -init => 'Socialtext::Authz::SimpleChecker->new
                    ( user => $self->current_user, workspace => $self->current_workspace )';

field 'current_workspace';
field 'current_user';

field config_files => [];

=head1 NAME

Socialtext::Hub - Central request-like object

=head1 SYNOPSIS

Kind of like a "Request" object - has current user/workspace/page, and
references to other "class objects". Since most classes in the system
have a reference to the hub, and the hub has references to a bunch of
other stuff, some special considerations have to be made.

=cut

# Override field 'hub' in Socialtext::Base to make sure we never reference
# ourself
sub hub {}

# XXX - this is just here to let some tests pass that blow up if we
# try to load the config class
sub config { return {} }

sub process {
    my $self = shift;

    return $self->bug_safe unless $self->bugs_to_screen;
    return $self->_process;
}

# Was Socialtext::Hub->process, but we need to be able to call this form
# bug_safe, which is already called from process
sub _process {
    my $self = shift;

    $self->preload;
    $self->no_plugin_action
      unless defined $self->registry->lookup->action->{$self->action};
    my ($class_id, $method) =
      @{$self->registry->lookup->action->{$self->action}};
    $method ||= $self->action;
    $self->drop_workspace_breadcrumb($method);
    my $html = eval { $self->$class_id->$method };
    my $e = $@;
    if ( Exception::Class->caught('Socialtext::Exception::DataValidation') ) {
        $html = $self->handle_validation_error($@);
    } elsif ($e) {
        $e->rethrow if eval { $e->can('rethrow') };
        die "$e\n";
    }
    
    # Safari's JS doesn't properly handled raw utf8 data.
    # Escaping them to entities seems to be the only way out.
    if ( Socialtext::BrowserDetect::safari() && $self->cgi->is_xhr ) {
        $html =~ s/([^\x00-\xa0])/sprintf('&#x%x;', unpack('U', $1))/egs;
    }

    return $html;
}

sub drop_workspace_breadcrumb {
    my $self = shift;
    my $action = shift;
    return if $action eq 'bugs_dump';
    # XXX - There may be other actions/conditions to skip breadcrumbing...
    $self->current_workspace->drop_breadcrumb($self->current_user);
}

sub preload {
    my $self = shift;

    $self->registry->load;
    my $preload = $self->registry->lookup->preload;
    map {
        $self->_load_class($_->[0])
    } sort {
        $b->[1] <=> $a->[1]
    } map {
        my %hash = @{$preload->{$_}}[1..$#{$preload->{$_}}];
        [$_, $hash{priority} || 0];
    } keys %$preload;
    return $self;
}

sub no_plugin_action {
    my $self = shift;
    my $msg = 'An invalid action, '
        . $self->action
        . ', was entered. '
        . 'Returning to front page.';
    $self->fail_home_with_warning( $msg, "Invalid action: " . $self->action );
}

sub handle_validation_error {
    my $self = shift;
    my $error = shift;

    my $msg;
    if ( $error->can('messages') && $error->messages() ) {
        $msg = 'There was an error with your request:<br />';
        $msg .= "$_<br />" for $error->messages;
    }
    else {
        $msg = 'Malformed query.<br />';
    }
    my $support_address = Socialtext::AppConfig->support_address();
    $msg .=
        qq|Please send email to <a href="mailto:$support_address">$support_address</a> if you think it should have worked.|;
    $self->fail_home_with_warning( $msg, $error );
}

sub fail_home_with_warning {
    my ( $self, $msg, $error ) = @_;

    $self->main->status_message($msg);

    $self->action('homepage');

    warn "fail_home_with_warning: $error\n";
    return $self->homepage->homepage;
}

sub _load_class {
    my $self = shift;

    my ($class_id) = @_;
    return $self if $class_id eq 'hub';
    return $self->$class_id
      if defined $self->{$class_id};
    my $class_class = $class_id . '_class';
    my $registry = $self->{registry};
    my $class_name = $self->can($class_class)
        ? $self->$class_class
        : defined $registry
          ? (defined $registry->lookup and
             UNIVERSAL::isa($registry->lookup,
                            $registry->lookup_class)
            )
            ? $registry->lookup->classes->{$class_id}
            : Carp::confess "Can't find a class for class_id '$class_id'"
          : Carp::confess "Can't find a class for class_id '$class_id'";
    $self->create_class_object($class_name, $class_id);
}

# XXX in a typical page load, this method uses 9.70 % of cpu time
# (which makes sense)
sub create_class_object {
    my $self = shift;

    my ($class_name, $class_id) = @_;
    Carp::confess "No class defined for class_id '$class_id'"
      unless $class_name;

    my $object = $class_name->new(hub => $self)
      or die "Can't create new '$class_name' object";

    $class_id ||= $object->class_id;
    die "No class_id defined for class: '$class_name'\n"
      unless $class_id;

    $object->init if $object->can('init');
    return $object;
}

sub registry_loaded {
    my $self = shift;

    defined $self->{registry} &&
    defined $self->{registry}->lookup;
}

sub bugs_to_screen {
    return 1 if Socialtext::AppConfig->debug();
}

sub bug_safe {
    my $self = shift;

    my $return;
    # XXX would like to avoid assigning to $return. How?
    eval { $return = $self->_process(@_) };
    return $return unless $@;
    my $e = $@;
    $e->rethrow if eval { $e->can('rethrow') };
    warn $e;
    eval {$self->registry->load};
    die "Can't load registry for bug report:\n$e" if $@;
    $self->bugs->bugs_report($e);
}

# XXX - this was in Socialtext::Users - but mostly it just depends on the hub
# and knowing the current user's email address
sub preferences_object {
    my $self = shift;

    return $self->{preferences_object} = shift if @_;
    return $self->{preferences_object} if defined $self->{preferences_object};
    $self->{preferences_object}
        = $self->preferences->new_for_user( $self->current_user->email_address )
}

sub assert_current_user_is_admin {
    my $self = shift;

    return 1 if $self->checker->check_permission('admin_workspace');

    # Ideally, we'd show some sort of error to the user, but the app
    # has no way to do that except on the login pages. If I add an
    # error to the session, it will just sit there until the next time
    # the browser hits the login screen, which is obviously wrong.

    my $app = Socialtext::WebApp->NewForNLW;
    $app->redirect( uri => '?' );
}

{
    Readonly my $spec => {
        permission_name => SCALAR_TYPE,
        error_type      => SCALAR_TYPE,
    };
    sub require_permission {
        my $self = shift;
        my %p = validate( @_, $spec );

        return if
            $self->checker->check_permission( $p{permission_name} );

        $self->authz_error( error_type => $p{error_type} );
    }
}

{
    Readonly my $spec => { error_type => SCALAR_TYPE };
    sub authz_error {
        my $self = shift;
        my %p = validate( @_, $spec );

        # XXX - unclean!
        my $app = Socialtext::WebApp->NewForNLW;

        $app->abort_forbidden()
            if Socialtext::AppConfig->unauthorized_returns_forbidden();

        Socialtext::Challenger->Challenge( type    => $p{error_type},
                                           hub     => $self );
    }
}

sub _make_methods_for_class {
    my $class_id = shift;
    my $class = shift;

    eval <<"EOF";
sub ${class_id}_class { return '$class' }

sub $class_id {
    my \$self = shift;

    \$self->{ $class_id } = shift if \@_;
    \$self->{ $class_id } ||= \$self->_load_class( '$class_id' );

    return \$self->{ $class_id };
}
EOF
    die $@ if $@;
}

my @PluginClasses;
sub plugin_classes { @PluginClasses }

BEGIN {
    for my $class (
        qw(
            Socialtext::Attachments
            Socialtext::CGI
            Socialtext::CSS
            Socialtext::Formatter
            Socialtext::Formatter::Viewer
            Socialtext::Headers
            Socialtext::Helpers
            Socialtext::Log
            Socialtext::Pages
            Socialtext::PreferencesPlugin
            Socialtext::Template

            Socialtext::SearchPlugin
            Socialtext::AttachmentsUIPlugin
            Socialtext::WikiwygPlugin
            Socialtext::BacklinksPlugin
            Socialtext::BreadCrumbsPlugin
            Socialtext::BugsPlugin
            Socialtext::CategoryPlugin
            Socialtext::CommentUIPlugin
            Socialtext::DeletePagePlugin
            Socialtext::DisplayPlugin
            Socialtext::DuplicatePagePlugin
            Socialtext::EditPlugin
            Socialtext::EmailNotifyPlugin
            Socialtext::EmailPageUIPlugin
            Socialtext::FavoritesPlugin
            Socialtext::FetchRSSPlugin
            Socialtext::HitCounterPlugin
            Socialtext::HomepagePlugin
            Socialtext::NewFormPagePlugin
            Socialtext::PageAnchorsPlugin
            Socialtext::PdfExportPlugin
            Socialtext::RecentChangesPlugin
            Socialtext::RefcardPlugin
            Socialtext::RenamePagePlugin
            Socialtext::RevisionPlugin
            Socialtext::ShortcutLinksPlugin
            Socialtext::SOAPPlugin
            Socialtext::SOAPGoogle
            Socialtext::SyndicatePlugin
            Socialtext::TiddlyPlugin
            Socialtext::TechnoratiPlugin
            Socialtext::TimeZonePlugin
            Socialtext::UserPreferencesPlugin
            Socialtext::UserSettingsPlugin
            Socialtext::WatchlistPlugin
            Socialtext::WeblogPlugin
            Socialtext::WeblogArchive
            Socialtext::Wikiwyg::AnalyzerPlugin
            Socialtext::RtfExportPlugin
            Socialtext::WorkspacesUIPlugin
            Socialtext::ProvisionPlugin
        ) ) {
        eval "use $class ()";
        die $@ if $@;

        if ( __PACKAGE__->can( $class->class_id ) ) {
            die "The class_id for $class is already being used.";
        }

        _make_methods_for_class( $class->class_id, $class );
        push @PluginClasses, $class
            if $class->can('register');
    }
}


1;

