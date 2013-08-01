package LIMS2::Util::TarmitsFeedCreKnockin;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::TarmitsFeedCreKnockin::VERSION = '0.017';
}
## use critic


use Moose;
use LIMS2::Model;
use Log::Log4perl qw( :easy );
use Try::Tiny;                              # Exception handling
use LIMS2::Util::Tarmits;
use Const::Fast;

Log::Log4perl->easy_init($DEBUG);

has model => (
    is         => 'ro',
    isa        => 'LIMS2::Model',
    required   => 1,
);

has species => (
    is         => 'ro',
    isa        => 'Str',
    required   => 1,
);

has accepted_clones => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
);

has count_failed_allele_selects => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_found_alleles => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_not_found_alleles => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has failed_allele_selects => (
    is         => 'rw',
    isa        => 'HashRef',
    lazy_build => 1,
);

has count_allele_inserts => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_failed_allele_inserts => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_failed_tv_selects => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_found_tvs => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_not_found_tvs => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_tv_inserts => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_tv_updates => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_failed_tv_updates => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_failed_tv_inserts => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_failed_es_cell_selects => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_found_es_cells => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_not_found_es_cells => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_es_cell_inserts => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_es_cell_rtp_updates => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_failed_es_cell_rtp_updates => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_es_cell_asym_updates => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_failed_es_cell_asym_updates => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has count_failed_es_cell_inserts => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

sub _build_accepted_clones {
    my $self = shift;

    $self->count_failed_allele_selects(0);
    $self->failed_allele_selects({});
    $self->count_failed_tv_selects(0);
    $self->count_failed_es_cell_selects(0);

    my @accepted_clones_array = $self->select_accepted_clones();

	my %accepted_clones = $self->refactor_selected_clones( @accepted_clones_array );

    DEBUG "TarmitsFeedCreKnockin: -------------- Select Totals -------------";
    DEBUG "TarmitsFeedCreKnockin: Count of FAILED rows for Allele selects:"               . $self->count_failed_allele_selects;

    my %failed_allele_selects_copy = %{ $self->failed_allele_selects };
    foreach my $gene ( keys %failed_allele_selects_copy )
    {
      DEBUG 'TarmitsFeedCreKnockin: Failed select for: Gene: ' . $gene . ', Design ID: ' . $failed_allele_selects_copy{$gene} . "\n";
    }

    DEBUG "TarmitsFeedCreKnockin: Count of FAILED rows for Targeting vector selects:"     . $self->count_failed_tv_selects;
    DEBUG "TarmitsFeedCreKnockin: Count of FAILED rows for ES Cell clone selects:"        . $self->count_failed_es_cell_selects;

    DEBUG "TarmitsFeedCreKnockin: -------------- Selects End ---------------";

    return \%accepted_clones;
}

sub select_accepted_clones {
    my $self = shift;

    # fetch the list of accepted EP_PICK wells that match to Cre Knockin sponsor projects
    my $sponsor_id    = 'Cre Knockin';
    my $sql_query     = $self->sql_select_st_accepted_clones ( $sponsor_id );
    my $sql_resultset = $self->run_select_query( $sql_query );

    my @accepted_clones_array;

    foreach my $accepted_clone ( @$sql_resultset ) {
       push( @accepted_clones_array, $accepted_clone );
    }

    return [ @accepted_clones_array ];
}

# check each one is up to date in Tarmits
sub check_clones_against_tarmits {
    my $self = shift;

    $self->count_found_alleles(0);
    $self->count_not_found_alleles(0);
    $self->count_allele_inserts(0);
    $self->count_failed_allele_inserts(0);

    $self->count_found_tvs(0);
    $self->count_not_found_tvs(0);
    $self->count_tv_inserts(0);
    $self->count_tv_updates(0);
    $self->count_failed_tv_updates(0);
    $self->count_failed_tv_inserts(0);

    $self->count_found_es_cells(0);
    $self->count_not_found_es_cells(0);
    $self->count_es_cell_inserts(0);
    $self->count_es_cell_rtp_updates(0);
    $self->count_failed_es_cell_rtp_updates(0);
    $self->count_es_cell_asym_updates(0);
    $self->count_failed_es_cell_asym_updates(0);
    $self->count_failed_es_cell_inserts(0);

    my %accepted_clones_data = %{ $self->accepted_clones };

    for my $curr_gene_mgi_id ( sort keys %accepted_clones_data ) {

        $self->check_gene($curr_gene_mgi_id);

    }

    DEBUG "TarmitsFeedCreKnockin: -------------- Tarmits update Totals ------------";
    DEBUG "TarmitsFeedCreKnockin: Count of FAILED rows for Allele select:"                . $self->count_failed_allele_selects;

    my %failed_allele_selects_copy = %{ $self->failed_allele_selects };
    foreach my $gene ( keys %failed_allele_selects_copy )
    {
      DEBUG 'TarmitsFeedCreKnockin: Failed select Gene: ' . $gene . ', Design ID: ' . $failed_allele_selects_copy{$gene};
    }

    DEBUG "TarmitsFeedCreKnockin: Count of FAILED rows for Targeting vector selects:"     . $self->count_failed_tv_selects;
    DEBUG "TarmitsFeedCreKnockin: Count of FAILED rows for ES Cell clone selects:"        . $self->count_failed_es_cell_selects;

    DEBUG "TarmitsFeedCreKnockin: Count of rows where Allele already in Tarnits:"         . $self->count_found_alleles;
    DEBUG "TarmitsFeedCreKnockin: Count of rows where Allele not found in Tarmits:"       . $self->count_not_found_alleles;
    DEBUG "TarmitsFeedCreKnockin: Count of rows where Allele was inserted:"               . $self->count_allele_inserts;
    DEBUG "TarmitsFeedCreKnockin: Count of FAILED rows for Allele inserts:"               . $self->count_failed_allele_inserts;

    DEBUG "TarmitsFeedCreKnockin: Count of rows where Targeting vector already in Tarnits:"         . $self->count_found_tvs;
    DEBUG "TarmitsFeedCreKnockin: Count of rows where Targeting vector not found in Tarmits:"       . $self->count_not_found_tvs;
    DEBUG "TarmitsFeedCreKnockin: Count of rows where Targeting vector was inserted:"               . $self->count_tv_inserts;
    DEBUG "TarmitsFeedCreKnockin: Count of rows where Targeting vector report flag was updated:"    . $self->count_tv_updates;
    DEBUG "TarmitsFeedCreKnockin: Count of FAILED rows for Targeting vector inserts:"               . $self->count_failed_tv_inserts;

    DEBUG "TarmitsFeedCreKnockin: Count of rows where ES Cell already in Tarnits:"                          . $self->count_found_es_cells;
    DEBUG "TarmitsFeedCreKnockin: Count of rows where ES Cell not found in Tarmits:"                        . $self->count_not_found_es_cells;
    DEBUG "TarmitsFeedCreKnockin: Count of rows where ES Cell was inserted into Tarmits:"                   . $self->count_es_cell_inserts;
    DEBUG "TarmitsFeedCreKnockin: Count of rows where ES Cell report to public flag was updated:"           . $self->count_es_cell_rtp_updates;
    DEBUG "TarmitsFeedCreKnockin: Count of FAILED rows for ES Cell report to public flag updates:"          . $self->count_failed_es_cell_rtp_updates;
    DEBUG "TarmitsFeedCreKnockin: Count of rows where ES Cell allele symbol superscript flag was updated:"  . $self->count_es_cell_asym_updates;
    DEBUG "TarmitsFeedCreKnockin: Count of FAILED rows for ES Cell allele symbol superscript flag updates:" . $self->count_failed_es_cell_asym_updates;
    DEBUG "TarmitsFeedCreKnockin: Count of FAILED rows for ES Cell inserts:"                                . $self->count_failed_es_cell_inserts;

    DEBUG "TarmitsFeedCreKnockin: -------------- Tarmits update End ---------------";

    return;
}

