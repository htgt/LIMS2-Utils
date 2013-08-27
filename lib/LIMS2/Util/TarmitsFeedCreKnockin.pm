package LIMS2::Util::TarmitsFeedCreKnockin;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::TarmitsFeedCreKnockin::VERSION = '0.019';
}
## use critic


use Moose;
use LIMS2::Model;
use Log::Log4perl qw( :easy );              # TRACE to INFO to WARN to ERROR to LOGDIE
use Try::Tiny;                              # Exception handling
use LIMS2::Util::Tarmits;
use Const::Fast;

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

has gene_id => (
    is         => 'ro',
    isa        => 'Str',
    required   => 0,
);

# to hold large structured hashref of lims2 clones
has es_clones => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
);

# hashref to hold list of failed allele selects for display
has failed_allele_selects => (
    is         => 'rw',
    isa        => 'HashRef',
    default    => sub { {} },
);

has tm => (
    is         => 'ro',
    isa        => 'LIMS2::Util::Tarmits',
    lazy_build => 1,
);

# multiple counters to track what is done
for my $name (
    qw( counter_failed_allele_selects
        counter_found_alleles
        counter_not_found_alleles
        counter_allele_inserts
        counter_failed_allele_inserts
        counter_failed_tv_selects
        counter_found_tvs
        counter_not_found_tvs
        counter_tv_inserts
        counter_failed_tv_inserts
        counter_tv_updates
        counter_failed_tv_updates
        counter_failed_es_cell_selects
        counter_found_es_cells
        counter_not_found_es_cells
        counter_es_cell_inserts
        counter_es_cell_rtp_updates_to_true
        counter_es_cell_rtp_updates_to_false
        counter_failed_es_cell_rtp_updates
        counter_es_cell_asym_updates
        counter_failed_es_cell_asym_updates
        counter_ignored_es_cells
        counter_failed_es_cell_inserts )
    ) {
    my $inc_name = 'inc_' . $name;
    my $dec_name = 'dec_' . $name;
    my $reset_name = 'reset_' . $name;
    has $name => (
        traits  => ['Counter'],
        is      => 'ro',
        isa     => 'Num',
        default => 0,
        handles => {
          $inc_name   => 'inc',
          $dec_name   => 'dec',
          $reset_name => 'reset',
        },
    );
}

sub _build_es_clones {
    my $self = shift;

    my $sponsor_id      = 'Cre Knockin';

    # create SQL to fetch the list of es EP_PICK wells that match to Cre Knockin sponsor projects
    my $sql_query       = $self->sql_select_st_es_clones ( $sponsor_id );

    # run the SQL to fetch rows from the summaries table
    my $es_clones_array = $self->run_select_query( $sql_query );

    # refactor the data from flattened structure into nested hash
    my $es_clones       = $self->refactor_selected_clones( $es_clones_array );

    INFO "-------------- Select Totals -------------";
    INFO "Count of FAILED rows for Allele selects: "               . $self->counter_failed_allele_selects;

    my %failed_allele_selects_copy = %{ $self->failed_allele_selects };
    foreach my $gene ( keys %failed_allele_selects_copy )
    {
      INFO "Failed select for: Gene: $gene, Design ID: " . $failed_allele_selects_copy{$gene};
    }

    INFO "Count of FAILED rows for Targeting vector selects: "     . $self->counter_failed_tv_selects;
    INFO "Count of FAILED rows for ES Cell clone selects: "        . $self->counter_failed_es_cell_selects;

    INFO "-------------- Selects End ---------------";

    return $es_clones;
}

sub _build_tm {
    my $self = shift;

    my $tm = LIMS2::Util::Tarmits->new_with_config;

    return $tm;
}

