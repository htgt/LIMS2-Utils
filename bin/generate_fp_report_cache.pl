#!/usr/bin/env perl
use strict;
use warnings;

use WWW::Mechanize;
use Sys::Hostname;
use Log::Log4perl ':easy';
use Getopt::Long;
use Pod::Usage;

my $log_level = $INFO;

Log::Log4perl->easy_init( { level => $log_level, layout => 'fp_cache on %H %d [%p]  %m%n', } );


# get args

my $cache_server = 'production';
GetOptions(
    'help'           => sub { pod2usage( -verbose    => 1 ) },
    'man'            => sub { pod2usage( -verbose    => 2 ) },
    'cache_server=s' => \$cache_server,
    'debug'          => sub { $log_level = $DEBUG },
) or pod2usage(2);


# from the provided args get the webapp url, default to live

my $base_path;
for ($cache_server) {
    if    (/production/) { INFO "Selected $cache_server server";
                            $base_path = "http://www.sanger.ac.uk/htgt/lims2"; }
    elsif (/staging/)    { INFO "Selected $cache_server server";
                            $base_path = "http://www.sanger.ac.uk/htgt/lims2/staging"; }
    elsif (/^\d+$/)      { INFO "Selected t87-dev server on port $cache_server";
                            $base_path = "http://t87-dev.internal.sanger.ac.uk:$cache_server"; }
    else                 { die ERROR "Invalid cache_server provided. valid options: production, staging, and a port number for t87-dev." }
}


# create folder if does not exist

my $report_name_leader = "/opt/t87/local/report_cache/lims2_cache_fp_report/$cache_server/";
unless(-d $report_name_leader){
    mkdir $report_name_leader or die ERROR "Cannot create folder $report_name_leader";
}

my $report_name_trailer = '.html';
my $report_name_trailer_full = '_full.html';
my $csv_name_trailer = '.csv';
my %front_page_url = (
    'human' => ("$base_path/public_reports/sponsor_report?generate_cache=1&species=Human"),
    'mouse' => ("$base_path/public_reports/sponsor_report?generate_cache=1&species=Mouse"),
);

# Write an html cache of the front page sub-reports


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
INFO 'Using Human URL: ' . $front_page_url{'human'};
INFO 'Using Mouse URL: ' . $front_page_url{'mouse'};

cache_reports( 'human', @human_link_names);
cache_reports( 'mouse', @mouse_link_names);

INFO 'Completed cache generation for front page reports';

exit();

#================

sub cache_reports {
    my $species = shift;
    my @link_names = @_;

    my $mech = WWW::Mechanize->new();

    INFO "..will cache these $species reports:";
    foreach my $name ( @link_names ) {
        INFO '.... ' . $name;
    }

    my $first_time_species = 1;

    foreach my $name ( @link_names ) {
        my $r; # The server's HTTP::Response
        INFO 'Fetch top level ' . $species . ' page...';
        $r = $mech->get( $front_page_url{$species} );
        server_responder( $r );
        if ( $first_time_species ) {
            cache_front_page( $mech, $species );
            $first_time_species = 0;
        }
        INFO 'Fetching page for ' . $name . ' report...';
        $r = $mech->follow_link( url_regex => qr/$name/ );
        server_responder( $r );
        cache_sub_page( $mech, $name );
        cache_sub_page_full( $mech, $name );
        cache_csv_content( $mech, $name );
    }
    return;
}

sub cache_front_page {
    my $mech = shift;
    my $species = shift;

    my $content = $mech->content();

    $content =~ s/sponsor_report\/[^\/]*\/([^\/]*)\/Genes/cached_sponsor_report\/$1/g;
    $content =~ s/without_cache/with_cache/g;
    $content =~ s/(?<=[^:])\/\/+/\//g;

    cache_report_content( $content, $species );

    return;
}

sub cache_sub_page {
    my $mech = shift;
    my $species = shift;

    my $content = $mech->content();
    $content =~ s/sponsor_report\/[^\/]*\/([^\/]*)\/Genes[^>]*type=full/cached_sponsor_report_full\/$1/g;
    $content =~ s/sponsor_report\/[^\/]*\/([^\/]*)\/Genes[^>]*csv=1/cached_sponsor_csv\/$1/g;
    $content =~ s/without_cache/with_cache/g;
    $content =~ s/(?<=[^:])\/\/+/\//g;

    cache_report_content( $content, $species );
    return;
}