sub check_gene {
    my $self = shift;
    my $curr_gene_mgi_id = shift;

    my %accepted_clones_data = %{$self->accepted_clones};

    DEBUG "TarmitsFeedCreKnockin: Gene = $curr_gene_mgi_id:";

    for my $curr_design_id ( sort keys %{ $accepted_clones_data{ $curr_gene_mgi_id }->{ 'designs' } } ) {

        $self->check_allele($curr_gene_mgi_id, $curr_design_id);

    }

    return;
}

sub check_allele {
    my $self = shift;
    my $curr_gene_mgi_id = shift;
    my $curr_design_id = shift;

    my %accepted_clones_data = %{$self->accepted_clones};

    DEBUG "TarmitsFeedCreKnockin: Design = $curr_design_id: \n";

    my $design = $accepted_clones_data{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id };

    my $tm = LIMS2::Util::Tarmits->new_with_config;

    # List of unique design features
    # :gene_id, 
    # :assembly,
    # :chromosome,
    # :strand,
    # :cassette,
    # :backbone,
    # :homology_arm_start,
    # :homology_arm_end,
    # :cassette_start,
    # :cassette_end,
    # :loxp_start,
    # :loxp_end

    my %find_allele_params = (
        'project_design_id_eq'     => $curr_design_id,
        'gene_mgi_accession_id_eq' => $curr_gene_mgi_id,
        'assembly_eq'              => $design->{ 'design_details' }->{ 'genomic_position' }->{ 'assembly' },
        'chromosome_eq'            => $design->{ 'design_details' }->{ 'genomic_position' }->{ 'chromosome' },
        'strand_eq'                => $design->{ 'design_details' }->{ 'genomic_position' }->{ 'strand' },
        'cassette_eq'              => $design->{ 'design_details' }->{ 'mutation_details' }->{ 'cassette' },
        'backbone_eq'              => $design->{ 'design_details' }->{ 'mutation_details' }->{ 'backbone' },
        'homology_arm_start_eq'    => $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'homology_arm' }->{ 'start' },
        'homology_arm_end_eq'      => $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'homology_arm' }->{ 'end' },
        'cassette_start_eq'        => $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'cassette' }->{ 'start' },
        'cassette_end_eq'          => $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'cassette' }->{ 'end' },
    );

    if ( defined $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'start' } ) {
        $find_allele_params{ 'loxp_start_eq' } = $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'start' };
    }
    if ( defined $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'end' } ) {
        $find_allele_params{ 'loxp_end_eq' } = $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'end' };
    }

    # access Tarmits to see if we can locate the allele
    my $find_allele_results = $tm->find_allele( \%find_allele_params );

    my $insert_error = 0;

    # allele id needed for targeting vector checks
    my $curr_allele_id;

    if ( defined $find_allele_results && scalar @{ $find_allele_results } > 0 ) {

        # allele already exists in Tarmits
        $self->count_found_alleles($self->count_found_alleles + 1);

        # fetch allele id for use when looking at targeting vectors
        $curr_allele_id = $find_allele_results->[0]->{ 'id' };

        DEBUG 'TarmitsFeedCreKnockin: Found allele match, continuing. Allele ID: ' . $curr_allele_id;
    }
    else
    {
        # did not find allele in Tarmits, insert it
        $self->count_not_found_alleles($self->count_not_found_alleles + 1);
        DEBUG 'TarmitsFeedCreKnockin: No allele match, inserting';

        my %insert_allele_params = (
            'project_design_id'        => $curr_design_id,
            'gene_mgi_accession_id'    => $curr_gene_mgi_id,
            'assembly'                 => $design->{ 'design_details' }->{ 'genomic_position' }->{ 'assembly' },
            'chromosome'               => $design->{ 'design_details' }->{ 'genomic_position' }->{ 'chromosome' },
            'strand'                   => $design->{ 'design_details' }->{ 'genomic_position' }->{ 'strand' },
            'cassette'                 => $design->{ 'design_details' }->{ 'mutation_details' }->{ 'cassette' },
            'backbone'                 => $design->{ 'design_details' }->{ 'mutation_details' }->{ 'backbone' },
            'homology_arm_start'       => $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'homology_arm' }->{ 'start' },
            'homology_arm_end'         => $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'homology_arm' }->{ 'end' },
            'cassette_start'           => $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'cassette' }->{ 'start' },
            'cassette_end'             => $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'cassette' }->{ 'end' },
            'cassette_type'            => $design->{ 'design_details' }->{ 'mutation_details' }->{ 'cassette_type' },
            'mutation_type_name'       => $design->{ 'design_details' }->{ 'mutation_details' }->{ 'mutation_type' },
            # leave mutation subtype blank
            #'mutation_subtype_name'    => $design->{ 'design_details' }->{ 'mutation_details' }->{ 'mutation_subtype' },
            'mutation_method_name'     => $design->{ 'design_details' }->{ 'mutation_details' }->{ 'mutation_method' },
            'floxed_start_exon'        => $design->{ 'design_details' }->{ 'mutation_details' }->{ 'floxed_start_exon' },
            'floxed_end_exon'          => $design->{ 'design_details' }->{ 'mutation_details' }->{ 'floxed_end_exon' },
        );

        if ( defined $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'start' } ) {
            $insert_allele_params{ 'loxp_start' } = $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'start' };
        }
        if ( defined $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'end' } ) {
            $insert_allele_params{ 'loxp_end' } = $design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'end' };
        }

        try {
            my $insert_allele_results = $tm->create_allele( \%insert_allele_params );

            if ( $insert_allele_results->{ 'project_design_id' } == $curr_design_id ) {

                $self->count_allele_inserts($self->count_allele_inserts + 1);

                # store allele id for use for targeting vector inserts
                $curr_allele_id = $insert_allele_results->{ 'id' };

                DEBUG 'TarmitsFeedCreKnockin: Inserted allele successfully, continuing. Allele ID: ' . $curr_allele_id;
            }
            else {

                DEBUG "TarmitsFeedCreKnockin: Check on inserted Allele failed for gene: " . $curr_gene_mgi_id . " design: ". $curr_design_id;

                # increment counter
                $self->count_failed_allele_inserts($self->count_failed_allele_inserts + 1);
                $insert_error = 1;
            }

        } catch {
            DEBUG "TarmitsFeedCreKnockin: Failed Allele insert for gene: " . $curr_gene_mgi_id . " design: ". $curr_design_id . " Exception: " . $_;

            # increment counter
            $self->count_failed_allele_inserts($self->count_failed_allele_inserts + 1);
            $insert_error = 1;
        }
    }

    # do not continue on with targeting vectors and clones for this allele
    return if $insert_error;

    # Cycle through the targeting vectors in the allele
    for my $curr_targeting_vector_name ( sort keys %{ $accepted_clones_data{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id }->{ 'targeting_vectors' } } ) {

        $self->check_targeting_vector($tm, $curr_gene_mgi_id, $curr_design_id, $curr_allele_id, $curr_targeting_vector_name);

    }

    return;
}