sub check_clones_against_tarmits {
    my $self = shift;

    #my %es_clones_data = %{ $self->es_clones };

    # for my $curr_gene_mgi_id ( sort keys %es_clones_data ) {
    for my $curr_gene_mgi_id ( sort keys %{ $self->es_clones } ) {

        INFO "Processing gene ID $curr_gene_mgi_id";

        $self->_check_gene_against_tarmits($curr_gene_mgi_id);

    }

    INFO "-------------- Tarmits update Totals ------------";

    # counters from selection of data from LIMS2
    INFO "Count of FAILED rows for Allele select: "                . $self->counter_failed_allele_selects;
    my %failed_allele_selects_copy = %{ $self->failed_allele_selects };
    foreach my $gene ( keys %failed_allele_selects_copy )
    {
      INFO "FAILED the select Gene: $gene, Design ID: " . $failed_allele_selects_copy{$gene};
    }
    INFO "Count of FAILED rows for Targeting vector selects: "     . $self->counter_failed_tv_selects;
    INFO "Count of FAILED rows for ES Cell clone selects: "        . $self->counter_failed_es_cell_selects;

    # counters from tarmits updates/inserts for alleles
    INFO "Count of rows where Allele already in Tarnits: "         . $self->counter_found_alleles;
    INFO "Count of rows where Allele not found in Tarmits: "       . $self->counter_not_found_alleles;
    INFO "Count of rows where Allele was inserted: "               . $self->counter_allele_inserts;
    INFO "Count of FAILED rows for Allele inserts: "               . $self->counter_failed_allele_inserts;

    # counters from tarmits updates/inserts for targeting vectors
    INFO "Count of rows where Targeting vector already in Tarnits: "         . $self->counter_found_tvs;
    INFO "Count of rows where Targeting vector not found in Tarmits: "       . $self->counter_not_found_tvs;
    INFO "Count of rows where Targeting vector was inserted: "               . $self->counter_tv_inserts;
    INFO "Count of rows where Targeting vector report flag was updated: "    . $self->counter_tv_updates;
    INFO "Count of FAILED rows for Targeting vector inserts: "               . $self->counter_failed_tv_inserts;

    # counters from tarmits updates/inserts for es clones
    INFO "Count of rows where ES Cell already in Tarnits: "                          . $self->counter_found_es_cells;
    INFO "Count of rows where ES Cell not found in Tarmits: "                        . $self->counter_not_found_es_cells;
    INFO "Count of rows where ES Cell was inserted into Tarmits: "                   . $self->counter_es_cell_inserts;
    INFO "Count of rows where ES Cell report to public flag was updated to TRUE: "   . $self->counter_es_cell_rtp_updates_to_true;
    INFO "Count of rows where ES Cell report to public flag was updated to FALSE: "  . $self->counter_es_cell_rtp_updates_to_false;
    INFO "Count of FAILED rows for ES Cell report to public flag updates: "          . $self->counter_failed_es_cell_rtp_updates;
    INFO "Count of rows where ES Cell allele symbol superscript flag was updated: "  . $self->counter_es_cell_asym_updates;
    INFO "Count of FAILED rows for ES Cell allele symbol superscript flag updates: " . $self->counter_failed_es_cell_asym_updates;
    INFO "Count of IGNORED rows for ES Cells: "                                      . $self->counter_ignored_es_cells;

    INFO "-------------- Tarmits update End ---------------";

    return;
}

sub _check_gene_against_tarmits {
    my ( $self, $curr_gene_mgi_id ) = @_;

    TRACE "Gene = $curr_gene_mgi_id:";

    for my $curr_design_id ( sort keys %{ $self->es_clones->{ $curr_gene_mgi_id }->{ 'designs' } } ) {
        $self->_check_allele_against_tarmits($curr_gene_mgi_id, $curr_design_id);
    }

    return;
}

sub _check_allele_against_tarmits {
    my ( $self, $curr_gene_mgi_id, $curr_design_id ) = @_;

    # my %es_clones_data = %{$self->es_clones};

    TRACE "Design = $curr_design_id:";

    # my $design = $es_clones_data{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id };
    my $design = $self->es_clones->{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id };

    my $find_allele_results = $self->_check_for_existing_allele( $curr_design_id, $curr_gene_mgi_id, $design );

    my $curr_allele_id = 0;

    if ( defined $find_allele_results && scalar @{ $find_allele_results } > 0 ) {

        # allele already exists in Tarmits
        $self->inc_counter_found_alleles;

        # fetch allele id for use when looking at targeting vectors
        $curr_allele_id = $find_allele_results->[0]->{ 'id' };

        DEBUG "Found allele match, continuing. Allele ID: $curr_allele_id";
    }
    else
    {
        # did not find allele in Tarmits, insert it
        $self->inc_counter_not_found_alleles;

        $curr_allele_id = $self->_insert_allele ( $curr_design_id, $curr_gene_mgi_id, $design );

        DEBUG "Allele ID returned = $curr_allele_id";
    }

    if ( !$curr_allele_id ) {
        # do not continue down to targeting vectors for this allele
        return;
    }

    INFO "Processing targeting vectors in Allele ID $curr_allele_id";

    # Cycle through the targeting vectors in the allele
    for my $curr_targeting_vector_name ( sort keys %{ $self->es_clones->{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id }->{ 'targeting_vectors' } } ) {

        $self->_check_targeting_vector_against_tarmits( $curr_gene_mgi_id, $curr_design_id, $curr_allele_id, $curr_targeting_vector_name );
    }

    return;
}

sub _check_for_existing_allele {
    my ( $self, $curr_design_id, $curr_gene_mgi_id, $design ) = @_;

    # Create selection criteria hash to be used to determine if the allele already exists in Tarmits
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
    my $find_allele_results = $self->tm->find_allele( \%find_allele_params );

    return $find_allele_results;
}

