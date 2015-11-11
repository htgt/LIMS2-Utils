package LIMS2::Util::TarmitsUpdate;

=head

Methods to find accepted EP_PICK(es cells) and FINAL(targeting vetor) wells in
LIMS2 and create, update or delete in Tarmits as required.

This is the LIMS2 equivalent of HTGT::Utils::TargRep::Update

=cut

use Moose;

with qw( MooseX::Log::Log4perl );

has lims2_model => (
    is       => 'ro',
    isa      => 'LIMS2::Model',
    required => 1,
);

has tarmits_api => (
    is       => 'ro',
    isa      => 'LIMS2::Util::Tarmits',
    required => 1,
);

# Gene symbols to do update for (optional)
has genes => (
    is      => 'ro',
    isa     => 'ArrayRef',
    traits  => ['Array'],
    handles => { has_genes => 'count', },
    default => sub{ [] },
);

has commit => (
    is       => 'ro',
    isa      => 'Bool',
    default  => 0,
    required => 1,
);

has hide_non_distribute => (
    is       => 'ro',
    isa      => 'Bool',
    default  => 0,
    required => 1,
);

has targeting_vectors => (
    is      => 'ro',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        seen_targeting_vector      => 'exists',
        targeting_vector_processed => 'set',
        get_targeting_vector_id    => 'get',
    }
);

has es_cells => (
    is      => 'ro',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        seen_es_cell      => 'exists',
        es_cell_processed => 'set',
    }
);

my %VALIDATION_AND_METHODS = (
    allele => {
        fields => [
            qw(
                cassette_type
                mutation_type_name
                mutation_subtype_name
                mutation_method_name
                project_design_id
            )
        ],
        optional_fields => [
            qw(
                floxed_start_exon
                floxed_end_exon
            )
        ],
        update        => \&update_allele,
        update_method => 'update_allele',
        create_method => 'create_allele',
    },
    genbank_file => {
        fields => [
            qw(
                escell_clone
                targeting_vector
            )
        ],
        update        => \&update_genbank,
        update_method => 'update_genbank_file',
        create_method => 'create_genbank_file',
    },
    es_cell => {
        fields => [
            qw(
                targeting_vector_id
                ikmc_project_id
                parental_cell_line
                pipeline_id
                report_to_public
                production_qc_five_prime_screen
                production_qc_three_prime_screen
            )
        ],
        sanger_epd  => [
             qw(
                mgi_allele_symbol_superscript
                production_qc_loxp_screen
                production_qc_loss_of_allele
             )
        ],
        update        => \&update_es_cell,
        update_method => 'update_es_cell',
        create_method => 'create_es_cell',
    },
    distribution_qc => {
        fields => [
            qw(
                five_prime_sr_pcr
                three_prime_sr_pcr
                karyotype_low
                karyotype_high
                copy_number
                loa
                loxp
                lacz
                chr1
                chr8a
                chr8b
                chr11a
                chr11b
                chry
            )
        ],
        update        => \&update_distribution_qc,
        update_method => 'update_distribution_qc',
        create_method => 'create_distribution_qc',
    },
    targeting_vector => {
        fields => [
            qw(
                ikmc_project_id
                intermediate_vector
                pipeline_id
                report_to_public
            )
        ],
        update        => \&update_targeting_vector,
        update_method => 'update_targeting_vector',
        create_method => 'create_targeting_vector',
    },
);

sub lims2_to_tarmits{
	my $self = shift;

	$self->process_summaries( $self->get_summaries );

}

sub get_summaries{
	my $self = shift;

	my %where = (
        '-or' => [
            ep_pick_well_accepted => 1,
            final_well_accepted   => 1,
        ]
	);

	if ($self->has_genes){
		$where{design_gene_symbol} = { '-in' => $self->genes };
	}

	my $summaries_rs = $self->lims2_model->schema->resultset('Summary')->search(\%where);
    return $summaries_rs;
}

sub process_summaries{
	my ($self, $summaries) = @_;
	foreach my $row ($summaries->all){
        $self->log->debug("design id: ".$row->design_id);
        $self->log->debug("gene symbol: ".$row->design_gene_symbol);
	}
	return;
}

1;