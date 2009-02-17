use strict;
use Test::WWW::Mechanize;
use Test::More qw(no_plan);

my $url = 'http://powerball.com/powerball/pb_nbr_search.asp';
my $mech = Test::WWW::Mechanize->new();
$mech->get_ok( $url );
$mech->success or die "Can't get the search page for $url";
        $mech->submit_form(
        form_name => 'search',
        fields => {
                startDate  => '5/9/2007',
                endDate    => '5/9/2007',
                set0num0   => '22',
                set0num1   => '22',
                set0num2   => '22',
                set0num3   => '22',
                set0num4   => '22',

                set1num0   => '11',
                showPrizes => 1,
        },
        );

$mech->content_contains("Sorry, no matches found");