sub _insert_allele {
    my ( $self, $curr_design_id, $curr_gene_mgi_id, $design ) = @_;

    DEBUG "No allele match, inserting";

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

    my $allele_id = 0;

    try {
        my $insert_allele_results = $self->tm->create_allele( \%insert_allele_params );

        if ( $insert_allele_results->{ 'project_design_id' } == $curr_design_id ) {

            $self->inc_counter_allele_inserts;

            # store allele id for use for targeting vector inserts
            $allele_id = $insert_allele_results->{ 'id' };

            INFO "Inserted allele ID $allele_id successfully, continuing.";
        }
        else {
            WARN "Check on inserted Allele failed for gene: $curr_gene_mgi_id design: $curr_design_id";

            # increment counter
            $self->inc_counter_failed_allele_inserts;
        }

    } catch {
        ERROR "FAILED Allele insert for gene: " . $curr_gene_mgi_id . " design: ". $curr_design_id;
        TRACE "Exception: " . $_;

        # increment counter
        $self->inc_counter_failed_allele_inserts;
    };

    return $allele_id;
}

sub _check_targeting_vector_against_tarmits {
    my ($self, $curr_gene_mgi_id, $curr_design_id, $curr_allele_id, $curr_targeting_vector_name ) = @_;

    DEBUG "Check targeting vector - name = $curr_targeting_vector_name:";

    # my $tv = $es_clones_data{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id }->{ 'targeting_vectors' }->{ $curr_targeting_vector_name };
    my $tv = $self->es_clones->{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id }->{ 'targeting_vectors' }->{ $curr_targeting_vector_name };

    # List of unique targeting vector features
    my %find_tv_params = (
        'name_eq' => $curr_targeting_vector_name,
    );

    # return type should be an array of hashes
    my $tv_find_results = $self->tm->find_targeting_vector( \%find_tv_params );

    # targeting vector id needed for es cell clone checks
    my $curr_targeting_vector_id = 0;

    if ( defined $tv_find_results && scalar @{ $tv_find_results } > 0 ) {

        # targeting vector already exists in Tarmits
        $self->inc_counter_found_tvs;

        # fetch targeting vector id for use when looking at es cell clones
        $curr_targeting_vector_id = $tv_find_results->[0]->{ 'id' };

        DEBUG "Found targeting vector match, ID: $curr_targeting_vector_id checking report to public flag";

        if ( $tv_find_results->[0]->{ 'report_to_public' } == 0 ) {

            my $update_ok = $self->_update_targ_vect_report_to_public_flag ( $curr_targeting_vector_id, $tv, $curr_gene_mgi_id, $curr_design_id, $curr_targeting_vector_name );

            if ( !$update_ok ) {
                # do not continue down to clones for this targeting vector
                return;
            }
        }
        else {
            DEBUG "Targeting vector report to public flag already set, continuing";
        }
    }
    else
    {
        # did not find targeting vector in Tarmits, insert it
        $self->inc_counter_not_found_tvs;

        $curr_targeting_vector_id = $self->_insert_targ_vect( $tv, $curr_targeting_vector_name, $curr_allele_id, $curr_gene_mgi_id, $curr_design_id );
    }

    if ( !$curr_targeting_vector_id ) {
        # do not continue down to clones for this targeting vector
        return;
    }

    INFO "Processing ES clones in targeting vector ID $curr_targeting_vector_id";

    # for my $curr_clone_name ( sort keys %{ $es_clones_data{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id }->{ 'targeting_vectors' }->{ $curr_targeting_vector_name }->{ 'clones' } } ) {
    for my $curr_clone_name ( sort keys %{ $self->es_clones->{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id }->{ 'targeting_vectors' }->{ $curr_targeting_vector_name }->{ 'clones' } } ) {
        $self->_check_es_cell_against_tarmits( $curr_gene_mgi_id, $curr_design_id, $curr_allele_id, $curr_targeting_vector_name, $curr_targeting_vector_id, $curr_clone_name );
    }

    return;
}

sub _update_targ_vect_report_to_public_flag {
    my ( $self, $curr_targeting_vector_id, $tv, $curr_gene_mgi_id, $curr_design_id, $curr_targeting_vector_name ) = @_;

    my $update_ok = 0;

    # update report to public flag to true
    DEBUG "Targeting Vector report to public is currently false, need to update it to true";

    try {
        my %update_tv_params = (
            'report_to_public' => $tv->{ 'targeting_vector_details' }->{ 'report_to_public' },
        );

        # update takes the id of the item plus the updated parameters
        my $tv_update_results = $self->tm->update_targeting_vector( $curr_targeting_vector_id, \%update_tv_params );

        if ( defined $tv_update_results && scalar @{ $tv_update_results } > 0 ) {
            $self->inc_counter_tv_updates;

            INFO "Updated targeting vector ID $curr_targeting_vector_id report to public flag successfully, continuing";

            $update_ok = 1;
        }
        else {
            $self->inc_counter_failed_tv_updates;

            DEBUG "Check on update of targeting vector failed for gene: $curr_gene_mgi_id, design: $curr_design_id, targeting vector: $curr_targeting_vector_name, targeting vector id: $curr_targeting_vector_id";
        }
    }
    catch {
        $self->inc_counter_failed_tv_updates;

        ERROR "FAILED Targeting vector insert for gene: $curr_gene_mgi_id, design: $curr_design_id, targeting vector: $curr_targeting_vector_name";
        TRACE "Exception: " . $_;
    };

    return $update_ok;
}

