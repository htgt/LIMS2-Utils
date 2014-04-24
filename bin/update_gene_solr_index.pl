#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use LWP::Simple;
use HTML::Entities;

use LIMS2::Model;
use LIMS2::Model::Util::DesignTargets qw( design_target_report_for_genes );
use LIMS2::Model::Constants qw( %DEFAULT_SPECIES_BUILD );
use List::Util qw(sum first);
use Log::Log4perl ':easy';



my $start_time=localtime;

my $update_file = '/var/tmp/gene_list.xml';

# Human data
my $human_file = '/var/tmp/hgnc_list.txt';


# get list of HGNC approved symbols
INFO "Getting list of HGNC genes...\n";
open (HGNC, ">$human_file");
my $url = 'http://www.genenames.org/cgi-bin/download?'.
          'col=gd_hgnc_id&'.
          'col=gd_app_sym&'.
          'col=gd_app_name&'.
          'col=md_ensembl_id&'.
          'status=Approved&'.
          'status_opt=2&'.
          'where=%28%28gd_pub_chrom_map%20not%20like%20%27%25patch%25%27%20and%20gd_pub_chrom_map%20not%20like%20%27%25alternate%20reference%20locus%25%27%29%20or%20gd_pub_chrom_map%20IS%20NULL%29&'.
          'order_by=gd_hgnc_id&'.
          'format=text&'.
          'limit=&'.
          'hgnc_dbtag=on&'.
          'submit=submit';
# save it on the new file
my $page = get($url)
or die ERROR "Could not get list of HGNC genes.\n";
print HGNC $page;
close (HGNC);


# Mouse data
my $mouse_file = '/var/tmp/mgi_list.txt';
my $mouse_location = 'ftp://ftp.informatics.jax.org/pub/reports/MRK_ENSEMBL.rpt';




# get list of MGI approved symbols
INFO "Getting list of MGI genes...\n";
my $status = getstore($mouse_location, $mouse_file);
if ( $status != 200) {
    die ERROR "Could not get list of MGI genes.\n";
}


# create the xml file to update the index
INFO "Building gene_list.xml...";
build_list();
system("rm $human_file");
system("rm $mouse_file");


INFO "Updating solr index...\n";
system("sh post.sh $update_file");
system("rm $update_file");
INFO "Done.\n";


#  End and print out totals
my $end_time=localtime;
INFO "LIMS2 gene solr index update: Start time was       : $start_time";
INFO "LIMS2 gene solr index update: Process completed at : $end_time";




# xml creation
sub build_list {

    my $model = LIMS2::Model->new( user => 'lims2' );

    my (@rows) = $model->schema->resultset('Project')->search({
        targeting_type => 'single_targeted',
    },{
        columns        => [qw/ gene_id /],
        distinct       => 1
    });


    open (GENE_LIST, ">$update_file");
    print GENE_LIST "<add>\n";

    my @gene_list = map {$_->gene_id} @rows;


    open (HUMAN_FILE, $human_file);
    while (<HUMAN_FILE>) {
        chomp;
        my $species = 'Human';
        if (/(HGNC:\d*)\t([^\t]*)\t([^\t]*)\t([^\t]*)/) {
            my ($id, $symbol, $ensembl, $name) = ($1, $2, $4, encode_entities($3) );

            print GENE_LIST "  <doc>
    <field name=\"id\">$id</field>
    <field name=\"symbol\">$symbol</field>
    <field name=\"ensembl_id\">$ensembl</field>
    <field name=\"species\">$species</field>";

            if ( first { $_ eq $id } @gene_list ) {

                # get the gibson design count
                my $report_params = {
                    type => 'simple',
                    off_target_algorithm => 'bwa',
                    crispr_types => 'pair'
                };

                my $build = $DEFAULT_SPECIES_BUILD{ lc($species) };

                my ( $designs ) = design_target_report_for_genes( $model->schema, $id, $species, $build, $report_params );

                my $design_count = sum map { $_->{ 'designs' } } @{$designs};
                if (!defined $design_count) {$design_count = 0};
                my $crispr_pairs_count = sum map { $_->{ 'crispr_pairs' } } @{$designs};
                if (!defined $crispr_pairs_count) {$crispr_pairs_count = 0};

                print GENE_LIST "
    <field name=\"design_count\">$design_count</field>
    <field name=\"crispr_pairs_count\">$crispr_pairs_count</field>";
            }

            print GENE_LIST "
  </doc>\n";

        }
    }
    close (HUMAN_FILE);


    open (MOUSE_FILE, $mouse_file);
    while (<MOUSE_FILE>) {
        chomp;
        my $species = 'Mouse';
        if (/(MGI:\d*)\t([^\t]*)\t([^\t]*)\t[^\t]*\t[^\t]*\t([^\t]*)/) {
            my ($id, $symbol, $ensembl, $name) = ($1, $2, $4, encode_entities($3) );

            print GENE_LIST "  <doc>
    <field name=\"id\">$id</field>
    <field name=\"symbol\">$symbol</field>
    <field name=\"ensembl_id\">$ensembl</field>
    <field name=\"species\">$species</field>";

            if ( first { $_ eq $id } @gene_list ) {

                # get the gibson design count
                my $report_params = {
                    type => 'simple',
                    off_target_algorithm => 'bwa',
                    crispr_types => 'pair'
                };

                my $build = $DEFAULT_SPECIES_BUILD{ lc($species) };

                my ( $designs ) = design_target_report_for_genes( $model->schema, $id, $species, $build, $report_params );

                my $design_count = sum map { $_->{ 'designs' } } @{$designs};
                if (!defined $design_count) {$design_count = 0};
                my $crispr_pairs_count = sum map { $_->{ 'crispr_pairs' } } @{$designs};
                if (!defined $crispr_pairs_count) {$crispr_pairs_count = 0};

                print GENE_LIST "
    <field name=\"design_count\">$design_count</field>
    <field name=\"crispr_pairs_count\">$crispr_pairs_count</field>";
            }

            print GENE_LIST "
  </doc>\n";

        }
    }
    close (MOUSE_FILE);


    print GENE_LIST "</add>\n";
    close (GENE_LIST);

    return;
}





