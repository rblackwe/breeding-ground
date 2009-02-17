#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::RtfExportPlugin;
use warnings;
use strict;

use base 'Socialtext::Plugin';
use Class::Field 'const';
use Imager;

=head1 NAME

Socialtext::RtfExportPlugin - Export a Workspace Page to RTF

=head1 DESCRIPTION

This module provides a system for outputting an RTF version of
a workspace page or pages that the user may save. The system works by
creating an HTML version of the pages and then translating that
version to RTF.

The translation is performed by an inner class
L<HTML::FormatRTFWithImages>, described below.

=head1 METHODS

=cut

sub class_id {'rtf_export'};
const class_title => 'Word Export';
const cgi_class   => 'Socialtext::RtfExportPlugin::CGI';

sub register {
    my $self     = shift;
    my $registry = shift;

    # REMEMBER: When we display the action in the UI we should probably
    # make it index.cgi/$page_name.rtf?action=rtf_export;page_name=$page_name
    # this will make the file save with a good name. We can also use
    # Content-Disposition as with attachments.
    $registry->add( action => 'rtf_export' );
    # We want this turned off while the feature is still being tested.
    # $registry->add( tool   => 'Export to Word', 'rtf_export' );
}

=head2 rtf_export

An action callable by the web interface to return an RTF
version of multiple pages named in the CGI page variable C<page_selected>.

=cut
sub rtf_export {
    my $self = shift;

    my @page_names = $self->cgi->page_selected;
    if ( 0 == @page_names ) {
        return "Error:<pre>No pages selected for export</pre>\n";
    }

    my $content;
    $self->export( \@page_names, \$content );

    my $filename = $self->cgi->filename || "$page_names[0].rtf";
    $self->hub->headers->add_attachment(
        filename => $filename,
        len => length($content),
        type => 'text/rtf',
    );
    $self->hub->headers->print;

    print $content;

    # If we always load this it breaks when we try to just compile the
    # module outside of mod_perl - this will be fixed in HTML::Mason
    # 1.33 (not released yet)
    require Socialtext::WebApp;
    Socialtext::WebApp::Exception::ContentSent->throw();
}

=head2 export($page_name, \$content)

Place an RTF formatted version of the pages specified by C<$page_name> in the
current workspace in the scalar reference C<$content>.

C<$page_names> can be a listref or a single string.

=cut
sub export {
    my $self        = shift;
    my $page_name   = shift;
    my $content_ref = shift;

    my @page_names = ref $page_name ? @$page_name : ($page_name);

    # FIXME: In multipage only, need H1s or somesuch to put page names atop
    # each page.
    my $html = join "\n<HR/>\n", map { $self->_get_html($_) } @page_names;

    $$content_ref = HTML::FormatRTFWithImages->format_string(
        $html,
        fontname_headings => "Verdana",
    );

}

sub _get_html {
    my $self = shift;
    my $page_name = shift;
    my $page = $self->hub->pages->new_from_name( $page_name );

    # FIXME: Add special link dictionary here.
    return "<html><head><title>"
        . $page->metadata->Subject
        . "</title><body>"
        . $page->to_absolute_html()
        . "</body></html>";
}

=head1 NAME

HTML::FormatRTFWithImages - Translate HTML into RTF, including images.

=cut

# REVIEW: Extract somewhere else?
package HTML::FormatRTFWithImages;
use base 'HTML::FormatRTF';

=head1 DESCRIPTION

A subclass of L<HTML::FormatRTF> that adds support for hyperlinks
and images.

=head1 LIMITATIONS

The output is pretty staid but we can tweak that.

Images that are formatted as JPEG, PNG, of GIF work. Other image
support may be possible, but would require a fair amount of work.

Images are satisfied by retrieving them over HTTP which presents
authentication issues. We are trying to surmount this by
proxying our existing cookie right out to another request.
Dastardly!

GIF handling is done by translating GIF to PNG using L<Imager>.

There is limited support for Tables. Since HTML and RTF tables
have fundamentally different models, perfect translation is
very difficult.

=cut
use Apache::Cookie;
use File::Temp;
use LWP::UserAgent;
use RTF::Writer qw(rtfesc);
use RTF::Writer::TableRowDecl;

my $InHref = 0;
my $In_Table = 0;

