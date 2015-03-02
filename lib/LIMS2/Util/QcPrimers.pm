package LIMS2::Util::QcPrimers;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::QcPrimers::VERSION = '0.064';
}
## use critic


=head1 NAME

LIMS2::Util::QcPrimers

=head1 DESCRIPTION

Currently generate genotyping primers for various targets:
    - MGP Recovery Crispr Groups
    - Short Arm Vector Crispr Groups
    - Single and paired crispr sequencing primers
    - PCR primers to amplify the region containing a set of sequencing primers
    - Gibson designs

More targets can be added by creating new config files and adding this
to the PRIMER_PROJECT_CONFIG_FILES hash. If a new type of target, e.g. nonsense
crispr oligo, needs to be added you'll need a new xxxx_primers method to get
the appropriate start and end coordinates for the region of interest

=cut

use Moose;

use LIMS2::Model;
use LIMS2::Exception;
use HTGT::QC::Util::GeneratePrimersAttempts;

use MooseX::Types::Path::Class::MoreCoercions qw/AbsDir AbsFile/;
use Try::Tiny;
use Path::Class;
use Const::Fast;
use YAML::Any qw( LoadFile DumpFile );
use Data::Dumper;
use Bio::Perl qw(reverse_complement_as_string);
use Bio::Seq;
use WebAppCommon::Util::FarmJobRunner;
use Path::Class;
use JSON;

use namespace::autoclean;

with 'MooseX::Log::Log4perl';

my %PRIMER_PROJECT_CONFIG_FILES = (
    mgp_recovery => $ENV{MGP_RECOVERY_GENOTYPING_PRIMER_CONFIG}
            || '/nfs/team87/farm3_lims2_vms/conf/primers/mgp_recovery_genotyping.yaml',
    short_arm_vectors => $ENV{SHORT_ARM_VECTOR_GENOTYPING_PRIMER_CONFIG}
            || '/nfs/team87/farm3_lims2_vms/conf/primers/short_arm_vector_genotyping.yaml',
    crispr_sequencing => $ENV{CRISPR_SEQUENCING_PRIMER_CONFIG}
            || '/nfs/team87/farm3_lims2_vms/conf/primers/crispr_sequencing_primer_conf.yaml',
    design_genotyping => $ENV{DESIGN_GENOTYPING_PRIMER_CONFIG}
            || '/nfs/team87/farm3_lims2_vms/conf/primers/design_genotyping_primer_conf.yaml',
    crispr_pcr => $ENV{CRISPR_PCR_PRIMER_CONFIG}
            || '/nfs/team87/farm3_lims2_vms/conf/primers/crispr_pcr_primer_conf.yaml',
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
    $self->log->info("using config file ".$PRIMER_PROJECT_CONFIG_FILES{ $self->primer_project_name });
    my $config = LoadFile( $PRIMER_PROJECT_CONFIG_FILES{ $self->primer_project_name } );
    $self->log->info("Config loaded: ",Dumper($config));
    return $config;
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
    $self->log->info(Dumper($self->config));
    if ( my $file_name = $self->config->{primer3_config} ) {
        $self->log->info("Using primer3 config file $file_name");
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

# Set to true to run primer generation on farm
has run_on_farm => (
    is       => 'ro',
    isa      => 'Bool',
    default  => 0,
);

# Set this to true to replace primers already in the database
has overwrite => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

# Set this to true to check if a primer sequence has previously
# been rejected by user before persisting it to database
has check_for_rejection => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has primer_name_sets => (
    is      => 'ro',
    isa     => 'ArrayRef',
    lazy_build => 1,
);

# project config file may contain just one set of primers
# or a list of primers with the names for multiple sets
# of primers, e.g.
# primer_names:
#   -forward: 'GF1'
#    reverse: 'GR1'
#
#   -forward: 'GF2'
#    reverse: 'GR2'
#
# the builder method creates an array even if only one set is provided
sub _build_primer_name_sets {
    my $self = shift;
    my $primer_names = $self->config->{primer_names};
    my @primer_name_sets;
    if(ref $self->config->{primer_names} eq ref []){
        @primer_name_sets = @{ $self->config->{primer_names} };
    }
    else{
        @primer_name_sets = ( $self->config->{primer_names} );
    }

    # I had to store the rank with the name set in order
    # to use it in _build_output_methods
    my $rank = 0;
    foreach my $name_set (@primer_name_sets){
        $name_set->{rank} = $rank;
        $rank++;
    }

    return \@primer_name_sets;
}

# List of field names that we want to output for each primer type
has primer_output_fields => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub{ [qw(seq strand length start end gc_content tm)] },
);

# Methods to generate these outputs given a single primer's
# hashref from the primer finder
has primer_output_methods => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy_build => 1,
);

