#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::Log;
use strict;
use warnings;

use base 'Exporter';
use Log::Dispatch;
use Log::Dispatch::Syslog;
use Socialtext::AppConfig;
use Class::Field qw(field);
use Encode;

=head1 NAME

Socialtext::Log - A logging utility class for NLW that dispatches to syslog

=head1 SYNOPSIS

    # log a debugging message via the hub
    $hub->log->debug('hello, this is a debug message');

    # log a notice using the class
    Socialtext::Log->new()->notice('you will be evicted soon'):

=head1 DESCRIPTION

Logging is a critical piece of any application. Socialtext::Log provides a 
very simple tool to enable logging to syslogd(8). Multiple levels
of logging are supported, see syslog(3). Log messages are sent to 
facility local7. See L</CONFIGURATION>.

Methods for each level of logging are automatically created.

=head1 CONFIGURATION

syslogd(8) must be configured to enable logging support. Add something
like the following to /etc/syslog,conf (or equivalent).

    local7.*                        /var/log/nlw.log

syslogd(8) will need to told to reread it's configuration. See the 
man page for details.

=cut

our @EXPORT_OK = qw( st_log );

sub class_id { 'log' }

field log      => -init => 'Log::Dispatch->new';

BEGIN {
    my @deferred_calls;

    # Set up pass-thru functions to parent class
    for my $l (qw( debug info notice warning error critical alert emergency )) {
        no strict 'refs';
        *{$l} = sub {
            eval {
                my $self = shift;
                foreach my $call (@deferred_calls) {
                    my $level   = $call->{level};
                    my $message = $call->{message};

                    $self->log->$level(@$message);
                }
                @deferred_calls = ();
                $self->log->$l(@_);
            };

            # Save it for later if we can't connect to syslog.
            if ($@) {
                die unless $@ =~ /no connection to syslog available/;
                push @deferred_calls, {
                    level   => $l,
                    message => [@_]
                };
            }
        };
    }
}

my $Instance;

=head1 IMPORTABLE SUBROUTINE

=head2 st_log(LEVEL, MESSAGE, [MESSAGE ...])

=head2 st_log->LEVEL(MESSAGE, [MESSAGE ...])

Provides an alternate, convenient method of calling a logging routine without
having to keep track of a C<Socialtext::Log> instance yourself.

For example,

    use Socialtext::Log 'st_log';

    st_log->debug("Riunite on ice...");
    st_log(notice => "so nice!");

=cut

sub st_log {
    my $method = shift;

    __PACKAGE__->new;
    return $method
        ? $Instance->$method(@_)
        : $Instance;
}

=head1 METHODS

=head2 new()

Create or make use of an existing Socialtext::Log object. The class maintains
a singleton instance of the object.

=cut
sub new {
    my $class = shift;
    return $Instance if $Instance;
    my $self = bless {}, $class;
    $self->_syslog_output;
    $self->_screen_output if $ENV{NLW_DEBUG_SCREEN};

    $Instance = $self;
    return $Instance;
}

=head2 debug_method_call()

Write to the log that a particular method was called.

=cut

sub debug_method_call {
    my $self = shift;
    my ($meth) = ( caller(1) )[3];
    $self->debug("$meth\n");
}


# REVIEW: A signal handler for changing min_level would be nice.
sub _syslog_output {
    my $self = shift;
    $self->log->add(
        Log::Dispatch::Syslog->new(
            name      => 'syslog',
            min_level => Socialtext::AppConfig->syslog_level,
            ident     => 'nlw',
            logopt    => 'pid',
            facility  => 'local7',
            callbacks => [ \&_add_apache_uid ],
        )
    );
}

sub _screen_output {
    my $self = shift;

    require Log::Dispatch::Screen;
    $self->log->add(
        Log::Dispatch::Screen->new(
            name      => 'screen',
            min_level => 'debug',
            callbacks => [ \&_add_newline, \&_add_hash_for_tests ],
        )
    );
}

sub _add_apache_uid {
    my %p = @_;

    # We need to pass raw bytes to Sys::Syslog or it dies.
    my $bytes = Encode::encode_utf8($p{message});
    return "[$<] " . $bytes;
}

sub _add_newline {
    my %p = @_;

    $p{message} =~ s/\n*$/\n/;

    return $p{message}
}

sub _add_hash_for_tests {
    my %p = @_;

    $p{message} =~ s/^/# /gm
        if $ENV{HARNESS_ACTIVE};

    return $p{message};
}

1;

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

