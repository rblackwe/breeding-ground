#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::UsageStats;

use warnings;
use strict;
# XXX replace with DateTime
use Date::Format;
use Email::Simple;
use Email::Send;
use Email::Send::Sendmail;
use Socialtext::User;
use Socialtext::Workspace;

$Email::Send::Sendmail::SENDMAIL = '/usr/sbin/sendmail';


our $VERSION = '0.01';

# Done at this level because it's a bit easier to diddle for testing
our $Mail_this_session = 1;

sub appliance_user_report {
    my %p = @_;

    # Count up the active users using the log files
    my %active_users = ();
    _read_log_files_for_active_users(\%active_users);
    # Get count of users and details on when they last logged in to
    # which workspace
    my $user_count = 0;
    my $detail     = '';
    _get_user_login_details( $p{socialtext_root}, \$user_count, \$detail, \%active_users );

    # XXX why two? what is the definition of active?
    # Apparently Seagate is driving this distinction, with
    # a special contract. We could make this an option. 
    # Leaving it alone for now to wait and see.
    my $active_user_count
        = scalar grep { $active_users{$_} > 2 } keys %active_users;

    # Choose or not to send email
    $Mail_this_session = !$p{no_mail};

    # send out the emails
    _send_appliance_report_emails(
        hostname => $p{hostname},
        user_count => $user_count,
        active_user_count => $active_user_count,
        user_details => $detail,
        summary_to => \@{$p{summary_to}},
        detail_to => \@{$p{detail_to}},
        product_version => $p{product_version},
    );
}

sub get_workspace_from_url {
    my $url = shift;

    my ($workspace) = ($url =~ m{^/([^/]+)/index\.cgi});
    # If someone stuck weird characters in the URL it can cause sadness for
    # st-workspace-view-edit-stats... clean them out here
    if ($workspace) {
        $workspace =~ s/[^a-z0-9\-]//g;
    }
    return $workspace;
}

# REVIEW: This is quite fragile, there are several ways to post
# into a workspace, not all for editing a page. This attempts
# to have page edits, attachment uploads, page deletes, and
# revision restores count as edits. Other stuff not.
sub is_edit_action {
    my $method  = shift;
    my $url     = shift;
    my $status  = shift;
    my $referer = shift;
    return (   $method eq 'POST'
            && defined $url
            && $url =~ m{^/[^/]+/index\.cgi$}
            && defined $status
            && $status == 302
            && ( ! defined $referer
                 || $referer !~ /action=workspaces_unsubscribe/ )
    );
}

sub get_user_last_login {
    my $socialtext_root = shift;
    my $workspace       = shift;
    my $user_id         = shift;

    my $trail_file = "$socialtext_root/user/$workspace/$user_id/.trail";

    my $last_login = _get_file_mtime($trail_file);

    if (defined($last_login)) {
        $last_login = Date::Format::time2str( '%Y-%m-%d', $last_login );
    }

    return $last_login;
}

