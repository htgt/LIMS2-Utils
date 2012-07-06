#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;
use LIMS2::Util::Solr;

ok my $s = LIMS2::Util::Solr->new, 'Create instance';

lives_ok {
    ok my $res = $s->query( 'cbx1' ), 'Query cbx1';
    is @{$res}, 1, 'returns 1 result';
};

lives_ok {
    ok my $res = $s->query( 'hox' ), 'Query hox';
    ok @{$res} > 1, 'returns many results';
};

lives_ok {
    ok my $res = $s->query( [ marker_symbol => 'Cbx1' ] ), 'Query Cbx1 by marker symbol';
    is @{$res}, 1, 'returns 1 result';
};

lives_ok {
    ok my $res = $s->query( [ mgi_accession_id => 'MGI:105369' ] ), 'Query MGI:105369';
    is @{$res}, 1, 'returns 1 result';
};

lives_ok {
    ok my $res = $s->query( 'hox', undef, 1 ), 'Query hox - page 1';
    ok @{$res} > 1, 'returns many results';
};

done_testing;


