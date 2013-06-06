#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;
use File::Temp;
use YAML::Any;

use_ok 'LIMS2::Util::Crisprs';

dies_ok { LIMS2::Util::Crisprs->new } 'constructor dies without species';
ok my $c = LIMS2::Util::Crisprs->new( species => 'human' ), 'constructor returns with species';

is $c->species, 'human', 'species set correctly';

$c->species( 'invalid' );
dies_ok { $c->get_filename( 'sites' ) } "can't get files for invalid species";

$c->species( 'mouse' );
is $c->species, 'mouse', 'species can be changed';

#create temp folder to run in
my $tmp_dir = File::Temp->newdir();

#change base dir to my our new temp dir
ok $c->base_dir( $tmp_dir->dirname ), 'can change base dir';

#make sure things can't be called out of order
dies_ok { $c->create_csv } "csv can't be created without data";
dies_ok { $c->create_db_yaml } "db yaml can't be created without data";
dies_ok { $c->write_seeds } "can't write seeds without them loaded";
dies_ok { $c->run_exonerate } "can't run exonerate without fasta file";
dies_ok { $c->process_exonerate } "can't run process exonerate without data loaded";

#exon with 1 crispr for simplicity
ok $c->find_crisprs( 'ENSMUSE00000517176' ), 'can find crisprs for exon';
ok -e $c->get_filename( 'sites' ), 'initial output exists';
ok -e $c->get_filename( 'fasta' ), 'fasta reads exist';

#could do with testing with a design as well...

ok $c->run_exonerate, 'exonerate can run';
ok -e $c->get_filename( 'exonerate' );

ok $c->process_exonerate, 'exonerate output can be processed'; 
ok -e $c->get_filename( 'final_output' );

note( 'Check csv works' );

ok $c->create_csv, 'csv can be created';
ok -e $c->get_filename( 'csv' );

#now check the data is right
my @lines = $c->get_filename( 'csv' )->slurp( chomp => 1 );
is scalar @lines, 2, 'correct number of lines in csv';

my @headers = qw( 
    Gene
    Ensembl_Gene_ID
    Ensembl_Exon_ID
    Exon_Rank
    Exon_Strand
    Crispr_Seq
    Off_Targets_Exon
    Off_Targets_Intron
    Off_Targets_Intergenic
    Total_Off_Targets
    Forward_Oligo
    Reverse_Oligo
);

my @data_row = (
    'Gypa',
    'ENSMUSG00000051839',
    'ENSMUSE00000517176',
    1,
    1,
    'GCAGGAAAATCGTGTTGAATTGG (-)',
    0,
    1,
    3,
    4,
    'ACCGCAGGAAAATCGTGTTGAAT',
    'AAACATTCAACACGATTTTCCTG',
);

is join( ",", @headers  ), $lines[0], 'csv headers match'; #headers line
is join( ",", @data_row ), $lines[1], 'csv data matches'; #data line

note( 'Check db yaml works' );

ok $c->create_db_yaml, 'db yaml can be created';
ok -e $c->get_filename( 'db' );

#make sure the yaml data is what we expect for this exon
my %data = (
    locus => {
        chr_end    => '80503093',
        chr_name   => '8',
        chr_start  => '80503071',
        chr_strand => '-1',
        comment    => '{Exons: 0, Introns: 1, Intergenic: 3}',
    },
    off_target_outlier => '',
    off_targets => [
        {
            chr_end    => '41697324',
            chr_name   => '3',
            chr_start  => '41697302',
            chr_strand => '-1',
            type       => 'Intronic',
        },
        {
            chr_end    => '41256691',
            chr_name   => '6',
            chr_start  => '41256669',
            chr_strand => '1',
            type       => 'Intergenic',
        },
        {
            chr_end    => '96547291',
            chr_name   => '8',
            chr_start  => '96547269',
            chr_strand => '1',
            type       => 'Intergenic',
        },
        {
            chr_end    => '71395183',
            chr_name   => '15',
            chr_start  => '71395161',
            chr_strand => '1',
            type       => 'Intergenic',
        },
    ],
    seq  => 'GCAGGAAAATCGTGTTGAATTGG',
    type => 'Exonic',
);

is_deeply \%data, YAML::Any::LoadFile( $c->get_filename( 'db' )->stringify ), 'db output data matches';

done_testing;
