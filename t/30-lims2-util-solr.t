#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;
use LIMS2::Util::Solr;

ok my $s = LIMS2::Util::Solr->new, 'Create instance';

# This solr instance is deprecated

done_testing;