sub check_targeting_vector {
    my ($self, $tm, $curr_gene_mgi_id, $curr_design_id, $curr_allele_id, $curr_targeting_vector_name ) = @_;

    my %accepted_clones_data = %{$self->accepted_clones};

    DEBUG "TarmitsFeedCreKnockin: TargVect = $curr_targeting_vector_name:";

    my $tv = $accepted_clones_data{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id }->{ 'targeting_vectors' }->{ $curr_targeting_vector_name };

    # List of unique targeting vector features
    # name

    my %find_tv_params = (
        'name_eq' => $curr_targeting_vector_name,
    );

    # return type should be an array of hashes
    my $tv_find_results = $tm->find_targeting_vector( \%find_tv_params );

    my $insert_error = 0;

    # targeting vector id needed for es cell clone checks
    my $curr_targeting_vector_id;

    if ( defined $tv_find_results && scalar @{ $tv_find_results } > 0 ) {

        # targeting vector already exists in Tarmits
        $self->count_found_tvs($self->count_found_tvs + 1);

        # fetch targeting vector id for use when looking at es cell clones
        $curr_targeting_vector_id = $tv_find_results->[0]->{ 'id' };

        DEBUG 'TarmitsFeedCreKnockin: Found targeting vector match, ID: ' . $curr_targeting_vector_id . ' checking report to public flag';

        if ( $tv_find_results->[0]->{ 'report_to_public' } == 0 ) {

            # update report to public flag to true
            DEBUG 'TarmitsFeedCreKnockin: Targeting Vector report to public is currently false, need to update it to true';

            try {
                my %update_tv_params = (
                    'report_to_public' => $tv->{ 'targeting_vector_details' }->{ 'report_to_public' },
                );

                # update takes the id of the item plus the updated parameters
                my $tv_update_results = $tm->update_targeting_vector( $curr_targeting_vector_id, \%update_tv_params );

                if ( defined $tv_update_results && scalar @{ $tv_update_results } > 0 ) {
                    $self->count_tv_updates($self->count_tv_updates + 1);
                    DEBUG 'TarmitsFeedCreKnockin: Updated targeting vector successfully, continuing';
                }
                else {
                    $self->count_failed_tv_updates($self->count_failed_tv_updates + 1);

                    DEBUG 'TarmitsFeedCreKnockin: Check on update of targeting vector failed for gene: ' . $curr_gene_mgi_id . ', design: ' . $curr_design_id . ', targeting vector: ' . $curr_targeting_vector_name . ', targeting vector id: ' . $curr_targeting_vector_id;
                }
            }
            catch {
                $self->count_failed_tv_updates($self->count_failed_tv_updates + 1);
                $insert_error = 1;

                DEBUG 'TarmitsFeedCreKnockin: Failed Targeting vector insert for gene: ' . $curr_gene_mgi_id . ', design: '. $curr_design_id . ', targeting vector: ' . $curr_targeting_vector_name . ' Exception: ' . $_;
            }
        }
        else {
            DEBUG 'TarmitsFeedCreKnockin: Targeting vector report to public flag already set, continuing';
        }
    }
    else
    {
        # did not find targeting vector in Tarmits, insert it
        $self->count_not_found_tvs($self->count_not_found_tvs + 1);
        DEBUG 'TarmitsFeedCreKnockin: No targeting vector match, inserting';

        my $ikmc_proj_id = ( $tv->{ 'targeting_vector_details' }->{ 'pipeline_name' } ) . '_' . $curr_allele_id;
        #DEBUG 'TarmitsFeedCreKnockin: ikmc_proj_id = ' . $ikmc_proj_id;

        my %insert_tv_params = (
            'name'                  => $curr_targeting_vector_name,
            'allele_id'             => $curr_allele_id,
            'ikmc_project_id'       => $ikmc_proj_id,
            'intermediate_vector'   => $tv->{ 'targeting_vector_details' }->{ 'intermediate_vector' },
            'pipeline_id'           => $tv->{ 'targeting_vector_details' }->{ 'pipeline_id' },
            'report_to_public'      => $tv->{ 'targeting_vector_details' }->{ 'report_to_public' },
        );

        try {
            my $results_tv_insert = $tm->create_targeting_vector( \%insert_tv_params );

            if ( defined $results_tv_insert && ( $results_tv_insert->{ 'name' } eq $curr_targeting_vector_name ) ) {

                $self->count_tv_inserts($self->count_tv_inserts + 1);

                # store targeting vector id for use for es cell clone checks
                $curr_targeting_vector_id = $results_tv_insert->{ 'id' };

                DEBUG 'TarmitsFeedCreKnockin: Inserted targeting vector successfully, new ID: ' . $curr_targeting_vector_id . ', continuing';
            }
            else {

                DEBUG "TarmitsFeedCreKnockin: Check on inserted targeting vector failed for gene: " . $curr_gene_mgi_id . ", design: ". $curr_design_id . ", targeting vector: " . $curr_targeting_vector_name;

                # increment counter
                $self->count_failed_tv_inserts($self->count_failed_tv_inserts + 1);
                $insert_error = 1;
            }

        } catch {
            DEBUG "TarmitsFeedCreKnockin: Failed Targeting vector insert for gene: " . $curr_gene_mgi_id . ", design: ". $curr_design_id . ", targeting vector: " . $curr_targeting_vector_name . " Exception: " . $_;

            # increment counter
            $self->count_failed_tv_inserts($self->count_failed_tv_inserts + 1);
            $insert_error = 1;
        }
    }

    # do not continue on with clones for this allele and targeting vector
    return if $insert_error;

    for my $curr_clone_name ( sort keys %{ $accepted_clones_data{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id }->{ 'targeting_vectors' }->{ $curr_targeting_vector_name }->{ 'clones' } } ) {

        $self->check_es_cells( $tm, $curr_gene_mgi_id, $curr_design_id, $curr_allele_id, $curr_targeting_vector_name, $curr_targeting_vector_id, $curr_clone_name );
    }

    return;
}