# Make the DEL tag, which Socialtext uses rather than S or STRIKE, work the
# same as the STRIKE tag.  By default, HTML::FormatRTF throws content inside
# DEL tags away.
{
    no warnings 'once';
    
    *del_start = __PACKAGE__->can('strike_start');
    *del_end   = __PACKAGE__->can('strike_end');
}

# create a HYPERLINK field anywhere we have a hyperlink in the source.
# See: http://www.biblioscape.com/rtf15_spec.htm#Heading59
#
# \ul is for underline
# \cf2 sets the foreground color of the following text to the
#      color described in slot 2 (from 0) of the color table
#      described in the prolog of the document. By default
#      that is [default, red, blue].
sub a_start {
    my ($self, $node) = @_;

    my $href = $node->attr('href');
    if ($href) {
        my $out;
        if ($In_Table) {
            $out
                = "{\\field{\\*\\fldinst HYPERLINK $href}{\\fldrslt \\pard\\intbl \\ul\\cf2 ";
        }
        else {
            $out = "{\\field{\\*\\fldinst HYPERLINK $href}{\\fldrslt \\pard \\ul\\cf2 ";
        }
        $InHref = 1;
        $self->out(\ $out);
    }
}

sub a_end {
    my ($self, $node) = @_;
    $InHref = 0;
    $self->out(\ ' }}');
}

# REVIEW: use object fields?
sub table_start {
    my $self = shift;
    $In_Table = 1;
    $self->out( \'\par\pard' );
}

sub table_end {
    $In_Table = 0;
}

sub tr_start {
    my ($self, $node) = @_;
    my $string;
    my $h = RTF::Writer->new_to_string( \$string );
    my @cells;

    # REVIEW: We need to set a width for the table cells, but in
    # HTML we don't really have a point of reference. We don't know
    # how wide the cells will be so we just divide the page by the
    # number of cells to come up with the TWIPS per page.
    @cells = $node->find_by_tag_name('td');
    my $width = int((6.5 * 1440) / scalar(@cells));
    my $tr_decl
        = RTF::Writer::TableRowDecl->new( widths => [ map {$width} @cells ] );

    $h->row(
        $tr_decl,
        map {
            $self->_each_td($_)
            } @cells
    );
    $self->out(\ $string);
    return 0;
}

sub _each_td {
    my $self = shift;
    my $td   = shift;

    my $formatter = HTML::FormatRTFWithImages->new(
        fontname_headings => "Verdana",
    );
    $formatter->{output} = [];
    # perform our own traverse becase we
    # don't want to use the begin found in format()
    foreach my $node ( $td->content_list() ) {
        if ( ref $node ) {
            $node->traverse(
                sub {
                    my ( $node, $start, $depth ) = @_;
                    if ( ref $node ) {
                        my $tag = $node->tag;
                        my $func = $tag . '_' . ( $start ? 'start' : 'end' );
                        if ( $formatter->can($func) ) {
                            return $formatter->$func($node);
                        }
                        else {
                            return 1;
                        }
                    }
                    else {
                        $formatter->textflow($node);
                    }
                    0;
                }
            );
        }
        else { $formatter->textflow($node); }
    }
    # REVIEW: There's much stinkiness here, but this worked after
    # a great deal of futzing around.
    my $output = join '', @{$formatter->{output}}, "\n";
    my $para   = $formatter->{Para};
    return ($output =~ /^\s*$/s ? \$para : \$output);
}

sub td_start {
    my ($self, $node) = @_;
    return 1;
}

sub img_start {
    my ($self, $node) = @_;
    my $src = $node->attr('src');

    if ($src) {
        return if $self->_get_remote_image($src);
    }

    $self->SUPER::img_start($node);
}

sub _write_image {
    my $self            = shift;
    my $image_file_name = shift;
    my $string;
    my $h = RTF::Writer->new_to_string( \$string );
    $h->print($h->image(
        filename => $image_file_name,
    ));
    $self->out(\ $string);
}

