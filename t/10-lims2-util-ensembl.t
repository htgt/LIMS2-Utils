
use strict;
use warnings FATAL => 'all';

use Test::Most;

use_ok 'LIMS2::Util::EnsEMBL';

ok my $u = LIMS2::Util::EnsEMBL->new, 'constructor returns';

is $u->species, 'mouse', 'default species is mouse';

can_ok $u, 'gene_adaptor';

isa_ok $u->gene_adaptor, 'Bio::EnsEMBL::DBSQL::GeneAdaptor';

done_testing;