sub _insert_targ_vect {
    my ( $self, $tv, $curr_targeting_vector_name, $curr_allele_id, $curr_gene_mgi_id, $curr_design_id ) = @_;

    DEBUG "No targeting vector match, inserting";

    my $ikmc_proj_id = ( $tv->{ 'targeting_vector_details' }->{ 'pipeline_name' } ) . '_' . $curr_allele_id;
    TRACE "ikmc_proj_id = $ikmc_proj_id";

    my %insert_tv_params = (
        'name'                  => $curr_targeting_vector_name,
        'allele_id'             => $curr_allele_id,
        'ikmc_project_id'       => $ikmc_proj_id,
        'intermediate_vector'   => $tv->{ 'targeting_vector_details' }->{ 'intermediate_vector' },
        'pipeline_id'           => $tv->{ 'targeting_vector_details' }->{ 'pipeline_id' },
        'report_to_public'      => $tv->{ 'targeting_vector_details' }->{ 'report_to_public' },
    );

    my $curr_targeting_vector_id = 0;

    try {
        my $results_tv_insert = $self->tm->create_targeting_vector( \%insert_tv_params );

        if ( defined $results_tv_insert && ( $results_tv_insert->{ 'name' } eq $curr_targeting_vector_name ) ) {

            $self->inc_counter_tv_inserts;

            # store targeting vector id for use for es cell clone checks
            $curr_targeting_vector_id = $results_tv_insert->{ 'id' };

            INFO "Inserted targeting vector ID $curr_targeting_vector_id successfully, continuing";
        }
        else {

            WARN "Check on inserted targeting vector failed for gene: $curr_gene_mgi_id, design: $curr_design_id, targeting vector: $curr_targeting_vector_name";

            # increment counter
            $self->inc_counter_failed_tv_inserts;
        }

    } catch {
        ERROR "FAILED Targeting vector insert for gene: $curr_gene_mgi_id, design: $curr_design_id, targeting vector: $curr_targeting_vector_name";
        TRACE "Exception: " . $_;

        # increment counter
        $self->inc_counter_failed_tv_inserts;
    };

    # do not continue down to clones for this targeting vector
    return $curr_targeting_vector_id;
}

sub _check_es_cell_against_tarmits { ##no critic(ProhibitManyArgs)
    my ($self, $curr_gene_mgi_id, $curr_design_id, $curr_allele_id, $curr_targeting_vector_name, $curr_targeting_vector_id, $curr_clone_name ) = @_;
    ## use critic
    DEBUG "Check ES cells - Clone = $curr_clone_name";

    my $curr_clone = $self->es_clones->{ $curr_gene_mgi_id }->{ 'designs' }->{ $curr_design_id }->{ 'targeting_vectors' }->{ $curr_targeting_vector_name }->{ 'clones' }->{ $curr_clone_name };
    my $curr_clone_accepted = $curr_clone->{ 'info' }->{ 'clone_accepted' };

    # List of unique clone parameters for select
    my %find_clone_params = (
        'name_eq' => $curr_clone_name,
    );

    # return type should be an array of hashes
    my $clone_find_results = $self->tm->find_es_cell( \%find_clone_params );

    if ( defined $clone_find_results && scalar @{ $clone_find_results } > 0 ) {

        # es cell clone already exists in Tarmits
        $self->inc_counter_found_es_cells;

        # fetch es cell clone id
        my $curr_es_cell_clone_id = $clone_find_results->[0]->{ 'id' };

        DEBUG "Found ES cell clone match, ID: $curr_es_cell_clone_id, checking report to public flag";

        # if report to public flag matches clone accepted flag do nothing, but if different then update
        my $tarmits_clone_report_to_public_string = $clone_find_results->[0]->{ 'report_to_public' };
        my $tarmits_clone_report_to_public = 0;
        if ( $tarmits_clone_report_to_public_string eq 'true' ) { $tarmits_clone_report_to_public = 1; }

        TRACE "Tarmits clone report to public is currently = $tarmits_clone_report_to_public";

        if ( $tarmits_clone_report_to_public != $curr_clone_accepted ) {
            DEBUG "LIMS2 clone accepted flag ($curr_clone_accepted) not equal to Tarmits report to public flag ($tarmits_clone_report_to_public), updating Tarmits";

            $self->_update_clone_report_to_public_flag( $curr_es_cell_clone_id, $curr_clone_name, $curr_clone_accepted, $curr_gene_mgi_id, $curr_design_id, $curr_targeting_vector_name );
        }
        else {
            DEBUG "ES Cells report to public flag already set to $curr_clone_accepted, continuing";
        }

        # check allele symbol superscript set for ES clone, if not set it

        if ( not defined ( $clone_find_results->[0]->{ 'allele_symbol_superscript' } ) ) {
            $self->_update_clone_allele_symbol( $curr_es_cell_clone_id, $curr_clone_name, $curr_clone, $curr_gene_mgi_id, $curr_design_id, $curr_targeting_vector_name );
        }
        else {
            DEBUG "ES Cells allele symbol superscript already set, continuing";
        }
    }
    else
    {
        # did not find es cell clone in Tarmits, insert it but ONLY if accepted
        if ( $curr_clone_accepted ) {
            $self->inc_counter_not_found_es_cells;
            $self->_insert_clone ( $curr_clone_name, $curr_clone, $curr_gene_mgi_id, $curr_design_id, $curr_allele_id, $curr_targeting_vector_name, $curr_targeting_vector_id );
        }
        else {
            DEBUG "Clone not accepted in LIMS2 and not in Tarnits: ignore";
            $self->inc_counter_ignored_es_cells;
        }
    }

    return;
}

