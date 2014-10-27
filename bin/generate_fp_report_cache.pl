#!/usr/bin/env perl
use strict;

use WWW::Mechanize;
use Log::Log4perl ':easy';

my $report_name_leader = '/var/tmp/lims2-cache-fp-report/';
my $report_name_trailer = '.html';
my $front_page_url = 'http://www.sanger.ac.uk/htgt/lims2';

# Write an html cache of the front page sub-reports
my $mech = WWW::Mechanize->new();


my $log_level = $INFO;

Log::Log4perl->easy_init( { level => $log_level, layout => 'fp_cache on %H %d [%p]  %m%n', } );

# If the names of the columns in the top page change, change the entries in link_names
# otherwise the relevant reports will not be cached.

my @link_names = ( 
    'All',
    'Experimental Cancer Genetics',
    'Mutation',
    'Pathogen',
    'Stem Cell Engineering',
    'Transfacs',
);
INFO 'Generating front page report cache...';

INFO '..will cache these reports:';
foreach my $name ( @ link_names ) {
    INFO '.... ' . $name;
}

foreach my $name ( @link_names ) {
    INFO 'Fetch top level page...';
    my $top_page = $mech->get( $front_page_url );
    INFO 'Fetching page for ' . $name . ' report...';
    my $response = $mech->follow_link( url_regex => qr/$name/ );
    my $sub_page_html = $mech->content();
    my $report_file_name = report_file( $name );
    INFO 'Writing html for ' . $name . ' report to ' . $report_file_name;
    open( my $html_file_h, ">:encoding(UTF-8)", $report_file_name )
        or die ERROR "Unable to open $report_file_name: $!";
    print $html_file_h $sub_page_html;
    close( $html_file_h )
        or die ERROR "Unable to close $report_file_name: $!";
}

sub report_file {
    my $this_report = shift;

    return $report_name_leader . $this_report . $report_name_trailer;
}

exit();