sub check_es_cells {  ##no critic(ProhibitManyArgs)
    my ($self, $tm, $curr_gene_mgi_id, $curr_design_id, $curr_allele_id, $curr_targeting_vector_name, $curr_targeting_vector_id, $curr_clone_name ) = @_;
    ## use critic
    DEBUG 'TarmitsFeedCreKnockin: Clone = ' . $curr_clone_name;

    my %accepted_clones_data = %{$self->accepted_clones};

    my $clone = $accepted_clones_data{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id }->{ 'targeting_vectors' }->{ $curr_targeting_vector_name }->{ 'clones' }->{ $curr_clone_name };

    # List of unique clone features
    # name

    my %find_clone_params = (
        'name_eq' => $curr_clone_name,
    );

    # return type should be an array of hashes
    my $clone_find_results = $tm->find_es_cell( \%find_clone_params );

    # es cell clone id needed for updates
    my $curr_es_cell_clone_id;

    if ( defined $clone_find_results && scalar @{ $clone_find_results } > 0 ) {

        # es cell clone already exists in Tarmits
        $self->count_found_es_cells($self->count_found_es_cells + 1);

        # fetch es cell clone id
        $curr_es_cell_clone_id = $clone_find_results->[0]->{ 'id' };

        DEBUG 'TarmitsFeedCreKnockin: Found es cell clone match,ID: ' . $curr_es_cell_clone_id . ', checking report to public flag';

        if ( $clone_find_results->[0]->{ 'report_to_public' } == 0 ) {

            DEBUG 'TarmitsFeedCreKnockin: ES Cell clone report to public is currently false, need to update it to true';

            try {
                my %update_es_cell_params = (
                    'report_to_public' => $clone->{ 'es_cell_details' }->{ 'report_to_public' },
                );

                # update takes the id of the item plus the updated parameters
                my $clone_update_resultset = $tm->update_es_cell( $curr_es_cell_clone_id, \%update_es_cell_params );

                if ( defined $clone_update_resultset && $clone_update_resultset != 0 ) {
                    $self->count_es_cell_rtp_updates($self->count_es_cell_rtp_updates + 1);
                    DEBUG 'TarmitsFeedCreKnockin: Updated report to public for ES cell clone ID: ' . $curr_es_cell_clone_id . ' successfully, continuing';
                }
                else {
                    $self->count_failed_es_cell_rtp_updates($self->count_failed_es_cell_rtp_updates + 1);

                    DEBUG "TarmitsFeedCreKnockin: Check on update of report to public for ES cell clone failed for gene: " . $curr_gene_mgi_id . ", design: ". $curr_design_id . ", targeting vector: " . $curr_targeting_vector_name . ", es cell clone name: " . $curr_clone_name;
                }
            }
            catch {
                $self->count_failed_es_cell_rtp_updates($self->count_failed_es_cell_rtp_updates + 1);

                DEBUG "TarmitsFeedCreKnockin: Failed report to public update fot ES Cell clone for gene: " . $curr_gene_mgi_id . ", design: ". $curr_design_id . ", targeting vector: " . $curr_targeting_vector_name . ", es cell clone name: " . $curr_clone_name . " Exception: " . $_;
            }
        }
        else {
            DEBUG 'TarmitsFeedCreKnockin: ES Cells report to public flag already set, continuing';
        }

        # check allele symbol superscript set for ES clone, if not set it

        if ( not defined ( $clone_find_results->[0]->{ 'allele_symbol_superscript' } ) ) {
            DEBUG 'TarmitsFeedCreKnockin: ES Cells allele symbol superscript empty, attempting to update';

            try {
                my %update_es_cell_params = (
                    'allele_symbol_superscript' => $clone->{ 'es_cell_details' }->{ 'allele_symbol_superscript' },
                );

                # update takes the id of the item plus the updated parameters
                my $clone_update_resultset = $tm->update_es_cell( $curr_es_cell_clone_id, \%update_es_cell_params );

                if ( defined $clone_update_resultset && $clone_update_resultset != 0 ) {
                    $self->count_es_cell_asym_updates($self->count_es_cell_asym_updates + 1);
                    DEBUG 'TarmitsFeedCreKnockin: Updated allele symbol superscript for ES cell clone ID: ' . $curr_es_cell_clone_id . ' successfully, continuing';
                }
                else {
                    $self->count_failed_es_cell_asym_updates($self->count_failed_es_cell_asym_updates + 1);

                    DEBUG "TarmitsFeedCreKnockin: Check on update of allele symbol superscript for ES cell clone failed for gene: " . $curr_gene_mgi_id . ", design: ". $curr_design_id . ", targeting vector: " . $curr_targeting_vector_name . ", es cell clone name: " . $curr_clone_name;
                }
            }
            catch {
                $self->count_failed_es_cell_asym_updates($self->count_failed_es_cell_asym_updates + 1);

                DEBUG "TarmitsFeedCreKnockin: Failed allele symbol superscript update for ES Cell clone for gene: " . $curr_gene_mgi_id . ", design: ". $curr_design_id . ", targeting vector: " . $curr_targeting_vector_name . ", es cell clone name: " . $curr_clone_name . " Exception: " . $_;
            }

        }
        else {
            DEBUG 'TarmitsFeedCreKnockin: ES Cells allele symbol superscript already set, continuing';
        }

    }
    else
    {
        # did not find es cell clone in Tarmits, insert it
        $self->count_not_found_es_cells($self->count_not_found_es_cells + 1);
        DEBUG 'TarmitsFeedCreKnockin: No es cell clone match, inserting';

        my $ikmc_proj_id = ( $clone->{ 'es_cell_details' }->{ 'pipeline_name' } ) . '_' . $curr_allele_id;
        #DEBUG 'TarmitsFeedCreKnockin: ikmc_proj_id = ' . $ikmc_proj_id;

        my %insert_es_cell_params = (
            'name'                  => $curr_clone_name,
            'allele_id'             => $curr_allele_id,
            'ikmc_project_id'       => $ikmc_proj_id,
            'targeting_vector_id'   => $curr_targeting_vector_id,
            'parental_cell_line'    => $clone->{ 'es_cell_details' }->{ 'parental_cell_line' },
            'pipeline_id'           => $clone->{ 'es_cell_details' }->{ 'pipeline_id' },
            'report_to_public'      => $clone->{ 'es_cell_details' }->{ 'report_to_public' },
            'allele_symbol_superscript'        => $clone->{ 'es_cell_details' }->{ 'allele_symbol_superscript' },
            # 'production_qc_five_prime_screen'  => $clone->{ 'qc_metrics' }->{ 'five_prime_screen' },
            # 'production_qc_three_prime_screen' => $clone->{ 'qc_metrics' }->{ 'three_prime_screen' },
            # 'production_qc_loxp_screen'        => $clone->{ 'qc_metrics' }->{ 'loxp_screen' },
            # 'production_qc_loss_of_allele'     => $clone->{ 'qc_metrics' }->{ 'loss_of_allele' },
            # 'production_qc_vector_integrity'   => $clone->{ 'qc_metrics' }->{ 'vector_integrity' },
        );

        try {
            my $results_es_cell_insert = $tm->create_es_cell( \%insert_es_cell_params );

            if ( defined $results_es_cell_insert && ( $results_es_cell_insert->{ 'name' } eq $curr_clone_name ) ) {

                $self->count_es_cell_inserts($self->count_es_cell_inserts + 1);

                # store es cell clone id
                $curr_es_cell_clone_id = $results_es_cell_insert->{ 'id' };

                DEBUG 'TarmitsFeedCreKnockin: Inserted es cell clone successfully, new ID: ' . $curr_es_cell_clone_id . ', continuing';
            }
            else {

                DEBUG "TarmitsFeedCreKnockin: Check on inserted es cell clone failed for gene: " . $curr_gene_mgi_id . ", design: ". $curr_design_id . ", targeting vector: " . $curr_targeting_vector_name . ", es cell clone name: " . $curr_clone_name;

                # increment counter
                $self->count_failed_es_cell_inserts($self->count_failed_es_cell_inserts + 1);
            }

        } catch {
            DEBUG "TarmitsFeedCreKnockin: Failed ES Cell clone insert for gene: " . $curr_gene_mgi_id . ", design: ". $curr_design_id . ", targeting vector: " . $curr_targeting_vector_name . ", es cell clone name: " . $curr_clone_name . " Exception: " . $_;

            # increment counter
            $self->count_failed_es_cell_inserts($self->count_failed_es_cell_inserts + 1);
        }
    }

    return;
}

