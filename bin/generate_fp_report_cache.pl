use WWW::Mechanize;

# Write an html cache of the front page sub-reports
my $mech = WWW::Mechanize->new();

my @link_names = ( 
    'All',
    'Experimental Cancer Genetics',
    'Mutation',
    'Pathogen',
    'Stem Cell Engineering',
    'Transfacs',
);

foreach my $name ( @link_names ) {
    my $top_page = $mech->get('http://www.sanger.ac.uk/htgt/lims2' );
    print 'Fetching page for ' . $name . ' report...' . " \n";
    my $response = $mech->follow_link( url_regex => qr/$name/ );
    my $sub_page_html = $mech->content();
    print 'Writing html for ' . $name . ' report to /var/tmp' . "\n";
    open( my $html_file_h, ">:encoding(UTF-8)", "/var/tmp/lims2-cache-fp-report/$name.html" );
    print $html_file_h $sub_page_html;
    close( $html_file_h );
}

exit();