sub _update_clone_report_to_public_flag { ##no critic(ProhibitManyArgs)
    my ( $self, $curr_es_cell_clone_id, $curr_clone_name, $curr_clone_accepted, $curr_gene_mgi_id, $curr_design_id, $curr_targeting_vector_name ) = @_;
    ## use critic

    DEBUG "ES Cell clone report to public flag does not match state in LIMS2, attempting to update";

    try {
        my %update_es_cell_params = (
            'report_to_public' => $curr_clone_accepted,
        );

        # update takes the id of the item plus the updated parameters
        my $clone_update_resultset = $self->tm->update_es_cell( $curr_es_cell_clone_id, \%update_es_cell_params );

        if ( defined $clone_update_resultset && $clone_update_resultset != 0 ) {
            if ( $curr_clone_accepted ) {
                $self->inc_counter_es_cell_rtp_updates_to_true;
            }
            else {
                $self->inc_counter_es_cell_rtp_updates_to_false;
            }

            INFO "Updated report to public for ES cell clone ID: $curr_es_cell_clone_id to value $curr_clone_accepted, continuing";
        }
        else {
            $self->inc_counter_failed_es_cell_rtp_updates;

            WARN "Check on update of report to public for ES cell clone failed for gene: $curr_gene_mgi_id, design: $curr_design_id, targeting vector: $curr_targeting_vector_name, es cell clone name: $curr_clone_name, es cell accepted: $curr_clone_accepted";
        }
    }
    catch {
        $self->inc_counter_failed_es_cell_rtp_updates;

        ERROR "FAILED to update report to public for ES Cell clone for gene: $curr_gene_mgi_id, design: $curr_design_id, targeting vector: $curr_targeting_vector_name, es cell clone name: $curr_clone_name, es cell accepted: $curr_clone_accepted";
        TRACE "Exception: " . $_;
    };

    return;
}

sub _update_clone_allele_symbol { ##no critic(ProhibitManyArgs)
    my ( $self, $curr_es_cell_clone_id, $curr_clone_name, $curr_clone, $curr_gene_mgi_id, $curr_design_id, $curr_targeting_vector_name ) = @_;
    ## use critic

    DEBUG "ES Cells allele symbol superscript empty, attempting to update";

    try {
        my %update_es_cell_params = (
            'allele_symbol_superscript' => $curr_clone->{ 'es_cell_details' }->{ 'allele_symbol_superscript' },
        );

        # update takes the id of the item plus the updated parameters
        my $clone_update_resultset = $self->tm->update_es_cell( $curr_es_cell_clone_id, \%update_es_cell_params );

        if ( defined $clone_update_resultset && $clone_update_resultset != 0 ) {
            $self->inc_counter_es_cell_asym_updates;

            INFO "Updated allele symbol superscript for ES cell clone ID: $curr_es_cell_clone_id successfully, continuing";
        }
        else {
            $self->inc_counter_failed_es_cell_asym_updates;

            WARN "Check on update of allele symbol superscript for ES cell clone failed for gene: $curr_gene_mgi_id, design: $curr_design_id, targeting vector: $curr_targeting_vector_name, es cell clone name: $curr_clone_name";
        }
    }
    catch {
        $self->inc_counter_failed_es_cell_asym_updates;

        ERROR "FAILED allele symbol superscript update for ES Cell clone for gene: $curr_gene_mgi_id, design: $curr_design_id, targeting vector: $curr_targeting_vector_name, es cell clone name: $curr_clone_name";
        TRACE "Exception: " . $_;
    };

    return;
}

