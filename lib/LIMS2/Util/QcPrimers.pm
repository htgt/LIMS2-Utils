package LIMS2::Util::QcPrimers;

=head1 NAME

LIMS2::Util::QcPrimers

=head1 DESCRIPTION

description

=cut

use Moose;

use LIMS2::Model;
use LIMS2::Exception;
use HTGT::QC::Util::GeneratePrimersAttempts;

use MooseX::Types::Path::Class::MoreCoercions qw/AbsDir AbsFile/;
use Try::Tiny;
use Path::Class;
use Const::Fast;

use namespace::autoclean;

with 'MooseX::Log::Log4perl';

# TODO change this
const our $MGP_RECOVERY_PRIMER3_CONFIG_FILE => $ENV{MGP_RECOVERY_PRIMER3_CONFIG}
    || '/nfs/team87/farm3_lims2_vms/conf/primer3_design_create_config.yaml';

has model => (
    is         => 'ro',
    isa        => 'LIMS2::Model',
    lazy_build => 1,
);

sub _build_model {
    return LIMS2::Model->new( user => 'tasks' );
}

has base_dir => (
    is       => 'ro',
    isa      => AbsDir,
    required => 1,
    coerce   => 1,
);

#TODO when we generate different types of primers within this
#     module then this code needs to be changed
has primer3_config_file => (
    is         => 'ro',
    isa        => AbsFile,
    lazy_build => 1,
);

sub _build_primer3_config_file {
    return file( $MGP_RECOVERY_PRIMER3_CONFIG_FILE )->absolute;
}

=head2 mgp_recovery_genotyping_primers

desc

=cut
sub mgp_recovery_genotyping_primers {
    my ( $self, $crispr_group_id ) = @_;

    my $crispr_group = try{ $self->model->retrieve_crispr_group( { id => $crispr_group_id } ) };

    LIMS2::Exception->throw( "Unable to find crispr group with id $crispr_group_id" )
        unless $crispr_group;

    my $work_dir = $self->base_dir->subdir( 'crispr_group_' . $crispr_group_id )->absolute;
    $work_dir->mkpath;

    $self->log->info( 'Searching for External Primers' );
    my $primer_finder = HTGT::QC::Util::GeneratePrimersAttempts->new(
        base_dir                  => $work_dir,
        species                   => $crispr_group->species,
        strand                    => 1, # TODO check just 1 all the time?
        chromosome                => $crispr_group->chr_name,
        target_start              => $crispr_group->start,
        target_end                => $crispr_group->end,
        five_prime_region_size    => 300,
        five_prime_region_offset  => 20,
        three_prime_region_size   => 300,
        three_prime_region_offset => 20,
        primer3_config_file       => $self->primer3_config_file,
    );

    my $primer_data = $primer_finder->find_primers;

    unless ( $primer_data ) {
        $self->log->error( 'Unable to generate primer pair for crispr group' );
        return;
    }

    $self->log->info( 'Found External Primers' );
    $self->log->info( 'Searching for Internal Primer' );
    my $picked_primers = $self->find_internal_primer( $crispr_group, $work_dir, $primer_data,
        $primer_finder->five_prime_region_size );
    return unless $picked_primers;

    $self->log->info( 'Found Internal Primer' );
    #$self->persist_crispr_primer_data( $primer_data );

    return $picked_primers;
}

=head2 find_internal_primer

desc

=cut
sub find_internal_primer {
    my ( $self, $crispr_group, $work_dir, $primer_data, $five_prime_region_size ) = @_;

    # Target is outer crisprs in the left group
    my $start_left_crispr = $crispr_group->left_ranked_crisprs->[0];
    my $end_left_crispr = $crispr_group->left_ranked_crisprs->[-1];

    # maximum search region for internal primer is the smallest gap between
    # the left and right crispr groups
    my $start_right_crispr = $crispr_group->right_ranked_crisprs->[0];
    my $max_search_region_size
        = $start_right_crispr->current_locus->chr_start - $end_left_crispr->current_locus->chr_end;

    # ideally internal primer within first 100 bases
    my $initial_region_size = 100;
    my $retry_attempts = 3;
    # number of bases to expand search region on each new attempt
    my $expand_size = int( ( $max_search_region_size - $initial_region_size ) / $retry_attempts );

    my $sequence_excluded_region = $self->calculate_sequence_excluded_region();
    my %primer_params = (
        species                     => $crispr_group->species,
        strand                      => 1,
        chromosome                  => $crispr_group->chr_name,
        target_start                => $start_left_crispr->current_locus->chr_start,
        target_end                  => $end_left_crispr->current_locus->chr_end,
        five_prime_region_size      => $five_prime_region_size,
        five_prime_region_offset    => 20, # does not really influence anything, so stays the same
        three_prime_region_size     => $initial_region_size,
        three_prime_region_offset   => 20,
        primer3_config_file         => $self->primer3_config_file,
        primer_product_size_range   => '120-500', # ideal product size
        max_three_prime_region_size => $max_search_region_size,
        primer_search_region_expand => $expand_size,
        retry_attempts              => $retry_attempts,
    );


    my $count = 1;
    for my $primers ( @{ $primer_data } ) {
        my $forward_primer_seq = $primers->{forward}{oligo_seq};
        $self->log->info( '========' );
        $self->log->info( "Search Internal Primer paired with forward primer: $forward_primer_seq" );
        $primer_params{additional_primer3_params} = { sequence_primer => $forward_primer_seq };
        $self->log->debug( "Chosen forward primer: $forward_primer_seq" );

        my $dir = $work_dir->subdir( 'internal_primer_' . $count++ )->absolute;
        $dir->mkpath;
        $primer_params{base_dir} = $dir;

        my $primer_finder = HTGT::QC::Util::GeneratePrimersAttempts->new( %primer_params );

        # TODO addtional product size checking .....
        # Size can not be within 30 bp of product size of deleted exon

        my $internal_primer_data = $primer_finder->find_primers;
        if ( $internal_primer_data ) {
            $primers->{internal} = $internal_primer_data->[0]{reverse};
            return $primers;
        }
    }

    $self->log->error( 'Unable to find internal primer' );
    return;
}

=head2 persist_crispr_primer_data

desc

=cut
sub persist_crispr_primer_data {
    my ( $self, $primer_data ) = @_;

    # TODO UPPERCASE SEQUENCE
    # multiple primers
    $self->model->create_crispr_primer(  );

    return;
}

=head2 calculate_sequence_excluded_region

    # SEQUENCE_EXCLUDED_REGION

=cut
sub calculate_sequence_excluded_region {
    my ( $self ) = @_;

}

__PACKAGE__->meta->make_immutable;

1;

__END__
