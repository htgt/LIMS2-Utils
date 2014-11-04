#!/usr/bin/env perl
use strict;
use warnings;

use WWW::Mechanize;
use Log::Log4perl ':easy';

my $report_name_leader = '/opt/t87/local/report_cache/lims2_cache_fp_report/';
my $report_name_trailer = '.html';
my $front_page_url = ($ENV{ 'LIMS2_CACHE_SERVER' } || 'http://www.sanger.ac.uk/htgt/lims2/public_reports/sponsor_report?cache_param=without_cache');
# Will not compile with // operator

# Write an html cache of the front page sub-reports
my $mech = WWW::Mechanize->new();


my $log_level = $INFO;

Log::Log4perl->easy_init( { level => $log_level, layout => 'fp_cache on %H %d [%p]  %m%n', } );

# If the names of the columns in the top page change, change the entries in link_names
# otherwise the relevant reports will not be cached.

my @human_link_names = (
    'All',
    'Experimental Cancer Genetics',
    'Mutation',
    'Pathogen',
    'Stem Cell Engineering',
    'Transfacs',
);

my @mouse_link_names = (
    'Barry Short Arm Recovery',
    'Cre Knockin',
    'EUCOMMTools Recovery',
    'MGP Recovery',
    'Pathogen Group 1',
    'Pathogen Group 2',
);

INFO 'Generating front page report cache...';
INFO 'Using URL: ' . $front_page_url;

cache_reports( 'human', @human_link_names);
cache_reports( 'mouse', @mouse_link_names);

INFO 'Completed cache generation for front page reports';

exit();

#================

sub cache_reports {
    my $species = shift;
    my @link_names = @_;

    INFO "..will cache these $species reports:";
    foreach my $name ( @link_names ) {
        INFO '.... ' . $name;
    }

    my $first_time_human = 1;
    my $first_time_mouse = 1;

    foreach my $name ( @link_names ) {
        my $r; # The server's HTTP::Response
        INFO 'Fetch top level page...';
        $r = $mech->get( $front_page_url );
        server_responder( $r );
        if ( $first_time_human ) {
            cache_front_page( $mech, $species );
            $first_time_human = 0;
            # Now we have changed the content so we now need to 
        }
        if ( $species eq 'mouse' ) {
            INFO 'Fetch mouse page...';
            $r = $mech->follow_link( url_regex => qr/species=Mouse/ );
            server_responder( $r );
            if ( $first_time_mouse ) {
                cache_front_page( $mech, $species );
                $first_time_mouse = 0;
            }
        }
        INFO 'Fetching page for ' . $name . ' report...';
        $r = $mech->follow_link( url_regex => qr/$name/ );
        server_responder( $r );
        cache_sub_page( $mech, $name );
#        cache_csv_content( $mech, $name );
    }
    return;
}

sub cache_front_page {
    my $mech = shift;
    my $species = shift;

    my $content = $mech->content();

    $content =~ s/sponsor_report\/[^\/]*\/([^\/]*)\/Genes/cached_sponsor_report\/$1/g;
    $content =~ s/without_cache/with_cache/g;
    cache_report_content( $content, $species );

    return; 
}

sub cache_sub_page {
    my $mech = shift;
    my $species = shift;

    my $content = $mech->content();
    $content =~ s/without_cache/with_cache/g;
    cache_report_content( $content, $species );
    return;
}

sub cache_report_content {
    my $sub_page_html = shift;
    my $name = shift;

    my $report_file_name = report_file( $name );
    INFO 'Writing html for ' . $name . ' report to ' . $report_file_name;
    open( my $html_file_h, ">:encoding(UTF-8)", $report_file_name )
        or die ERROR "Unable to open $report_file_name: $!";
    print $html_file_h $sub_page_html;
    close( $html_file_h )
        or die ERROR "Unable to close $report_file_name: $!";
    if ( $ENV{'HOSTNAME'} eq 't87-batch') {
        copy_file_to_remote_storage( $report_file_name );
    }
    return;
}

sub cache_csv_content {
    my $mech = shift;
    my $name = shift;

$DB::single=1;
    my $r = $mech->click( name => 'csv_download' );
    server_responder( $r );

    my $csv_page = $mech->content();
    my $csv_file_name = csv_file( $name );
    INFO 'Writing csv download file for ' . $name .  ' to ' . $csv_file_name;
    open( my $csv_file_h, ">:encoding(UTF-8)", $csv_file_name )
        or die ERROR "Unable to open $csv_file_name: $!";
    print $csv_file_h $csv_page;
    close( $csv_file_h )
        or die ERROR "Unable to close $csv_file_name: $!";
    if ( $ENV{'HOSTNAME'} eq 't87-batch') {
        copy_file_to_remote_storage( $csv_file_name );
    }

    return;
}

sub server_responder{
    my $response = shift;

    if ( $response->is_success ) {
        INFO 'Server response: ' . $response->message();
    }
    else {
        die ERROR 'Server told me: ' . $response->message();
    }
    return;
}

sub report_file {
    my $this_report = shift;

    $this_report =~ s/\ /_/g;

    return $report_name_leader . $this_report . $report_name_trailer;
}

sub copy_file_to_remote_storage {
    my $report_file_name = shift;

    system(
        'scp',
        '-q',
        '-r',
        '-B',
        $report_file_name,
        't87svc@t87-catalyst:' . $report_file_name,
    )
        or die ERROR ("Failed to copy report $report_file_name to t87-catalyst: $?");

    INFO ("Copied report $report_file_name to t87-catalyst");
    system(
        'scp',
        '-q',
        '-r',
        '-B',
        $report_file_name,
        't87svc@t87-dev:' . $report_file_name,
    )
        or die ERROR ("Failed to copy report $report_file_name to t87-dev: $?");
    INFO ("Copied report $report_file_name to t87-dev");
    return;
}