sub _insert_clone { ##no critic(ProhibitManyArgs)
    my ( $self, $curr_clone_name, $curr_clone, $curr_gene_mgi_id, $curr_design_id, $curr_allele_id, $curr_targeting_vector_name, $curr_targeting_vector_id ) = @_;
    ## use critic

    DEBUG "Inserting new accepted es clone";

    my $ikmc_proj_id = ( $curr_clone->{ 'es_cell_details' }->{ 'pipeline_name' } ) . '_' . $curr_allele_id;
    DEBUG "insert_clone ikmc_proj_id = $ikmc_proj_id";

    my %insert_es_cell_params = (
        'name'                  => $curr_clone_name,
        'allele_id'             => $curr_allele_id,
        'ikmc_project_id'       => $ikmc_proj_id,
        'targeting_vector_id'   => $curr_targeting_vector_id,
        'parental_cell_line'    => $curr_clone->{ 'es_cell_details' }->{ 'parental_cell_line' },
        'pipeline_id'           => $curr_clone->{ 'es_cell_details' }->{ 'pipeline_id' },
        'report_to_public'      => $curr_clone->{ 'info' }->{ 'clone_accepted' },
        'allele_symbol_superscript'        => $curr_clone->{ 'es_cell_details' }->{ 'allele_symbol_superscript' },
        # 'production_qc_five_prime_screen'  => $clone->{ 'qc_metrics' }->{ 'five_prime_screen' },
        # 'production_qc_three_prime_screen' => $clone->{ 'qc_metrics' }->{ 'three_prime_screen' },
        # 'production_qc_loxp_screen'        => $clone->{ 'qc_metrics' }->{ 'loxp_screen' },
        # 'production_qc_loss_of_allele'     => $clone->{ 'qc_metrics' }->{ 'loss_of_allele' },
        # 'production_qc_vector_integrity'   => $clone->{ 'qc_metrics' }->{ 'vector_integrity' },
    );

    my $curr_es_cell_clone_id = 0;

    try {
        my $results_es_cell_insert = $self->tm->create_es_cell( \%insert_es_cell_params );

        if ( defined $results_es_cell_insert && ( $results_es_cell_insert->{ 'name' } eq $curr_clone_name ) ) {

            $self->inc_counter_es_cell_inserts;

            # store es cell clone id
            $curr_es_cell_clone_id = $results_es_cell_insert->{ 'id' };

            INFO "Inserted es cell clone ID $curr_es_cell_clone_id successfully, continuing";
        }
        else {

            WARN "Check on inserted es cell clone failed for gene: $curr_gene_mgi_id, design: $curr_design_id, targeting vector: $curr_targeting_vector_name, es cell clone name: $curr_clone_name";

            # increment counter
            $self->inc_counter_failed_es_cell_inserts;
        }

    } catch {
        ERROR "Failed ES Cell clone insert for gene: $curr_gene_mgi_id, design: $curr_design_id, targeting vector: $curr_targeting_vector_name, es cell clone name: $curr_clone_name";
        ERROR "Exception: " . $_;

        # increment counter
        $self->inc_counter_failed_es_cell_inserts;
    };

    return $curr_es_cell_clone_id;
}

