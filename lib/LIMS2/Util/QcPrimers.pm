package LIMS2::Util::QcPrimers;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::QcPrimers::VERSION = '0.041';
}
## use critic


=head1 NAME

LIMS2::Util::QcPrimers

=head1 DESCRIPTION

Currently generate genotyping primers for various targets:
    - MGP Recovery Crispr Groups
    - Short Arm Vector Crispr Groups

More targets can be added by creating new config files and adding this
to the PRIMER_PROJECT_CONFIG_FILES hash.

=cut

use Moose;

use LIMS2::Model;
use LIMS2::Exception;
use HTGT::QC::Util::GeneratePrimersAttempts;

use MooseX::Types::Path::Class::MoreCoercions qw/AbsDir AbsFile/;
use Try::Tiny;
use Path::Class;
use Const::Fast;
use YAML::Any qw( LoadFile );

use namespace::autoclean;

with 'MooseX::Log::Log4perl';

my %PRIMER_PROJECT_CONFIG_FILES = (
    mgp_recovery => $ENV{MGP_RECOVERY_GENOTYPING_PRIMER_CONFIG}
            || '/opt/t87/global/conf/primers/mgp_recovery_genotyping.yaml',
    short_arm_vectors => $ENV{SHORT_ARM_VECTOR_GENOTYPING_PRIMER_CONFIG}
            || '/opt/t87/global/conf/primers/short_arm_vector_genotyping.yaml',
);

has model => (
    is  => 'ro',
    isa => 'LIMS2::Model',
);

has primer_project_name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    trigger  => \&_check_primer_project_name,
);

sub _check_primer_project_name {
    my ( $self, $name ) = @_;
    die ( "Unknown project name $name" ) unless exists $PRIMER_PROJECT_CONFIG_FILES{ $name };
    return;
}

# parse the config yaml file and store in this hash
has config => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
);

sub _build_config {
    my $self = shift;
    return LoadFile( $PRIMER_PROJECT_CONFIG_FILES{ $self->primer_project_name } );
}

has base_dir => (
    is       => 'ro',
    isa      => AbsDir,
    required => 1,
    coerce   => 1,
);

has primer3_config_file => (
    is         => 'ro',
    isa        => AbsFile,
    lazy_build => 1,
);

sub _build_primer3_config_file {
    my $self = shift;

    if ( my $file_name = $self->config->{primer3_config} ) {
        return file( $file_name )->absolute;
    }
    else {
        die 'No primer3_config value in primer project config file '
            . $PRIMER_PROJECT_CONFIG_FILES{ $self->primer_project_name };
    }

    return;
}

has persist_primers => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

=head2 crispr_group_genotyping_primers

Generate a pair of primers plus a internal primer for a given crispr group.

=cut
sub crispr_group_genotyping_primers {
    my ( $self, $crispr_group ) = @_;
    $self->log->info( '====================' );
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
        primer3_config_file         => $self->primer3_config_file,
        five_prime_region_size      => $self->config->{five_prime_region_size},
        five_prime_region_offset    => $self->config->{five_prime_region_offset},
        three_prime_region_size     => $self->config->{three_prime_region_size},
        three_prime_region_offset   => $self->config->{three_prime_region_offset},
        primer_search_region_expand => $self->config->{primer_search_region_expand},
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

    if ( $self->persist_primers ) {
        $self->model->txn_do(
            sub {
                $self->persist_crispr_primer_data( $picked_primers, $crispr_group );
            }
        );
    }

    return ( $picked_primers, $seq );
}

=head2 find_internal_primer

Find a internal primer ( reverse ) that matches a already generated forward primer.
The reverse primer must be found within a defined smaller search region.

Optionally the product size of the internal and forward primer may be restricted.
It may not be within 30 bases in size of the product of the external primers after the
sequence has been deleted by the crispr group.

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
        three_prime_region_offset   => $self->config->{internal_primer_region_offset},
        primer3_config_file         => $self->primer3_config_file,
        max_three_prime_region_size => $max_search_region_size,
        primer_search_region_expand => $expand_size,
        retry_attempts              => $retry_attempts,
        internal_only               => 1,
    );


    my $count = 1;
    for my $primers ( @{ $primer_data } ) {
        my $forward_primer = $primers->{forward};
        $self->log->info( '-------------' );
        $self->log->info( "Search Internal Primer paired with forward primer: " . $forward_primer->{oligo_seq} );

        $primer_params{forward_primer} = $forward_primer;
        if ( $self->config->{internal_primer_product_size_restriction} ) {
            my $avoid_size = $self->calculate_product_size_avoid( $primers, $crispr_group );
            $primer_params{product_size_avoid} = $avoid_size;
        }

        my $dir = $work_dir->subdir( 'internal_primer_' . $count++ )->absolute;
        $dir->mkpath;
        $primer_params{base_dir} = $dir;

        my $primer_finder = HTGT::QC::Util::GeneratePrimersAttempts->new( %primer_params );

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

Persist the primers generated for a crispr group.

=cut
sub persist_crispr_primer_data {
    my ( $self, $picked_primers, $crispr_group ) = @_;
    $self->log->info( 'Persisting crispr group primers' );

    my $chr_name = $crispr_group->chr_name;
    my $species = $crispr_group->right_most_crispr->species;
    my $assembly_id = $species->default_assembly->assembly_id;

    for my $type ( qw( forward reverse internal ) ) {
        next unless exists $picked_primers->{$type};
        my $data = $picked_primers->{$type};

        $self->model->create_crispr_primer(
            {
                crispr_group_id => $crispr_group->id,
                primer_name     => $self->config->{primer_names}{$type},
                primer_seq      => uc( $data->{oligo_seq} ),
                tm              => $data->{melting_temp},
                gc_content      => $data->{gc_content},
                locus => {
                    assembly   => $assembly_id,
                    chr_name   => $chr_name,
                    chr_start  => $data->{oligo_start},
                    chr_end    => $data->{oligo_end},
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

    my $primer_pair_product_size;
    # work out product size, strand dependant
    if ( $primers->{forward}{oligo_start} < $primers->{reverse}{oligo_start} ) {
        $primer_pair_product_size = $primers->{reverse}{oligo_end} - $primers->{forward}{oligo_start};
    }
    else {
        $primer_pair_product_size = $primers->{forward}{oligo_end} - $primers->{reverse}{oligo_start};
    }
    my $deleted_size = $crispr_group->end - $crispr_group->start;
    my $avoid_size = $primer_pair_product_size - $deleted_size;

    return $avoid_size;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
