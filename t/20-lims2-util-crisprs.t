#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;
use File::Temp;
use YAML::Any;

use Data::Dumper;

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
is scalar @lines, 3, 'correct number of lines in csv';


#NOTE:
#the oligos might not be correct. I don't know if we need to add a G to the oligo append sequence or not
#i need to get stuff farmed and this function isn't used currently so i'm leaving it like this.
my @data = (
    [ #headers
        qw( 
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
        )
    ],
    [ #first crispr
        'Gypa',
        'ENSMUSG00000051839',
        'ENSMUSE00000517176',
        5,
        1,
        'CAGGAAAATCGTGTTGAATTGG (-)',
        0,
        1,
        3,
        4,
        'ACCGCAGGAAAATCGTGTTGAAT',
        'AAACATTCAACACGATTTTCCTG',
    ],
    [ #second crispr
        'Gypa',
        'ENSMUSG00000051839',
        'ENSMUSE00000517176',
        5,
        1,
        'AATCGTGTTGAATTGGTGACGG (-)',
        1,
        4,
        12,
        17,
        'ACCGAATCGTGTTGAATTGGTGA',
        'AAACTCACCAATTCAACACGATT',
    ],
);

is $lines[0], join( ",", @{ $data[0] } ), 'csv headers match'; #headers line
is $lines[1], join( ",", @{ $data[1] } ), 'csv line 1 matches'; #data line
is $lines[2], join( ",", @{ $data[2] } ), 'csv line 2 matches';

note( 'Check db yaml works' );

ok $c->create_db_yaml, 'db yaml can be created';
ok -e $c->get_filename( 'db' );

#make sure the yaml data is what we expect for this exon
my @db_data = (
    { #first crispr
      off_targets => [
            {
              chr_start  => 12326336,
              chr_end    => 12326357,
              type       => 'Exonic',
              chr_strand => 1,
              chr_name   => '17'
            },
            {
              chr_start => 59412639,
              chr_end => 59412660,
              type => 'Intronic',
              chr_strand => -1,
              chr_name => '6'
            },
            {
              chr_start => 32529603,
              chr_end => 32529624,
              type => 'Intronic',
              chr_strand => -1,
              chr_name => '16'
            },
            {
              chr_start => 41095955,
              chr_end => 41095976,
              type => 'Intronic',
              chr_strand => -1,
              chr_name => '9'
            },
            {
              chr_start => 40312720,
              chr_end => 40312741,
              type => 'Intronic',
              chr_strand => -1,
              chr_name => '11'
            },
            {
              chr_start => 75172395,
              chr_end => 75172416,
              type => 'Intergenic',
              chr_strand => 1,
              chr_name => 'X'
            },
            {
              chr_start => 15271049,
              chr_end => 15271070,
              type => 'Intergenic',
              chr_strand => -1,
              chr_name => 'X'
            },
            {
              chr_start => 61607455,
              chr_end => 61607476,
              type => 'Intergenic',
              chr_strand => 1,
              chr_name => '18'
            },
            {
              chr_start => 118503908,
              chr_end => 118503929,
              type => 'Intergenic',
              chr_strand => 1,
              chr_name => '7'
            },
            {
              chr_start => 52180908,
              chr_end => 52180929,
              type => 'Intergenic',
              chr_strand => -1,
              chr_name => '7'
            },
            {
              chr_start => 124870322,
              chr_end => 124870343,
              type => 'Intergenic',
              chr_strand => -1,
              chr_name => '7'
            },
            {
              chr_start => 106107157,
              chr_end => 106107178,
              type => 'Intergenic',
              chr_strand => 1,
              chr_name => '5'
            },
            {
              chr_start => 145978317,
              chr_end => 145978338,
              type => 'Intergenic',
              chr_strand => -1,
              chr_name => '1'
            },
            {
              chr_start => 75375187,
              chr_end => 75375208,
              type => 'Intergenic',
              chr_strand => -1,
              chr_name => '8'
            },
            {
              chr_start => 39565765,
              chr_end => 39565786,
              type => 'Intergenic',
              chr_strand => 1,
              chr_name => '13'
            },
            {
              chr_start => 39158181,
              chr_end => 39158202,
              type => 'Intergenic',
              chr_strand => -1,
              chr_name => '16'
            },
            {
              chr_start => 92569574,
              chr_end => 92569595,
              type => 'Intergenic',
              chr_strand => 1,
              chr_name => '3'
            }
                      ],
      off_target_algorithm => 'strict',
      off_target_outlier => '',
      type => 'Exonic',
      off_target_summary => '{Exons: 1, Introns: 4, Intergenic: 12}',
      seq => 'AATCGTGTTGAATTGGTGACGG',
      locus => {
           chr_start  => 80503065,
           chr_end    => 80503086,
           chr_strand => '-1',
           chr_name   => '8'
        }
    },
    { #second crispr
        locus => {
            chr_end    => '80503092',
            chr_name   => '8',
            chr_start  => '80503071',
            chr_strand => '-1',
        },
        off_target_algorithm => 'strict',
        off_target_outlier   => '',
        off_target_summary   => '{Exons: 0, Introns: 1, Intergenic: 3}',
        off_targets => [
            {
                chr_end    => '41697323',
                chr_name   => '3',
                chr_start  => '41697302',
                chr_strand => '-1',
                type       => 'Intronic',
            },
            {
                chr_end    => '41256691',
                chr_name   => '6',
                chr_start  => '41256670',
                chr_strand => '1',
                type       => 'Intergenic',
            },
            {
                chr_end    => '96547291',
                chr_name   => '8',
                chr_start  => '96547270',
                chr_strand => '1',
                type       => 'Intergenic',
            },
            {
                chr_end    => '71395183',
                chr_name   => '15',
                chr_start  => '71395162',
                chr_strand => '1',
                type       => 'Intergenic',
            },
        ],
        seq  => 'CAGGAAAATCGTGTTGAATTGG',
        type => 'Exonic',
    },
);

is_deeply \@db_data, [ YAML::Any::LoadFile( $c->get_filename( 'db' )->stringify ) ], 'db output data matches';

done_testing;