# retrieve a png, jpeg or gif and write it into the rtf file
# REVIEW: this warns on error conditions but carries on
sub _get_remote_image {
    my $self = shift;
    my $src  = shift;

    my $ua = LWP::UserAgent->new;

    $self->_proxy_cookies( $src, $ua );

    my $response = $ua->get($src);
    if ( $response->is_success ) {
        my $content_type = $response->header('content-type');
        if ( $content_type =~ /(png|jpe?g)$/i ) {
            eval { $self->_write_content( $response->content ); };
            return 1 unless $@;
            warn "unable to retrieve and write image: $@";
        }
        elsif ( $content_type =~ /gif$/i ) {
            eval { $self->_write_content( $self->_gif_to_png( $response->content ) ); };
            return 1 unless $@;
            warn "unable to translate image posing as gif: $@";
        }
    }

    return 0;
}

# turn a string reprsenting a gif into a string
# representing a png
sub _gif_to_png {
    my $self       = shift;
    my $gif_string = shift;
    my $png_string;

    my $image = new Imager;
    $image->read( data => $gif_string, type => 'gif' )
        or (die "unable to read gif from string ", $image->errstr);
    $image->write( data => \$png_string, type => 'png' )
        or (die "unable to write png ", $image->errstr);

    return $png_string;
}


# If $uri is on our own host, add the 'NLW-user' cookie to $ua's headers.
sub _proxy_cookies {
    my ( $self, $uri, $ua ) = @_;

    my $self_uri = Socialtext::URI::uri();
    if ( $uri =~ /^\Q$self_uri\E/ && Apache::Cookie->can('fetch') ) {

        # FIXME: The cookie getting code belongs abstracted into WebHelpers or
        # (more probably), into Rug.  Since the latter is not done but
        # presumably on the way, I'll leave this in here for the time being.
        # -mml 2007-01-16
        my $cookies = Apache::Cookie->fetch;
        if ($cookies) {

            # FIXME: constant
            my $cookie = $cookies->{'NLW-user'};
            if ($cookie) {
                $ua->default_header( 'Cookie' => $cookie->as_string );
            }
        }
    }
}

sub _write_content {
    my $self = shift;
    my $content = shift;

    my ($fh, $filename) = File::Temp::tempfile();
    print $fh $content || die "unable to write image to tempfile: $!";
    close $fh || die "unable to close tempfile: $!";
    $self->_write_image($filename);
}

# REVIEW: We override this for table handling: When \pard is called
# in a table it needs to be followed with \intbl
# REVIEW: Maybe this should be namespaced override thing?
sub emit_para {      # rather like showline in FormatPS
  my $self = shift;

  my $para = $self->{'Para'};
  $self->{'Para'} = undef;

  unless( defined $para ) {
   #and length $para and $para =~ m/[^ ]/
    return;
  }

  $para =~ s/^ +//s;
  $para =~ s/ +$//s;

  # And now: a not terribly clever algorithm for inserting newlines
  # at a guaranteed harmless place: after a block of whitespace
  # after the 65th column.  This was copied from RTF::Writer.
  $para =~
    s/(
       [^\cm\cj\n]{65}        # Snare 65 characters from a line
       [^\cm\cj\n\x20]{0,50}  #  and finish any current word
      )
      (\x20{1,10})(?![\cm\cj\n]) # capture some spaces not at line-end
     /$1$2\n/gx     # and put a NL before those spaces
  ;

  my $pard = $In_Table ? '\pard\intbl' : '\pard';

  $self->collect(
    sprintf( '{%s\sa%d\li%d\ri%d%s\plain'."\n",
      $pard,
      #100 +
      10 * $self->{'normal_halfpoint_size'} * ($self->{'vspace'} || 0),

      $self->{'lm'},
      $self->{'rm'},

      $self->{'center'} ? '\qc' : '\ql',
    ),

    defined($self->{'next_bullet'}) ? do {
      my $bullet = $self->{'next_bullet'};
      $self->{'next_bullet'} = undef;
      sprintf "\\fi-%d\n%s",
        4.5 * $self->{'normal_halfpoint_size'},
        ($bullet eq '*') ? "\\'95 " : (rtfesc($bullet). ". ")
    } : (),

    $para,
    "\n\\par}\n\n",
  );

  $self->{'vspace'} = undef; # we finally get to clear it here!

  return;
}


package Socialtext::RtfExportPlugin::CGI;
use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'page_selected';
cgi 'filename';

1;

=head1 AUTHOR

Socialtext, C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc. All Rights Reserved.

=cut
