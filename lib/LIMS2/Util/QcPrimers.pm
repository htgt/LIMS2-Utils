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
    #|| '/nfs/team87/farm3_lims2_vms/conf/primer3_design_create_config.yaml';
    || '/nfs/users/nfs_s/sp12/workspace/LIMS2-Utils/primer3_mgp_recovery_crispr_group_primers.yaml';

has model => (
    is  => 'ro',
    isa => 'LIMS2::Model',
);

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

has commit => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

=head2 mgp_recovery_genotyping_primers

desc

=cut
sub mgp_recovery_genotyping_primers {
    my ( $self, $crispr_group ) = @_;
    $self->log->info( "GENERATE PRIMERS for $crispr_group, gene_id: " . $crispr_group->gene_id );

    my $work_dir = $self->base_dir->subdir( 'crispr_group_' . $crispr_group->id )->absolute;
    $work_dir->mkpath;

    $self->log->info( 'Searching for External Primers' );
    my $primer_finder = HTGT::QC::Util::GeneratePrimersAttempts->new(
        base_dir                    => $work_dir,
        species                     => $crispr_group->species,
        strand                      => 1, # always global +ve strand
        chromosome                  => $crispr_group->chr_name,
        target_start                => $crispr_group->start,
        target_end                  => $crispr_group->end,
        five_prime_region_size      => 300,
        five_prime_region_offset    => 20,
        three_prime_region_size     => 300,
        three_prime_region_offset   => 20,
        primer3_config_file         => $self->primer3_config_file,
        primer_search_region_expand => 400,
    );

    my ( $primer_data, $seq ) = $primer_finder->find_primers;

    unless ( $primer_data ) {
        $self->log->error( 'FAIL: Unable to generate primer pair for crispr group' );
        return;
    }

    $self->log->info( 'Found External Primers' );
    $self->log->info( 'Searching for Internal Primer' );
    my $picked_primers = $self->find_internal_primer( $crispr_group, $work_dir, $primer_data,
        $primer_finder->five_prime_region_size );

    unless( $picked_primers ) {
        $self->log->error( 'FAIL: Unable to find internal primer for crispr group' );
        return;
    }

    $self->log->info( 'SUCCESS: Found primers for target' );
    #$self->persist_crispr_primer_data( $primer_data, $crispr_group );

    return ( $picked_primers, $seq );
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
        max_three_prime_region_size => $max_search_region_size,
        primer_search_region_expand => $expand_size,
        retry_attempts              => $retry_attempts,
        internal_only               => 1,
    );


    my $count = 1;
    for my $primers ( @{ $primer_data } ) {
        my $forward_primer = $primers->{forward};
        $self->log->info( '========' );
        $self->log->info( "Search Internal Primer paired with forward primer: " . $forward_primer->{oligo_seq} );

        $primer_params{forward_primer} = $forward_primer;
        my $avoid_size = $self->calculate_product_size_avoid( $primers, $crispr_group );
        $primer_params{product_size_avoid} = $avoid_size;

        my $dir = $work_dir->subdir( 'internal_primer_' . $count++ )->absolute;
        $dir->mkpath;
        $primer_params{base_dir} = $dir;

        my $primer_finder = HTGT::QC::Util::GeneratePrimersAttempts->new( %primer_params );

        # TODO addtional product size checking .....

        my ( $internal_primer_data ) = $primer_finder->find_primers;
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
    my ( $self, $primer_data, $crispr_group ) = @_;

    my %primer_names = (
        forward  => 'CPF',
        internal => 'CGI',
        reverse  => 'CGR',
    );
    my $chr_name = $crispr_group->chr_name;
    my $species = $crispr_group->right_most_crispr->species;
    my $assembly_id = $species->default_assembly->assembly_id;

    for my $type ( qw( forward reverse internal ) ) {
        my $data = $primer_data->{$type};

        $self->model->create_crispr_primer(
            {
                crispr_group_id => $crispr_group->id,
                primer_name     => $primer_names{$type},
                primer_seq      => uc( $data->{oligo_seq} ),
                tm              => $data->{melting_temp},
                gc_content      => $data->{gc_content},
                locus => {
                    assembly   => $assembly_id,
                    chr_name   => $chr_name,
                    chr_start  => $data->{oligo_end},
                    chr_end    => $data->{oligo_start},
                    chr_strand => $type eq 'forward' ? 1 : -1,
                },
            }
        );
    }

    return;
}

=head2 calculate_product_size_avoid

Work out size of product we must avoid for internal primer ( matched to forward primer ).
This is so its product size is not the same as the product size of the external primers
minus the target region.

=cut
sub calculate_product_size_avoid {
    my ( $self, $primers, $crispr_group ) = @_;

    # TODO check this for -ve stranded target
    my $primer_pair_product_size = $primers->{reverse}{oligo_end} - $primers->{forward}{oligo_start};
    my $deleted_size = $crispr_group->end - $crispr_group->start;
    my $avoid_size = $primer_pair_product_size - $deleted_size;

    return  $avoid_size;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
