#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use LWP::Simple;
use HTML::Entities;

use List::Util qw(sum first);
use Log::Log4perl ':easy';

use Const::Fast;
const my $HUMAN_URL => 'https://www.genenames.org/cgi-bin/download?col=gd_hgnc_id&col=gd_app_sym&col=gd_app_name&col=gd_pub_chrom_map&col=md_ensembl_id&status=Approved&status_opt=2&where=&order_by=gd_app_sym_sort&format=text&limit=&hgnc_dbtag=on&submit=submit';
const my $MOUSE_URL => 'http://www.informatics.jax.org/downloads/reports/MRK_ENSEMBL.rpt';

#my $depr_mouse_location = 'ftp://ftp.informatics.jax.org/pub/reports/MGI_AllGenes.rpt';

my $start_time=localtime;

my $update_file = '/tmp/gene_list.xml';

# Human data
my $human_file = '/tmp/hgnc_list.txt';


# get list of HGNC approved symbols and save it on the new file
INFO "Getting list of HGNC genes...\n";
open my $HGNC, '>', "$human_file" or die $!;
my $page = get($HUMAN_URL)
or die ERROR "Could not get list of HGNC genes.\n";
print $HGNC $page;
close $HGNC;


# Mouse data
my $mouse_file = '/tmp/mgi_list.txt';


# get list of MGI approved symbols
INFO "Getting list of MGI genes...\n";
my $status = getstore($MOUSE_URL, $mouse_file);
if ( $status != 200) {
    die ERROR "Could not get list of MGI genes.\n";
}


# create the xml file to update the index
INFO "Building gene_list.xml...";


open my $GENE_LIST, '>' , $update_file or die $!;
open my $HUMAN_FILE, '<', $human_file or die $!;
open my $MOUSE_FILE, '<', $mouse_file or die $!;
build_list();
close $GENE_LIST;
close $HUMAN_FILE;
close $MOUSE_FILE;


system("rm $human_file");
system("rm $mouse_file");


INFO "Updating solr index...\n";
system("sh post.sh $update_file") == 0 or die "Posting update failed: $?";
system("rm $update_file") == 0 or die "File removal failed: $?";
INFO "Done.\n";


#  End and print out totals
my $end_time=localtime;
INFO "LIMS2 gene solr index update: Start time was       : $start_time";
INFO "LIMS2 gene solr index update: Process completed at : $end_time";


# xml creation
## no critic(ProhibitComplexRegexes)
sub build_list {

    print $GENE_LIST "<add>\n";

    while (<$HUMAN_FILE>) {
        chomp;
        my $species = 'Human';
        if (/(HGNC:\d*)\t([^\t]*)\t([^\t]*)\t([^qp]*)[^\t]*\t([^\t]*)/) {
            my ($id, $symbol, $ensembl, $name, $chromosome) = ($1, $2, $5, encode_entities($3), $4 );

            print $GENE_LIST <<"END";
  <doc>
    <field name=\"id\">$id</field>
    <field name=\"symbol\">$symbol</field>
    <field name=\"ensembl_id\">$ensembl</field>
    <field name=\"species\">$species</field>
    <field name=\"chromosome\">$chromosome</field>
  </doc>
END

        }
    }

    while (<$MOUSE_FILE>) {
        chomp;
        my $species = 'Mouse';
        if (/(MGI:\d*)\t([^\t]*)\t([^\t]*)\t[^\t]*\t([^\t]*)\t([^\t]*)\t[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*/) {
            my ($id, $symbol, $ensembl, $name, $chromosome) = ($1, $2, $5, encode_entities($3), $4 );

            print $GENE_LIST <<"END";
  <doc>
    <field name=\"id\">$id</field>
    <field name=\"symbol\">$symbol</field>
    <field name=\"ensembl_id\">$ensembl</field>
    <field name=\"species\">$species</field>
    <field name=\"chromosome\">$chromosome</field>
  </doc>
END

        }
    }

    print $GENE_LIST "</add>\n";

    return;
}
## use critic



