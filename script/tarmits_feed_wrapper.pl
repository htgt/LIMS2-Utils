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

my $accepted_cre_clones = $tarmits_feed->accepted_clones;

# now we have hash of curremt accepted clones in LIMS2, need to check each one is up to date in Tarmits
my $result = $tarmits_feed->check_clones_against_tarmits();