#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Test::Socialtext;
use strict;
use warnings;

use lib 'lib';

use Cwd ();
use Test::Base 0.52 -Base;
use Socialtext::Base;
use Test::Builder;
use Test::Socialtext::Environment;
use YAML;
use File::Temp qw/tempdir/;
use File::Spec;

# Set this to 1 to get rid of that stupid "but matched them out of order"
# warning.
our $Order_doesnt_matter = 0;

our @EXPORT = qw(
    fixtures
    new_hub
    SSS
    run_smarter_like
    smarter_like
    smarter_unlike
    ceqlotron_run_synchronously
    setup_test_appconfig_dir
);

our @EXPORT_OK = qw(
    content_pane 
    main_hub
    run_manifest
    check_manifest
);

{
    my $builder = Test::Builder->new();
    my $fh = $builder->output();
    # Get around syntax checking warnings
    if (defined $fh) {
        binmode $fh, ':utf8';
        $builder->output($fh);
    }
}

sub fixtures () {
    $ENV{NLW_CONFIG} = Cwd::cwd . '/t/tmp/etc/socialtext/socialtext.conf';

    Test::Socialtext::Environment->CreateEnvironment( fixtures => [ @_ ] );
}

sub run_smarter_like() {
    (my ($self), @_) = find_my_self(@_);
    my $string_section = shift;
    my $regexp_section = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    for my $block ($self->blocks) {
        local $SIG{__DIE__};
        smarter_like(
            $block->$string_section,
            $block->$regexp_section,
            $block->name
        );
    }
}

sub smarter_like() {
    my $str = shift;
    my $re = shift;
    my $name = shift;
    my $order_doesnt_matter = shift || 0;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my @res = split /\n/, $re;
    for my $i (0 .. $#res) {
        my $x = qr/$res[$i]/;
        unless ($str =~ $x) {
            test_more_fail(
                "The string: '$str'\n"
                . "...doesn't match $x (line $i of regexp)",
                $name
            );
            return;
        }
    }
    my $mashed = join '.*', @res;
    $mashed = qr/$mashed/sm;
    die "This looks like a crazy regexp:\n\t$mashed is a crazy regexp"
        if $mashed =~ /\.[?*]\.[?*]/;
    if (!$order_doesnt_matter) {
        unless ($str =~ $mashed) {
            test_more_fail(
                "The string: '$str'\n"
                . "...matched all the parts of $mashed\n"
                . "...but didn't match them in order.",
                $name
            );
            return;
        }
    }
    ok 1, "$name - success";
}

sub smarter_unlike() {
    my $str = shift;
    my $re = shift;
    my $name = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my @res = split /\n/, $re;
    for my $i (0 .. $#res) {
        my $x = qr/$res[$i]/;
        if ($str =~ $x) {
            test_more_fail(
                "The string: '$str'\n"
                . "...matched $x (line $i of regexp)",
                $name
            );
            return;
        }
    }
    pass( "$name - success" );
}

sub ceqlotron_run_synchronously() {
    # We have to do this here because at compile time, gen-config may
    # not have yet created the appconfig file, and Socialtext::Ceqlotron uses
    # Socialtext::AppConfig.
    require Socialtext::Ceqlotron;
    import Socialtext::Ceqlotron;

    # Temporarily override ceqlotron_synchronous.
    my $prev_appconfig = $ENV{NLW_APPCONFIG} || '';
    local $ENV{NLW_APPCONFIG} = "ceqlotron_synchronous=1,$prev_appconfig";

    # Actually run the queue.
    Socialtext::Ceqlotron::run_current_queue();
}

# Create a temp directory and setup an AppConfig using that directory.
sub setup_test_appconfig_dir {
    my %opts = @_;

    # We want our own dir because when we try to create files later,
    # we need to make sure we're not trying to overwrite a file
    # someone else created.
    my $dir = $opts{dir} || tempdir( CLEANUP => 1 );

    # Cannot use Socialtext::File::catfile here because it depends on
    # Socialtext::AppConfig, and we don't want it reading the wrong config
    # file.
    my $config_file = File::Spec->catfile( $dir, 'socialtext.conf' );

    open(my $config_fh, ">$config_file")
        or die "Cannot open to $config_file: $!";

    select my $old = $config_fh; 
    $| = 1;  # turn on autoflush
    select $old;
    print $config_fh YAML::Dump($opts{config_data});
    close $config_fh or die "Can't write to $config_file: $!";
    return $config_file if $opts{write_config_only};

    require Socialtext::AppConfig;
    Socialtext::AppConfig->new(
        file => $config_file,
        _singleton => 1,
    );
    return $config_file;
}