sub _build_primer_output_methods {
    my $self = shift;

    my $methods = {
        seq    => sub{ shift->{oligo_seq} },
        strand => sub{ shift->{oligo_direction } },
        length => sub{ shift->{oligo_length} },
        gc_content => sub{ shift->{gc_content} },
        tm         => sub{ shift->{melting_temp} },
        start  => sub{ shift->{oligo_start} },
        end    => sub{ shift->{oligo_end} }
    };

    return $methods;
}

has output_headings => (
     is         => 'ro',
     isa        => 'ArrayRef',
     lazy_build => 1,
);

sub _build_output_headings {
    my $self = shift;

    my @headings;

    foreach my $primer_set( @{ $self->primer_name_sets }){
        TYPE: foreach my $type ( qw(forward reverse internal) ){
            my $primer_name = $primer_set->{$type};
            next TYPE unless $primer_name;
            foreach my $field_type (@{ $self->primer_output_fields}){
                push @headings, $primer_name."_".$field_type;
            }
        }
    }
    return \@headings;
}

has output_methods => (
    is          => 'ro',
    isa         => 'HashRef',
    lazy_build  => 1,
);

sub _build_output_methods {
    my $self = shift;
    my $methods;

    foreach my $primer_set( @{ $self->primer_name_sets }){
        TYPE: foreach my $type ( qw(forward reverse internal) ){
            my $primer_name = $primer_set->{$type};
            next TYPE unless $primer_name;
            foreach my $field_type (@{ $self->primer_output_fields}){
                my $field_name = $primer_name."_".$field_type; # e.g. SR1_gc_content
                $methods->{$field_name} = sub {
                    # e.g. get 0 ranked reverse primer for SR1
                    my $primer_data = shift;
                    my $rank = $primer_set->{rank};
                    my $picked_primers = $primer_data->[$rank] or return;
                    my $primer = $picked_primers->{$type} or return;
                    # e.g. apply the gc_content fetcher method to the reverse primer
                    return $self->primer_output_methods->{$field_type}->($primer);
                }
            }
        }
    }
    return $methods;
}