sub refactor_selected_clones {
    my ( $self, $es_clones_array ) = @_;

    my %results_refactored;

    RESULTS_LOOP: foreach my $result (@$es_clones_array) {

        my $is_error = 0;

        # if gene doesn't exist in hash then add it
        my $current_gene_id = $result->{ 'design_gene_id' };

        unless ( exists $results_refactored{ $current_gene_id } ) {

            DEBUG "Processing gene ID $current_gene_id";

            my %gene_details;

            #Gene ascession id - e.g. MGI:2140237                -> from summaries.design_gene_id
            $gene_details{ 'gene_accession_id' }  = $current_gene_id;

            $results_refactored{ $current_gene_id }->{ 'gene_details' }   = { %gene_details };

        }

        next RESULTS_LOOP if $is_error;

        # if current design id (allele) doesn't exist in hash then add it
        my $current_design_id = $result->{ 'design_id' };

        unless ( exists $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id } ) {

            #skip if already im error list
            next RESULTS_LOOP if ( exists $self->failed_allele_selects->{ $current_gene_id } );

            try {

                # fetch design object
                my $design = $self->model->retrieve_design( { 'id' => $result->{ 'design_id' }, 'species' => $self->species } );
                my $design_info = $design->info;

                # fetch hashref of oligos from design info
                my $design_oligos =$design_info->oligos;

                # build design details hash
                my $design_details = $self->_select_lims2_design_details ( $result, $design_info, $design_oligos );

                $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id }->{ 'design_details' } = $design_details;

            } catch {

                WARN "FAILED Allele selection for gene: " . $result->{ 'design_gene_id' } . " design: ". $result->{ 'design_id' };
                TRACE "Exception: " . $_;

                # increment counter
                $self->inc_counter_failed_allele_selects;

                # add details tp failed hash for report
                $self->failed_allele_selects->{ $current_gene_id } = $current_design_id;

                # set flag to trigger next loop cycle (cannot next here as out of scope)
                $is_error = 1;
            };
        }

        next RESULTS_LOOP if $is_error;

        # if vector info doesn't exist in allele hash then add it
        my $targeting_vector_id = $result->{ 'targeting_vector_plate_name' } . '_' . $result->{ 'targeting_vector_well_name' };
        my $intermediate_vector_id = $result->{ 'int_plate_name' } . '_' . $result->{ 'int_well_name' };

        unless ( exists $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id }->{ 'targeting_vectors' }->{ $targeting_vector_id } ) {

            my $new_tar_vec = $self->_select_lims2_targeting_vector_details ( $result, $targeting_vector_id, $intermediate_vector_id );
            $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id }->{ 'targeting_vectors' }->{ $targeting_vector_id } = $new_tar_vec;
        }

        next RESULTS_LOOP if $is_error;

        # fetch clone id
        my $es_clone_id = $result->{ 'clone_plate_name' } . '_' . $result->{ 'clone_well_name' };

        # if the clone does not already exist in the main hash then add it
        unless ( exists $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id }->{ 'targeting_vectors' }->{ $targeting_vector_id }->{ 'clones' }->{ $es_clone_id } ) {

            my $new_clone = $self->_select_lims2_es_clone_details ( $result, $es_clone_id, $targeting_vector_id );
            $results_refactored{ $current_gene_id }->{ 'designs' }->{ $current_design_id }->{ 'targeting_vectors' }->{ $targeting_vector_id }->{ 'clones' }->{ $es_clone_id } = $new_clone;
        }
    }

    return \%results_refactored;
}

sub _select_lims2_design_details {
    my ( $self, $result, $design_info, $design_oligos ) = @_;

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

    my %molecular_co_ords = ();

    # fetch various molecular co-ordinates
    $self->_get_homology_arm_coords( \%molecular_co_ords, $design_oligos, $strand );
    $self->_get_cassette_coords( \%molecular_co_ords, $design_oligos, $strand, $design_info->type );
    $self->_get_loxp_coords( \%molecular_co_ords, $design_oligos, $strand, $design_info->type );

    $design_details{ 'molecular_co_ords' }                = { %molecular_co_ords };

    return \%design_details;
}

sub _get_loxp_coords {
    my ( $self, $molecular_co_ords, $design_oligos, $strand, $design_type ) = @_;

    if ( ( $design_type eq 'conditional' || $design_type eq 'artificial-intron' )
        and $design_oligos->{ 'D5' }
        and $design_oligos->{ 'D3' } )
    {
        if ( $strand eq '+' ) {
            $molecular_co_ords->{ 'loxp' }->{ 'start' }         = $design_oligos->{ 'D5' }->{ 'end' };
            $molecular_co_ords->{ 'loxp' }->{ 'end' }           = $design_oligos->{ 'D3' }->{ 'start' };
        }
        else {
            $molecular_co_ords->{ 'loxp' }->{ 'start' }         = $design_oligos->{ 'D5' }->{ 'start' };
            $molecular_co_ords->{ 'loxp' }->{ 'end' }          = $design_oligos->{ 'D3' }->{ 'end' };
        }
    }

    return;
}

sub _get_cassette_coords {
    my ( $self, $molecular_co_ords, $design_oligos, $strand, $design_type ) = @_;

    if ( ( $design_type eq 'deletion' || $design_type eq 'insertion' )
        and $design_oligos->{ 'U5' }
        and $design_oligos->{ 'D3' } )
    {
        if ( $strand eq '+' ) {
            $molecular_co_ords->{ 'cassette' }->{ 'start' }     = $design_oligos->{ 'U5' }->{ 'end' };
            $molecular_co_ords->{ 'cassette' }->{ 'end' }       = $design_oligos->{ 'D3' }->{ 'start' };
        }
        else {
            $molecular_co_ords->{ 'cassette' }->{ 'start' }     = $design_oligos->{ 'U5' }->{ 'start' };
            $molecular_co_ords->{ 'cassette' }->{ 'end' }       = $design_oligos->{ 'D3' }->{ 'end' };
        }
    }
    elsif ( ( $design_type eq 'conditional' || $design_type eq 'artificial-intron' )
        and $design_oligos->{ 'U5' }
        and $design_oligos->{ 'U3' } )
    {
        if ( $strand eq '+' ) {
            $molecular_co_ords->{ 'cassette' }->{ 'start' }     = $design_oligos->{ 'U5' }->{ 'end' };
            $molecular_co_ords->{ 'cassette' }->{ 'end' }       = $design_oligos->{ 'U3' }->{ 'start' };
        }
        else {
            $molecular_co_ords->{ 'cassette' }->{ 'start' }     = $design_oligos->{ 'U5' }->{ 'start' };
            $molecular_co_ords->{ 'cassette' }->{ 'end' }       = $design_oligos->{ 'U3' }->{ 'end' };
        }
    }

    return;
}

