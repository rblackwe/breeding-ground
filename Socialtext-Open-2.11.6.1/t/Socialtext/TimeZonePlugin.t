#!perl
#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#

use strict;
use warnings;

use Test::Socialtext;
fixtures( 'admin_no_pages' );

BEGIN {
    unless ( eval { require DateTime::Format::HTTP; 1 } ) {
        plan skip_all => 'These tests require DateTime::Format::HTTP to run.';
    }
}

use DateTime;
use Socialtext::TimeZonePlugin;

my $zones = Socialtext::TimeZonePlugin->zones;
my $hub = new_hub('admin');
my $prefs = $hub->preferences_object;

my $tz = $hub->timezone;

my @formats = qw( mmm_d d_mmm mm_dd mmm_d_yyyy d_mmm_yy yyyy_mm_dd );
my %strftime_formats = ( mmm_d      => '%b %{day}, %Y',
                         d_mmm      => '%{day}-%b-%y',
                         mm_dd      => '%Y-%m-%d',
                         mmm_d_yyyy => '%b %{day}, %Y',
                         d_mmm_yy   => '%{day}-%b-%y',
                         yyyy_mm_dd => '%Y-%m-%d',
                       );
my @dst = qw( on off auto-us never );
my @hours_display = qw( 12 24 );
my @show_seconds  = ( 0, 1 );

my @tests = 
    ( { string => '2004-10-15 09:30:05',
        is_dst => 1,
      },
      { string => '2004-12-06 15:30:31',
        is_dst => 0,
      },
    );

$_->{dt} = DateTime::Format::HTTP->parse_datetime( $_->{string}, 'UTC' ) for @tests;

my $permutations = 
  (keys %$zones) * @formats * @dst * @hours_display * @show_seconds;
my %test_numbers = ();
if ($ENV{NLW_TEST_FASTER}) 
{
    my $total_tests = 10;
    $test_numbers{int(rand($permutations))} = 1
      while scalar(keys %test_numbers) < $total_tests;
    $permutations = $total_tests;
}

plan tests => ( $permutations * @tests ) + 3;

my $formats_re = join '|', @formats;

# Is there a less grotesque way to do this?
# I don't know, but there is a _FASTER way.
my $i = 0;
foreach my $z ( keys %$zones )
{
    foreach my $f (@formats)
    {
        foreach my $dst (@dst)
        {
            foreach my $h (@hours_display)
            {
                foreach my $s (@show_seconds)
                {
                    if (not($ENV{NLW_TEST_FASTER}) or
                        exists($test_numbers{$i++}))
                    {
                        $prefs->timezone->value($z);
                        $prefs->date_display_format->value($f);
                        $prefs->dst->value($dst);
                        $prefs->time_display_12_24->value($h);
                        $prefs->time_display_seconds->value($s);
                        run_tests($prefs);
                    }
                }
            }
        }
    }
}

# These tests make sure that when the year is equal to this
# year, it is not included with the short date formats.
{
    my $date_with_this_year = 1900 + (localtime)[5] . '-12-05 10:10:10';
    $prefs->timezone->value('+0000');
    $prefs->dst->value('off');
    $prefs->time_display_12_24->value(24);
    $prefs->time_display_seconds->value(0);

    $prefs->date_display_format->value('mm_dd');
    is( $tz->date_local( $date_with_this_year ), '12-05 10:10',
        'test short date format with current year - mm_dd' );

    $prefs->date_display_format->value('d_mmm');
    is( $tz->date_local( $date_with_this_year ), '5-Dec 10:10',
        'test short date format with current year - d_mmm' );

    $prefs->date_display_format->value('mmm_d');
    is( $tz->date_local( $date_with_this_year ), 'Dec 5 10:10',
        'test short date format with current year - mmm_d' );
}

sub run_tests
{
    my $prefs = shift;

    my $tz_pref = $prefs->timezone->value;
    my $dst_pref = $prefs->dst->value;
    my $time_display_pref = $prefs->time_display_12_24->value;
    my $seconds_pref = $prefs->time_display_seconds->value;

    foreach my $test (@tests)
    {
        my $dt = $test->{dt}->clone;
        my $zone = $tz_pref;
        $zone =~ s/(?:nz|id)$//;
        $dt->set_time_zone($zone);

        if ( $dst_pref eq 'on' ||
             ( $dst_pref eq 'auto-us' && $test->{is_dst} )
           )
        {
            $dt->add( minutes => 60 );
        }

        my $strftime = $strftime_formats{ $prefs->date_display_format->value };

        $strftime .= ' ';
        $strftime .= $time_display_pref eq '12' ? '%{hour_12}' : '%H';
        $strftime .= ':%M';
        $strftime .= ':%S' if $seconds_pref;
        $strftime .= '%P' if $time_display_pref eq '12';

        is( $tz->date_local( $test->{string} ), $dt->strftime($strftime),
            "Formatting of $test->{string} (strftime = $strftime, dst = $dst_pref, zone = $tz_pref, 12/24 = $time_display_pref)" );
    }
}