sub refactor_selected_clones {
    my $self = shift;
    my $accepted_clones_array = shift;

    my %results_refactored;

    RESULTS_LOOP: foreach my $result (@$accepted_clones_array) {

        my $is_error = 0;

        # if gene doesn't exist in hash then add it
        my $current_gene_id = $result->{ 'design_gene_id' };

        unless ( exists $results_refactored{ $current_gene_id } ) {

            my %gene_details;

            #Gene ascession id - e.g. MGI:2140237                -> from summaries.design_gene_id
            $gene_details{ 'gene_accession_id' }  = $current_gene_id;

            $results_refactored{ $current_gene_id }->{ 'gene_details' }   = { %gene_details };

        }

        next RESULTS_LOOP if $is_error;

        # if current design id (allele) doesn't exist in hash then add it
        my $current_design_id = $result->{ 'design_id' };

        unless ( exists $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id } ) {

            try {

                # fetch design object
                my $design = $self->model->retrieve_design( { 'id' => $result->{ 'design_id' }, 'species' => $self->species } );
                my $design_info = $design->info;

                # hashref of oligos from design info
                my $design_oligos =$design_info->oligos;

                my %design_details;

                #Project Design ID - e.g. 36071                      -> from summaries.design_id
                $design_details{ 'project_design_id' }  = $result->{ 'design_id' };

                # extras
                $design_details{ 'info' }->{ 'lims2_project_id' }   = $result->{ 'project_id' };
                $design_details{ 'info' }->{ 'design_gene_symbol' } = $result->{ 'design_gene_symbol' };
                $design_details{ 'info' }->{ 'design_name' }        = $result->{ 'design_name' };
                $design_details{ 'info' }->{ 'design_phase' }       = $result->{ 'design_phase' };
                $design_details{ 'info' }->{ 'design_type' }        = $result->{ 'design_type' };
                $design_details{ 'info' }->{ 'design_plate_id' }    = $result->{ 'design_plate_id' };
                $design_details{ 'info' }->{ 'design_plate_name' }  = $result->{ 'design_plate_name' };
                $design_details{ 'info' }->{ 'design_well_id' }     = $result->{ 'design_well_id' };
                $design_details{ 'info' }->{ 'design_well_name' }   = $result->{ 'design_well_name' };

                my %new_genomic_position;
                # Genomic Position
                #   Assembly          - e.g. GRCm38                  -> hardcoded
                $new_genomic_position{ 'assembly' }           = 'GRCm38';

                #   Chromosome        - e.g. 4                       -> design->design_info.chr_name
                $new_genomic_position{ 'chromosome' }         = $design_info->chr_name;

                #   Strand            - e.g. +                       -> design->design_info.chr_strand
                my $strand                                    = ( $design_info->chr_strand eq "1" ) ? "+" : "-";
                $new_genomic_position{ 'strand' }             = $strand;

                $design_details{ 'genomic_position' }         = { %new_genomic_position };

                # Mutation Details
                my %new_mutation_details;

                #   Mutation method   - e.g. Targeted Mutation       -> hardcoded
                $new_mutation_details{ 'mutation_method' }    = 'Targeted Mutation';

                #   Mutation type     - e.g. Cre Knock In            -> hardcoded
                $new_mutation_details{ 'mutation_type' }      = 'Cre Knock In'; #change this for any deletions?

                #   Mutation subtype  - e.g. ?                       -> hardcoded
                #$new_mutation_details{ 'mutation_subtype' }   = undef;

                #   Cassette          - e.g. pL1L2_GT0_LF2A          -> summaries.final_pick_cassette_name
                $new_mutation_details{ 'cassette' }           = $result->{ 'vector_cassette_name' };

                #   Cassette Type     - e.g. Promotorless            -> cassettes.promoter
                if ( $result->{ 'vector_cassette_promotor' } ) {
                  $new_mutation_details{ 'cassette_type' }    = 'Promotor Driven';
                }
                else {
                  $new_mutation_details{ 'cassette_type' }    = 'Promotorless';
                }

                #   Backbone          - e.g. L3L4_pD223_DTA_T_spec   -> summaries.final_pick_backbone_name
                $new_mutation_details{ 'backbone' }           = $result->{ 'vector_backbone_name' };

                #   Floxed Exon       - e.g. ?                       -> from designs.target_transcript
                $new_mutation_details{ 'floxed_start_exon' }  = $design_info->first_floxed_exon->stable_id;
                $new_mutation_details{ 'floxed_end_exon' }    = $design_info->last_floxed_exon->stable_id;

                $design_details{ 'mutation_details' }         = { %new_mutation_details };

                my %new_molecular_co_ords;

                my $design_homology_coords                    = $self->_get_homology_arm_coords( $design_oligos, $strand );
                my $design_cassette_coords                    = $self->_get_cassette_coords( $design_oligos, $strand, $design_info->type );
                my $design_loxp_coords                        = $self->_get_loxp_coords( $design_oligos, $strand, $design_info->type );

                # Molecular Co-Ordinates                             -> from design info
                #   Feature       Start       End
                #   Homology Arm  45983698    45993919
                $new_molecular_co_ords{ 'homology_arm' }->{ 'start' } = $design_homology_coords->{ 'homology_arm_start' };
                $new_molecular_co_ords{ 'homology_arm' }->{ 'end' }   = $design_homology_coords->{ 'homology_arm_end' };

                #   Cassette      45988603    45988690
                $new_molecular_co_ords{ 'cassette' }->{ 'start' }     = $design_cassette_coords->{ 'cassette_start' };
                $new_molecular_co_ords{ 'cassette' }->{ 'end' }       = $design_cassette_coords->{ 'cassette_end' };

                #   LoxP          45989415    45989491
                $new_molecular_co_ords{ 'loxp' }->{ 'start' }         = $design_loxp_coords->{ 'loxp_start' };
                $new_molecular_co_ords{ 'loxp' }->{ 'end' }           = $design_loxp_coords->{ 'loxp_end' };

                $design_details{ 'molecular_co_ords' }                = { %new_molecular_co_ords };

                $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id }->{ 'design_details' } = { %design_details };

            } catch {

                DEBUG "TarmitsFeedCreKnockin: Failed Allele selection for gene: " . $result->{ 'design_gene_id' } . " design: ". $result->{ 'design_id' } . " Exception: " . $_;

                # increment counter
                $self->count_failed_allele_selects($self->count_failed_allele_selects + 1);

                # add details tp failed hash for report
                my %failed_allele_selects_copy = %{ $self->failed_allele_selects };
                $failed_allele_selects_copy{ $current_gene_id } = $current_design_id;
                $self->failed_allele_selects( \%failed_allele_selects_copy );

                # set flag to trigger next loop cycle (cannot next here as out of scope)
                $is_error = 1;
            };
        }

        next RESULTS_LOOP if $is_error;

        # if vector info doesn't exist in allele hash then add it
        my $targeting_vector_id = $result->{ 'targeting_vector_plate_name' } . '_' . $result->{ 'targeting_vector_well_name' };
        my $intermediate_vector_id = $result->{ 'int_plate_name' } . '_' . $result->{ 'int_well_name' };

        unless ( exists $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id }->{ 'targeting_vectors' }->{ $targeting_vector_id } ) {
            my %new_tar_vec;
            $new_tar_vec{ 'info' }->{ 'targeting_vector_plate_id' }   = $result->{ 'targeting_vector_plate_id' };
            $new_tar_vec{ 'info' }->{ 'targeting_vector_plate_name' } = $result->{ 'targeting_vector_plate_name' };
            $new_tar_vec{ 'info' }->{ 'targeting_vector_well_id' }    = $result->{ 'targeting_vector_well_id' };
            $new_tar_vec{ 'info' }->{ 'targeting_vector_well_name' }  = $result->{ 'targeting_vector_well_name' };
            $new_tar_vec{ 'info' }->{ 'vector_cassette_promotor' }    = $result->{ 'vector_cassette_promotor' };
            #$new_tar_vec{ '' }    = $result->{ '' };        

            my %new_targeting_vectors;
            # Targeting Vectors (multiple rows)
            #   Pipeline             - e.g. EUCOMMToolsCre          -> hardcoded
            $new_targeting_vectors{ 'pipeline_name' }       = 'EUCOMMToolsCre';
            $new_targeting_vectors{ 'pipeline_id' }         = 8;

            #   IKMC project ID      - e.g. 125168                  -> create this from pipeline and allele id e.g. EUCOMMToolsCre_23456
            #$new_targeting_vectors{ 'ikmc_project_id' }     = 'tbc';

            #   Targeting vector     - e.g. ETPG0008_Z_3_B03        -> from summaries.final_pick_plate_name and _well_name
            $new_targeting_vectors{ 'targeting_vector' }    = $targeting_vector_id;

            #   Intermediate vector  - e.g. ETPCS0008_A_1_C03       -> from summaries.int_plate_name and _well_name
            $new_targeting_vectors{ 'intermediate_vector' } = $intermediate_vector_id;

            #   Report to public     - e.g. boolean, tick or cross  -> set to true
            $new_targeting_vectors{ 'report_to_public' }    = 1;

            $new_tar_vec{ 'targeting_vector_details' }      = { %new_targeting_vectors };

            $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id }->{ 'targeting_vectors' }->{ $targeting_vector_id } = { %new_tar_vec };
        }

        next RESULTS_LOOP if $is_error;

        # add clone to hash
        my $es_cell_id = $result->{ 'clone_plate_name' } . '_' . $result->{ 'clone_well_name' };

        unless ( exists $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id }->{ 'targeting_vectors' }->{ $targeting_vector_id }->{ 'clones' }->{ $es_cell_id } ) {

            my $clone_well = $self->model->retrieve_well( { 'id' => $result->{ 'clone_well_id' } } );

            my %new_clone;

            $new_clone{ 'info' }->{ 'clone_plate_id' }     = $result->{ 'clone_plate_id' };
            $new_clone{ 'info' }->{ 'clone_plate_name' }   = $result->{ 'clone_plate_name' };
            $new_clone{ 'info' }->{ 'clone_well_id' }      = $result->{ 'clone_well_id' };
            $new_clone{ 'info' }->{ 'clone_well_name' }    = $result->{ 'clone_well_name' };
            #$new_clone{ '' }    = $result->{ '' };

            my %es_cell_details;
            # ES Cells (multiple rows)
            #   Pipeline                  - e.g. EUCOMMToolsCre          -> hardcoded
            $es_cell_details{ 'pipeline_name' }             = 'EUCOMMToolsCre';
            $es_cell_details{ 'pipeline_id' }               = 8;

            #   ES Cell                   - e.g. CEPD0026_4_B10          -> from summaries.ep_pick_plate_name and _well_name
            $es_cell_details{ 'es_cell_id' }                = $es_cell_id;

            #   Targeting Vector          - e.g. ETPG0008_Z_3_B03        -> from summaries.final_pick_plate_name and _well_name
            $es_cell_details{ 'targeting_vector' }          = $targeting_vector_id;

            #   MGI Allele ID             - e.g. empty...                -> ?
            $es_cell_details{ 'mgi_allele_id' }             = 'tbc';

            #   Allele symbol superscript - e.g. empty...                -> ?
            $es_cell_details{ 'allele_symbol_superscript' } = 'tm1(CreERT2_EGFP)Wtsi';

            #   Parental Cell Line        - e.g. JM8.N4                  -> from summaries.ep_first_cell_line_name
            $es_cell_details{ 'parental_cell_line' }        = $result->{ 'cell_line' };

            #   IKMC Project ID           - e.g. 125168                  -> created at targeting vector insert time
            #$es_cells{ 'ikmc_project_id' }           = 'tbc';

            #   Report to public          - e.g. boolean, tick or cross  -> set to true
            $es_cell_details{ 'report_to_public' }          = 1;

            $new_clone{ 'es_cell_details' }                 = { %es_cell_details };

            my %qc_metrics;
            #   QC Metrics
            #     Production Centre Screen
            #       5' Screen                - e.g. empty...             -> ?
            $qc_metrics{ 'production_centre_screen' }->{ 'five_prime_screen' }     = 'tbc';

            #       LoxP Screen              - e.g. empty...             -> ?
            $qc_metrics{ 'production_centre_screen' }->{ 'loxp_screen' }           = 'tbc';

            #       3' Screen                - e.g. empty...             -> ?
            $qc_metrics{ 'production_centre_screen' }->{ 'three_prime_screen' }    = 'tbc';

            #       Loss of WT Allele (LOA)  - e.g. empty...             -> ?
            $qc_metrics{ 'production_centre_screen' }->{ 'loss_of_allele' }        = 'tbc';

            #       Vector Integrity         - e.g. empty...             -> ?
            $qc_metrics{ 'production_centre_screen' }->{ 'vector_integrity' }      = 'tbc';

            #     User/Mouse Clinic QC
            #       Mouse Clinic              - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'mouse_clinic' }               = 'tbc';

            #       Southern Blot             - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'southern_blot' }              = 'tbc';

            #       Map Test                  - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'map_test' }                   = 'tbc';

            #       Karyotype                 - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'karyotype' }                  = 'tbc';

            #       Karyotype Spread          - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'karyotype_spread' }           = 'tbc';

            #       Karyotype PCR             - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'karyotype_pcr' }              = 'tbc';

            #       TV Backbone Assay         - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'tv_backbone_assay' }          = 'tbc';

            #       Loss of WT Allele (LOA)   - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'loa' }                        = 'tbc';

            #       5' Cassette Integrity     - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ '5_prime_cassette_integrity' } = 'tbc';

            #       Neo Count (qPCR)          - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'neo_count_qpcr' }             = 'tbc';

            #       Neo SR-PCR                - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'neo_sr_pcr' }                 = 'tbc';

            #       Mutant Specific SR-PCR    - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'mutant_specific_sr_pcr' }     = 'tbc';

            #       LacZ SR-PCR               - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'lacz_sr_pcr' }                = 'tbc';

            #       LacZ qPCR                 - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'lacz_qpcr' }                  = 'tbc';

            #       Chry                      - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'chry' }                       = 'tbc';

            #       Chr1                      - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'chr1' }                       = 'tbc';

            #       Chr8                      - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'chr8' }                       = 'tbc';

            #       Chr11                     - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'chr11' }                      = 'tbc';

            #       LoxP Confirmation         - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'loxp_confirmation' }          = 'tbc';

            #       Loxp SRPCR and Sequencing - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ 'loxp_sr_pcr_sequencing' }     = 'tbc';

            #       3' LR-PCR                 - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ '3_prime_lr_pcr' }             = 'tbc';

            #       5' LR-PCR                 - e.g. empty...            -> ?
            $qc_metrics{ 'use_mouse_clinic_qc' }->{ '5_prime_lr_pcr' }             = 'tbc';

            $new_clone{ 'qc_metrics' }                                             = { %qc_metrics };

            $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id }->{ 'targeting_vectors' }->{ $targeting_vector_id }->{ 'clones' }->{ $es_cell_id } = { %new_clone };
        }
    }

    return %results_refactored;
}

