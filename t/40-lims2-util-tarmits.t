#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;

use_ok 'LIMS2::Util::Tarmits';

#TODO: test the other parts of the api

{
    ok my $tarmits = LIMS2::Util::Tarmits->new_with_config, 'Create instance';

    isa_ok $tarmits, 'LIMS2::Util::Tarmits', 'module is correct type';

    ok my $data = $tarmits->find_allele( { id_eq => 138 } ), 'fetch allele';

    isa_ok $data, 'ARRAY', 'check data return type';

    is scalar @{$data}, 1, 'only got one allele';

    ok my $row = pop( @{$data} ), 'can get first entry';

    isa_ok $row, 'HASH', 'row is a hash';

    is $row->{id}, 138, 'allele id correct';
}

done_testing;