sub cache_sub_page_full {
    my $mech = shift;
    my $species = shift;

    my $r = $mech->follow_link( url_regex => qr/type=full/ );
    server_responder( $r );

    my $content = $mech->content();
    $content =~ s/sponsor_report\/[^\/]*\/([^\/]*)\/Genes[^>]*type=simple/cached_sponsor_report\/$1/g;
    $content =~ s/sponsor_report\/[^\/]*\/([^\/]*)\/Genes[^>]*csv=1/cached_sponsor_csv\/$1/g;
    $content =~ s/without_cache/with_cache/g;
    $content =~ s/(?<=[^:])\/\/+/\//g;

    my $report_file_name = report_file_full( $species );
    INFO 'Writing html for ' . $species . ' full report to ' . $report_file_name;
    open( my $html_file_h, ">:encoding(UTF-8)", $report_file_name )
        or die ERROR "Unable to open $report_file_name: $!";
    print $html_file_h $content;
    close( $html_file_h )
        or die ERROR "Unable to close $report_file_name: $!";
    my $host = hostname;
    if ( $host eq 't87-batch' ) { # t87-batch does not seem able to access $ENV{'HOSTNAME'}!
        copy_file_to_remote_storage( $report_file_name );
    }

    return;
}

sub cache_report_content {
    my $sub_page_html = shift;
    my $name = shift;

    my $report_file_name = report_file( $name );
    INFO 'Writing html for ' . $name . ' simple report to ' . $report_file_name;
    open( my $html_file_h, ">:encoding(UTF-8)", $report_file_name )
        or die ERROR "Unable to open $report_file_name: $!";
    print $html_file_h $sub_page_html;
    close( $html_file_h )
        or die ERROR "Unable to close $report_file_name: $!";
    my $host = hostname;
    if ( $host eq 't87-batch' ) { # t87-batch does not seem able to access $ENV{'HOSTNAME'}!
        copy_file_to_remote_storage( $report_file_name );
    }
    return;
}


sub cache_csv_content {
    my $mech = shift;
    my $name = shift;

    INFO 'Generating csv for ' . $name . ' report';
    my $r = $mech->follow_link( url_regex => qr/csv=1/ );
    server_responder( $r );

    my $csv_page = $mech->content();
    my $csv_file_name = csv_file( $name );
    INFO 'Writing csv download file for ' . $name .  ' to ' . $csv_file_name;
    open( my $csv_file_h, ">:encoding(UTF-8)", $csv_file_name )
        or die ERROR "Unable to open $csv_file_name: $!";
    print $csv_file_h $csv_page;
    close( $csv_file_h )
        or die ERROR "Unable to close $csv_file_name: $!";
    my $host = hostname;
    if ( $host eq 't87-batch' ) { # t87-batch does not seem able to access $ENV{'HOSTNAME'}!
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

sub report_file_full {
    my $this_report = shift;

    $this_report =~ s/\ /_/g;

    return $report_name_leader . $this_report . $report_name_trailer_full;
}


sub csv_file {
    my $this_csv = shift;

    $this_csv =~ s/\ /_/g;

    return $report_name_leader . $this_csv . $csv_name_trailer;
}


sub copy_file_to_remote_storage {
    my $report_file_name = shift;

    if (system(
        'scp',
        '-q',
        '-r',
        '-B',
        $report_file_name,
        't87svc@t87-catalyst:' . $report_file_name,
    )){
        ERROR ("Failed to copy report $report_file_name to t87-catalyst: $?");
    }
    else {
        INFO ("Copied report $report_file_name to t87-catalyst");
    }
    return;
}

__END__

=head1 NAME

generate_fp_report_cache.pl - regenerates the cached front page report.

=head1 SYNOPSIS

  generate_fp_report_cache.pl [options]

      --help            Display a brief help message
      --man             Display the manual page
      --debug           Debug output
      --cache_server    Sets the cache_server. Default production, staging optional, port number for t87-dev devel.

IMPORTANT:
LIMS2_CACHE_SERVER env variable can be set to production, staging, or a port number that will represent the t87-dev port server to be used.
By default production is used.

=head1 DESCRIPTION

Transfer one bac, plus all its associated data from one database to another.
Used to help generate fixture data for test.

=head1 BUGS

None reported... yet.

=head1 TODO

=cut
