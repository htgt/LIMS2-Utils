#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use LIMS2::Model;
use Log::Log4perl qw( :easy );
use LIMS2::Util::Tarmits;
use LIMS2::Util::TarmitsUpdate;
use Getopt::Long;

my $updater = LIMS2::Util::TarmitsUpdate->new({
    lims2_model      => LIMS2::Model->new({ user => 'tasks' }),
    tarmits_api      => LIMS2::Util::Tarmits->new_with_config,
    commit           => 1,
    cpg_islands_only => 1,
    mgi_ids_report   => '/nfs/users/nfs_a/af11/tmp/Cpgi_MKI_MRK.rpt',
});


$updater->lims2_to_tarmits();
