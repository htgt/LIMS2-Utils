#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use LIMS2::Model;
use Log::Log4perl qw( :easy );
use LIMS2::Util::TarmitsFeedCreKnockin;

Log::Log4perl->easy_init($DEBUG);

# Create a new connection Model to link to DB
my $model = LIMS2::Model->new( user => 'tasks' );
my $species = 'Mouse';

my $tarmits_feed = LIMS2::Util::TarmitsFeedCreKnockin->new( { 'species' => $species, 'model' => $model, } );

# select all the valid clones from LIMS2 into a multi-level hash (genes -> alleles -> targeting vectors -> clones)
my $es_cre_clones = $tarmits_feed->es_clones;

# could print out es_cre_clones hash here, also held internally in TarmitsFeedCreKnockin instance

# now we have hash of curremt es clones in LIMS2, need to insert / update them in Tarmits
my $result = $tarmits_feed->check_clones_against_tarmits();