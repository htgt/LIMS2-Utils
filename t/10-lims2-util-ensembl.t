#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;

use_ok 'LIMS2::Util::EnsEMBL';

ok my $u = LIMS2::Util::EnsEMBL->new, 'constructor returns';

is $u->species, 'mouse', 'default species is mouse';

note( 'Check all adaptors are present' );

can_ok $u, 'gene_adaptor';
isa_ok $u->gene_adaptor, 'Bio::EnsEMBL::DBSQL::GeneAdaptor';

can_ok $u, 'exon_adaptor';
isa_ok $u->exon_adaptor, 'Bio::EnsEMBL::DBSQL::ExonAdaptor';

can_ok $u, 'transcript_adaptor';
isa_ok $u->transcript_adaptor, 'Bio::EnsEMBL::DBSQL::TranscriptAdaptor';

can_ok $u, 'slice_adaptor';
isa_ok $u->slice_adaptor, 'Bio::EnsEMBL::DBSQL::SliceAdaptor';

can_ok $u, 'db_adaptor';
isa_ok $u->db_adaptor, 'Bio::EnsEMBL::DBSQL::DBAdaptor';

can_ok $u, 'repeat_feature_adaptor';
isa_ok $u->repeat_feature_adaptor, 'Bio::EnsEMBL::DBSQL::RepeatFeatureAdaptor';

note( 'Check get_best_transcript' );

ok my $gene = $u->gene_adaptor->fetch_by_stable_id( 'ENSMUSG00000024617' ), 'can fetch gene';
isa_ok $gene, 'Bio::EnsEMBL::Gene';
is $u->get_best_transcript( $gene )->stable_id, 'ENSMUST00000025519', 'transcript is correct';

note( 'Check get_exon_rank' );

ok my $transcript = $u->transcript_adaptor->fetch_by_stable_id( 'ENSMUST00000025519' ), 'can fetch transcript';
isa_ok $transcript, 'Bio::EnsEMBL::Transcript';
is $u->get_exon_rank( $transcript, 'ENSMUSE00001117273' ), 1, 'first exon rank correct';
is $u->get_exon_rank( $transcript, 'ENSMUSE00000572374' ), 5, 'fifth exon rank correct';

note( 'Check get_gene_from_exon_id' );
is $u->get_gene_from_exon_id( 'ENSMUSE00000572374' )->stable_id, 'ENSMUSG00000024617', 'gene is correct';

done_testing;