sub _get_loxp_coords {
    my ( $self, $design_oligos, $strand, $design_type ) = @_;

    my %loxp_coords = ();

    if ( ( $design_type eq 'conditional' || $design_type eq 'artificial-intron' )
        and $design_oligos->{ 'D5' }
        and $design_oligos->{ 'D3' } )
    {
        if ( $strand eq '+' ) {
            $loxp_coords{ 'loxp_start' } = $design_oligos->{ 'D5' }->{ 'end' };
            $loxp_coords{ 'loxp_end' }   = $design_oligos->{ 'D3' }->{ 'start' };
        }
        else {
            $loxp_coords{ 'loxp_start' } = $design_oligos->{ 'D5' }->{ 'start' };
            $loxp_coords{ 'loxp_end' }   = $design_oligos->{ 'D3' }->{ 'end' };
        }
    }

    return \%loxp_coords;
}

sub _get_cassette_coords {
    my ( $self, $design_oligos, $strand, $design_type ) = @_;

    my %cassette_coords = ();

    if ( ( $design_type eq 'deletion' || $design_type eq 'insertion' )
        and $design_oligos->{ 'U5' }
        and $design_oligos->{ 'D3' } )
    {
        if ( $strand eq '+' ) {
            $cassette_coords{ 'cassette_start' } = $design_oligos->{ 'U5' }->{ 'end' };
            $cassette_coords{ 'cassette_end' }   = $design_oligos->{ 'D3' }->{ 'start' };
        }
        else {
            $cassette_coords{ 'cassette_start' } = $design_oligos->{ 'U5' }->{ 'start' };
            $cassette_coords{ 'cassette_end' }   = $design_oligos->{ 'D3' }->{ 'end' };
        }
    }
    elsif ( ( $design_type eq 'conditional' || $design_type eq 'artificial-intron' )
        and $design_oligos->{ 'U5' }
        and $design_oligos->{ 'U3' } )
    {
        if ( $strand eq '+' ) {
            $cassette_coords{ 'cassette_start' } = $design_oligos->{ 'U5' }->{ 'end' };
            $cassette_coords{ 'cassette_end' }   = $design_oligos->{ 'U3' }->{ 'start' };
        }
        else {
            $cassette_coords{ 'cassette_start' } = $design_oligos->{ 'U5' }->{ 'start' };
            $cassette_coords{ 'cassette_end' }   = $design_oligos->{ 'U3' }->{ 'end' };
        }
    }

    return \%cassette_coords;
}

