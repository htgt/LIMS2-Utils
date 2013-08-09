#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use LIMS2::Model;
use Log::Log4perl qw( :easy );
use LIMS2::Util::TarmitsFeedCreKnockin;
use Getopt::Long;                                   # Command line options

# use Data::Dumper;
# use FileHandle;

#---------------------------------------------------------------------
#  Variables
#---------------------------------------------------------------------

my $gene_id = 0;                                    # MGI gene ID
my $model = LIMS2::Model->new( user => 'tasks' );   # LIMS2 Model
my $species = 'Mouse';                              # Species
my $loglevel = $INFO;                               # Logging level

#---------------------------------------------------------------------
#  Check for input of single gene ID or if we are processing all genes
#---------------------------------------------------------------------

GetOptions(
#    'help'             => sub { pod2usage( -verbose => 1 ) },
#    'man'              => sub { pod2usage( -verbose => 2 ) },
    'debug'            => sub { $loglevel = $DEBUG },
    'gene_id=s'        => \$gene_id,
);

#---------------------------------------------------------------------
#  Initialise logging
#---------------------------------------------------------------------

my %log4perl = (
    level  => $loglevel,
    layout => '%d %p %x %m%n',  # d= date p=level msg  x=ndc value m= ?  n=?
);

Log::Log4perl->easy_init( \%log4perl );

#---------------------------------------------------------------------
#  Create a new connection Model to link to DB
#---------------------------------------------------------------------

my $tarmits_feed = LIMS2::Util::TarmitsFeedCreKnockin->new( { 'species' => $species, 'model' => $model, 'gene_id' => $gene_id, } );

#---------------------------------------------------------------------
# select all the valid clones from LIMS2 into a multi-level hash
# this section optional as es clone hash creation is lazy build
#---------------------------------------------------------------------

# Log::Log4perl::NDC->push( 'Tarmits Feed - Select From LIMS2:' );

# my $es_cre_clones = $tarmits_feed->es_clones;

# Log::Log4perl::NDC->pop;

# Log::Log4perl::NDC->push( 'Tarmits Feed - Writing out hash data:' );

# my $file = '/nfs/users/nfs_a/as28/Sandbox/tarmits_data.out';

# my $str = Data::Dumper->Dump([ $es_cre_clones ], [ 'ES Clones data' ]);

# DEBUG 'Attempting to write output file';

# my $out = new FileHandle ">$file";
# print $out $str;
# close $out;

# Log::Log4perl::NDC->pop;

#---------------------------------------------------------------------
# check es clones from LIMS2 against Tarmits and insert or update
#---------------------------------------------------------------------

Log::Log4perl::NDC->push( 'Tarmits Feed - Update Tarmits:' );

$tarmits_feed->check_clones_against_tarmits();

Log::Log4perl::NDC->pop;