sub _get_homology_arm_coords {
    my ( $self, $molecular_co_ords, $design_oligos, $strand ) = @_;

    if ( $design_oligos->{ 'G5' } and $design_oligos->{ 'G3' } ) {
        if ( $strand eq '+' ) {
            $molecular_co_ords->{ 'homology_arm' }->{ 'start' } = $design_oligos->{ 'G5' }->{ 'end' };
            $molecular_co_ords->{ 'homology_arm' }->{ 'end' }   = $design_oligos->{ 'G3' }->{ 'start' };
        }
        else {
            $molecular_co_ords->{ 'homology_arm' }->{ 'start' } = $design_oligos->{ 'G5' }->{ 'start' };
            $molecular_co_ords->{ 'homology_arm' }->{ 'end' }   = $design_oligos->{ 'G3' }->{ 'end' };
        }
    }

    return;
}

sub _select_lims2_targeting_vector_details {
    my ( $self, $result, $targeting_vector_id, $intermediate_vector_id ) = @_;

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

    return \%new_tar_vec;
}

sub _select_lims2_es_clone_details {
    my ( $self, $result, $es_clone_id, $targeting_vector_id ) = @_;

    my %new_clone;

    $new_clone{ 'info' }->{ 'clone_plate_id' }      = $result->{ 'clone_plate_id' };
    $new_clone{ 'info' }->{ 'clone_plate_name' }    = $result->{ 'clone_plate_name' };
    $new_clone{ 'info' }->{ 'clone_well_id' }       = $result->{ 'clone_well_id' };
    $new_clone{ 'info' }->{ 'clone_well_name' }     = $result->{ 'clone_well_name' };
    $new_clone{ 'info' }->{ 'clone_accepted' }      = $result->{ 'clone_accepted' };

    $self->_get_es_clone_cell_details( \%new_clone, $es_clone_id, $targeting_vector_id, $result );

    $self->_get_es_clone_qc_metric_details( \%new_clone );

    return \%new_clone;
}

sub _get_es_clone_cell_details {
    my ( $self, $new_clone, $es_clone_id, $targeting_vector_id, $result ) = @_;

    my %es_cell_details;
    # ES Cells (multiple rows)
    #   Pipeline                  - e.g. EUCOMMToolsCre          -> hardcoded
    $es_cell_details{ 'pipeline_name' }             = 'EUCOMMToolsCre';
    $es_cell_details{ 'pipeline_id' }               = 8;

    #   ES Cell                   - e.g. CEPD0026_4_B10          -> from summaries.ep_pick_plate_name and _well_name
    $es_cell_details{ 'es_clone_id' }                = $es_clone_id;

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

    #   Report to public          - e.g. boolean, same as accepted flag so use that
    #$es_cell_details{ 'report_to_public' }          = $result->{ 'clone_accepted' };

    $new_clone->{ 'es_cell_details' }                 = { %es_cell_details };

    return;
}

sub _get_es_clone_qc_metric_details {
    my ( $self, $new_clone ) = @_;

    my %qc_metrics = ();
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

    $new_clone->{ 'qc_metrics' }                                           = { %qc_metrics };

    return;
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
sub sql_select_st_es_clones {
    my ( $self, $sponsor_id ) = @_;

    my $species_id     = $self->species;
    my $mgi_gene_id    = $self->gene_id;

my $sql_query_top =  <<"SQL_TOP_END";
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
WHERE p.sponsor_id   = '$sponsor_id'
AND p.targeting_type = 'single_targeted'
AND p.species_id     = '$species_id'
SQL_TOP_END

my $sql_query_optional =  <<"SQL_OPTIONAL_END";
AND p.gene_id        = '$mgi_gene_id'
SQL_OPTIONAL_END

my $sql_query_btm =  <<"SQL_BTM_END";
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
, s.ep_pick_well_accepted AS clone_accepted
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
AND s.ep_pick_well_id > 0
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
, s.ep_pick_well_accepted
ORDER BY pr.project_id
, s.design_id
, s.design_gene_id
, s.final_pick_well_id
, s.ep_pick_well_id
SQL_BTM_END

    my $sql_query;
    if ( $mgi_gene_id ) {
        $sql_query = $sql_query_top . $sql_query_optional . $sql_query_btm;
    }
    else {
        $sql_query = $sql_query_top . $sql_query_btm;
    }

    return $sql_query;
}


1;

__END__