sub _get_homology_arm_coords {
    my ( $self, $design_oligos, $strand ) = @_;

    my %homology_arm_coords = ();

    if ( $design_oligos->{ 'G5' } and $design_oligos->{ 'G3' } ) {
        if ( $strand eq '+' ) {
            $homology_arm_coords{ 'homology_arm_start' } = $design_oligos->{ 'G5' }->{ 'end' };
            $homology_arm_coords{ 'homology_arm_end' }   = $design_oligos->{ 'G3' }->{ 'start' };
        }
        else {
            $homology_arm_coords{ 'homology_arm_start' } = $design_oligos->{ 'G5' }->{ 'start' };
            $homology_arm_coords{ 'homology_arm_end' }   = $design_oligos->{ 'G3' }->{ 'end' };
        }
    }

    return \%homology_arm_coords;
}

# Generic method to run select SQL
sub run_select_query {
   my ( $self, $sql_query ) = @_;

   my $sql_result = $self->model->schema->storage->dbh_do(
      sub {
         my ( $storage, $dbh ) = @_;
         my $sth = $dbh->prepare( $sql_query );
         $sth->execute or die "Unable to execute query: $dbh->errstr\n";
         $sth->fetchall_arrayref({

         });
      }
    );

    return $sql_result;
}

# Clones
sub sql_select_st_accepted_clones {
    my ( $self, $sponsor_id ) = @_;

    my $species_id = $self->species;

my $sql_query =  <<"SQL_END";
WITH project_requests AS (
SELECT p.id AS project_id,
 p.sponsor_id,
 p.gene_id,
 p.targeting_type,
 pa.allele_type,
 pa.cassette_function,
 pa.mutation_type,
 cf.id AS cassette_function_id,
 cf.promoter,
 cf.conditional,
 cf.cre,
 cf.well_has_cre,
 cf.well_has_no_recombinase
FROM projects p
INNER JOIN project_alleles pa ON pa.project_id = p.id
INNER JOIN cassette_function cf ON cf.id = pa.cassette_function
WHERE p.sponsor_id = '$sponsor_id'
AND p.targeting_type = 'single_targeted'
AND p.species_id = '$species_id'
)
SELECT pr.project_id
, s.design_id
, s.design_name
, s.design_type
, s.design_phase
, s.design_plate_name
, s.design_plate_id
, s.design_well_name
, s.design_well_id
, s.design_gene_id
, s.design_gene_symbol
, s.int_plate_name
, s.int_plate_id
, s.int_well_name
, s.int_well_id
, s.final_pick_plate_name AS targeting_vector_plate_name
, s.final_pick_plate_id AS targeting_vector_plate_id
, s.final_pick_well_name AS targeting_vector_well_name
, s.final_pick_well_id AS targeting_vector_well_id
, s.final_pick_cassette_name AS vector_cassette_name
, s.final_pick_cassette_promoter AS vector_cassette_promotor
, s.final_pick_backbone_name AS vector_backbone_name
, s.ep_first_cell_line_name AS cell_line
, s.ep_pick_plate_name AS clone_plate_name
, s.ep_pick_plate_id AS clone_plate_id
, s.ep_pick_well_name AS clone_well_name
, s.ep_pick_well_id AS clone_well_id
FROM summaries s
INNER JOIN project_requests pr ON s.design_gene_id = pr.gene_id
WHERE s.design_type IN (SELECT design_type FROM mutation_design_types WHERE mutation_id = pr.mutation_type)
AND (
    (pr.conditional IS NULL)
    OR
    (pr.conditional IS NOT NULL AND s.final_pick_cassette_conditional = pr.conditional)
)
AND (
    (pr.promoter IS NULL)
    OR
    (pr.promoter IS NOT NULL AND pr.promoter = s.final_pick_cassette_promoter)
)
AND (
    (pr.cre IS NULL)
    OR
    (pr.cre IS NOT NULL AND s.final_pick_cassette_cre = pr.cre)
)
AND (
    (pr.well_has_cre IS NULL)
    OR
    (
        (pr.well_has_cre = true AND s.final_pick_recombinase_id = 'Cre')
        OR
        (pr.well_has_cre = false AND (s.final_pick_recombinase_id = '' OR s.final_pick_recombinase_id IS NULL))
    )
)
AND (
    (pr.well_has_no_recombinase IS NULL)
    OR
    (
     pr.well_has_no_recombinase IS NOT NULL AND (
      (pr.well_has_no_recombinase = true AND (s.final_pick_recombinase_id = '' OR s.final_pick_recombinase_id IS NULL))
       OR
      (pr.well_has_no_recombinase = false AND s.final_pick_recombinase_id IS NOT NULL)
     )
    )
)
AND s.ep_pick_well_accepted = true
GROUP by pr.project_id
, s.design_id
, s.design_name
, s.design_type
, s.design_phase
, s.design_plate_name
, s.design_plate_id
, s.design_well_name
, s.design_well_id
, s.design_gene_id
, s.design_gene_symbol
, s.int_plate_name
, s.int_plate_id
, s.int_well_name
, s.int_well_id
, s.final_pick_plate_name
, s.final_pick_plate_id
, s.final_pick_well_name
, s.final_pick_well_id
, s.final_pick_cassette_name
, s.final_pick_cassette_promoter
, s.final_pick_backbone_name
, s.ep_first_cell_line_name
, s.ep_pick_plate_name
, s.ep_pick_plate_id 
, s.ep_pick_well_name
, s.ep_pick_well_id
ORDER BY pr.project_id
, s.design_id
, s.design_gene_id
, s.final_pick_well_id
, s.ep_pick_well_id
SQL_END

    return $sql_query;
}


1;

__END__