sub primer_params_from_config {
    my $self = shift;

    my $params = {
        primer3_config_file         => $self->primer3_config_file,
        five_prime_region_size      => $self->config->{five_prime_region_size},
        five_prime_region_offset    => $self->config->{five_prime_region_offset},
        three_prime_region_size     => $self->config->{three_prime_region_size},
        three_prime_region_offset   => $self->config->{three_prime_region_offset},
        primer_search_region_expand => $self->config->{primer_search_region_expand},
        check_genomic_specificity   => ($self->config->{check_genomic_specificity} // 1),
        exclude_from_product_length => ($self->config->{exclude_from_product_length} // 0),
        no_repeat_masking           => ($self->config->{no_repeat_masking} // 1),
    };
    return $params;
}

=head2 get_new_crispr_primer_finder_params

Constructs the parameters required to create a new GeneratePrimersAttempts object
targetting a given crispr single, pair or group

input:
  working directory
  Crispr, CrisprPair or CrisprGroup
  strand

=cut

sub get_new_crispr_primer_finder_params {
    my ($self, $work_dir, $crispr_collection, $strand) = @_;

    return {
        base_dir                    => $work_dir,
        species                     => $crispr_collection->species_id,
        strand                      => $strand,
        chromosome                  => $crispr_collection->chr_name,
        target_start                => $crispr_collection->start,
        target_end                  => $crispr_collection->end,
        %{ $self->primer_params_from_config }
    };
}

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
    my $strand = 1; # always global +ve strand
    my $params = $self->get_new_crispr_primer_finder_params($work_dir, $crispr_group, $strand);

    my ( $primer_data, $seq, $five_prime_region_size) = $self->run_generate_primers_attempts($params);

    unless ( $primer_data ) {
        $self->log->error( 'FAIL: Unable to generate primer pair for crispr group' );
        return;
    }

    $self->log->info( 'Found External Primers' );
    $self->log->info( 'Searching for Internal Primer' );
    my $picked_primers = $self->find_internal_primer( $crispr_group, $work_dir, $primer_data,
        $five_prime_region_size );

    unless( $picked_primers ) {
        $self->log->error( 'FAIL: Unable to find internal primer for crispr group' );
        return;
    }

    $self->log->info( 'SUCCESS: Found primers for target' );
    DumpFile( $work_dir->file('primers.yaml'), $picked_primers );

    my $db_primers = [];
    if ( $self->persist_primers ) {
        $self->model->txn_do(
            sub {
                $db_primers = $self->persist_crispr_primer_data( $picked_primers, $crispr_group );
            }
        );
    }

    return ( [ $picked_primers ], $seq, $db_primers );
}

=head2 crispr_sequencing_primers

Generate a pair of primers for a given crispr single or pair.

=cut
sub crispr_sequencing_primers {
    my ( $self, $crispr_single_or_pair ) = @_;
    $self->log->info( '====================' );
    $self->log->info( "GENERATE PRIMERS for $crispr_single_or_pair, gene_id: " . $crispr_single_or_pair->gene_id );

    my $work_dir = $self->base_dir->subdir( 'crispr_sequencing_' . $crispr_single_or_pair->id )->absolute;
    $work_dir->mkpath;

    $self->log->info( 'Searching for Primers' );
    my $strand = 1; # always global +ve strand
    my $params = $self->get_new_crispr_primer_finder_params($work_dir, $crispr_single_or_pair, $strand);

    my ( $primer_data, $seq ) = $self->run_generate_primers_attempts($params);

    unless ( $primer_data ) {
        $self->log->error( 'FAIL: Unable to generate primer pair for crispr' );
        return;
    }

    $self->log->info( 'SUCCESS: Found primers for target' );
    DumpFile( $work_dir->file('primers.yaml'), $primer_data );

    my $db_primers = [];
    if ( $self->persist_primers ) {
        $self->model->txn_do(
            sub {
                $db_primers = $self->persist_crispr_primer_data( $primer_data, $crispr_single_or_pair );
            }
        );
    }

    return ( $primer_data, $seq, $db_primers );
}

=head2 design_genotyping_primers

For a Design fetch the design oligos and use min and max oligo positions
as inputs to generate primers

=cut

sub design_genotyping_primers{
    my ($self, $design) = @_;
    $self->log->info( '====================' );
    $self->log->info( "GENERATE PRIMERS for design_id: " . $design->id );

    my $work_dir = $self->base_dir->subdir( 'design_genotyping_' . $design->id )->absolute;
    $work_dir->mkpath;

    $self->log->info( 'Searching for Design Genotyping Primers' );

    my @oligos = @{ $design->oligos_sorted || [] };

    my $start_coord = $oligos[0]->{locus}->{chr_start};
    my $end_coord = $oligos[-1]->{locus}->{chr_end};
    my $strand = $oligos[0]->{locus}->{chr_strand};

    $self->log->debug('Strand for design '.$design->id.": $strand");
    my $params = {
        base_dir                    => $work_dir,
        species                     => $design->species_id,
        strand                      => $strand,
        chromosome                  => $oligos[0]->{locus}->{chr_name},
        target_start                => $start_coord,
        target_end                  => $end_coord,
        %{ $self->primer_params_from_config }
    };

    my ( $primer_data, $seq ) = $self->run_generate_primers_attempts($params);

    # For designs with genes on the reverse strand we need to reverse complement the primers
    # and store them such that the forward primer e.g. GF1, lies on the reverse strand
    # and the reverse primer, e.g. GR1, lies on the forward strand
    if($strand == -1){
        $self->log->debug("Reverse complementing primers for gene on reverse strand");
        foreach my $primer_group (@$primer_data){
            foreach my $primer_type (keys %$primer_group){
                my $orig_seq = $primer_group->{$primer_type}->{oligo_seq};
                my $orig_direction = $primer_group->{$primer_type}->{oligo_direction};

                my $store_seq = reverse_complement_as_string($orig_seq);
                my $store_direction = $orig_direction eq 'forward' ? 'reverse' : 'forward';

                $primer_group->{$primer_type}->{oligo_seq} = $store_seq;
                $primer_group->{$primer_type}->{oligo_direction} = $store_direction;
            }
        }
    }

    unless ( $primer_data ) {
        $self->log->error( 'FAIL: Unable to generate genotyping primers for design' );
        return;
    }

    $self->log->info( 'SUCCESS: Found primers for target' );
    DumpFile( $work_dir->file('primers.yaml'), $primer_data );

    my $db_primers = [];
    if ( $self->persist_primers ) {
        $self->model->txn_do(
            sub {
                $db_primers = $self->persist_genotyping_primer_data( $primer_data, $design );
            }
        );
    }

    return ( $primer_data, $seq, $db_primers );
}

=head2 crispr_PCR_primers

For a set of crispr primers use the oligo start and end positions of the 0 ranked primer pair
as inputs to generate primers. Pass the crispr single/pair/group to this method too as
we need this to get the species and chromosome.

=cut

sub crispr_PCR_primers{
    my ($self, $crispr_primers, $crispr) = @_;
    $self->log->info( '====================' );
    $self->log->info( "GENERATE PCR PRIMERS for".$crispr->id_column_name.": ".$crispr->id );

    my $work_dir = $self->base_dir->subdir( 'crispr_PCR_' . $crispr->id )->absolute;
    $work_dir->mkpath;

    $self->log->info( 'Searching for Crispr PCR Primers' );

    my $target_start = $crispr_primers->[0]->{forward}->{oligo_start} + 1;
    my $target_end =  $crispr_primers->[0]->{reverse}->{oligo_end} + 1;
    $self->log->info("PCR Target start: $target_start");
    $self->log->info("PCR Target end: $target_end");

    my $strand = 1;

    my $params = {
        base_dir                    => $work_dir,
        species                     => $crispr->species_id,
        strand                      => $strand,
        chromosome                  => $crispr->chr_name,
        target_start                => $target_start,
        target_end                  => $target_end,
        %{ $self->primer_params_from_config }
    };

    my ( $primer_data, $seq ) = $self->run_generate_primers_attempts($params);

    unless ( $primer_data ) {
        $self->log->error( 'FAIL: Unable to generate crispr PCR primers for well' );
        return;
    }

    $self->log->info( 'SUCCESS: Found primers for target' );
    DumpFile( $work_dir->file('primers.yaml'), $primer_data );

    my $db_primers = [];
    if ( $self->persist_primers ) {
        $self->model->txn_do(
            sub {
                $db_primers = $self->persist_crispr_primer_data( $primer_data, $crispr );
            }
        );
    }

    return ( $primer_data, $seq, $db_primers );
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
        species                     => $crispr_group->species_id,
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
        no_repeat_masking           => ( $self->config->{internal_primer_no_repeat_masking} // 1 )
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

        my ( $internal_primer_data ) = $self->run_generate_primers_attempts(\%primer_params);
        if ( $internal_primer_data ) {
            $primers->{internal} = $internal_primer_data->[0]{reverse};
            return $primers;
        }
    }

    $self->log->error( 'Unable to find internal primer' );
    return;
}

=head2 persist_crispr_primer_data

Persist the primers generated for a crispr, pair or group.

=cut
sub persist_crispr_primer_data {
    my ( $self, $generated_primers, $crispr_collection ) = @_;
    $self->log->info( 'Persisting crispr primers' );

    my $db_primers = $self->_persist_primer_data({
        primers        => $generated_primers,
        create_method  => 'create_crispr_primer',
        id_column_name => $crispr_collection->id_column_name,
        id             => $crispr_collection->id,
        assembly_id    => $crispr_collection->default_assembly->assembly_id,
        chr_name       => $crispr_collection->chr_name,
    });

    return $db_primers;
}

=head2 persist_genotyping_primer_data

Persist the primers generated for a design.

=cut
sub persist_genotyping_primer_data {
    my ( $self, $generated_primers, $design ) = @_;
    $self->log->info( 'Persisting design genotyping primers' );

    my $assembly_id = $design->species->default_assembly->assembly_id;

    my $db_primers = $self->_persist_primer_data({
        primers        => $generated_primers,
        create_method  => 'create_genotyping_primer',
        id_column_name => 'design_id',
        id             => $design->id,
        assembly_id    => $assembly_id,
        chr_name       => $design->chr_name,
    });

    return $db_primers;
}

sub _persist_primer_data{
    my ($self, $params) = @_;

    # $generated_primers should be a ref to a ranked array of primer sets
    # For backwards compatability we put a single set of generated primers
    # into an array
    my $generated_primers = $params->{primers};
    my $create_method = $params->{create_method};

    unless(ref $generated_primers eq ref []){
        $generated_primers = [ $generated_primers ];
    }

    my @db_primers;
    my $rank = 0;
    foreach my $primer_set (@{ $self->primer_name_sets }){
        my $picked_primers = $generated_primers->[$rank];
        last unless $picked_primers;
        $rank++;
        for my $type ( qw( forward reverse internal ) ) {
            next unless exists $picked_primers->{$type};
            my $data = $picked_primers->{$type};

            my $chr_strand = $type eq 'forward' ? 1 : -1;
            if(defined $data->{oligo_strand_to_store}){
                $chr_strand = $data->{oligo_strand_to_store};
            }

            # Use oligo direction instead of primer type to determine
            # strandedness in case we have reversed the primer orientation
            # for design genotyping primers for gene on reverse strand
            my $strand = $data->{oligo_direction} eq 'forward' ? 1 : -1;

            my $column_name = $params->{id_column_name};
            my $primer = $self->model->$create_method(
                {
                    $column_name    => $params->{id},
                    primer_name     => $primer_set->{$type},
                    primer_seq      => uc( $data->{oligo_seq} ),
                    tm              => $data->{melting_temp},
                    gc_content      => $data->{gc_content},
                    locus => {
                        assembly   => $params->{assembly_id},
                        chr_name   => $params->{chr_name},
                        chr_start  => $data->{oligo_start},
                        chr_end    => $data->{oligo_end},
                        chr_strand => $strand,
                    },
                    overwrite      => $self->overwrite,
                    check_for_rejection => $self->check_for_rejection,
                }
            );

            push @db_primers, $primer;
        }
    }
    return \@db_primers;
}

=head2 get_output_headings

    return array ref of field names to use as column headings in output

=cut

sub get_output_headings {
    return shift->output_headings;
}

=head2 get_output_values

   return hash ref of values for the fields in the output_headings array
   requires a primer_data arrayref as input

=cut

sub get_output_values{
    my ($self, $primer_data) = @_;
    my $values;

    unless($primer_data){
        $self->log->debug("No primer data provided to get_output_values");
        return;
    }

    while ( my($field_name, $method) = each %{ $self->output_methods }){
        $values->{$field_name} = $method->($primer_data);
    }
    return $values;
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

sub run_generate_primers_attempts {
    my ( $self, $params ) = @_;

    my ($primer_data, $seq, $five_prime_region_size);
    if($self->run_on_farm){
        # Write GeneratePrimersAttempts constructor params to file
        my $base_dir = $params->{base_dir};

        $params->{base_dir} = $base_dir->stringify;
        $params->{primer3_config_file} = $params->{primer3_config_file}->stringify;

        my $params_file = $base_dir->file( 'generate_primers_params.yaml' );

        DumpFile("$params_file", $params);

        my $out_file = $base_dir->file( 'generated_primers.json' );

        my $primer_script = '/nfs/team87/farm3_lims2_vms/software/perl/bin/generate_primers_attempts.pl';
        my @cmd = ( $primer_script,
               '--params-file' => "$params_file",
               '--output-file' => "$out_file",
               );

        my $runner = WebAppCommon::Util::FarmJobRunner->new;

        my $done;
        $self->log->debug('Command to submit to farm: ',(join " ", @cmd));
        try {
            $done = $runner->submit_and_wait(
                out_file => $base_dir->file( 'run_generate_primers.out' ),
                err_file => $base_dir->file( 'run_generate_primers.err' ),
                memory_required => '4000',
                queue => 'small',
                timeout  => 300,
                interval => 10,
                cmd      => \@cmd,
            );

            $self->log->debug( "Job completion status: $done" );
        }
        catch {
            die("Error running primer generation job on farm ".$_);
        };

        if($done){
            my $results = decode_json( $out_file->slurp );
            $primer_data = $results->{primer_data};
            $seq = Bio::Seq->new( -seq => $results->{seq} );
            # This is needed for internal primer generation
            # Output file contains five and three prime size and offsets
            $five_prime_region_size = $results->{five_prime_region_size};
        }
        else{
            die("Primer generation on farm failed or did not complete within expected time");
        }
    }
    else{
        my $primer_finder = HTGT::QC::Util::GeneratePrimersAttempts->new($params);
        ($primer_data, $seq) = $primer_finder->find_primers;
        # This is needed for internal primer generation
        $five_prime_region_size = $primer_finder->five_prime_region_size;
    }

    return ($primer_data, $seq, $five_prime_region_size);
}
__PACKAGE__->meta->make_immutable;

1;

__END__
