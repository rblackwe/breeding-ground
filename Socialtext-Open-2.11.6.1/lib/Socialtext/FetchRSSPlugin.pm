#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
# XXX we should think about renaming this class
package Socialtext::FetchRSSPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Cache::FileCache;
use Class::Field qw( const field );
use LWP::UserAgent;
use Socialtext::Paths;
use XML::Feed;

sub class_id { 'fetchrss' }
const class_title    => 'Fetch RSS';
const agent          => __PACKAGE__;
const default_expire => '1 h';
const proxy => '';
const ua_timeout => '30';

field 'cache';
field 'error';
field 'expire';
field 'cache_dir' => '-init' => 'Socialtext::Paths::plugin_directory( $self->hub->current_workspace->name )';
field timeout => -init => '$self->ua_timeout';

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add( wafl => fetchrss  => 'Socialtext::FetchRSS::Wafl' );
    $registry->add( wafl => fetchatom => 'Socialtext::FetchRSS::Wafl' );
    $registry->add( wafl => feed      => 'Socialtext::FetchRSS::Wafl' );
}

sub get_feed {
    my $self = shift;
    my $feed;
    $self->error(undef);
    # override NLW's override
    local $SIG{__DIE__} ;
    eval {
        $feed = $self->_get_feed(@_);
    };
    if ($@) {
        $self->error($@);
        return undef;
    }
    return $feed;
}

sub _get_feed {
    my $self = shift;
    my $url = shift;
    my $expire = shift;

    $self->expire($expire
        ? $expire
        : $self->default_expire
    );
    $self->_setup_cache;

    my $content = $self->_get_cached_result($url);
    if ( !defined($content) or !length($content) ) {
        $content = $self->_get_content($url);
    }

    if (defined($content) and length($content)) {
        my $feed = XML::Feed->parse(\$content) or
                die XML::Feed->errstr, "\n";
        return $feed;
    }
}

sub _get_content {
    my $self = shift;
    my $url = shift;
    my $content;

    my $ua  = LWP::UserAgent->new();
    $ua->agent($self->agent);
    $ua->timeout($self->timeout);
    if ( Socialtext::AppConfig->web_services_proxy ) {
        $ua->proxy([ 'http' ], Socialtext::AppConfig->web_services_proxy);
    }
    my $response = $ua->get($url);
    if ($response->is_success()) {
        $content  = $response->content();
        if (length($content)) {
            $self->cache->set( $url, $content, $self->expire );
        } else {
            die "zero length response\n";
        }
    } else {
        die $response->status_line, "\n";
    }
    return $content;
}

sub _setup_cache {
    my $self = shift;
    $self->cache(Cache::FileCache->new( {
         namespace   => $self->class_id,
         cache_root  => $self->cache_dir,
         cache_depth => 1,
         cache_umask => 002,
    } ));
}

sub _get_cached_result {
    my $self = shift;
    my $name  = shift;
    return($self->cache->get($name));
}

package Socialtext::FetchRSS::Wafl;

use Socialtext::Formatter::WaflPhrase;
use base 'Socialtext::Formatter::WaflPhraseDiv';
use Apache::Request;

sub html {
    my $self = shift;
    my ($url, $full, $expire) = split(/,?\s+/, $self->arguments);
    return $self->syntax_error unless $url;
    return $self->syntax_error("Recursive Fetchrss")
        if $self->_is_recursive($url);
    my $feed = $self->hub->fetchrss->get_feed($url, $expire);
    $self->hub->template->process('fetchrss.html',
        full => $full,
        method => $self->method,
        fetchrss_url => $url,
        feed => $feed,
        fetchrss_error => $self->hub->fetchrss->error,
    );
}

# This is a hack to prevent the system from recursing when we call
# a feed that will include this page. Because multiple http requests
# are involved here, this can't be done with an in process semaphore.
# Could potentially do something on disk.
#
# $current_url is just the path of the uri. No query string, no host
# etc.
sub _is_recursive {
    return 0 unless $ENV{MOD_PERL};
    my $self = shift;
    my $url = shift;
    # REVIEW: is there somewhere else to get the url of the current request?
    my $current_url = Apache::Request->instance( Apache->request )->uri;
    $url =~ s/\?.*\z//;
    return 1 if $url =~ /$current_url\z/;
    return 0;
}

package Socialtext::FetchRSSPlugin;



1;

__END__

=head1 NAME

Socialtext::FetchRSSPlugin - Wafl Phrase for including RSS or Atom feeds in a Page

=head1 DESCRIPTION

  {fetchrss <feed url> [full] [expire]}

Socialtext::FetchRSSPlugin retrieves and caches an RSS or Atom feeds from a blog,
news site, wiki, wherever and presents it in a page. It can optionally display
the description text for each item, or just the headline. Cache expiration
times for each phrase may be set, or a default can be set in the code.

=head1 AUTHORS

This code is derived from L<Kwiki::FetchRSS> by Alex Goller and 
Chris Dent <cdent@burningchrome.com>

=head1 SEE ALSO

L<Kwiki>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005, the authors

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