# REVIEW: There's probably a module to do this for us
sub parse_apache_log_line {
    my $line = shift;

    # initialize the data hash
    my %log_data
        = map { $_ => '' } qw( host user timestamp method url status referer);

    chomp($line);
    my @log = split(' ', $line);
    $log_data{host} = $log[0];
    $log_data{user} = $log[2];
    $log[3] =~ s/^\[//;
    $log_data{timestamp} = $log[3];
    $log[5] =~ s/^"//;
    $log_data{method} = $log[5];
    $log_data{url} = $log[6];
    $log_data{status} = $log[8];
    $log[10] =~ s/"//g;
    $log_data{referer} = $log[10];

    return \%log_data;
}

# Not using Socialtext::EmailSend because it is a plugin
sub send_email {
    # REVIEW: Should validate input paramters
    my %p = @_;

    my $email = Email::Simple->create(
        header => [
            From    => $p{from},
            To      => $p{to},
            Subject => $p{subject},
        ],
        body => $p{body},
    );

    if ($Mail_this_session) {
        Email::Send->new( { mailer => 'Sendmail' } )->send($email)
            or warn "unable to send mail to $p{to}: $!\n";
    }
    else {
        print $email->as_string;
    }
}

sub _send_appliance_report_emails {
    # REVIEW: Consider validation here
    my %p = @_;
    $p{date} = Date::Format::time2str( '%Y-%m-%d', time );

    if (@{$p{detail_to}}) {
        _send_detail_report(%p);
    }

    _send_summary_report(%p);
}

sub _send_detail_report {
    my %p = @_;

    my $body = <<"EOF";
Category: usage report blog - detailed

Total user count for $p{hostname}: $p{user_count}
Active user count for $p{hostname}: $p{active_user_count}

| *User Name* | *Workspace* | *Last Login* | *Active?* |
$p{user_details}

Socialtext $p{product_version}
EOF
    send_email(
        from    => 'appliance@' . $p{hostname},
        to      => ( join ', ', @{ $p{detail_to} } ),
        subject => "Socialtext detailed use report: $p{hostname}, $p{date}",
        body    => $body,
    );
}

# XXX duplication with _send_detail_report
sub _send_summary_report {
    my %p = @_;

    my $body = <<"EOF";
Category: usage report blog - summary

Total user count for $p{hostname}: $p{user_count}
Active user count for $p{hostname}: $p{active_user_count}

Socialtext $p{product_version}
EOF
    send_email(
        from    => 'appliance@' . $p{hostname},
        to      => ( join ', ', @{ $p{summary_to} } ),
        subject => "Socialtext summary use report: $p{hostname}, $p{date}",
        body    => $body,
    );
}

sub _get_user_login_details {
    my $socialtext_root = shift;
    my $user_count_ref  = shift;
    my $detail_ref      = shift;
    my $active_ref      = shift;

    my $users = Socialtext::User->All();

    while ( my $user = $users->next() ) {
        # count this user in the total user count
        $$user_count_ref++;

        my $username = $user->username();
        my $workspaces = $user->workspaces();

        while ( my $ws = $workspaces->next() ) {
            my $ws_name = $ws->name();

            my $last_login = get_user_last_login(
                $socialtext_root,
                $ws_name,
                $user->email_address,
            );
            $last_login ||= 'never';

            my $active = $active_ref->{$username} ? 'yes' : 'no';
            # XXX gather data not strings!
            $$detail_ref .= "| $username | $ws_name | $last_login | $active |\n";
        }
    }
}

sub _read_log_files_for_active_users {
    my $active_users_ref = shift;

    # parse up the log
    while (my $log_line = <STDIN>) {
        my $log_ref = parse_apache_log_line($log_line);

        # skip this line if the request is not successful and 
        # does not have a socialtext user_id (email address)
        next unless $log_ref->{status} =~ /^[23]/;
        next unless $log_ref->{user} =~ /\w/;

        my $workspace = get_workspace_from_url($log_ref->{url});
        next unless defined($workspace);

        my $action = 'view';
        if ( is_edit_action(
                $log_ref->{method},
                $log_ref->{url},
                $log_ref->{status},
                $log_ref->{referer},
            ) ) {
            $action = 'edit';
        }

        if ( $action eq 'edit' ) {
            $active_users_ref->{ $log_ref->{user} }++;
        }
    }
}

sub _get_file_mtime {
    my $file = shift;

    my $mtime = (
        -e $file
        ? (stat(_))[9]
        : undef
    );

    return $mtime;
}

=head1 NAME

Socialtext::UsageStats - A container module for doing statistics in Socialtext

=head1 SYNOPSIS

    use Socialtext::UsageStats;

    my $workspace = Socialtext::UsageStats::get_workspace_from_url($url);
    ...

=head1 DESCRIPTION

This is a starter class that is expected to change. It contains userful
methods for doing statistics on counting users, math on apache log files
and things like that. It's a place to lump things until better places
are discovered.

=head1 FUNCTIONS

=head2 appliance_user_report

    appliance_user_report(
        detail_to       => \@detail_to,
        summary_to      => \@summary_to,
        hostname        => $HOSTNAME,
        product_version => $VERSION,
        user_db_file    => $USER_DB_FILE,
    );

Calculate and mail detail and summary reports for appliance usage.

=head2 get_workspace_from_url($url)

Given the path part of a url, return the workspace named in the path,
if any. undef otherwise.

=head2 is_edit_action($method, $url, $status)

Given the method, url and response status of a request, determine if
if was a request that in some way edits a page.

=head2 get_user_last_login($workspace, $user_id)

Use the breadcrumbs trail file modification time to determine the
last time a user visited a workspace. Returns time in YYYY-MM-DD
format (as that's how it was used before pulling in here). Should
perhaps do something more generic.

=head2 parse_apache_log_line($log_line)

Take one line from an apache log and turns into a reference to a
hash of the relevant pieces of data.

=head2 send_email(from => $from, to => $to, subject => $subject, body => $body)

Very simple emailer. As yet, no error handling or validation.
Coming soon to a theater near you.

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