sub test_more_fail() {
    my $str = shift;
    my $test_name = shift || '';
    warn $str; # This doesn't get shown unless in verbose mode.
    Test::More::fail($test_name); # to get the counts right.
}

sub run_manifest() {
    (my ($self), @_) = find_my_self(@_);
    for my $block ($self->blocks) {
        $self->check_manifest($block) 
          if exists $block->{manifest};
    }
}

sub check_manifest {
    my $block = shift;
    my @manifest = $block->manifest;
    my @unfound = grep not(-e), @manifest;
    my $message = 'expected files exist';
    if (@unfound) {
        warn "$_ does not exist\n" for @unfound;
        $message = sprintf "Couldn't find %s of %s paths\n",
          scalar(@unfound),
          scalar(@manifest);
    }
    ok(0 == scalar @unfound, $message);
}

sub new_hub() {
    no warnings 'once';
    my $name = shift or die "No name provided to new_hub\n";
    my $hub = Test::Socialtext::Environment->instance()->hub_for_workspace($name);
    $Test::Socialtext::Filter::main_hub = $hub;
    return $hub;
}

my $main_hub;

sub main_hub {
    $main_hub = shift if @_;
    $main_hub ||= Test::Socialtext::new_hub('admin');
    return $main_hub;
}

sub SSS() {
    my $sh = $ENV{SHELL} || 'sh';
    system("$sh > `tty`");
    return @_;
}

package Test::Socialtext::Filter;
use strict;
use warnings;

use base 'Test::Base::Filter';

# Add Test::Base filters that are specific to NLW here. If they are really
# generic and interesting I'll move them into Test::Base

sub interpolate_global_scalars {
    map {
        s/"/\\"/g;
        s/@/\\@/g;
        $_ = eval qq{"$_"};
        die "Error interpolating '$_': $@" 
          if $@;
        $_;
    } @_;
}

sub tmp_nlwroot_path {
    map { 't/tmp/' . $_ } @_;
}

# Regexps with the '#' character seem to get messed up.
sub literal_lines_regexp {
    $self->assert_scalar(@_);
    my @lines = $self->lines(@_);
    @lines = $self->chomp(@lines);
    my $string = join '', map {
        # REVIEW: This is fragile and needs research.
        s/([\$\@\}])/\\$1/g;
        "\\Q$_\\E.*?\n";
    } @lines;
    my $flags = $Test::Base::Filter::arguments;
    $flags = 'xs' unless defined $flags;

    my $regexp = eval "qr{$string}$flags";
    die $@ if $@;
    return $regexp;
}

sub wiki_to_html {
    $self->assert_scalar(@_);
    Test::Socialtext::main_hub()->formatter->text_to_html(shift);
}

sub wrap_p_tags {
    $self->assert_scalar(@_);
    sprintf qq{<p>\n%s<\/p>\n}, shift;
}

sub wrap_wiki_div {
    $self->assert_scalar(@_);
    sprintf qq{<div class="wiki">\n%s<\/div>\n}, shift;
}

sub new_page {
    $self->assert_scalar(@_);
    my $hub = Test::Socialtext::main_hub();
    my $page = $hub->pages->new_page_from_any(shift);
    $page->metadata->update( user => $hub->current_user );
    return $page;
}

sub store_new_page {
    $self->assert_scalar(@_);
    my $page = $self->new_page(shift);
    $page->store( user => Test::Socialtext::main_hub()->current_user );
    return $page;
}

sub content_pane {
    my $html = shift;
    $html =~ s/
        .*(
        <div\ id="page-container">
        .*
        <td\ class="page-center-control-sidebar-cell"
        ).*
    /$1/xs;
    $html
}

sub _cleanerr() {
    my $output = shift;
    $output =~ s/^.*index.cgi: //gm;
    my @lines = split /\n/, $output;
    pop @lines;
    if (@lines > 15) {
        push @lines, "\n...more above\n", @lines[0..15]
    }
    join "\n", @lines;
}

1;

