package LIMS2::Util::TarmitsFeedCreKnockin;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::TarmitsFeedCreKnockin::VERSION = '0.082';
}
## use critic


use Moose;
use LIMS2::Model;
use Log::Log4perl qw( :easy );              # TRACE to INFO to WARN to ERROR to LOGDIE
use Try::Tiny;                              # Exception handling
use LIMS2::Util::Tarmits;
use Const::Fast;
use EngSeqBuilder;
use JSON;
use LIMS2::Model::Util::EngSeqParams qw ( generate_well_eng_seq_params );

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

# hashref to hold list of failed design selects for display
has failed_design_selects => (
    is         => 'rw',
    isa        => 'HashRef',
    default    => sub { {} },
);

has tm => (
    is         => 'ro',
    isa        => 'LIMS2::Util::Tarmits',
    lazy_build => 1,
);

has curr_gene_mgi_id => (
    is         => 'rw',
    isa        => 'Maybe[Str]',
    required   => 0,
);

has curr_design_id => (
    is         => 'rw',
    isa        => 'Maybe[Str]',
    required   => 0,
);

has curr_design => (
    is         => 'rw',
    isa        => 'Maybe[HashRef]',
    required   => 0,
);

# allele (dre) attributes
has curr_allele_dre_id => (
    is         => 'rw',
    isa        => 'Maybe[Str]',
    required   => 0,
);

has curr_allele_dre_genbank_exists => (
    is         => 'rw',
    isa        => 'Int',
    default    => 0,
    required   => 0,
);

has curr_allele_dre_genbank_checked => (
    is         => 'rw',
    isa        => 'Int',
    default    => 0,
    required   => 0,
);

has curr_allele_dre_genbank_db_id => (
    is         => 'rw',
    isa        => 'Maybe[Int]',
    required   => 0,
);

# allele (no dre) attributes
has curr_allele_no_dre_id => (
    is         => 'rw',
    isa        => 'Maybe[Str]',
    required   => 0,
);

has curr_allele_no_dre_genbank_exists => (
    is         => 'rw',
    isa        => 'Int',
    default    => 0,
    required   => 0,
);

has curr_allele_no_dre_genbank_checked => (
    is         => 'rw',
    isa        => 'Int',
    default    => 0,
    required   => 0,
);

has curr_allele_no_dre_genbank_vector_checked => (
    is         => 'rw',
    isa        => 'Int',
    default    => 0,
    required   => 0,
);

has curr_allele_no_dre_genbank_db_id => (
    is         => 'rw',
    isa        => 'Maybe[Int]',
    required   => 0,
);

# targeting vector attributes
has curr_targeting_vector_id => (
    is         => 'rw',
    isa        => 'Maybe[Str]',
    required   => 0,
);

has curr_targeting_vector => (
    is         => 'rw',
    isa        => 'Maybe[HashRef]',
    required   => 0,
);

has curr_targeting_vector_name => (
    is         => 'rw',
    isa        => 'Maybe[Str]',
    required   => 0,
);

# es cell clone attributes
has curr_es_cell_clone_id => (
    is         => 'rw',
    isa        => 'Maybe[Str]',
    required   => 0,
);

has curr_clone => (
    is         => 'rw',
    isa        => 'Maybe[HashRef]',
    required   => 0,
);

has curr_clone_name => (
    is         => 'rw',
    isa        => 'Maybe[Str]',
    required   => 0,
);

has curr_clone_accepted => (
    is         => 'rw',
    isa        => 'Int',
    default    => 0,
    required   => 0,
);

has curr_clone_has_dre => (
    is         => 'rw',
    isa        => 'Int',
    default    => 0,
    required   => 0,
);

# to force updates
has force_updates => (
    is         => 'rw',
    isa        => 'Int',
    default    => 0,
    required   => 0,
);

# multiple counters to track what is done
for my $name (
    qw( counter_failed_no_dre_allele_selects
        counter_found_no_dre_alleles
        counter_not_found_no_dre_alleles
        counter_no_dre_allele_inserts
        counter_failed_no_dre_allele_inserts
        counter_failed_dre_allele_selects
        counter_found_dre_alleles
        counter_not_found_dre_alleles
        counter_dre_allele_inserts
        counter_failed_dre_allele_inserts
        counter_failed_tv_selects
        counter_found_tvs
        counter_not_found_tvs
        counter_tv_inserts
        counter_failed_tv_inserts
        counter_tv_rtp_updates
        counter_failed_tv_rtp_updates
        counter_tv_allele_id_updates
        counter_failed_tv_allele_id_updates
        counter_tv_ikmc_proj_id_updates
        counter_failed_tv_ikmc_proj_id_updates
        counter_failed_es_cell_selects
        counter_found_es_cells
        counter_not_found_es_cells
        counter_es_cell_inserts
        counter_es_cell_rtp_updates_to_true
        counter_es_cell_rtp_updates_to_false
        counter_es_cell_ikmc_proj_id_updates
        counter_failed_es_cell_ikmc_proj_id_updates
        counter_es_cell_allele_id_updates
        counter_failed_es_cell_allele_id_updates
        counter_es_cell_targ_vect_updates
        counter_failed_es_cell_targ_vect_updates
        counter_failed_es_cell_rtp_updates
        counter_es_cell_allele_symb_updates
        counter_failed_es_cell_allele_symb_updates
        counter_ignored_es_cells
        counter_failed_es_cell_inserts
        counter_successful_no_dre_genbank_checks
        counter_failed_no_dre_genbank_checks
        counter_successful_no_dre_genbank_file_inserts
        counter_failed_no_dre_genbank_file_inserts
        counter_successful_no_dre_genbank_file_updates
        counter_failed_no_dre_genbank_file_updates
        counter_successful_dre_genbank_checks
        counter_failed_dre_genbank_checks
        counter_successful_dre_genbank_file_inserts
        counter_failed_dre_genbank_file_inserts
        counter_successful_dre_genbank_file_updates
        counter_failed_dre_genbank_file_updates
        )
    ) {
    my $inc_name = 'inc_'.$name;
    my $dec_name = 'dec_'.$name;
    my $reset_name = 'reset_'.$name;
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
    my ( $self ) = @_;

    my $sponsor_id      = 'Cre Knockin';

    # create SQL to fetch the list of es EP_PICK wells that match to Cre Knockin sponsor projects
    my $sql_query       = $self->_sql_select_st_es_clones ( $sponsor_id );

    # run the SQL to fetch rows from the summaries table
    my $es_clones_array = $self->_run_select_query( $sql_query );

    # refactor the data from flattened structure into nested hash
    my $es_clones       = $self->_refactor_selected_clones( $es_clones_array );

    if ( $self->force_updates ) {
        INFO "Flag for FORCE UPDATES is set to true";
    }

    INFO "-------------- Select Totals -------------";
    INFO "Count of FAILED rows for Allele selects: "              .$self->counter_failed_no_dre_allele_selects;

    my %failed_design_selects_copy = %{ $self->failed_design_selects };
    foreach my $gene ( keys %failed_design_selects_copy )
    {
      INFO "Failed Design select for: Gene: $gene, design ID: ".$failed_design_selects_copy{$gene};
    }

    INFO "Count of FAILED rows for Targeting vector selects: "    .$self->counter_failed_tv_selects;
    INFO "Count of FAILED rows for ES Cell clone selects: "       .$self->counter_failed_es_cell_selects;

    INFO "-------------- Selects End ---------------";

    return $es_clones;
}

sub _build_tm {
    my ( $self ) = @_;

    my $tm = LIMS2::Util::Tarmits->new_with_config;

    return $tm;
}

sub check_clones_against_tarmits {
    my ( $self ) = @_;

    for my $gene_mgi_id ( sort keys %{ $self->es_clones } ) {

        INFO "Processing gene ID: ".$gene_mgi_id;

        $self->curr_gene_mgi_id ( $gene_mgi_id );

        $self->_check_gene_against_tarmits();
    }

    INFO "-------------- Tarmits update Totals ------------";

    # counters from selection of data from LIMS2
    INFO "Count of FAILED rows for Allele select: "                                   .$self->counter_failed_no_dre_allele_selects;
    my %failed_design_selects_copy = %{ $self->failed_design_selects };
    foreach my $gene ( keys %failed_design_selects_copy )
    {
      INFO "FAILED design select Gene: $gene, design ID: ".$failed_design_selects_copy{$gene};
    }
    INFO "Count of FAILED rows for Targeting vector selects: "                        .$self->counter_failed_tv_selects;
    INFO "Count of FAILED rows for ES Cell clone selects: "                           .$self->counter_failed_es_cell_selects;
    INFO "-------------------";
    # counters from tarmits updates/inserts for alleles
    INFO "Count of rows where (no Dre) Allele already in Tarmits: "                   .$self->counter_found_no_dre_alleles;
    INFO "Count of rows where (no Dre) Allele not found in Tarmits: "                 .$self->counter_not_found_no_dre_alleles;
    INFO "Count of rows where (no Dre) Allele was inserted: "                         .$self->counter_no_dre_allele_inserts;
    INFO "Count of existing genbank files for (no Dre) alleles: "                     .$self->counter_successful_no_dre_genbank_checks;
    INFO "Count of successful genbank file inserts for (no Dre) alleles: "            .$self->counter_successful_no_dre_genbank_file_inserts;
    INFO "Count of successful genbank file updates for (no Dre) alleles: "            .$self->counter_successful_no_dre_genbank_file_updates;
    INFO "---";
    INFO "Count of FAILED rows for (no Dre) Allele inserts: "                         .$self->counter_failed_no_dre_allele_inserts;
    INFO "Count of FAILED genbank file checks for (no Dre) alleles: "                 .$self->counter_failed_no_dre_genbank_checks;
    INFO "Count of FAILED genbank file inserts for (no Dre) alleles: "                .$self->counter_failed_no_dre_genbank_file_inserts;
    INFO "Count of FAILED genbank file updates for (no Dre) alleles: "                .$self->counter_failed_no_dre_genbank_file_updates;
    INFO "-------------------";
    INFO "Count of rows where (with Dre) Allele already in Tarmits: "                 .$self->counter_found_dre_alleles;
    INFO "Count of rows where (with Dre) Allele not found in Tarmits: "               .$self->counter_not_found_dre_alleles;
    INFO "Count of rows where (with Dre) Allele was inserted: "                       .$self->counter_dre_allele_inserts;
    INFO "Count of existing genbank files for (with Dre) alleles: "                   .$self->counter_successful_dre_genbank_checks;
    INFO "Count of successful genbank file inserts for (with Dre) alleles: "          .$self->counter_successful_dre_genbank_file_inserts;
    INFO "Count of successful genbank file updates for (with Dre) alleles: "          .$self->counter_successful_dre_genbank_file_updates;
    INFO "---";
    INFO "Count of FAILED rows for (with Dre) Allele inserts: "                       .$self->counter_failed_dre_allele_inserts;
    INFO "Count of FAILED genbank file checks for (with Dre) alleles: "               .$self->counter_failed_dre_genbank_checks;
    INFO "Count of FAILED genbank file inserts for (with Dre) alleles: "              .$self->counter_failed_dre_genbank_file_inserts;
    INFO "Count of FAILED genbank file updates for (with Dre) alleles: "              .$self->counter_failed_dre_genbank_file_updates;
    INFO "-------------------";
    # counters from tarmits updates/inserts for targeting vectors
    INFO "Count of rows where Targeting vector already in Tarmits: "                  .$self->counter_found_tvs;
    INFO "Count of rows where Targeting vector not found in Tarmits: "                .$self->counter_not_found_tvs;
    INFO "Count of rows where Targeting vector was inserted: "                        .$self->counter_tv_inserts;
    INFO "Count of rows where Targeting vector report to public flag was updated: "   .$self->counter_tv_rtp_updates;
    INFO "Count of rows where Targeting vector allele ID was updated: "               .$self->counter_tv_allele_id_updates;
    INFO "Count of rows where Targeting vector ikmc project ID was updated: "         .$self->counter_tv_ikmc_proj_id_updates;
    INFO "---";
    INFO "Count of FAILED rows for Targeting vector report to public flag updates: "  .$self->counter_tv_rtp_updates;
    INFO "Count of FAILED rows for Targeting vector allele ID updates: "              .$self->counter_failed_tv_allele_id_updates;
    INFO "Count of FAILED rows for Targeting vector ikmc project ID updates: "        .$self->counter_failed_tv_ikmc_proj_id_updates;
    INFO "Count of FAILED rows for Targeting vector inserts: "                        .$self->counter_failed_tv_inserts;
    INFO "-------------------";
    # counters from tarmits updates/inserts for es clones
    INFO "Count of rows where ES Cell already in Tarmits: "                           .$self->counter_found_es_cells;
    INFO "Count of rows where ES Cell not found in Tarmits: "                         .$self->counter_not_found_es_cells;
    INFO "Count of rows where ES Cell was inserted into Tarmits: "                    .$self->counter_es_cell_inserts;
    INFO "Count of rows where ES Cell report to public flag was updated to TRUE: "    .$self->counter_es_cell_rtp_updates_to_true;
    INFO "Count of rows where ES Cell report to public flag was updated to FALSE: "   .$self->counter_es_cell_rtp_updates_to_false;
    INFO "Count of rows where ES Cell ikmc project ID was updated: "                  .$self->counter_es_cell_ikmc_proj_id_updates;
    INFO "Count of rows where ES Cell allele symbol superscript flag was updated: "   .$self->counter_es_cell_allele_symb_updates;
    INFO "Count of rows where ES Cell allele ID was updated: "                        .$self->counter_es_cell_allele_id_updates;
    INFO "Count of rows where ES Cell targeting vector ID was updated: "              .$self->counter_es_cell_targ_vect_updates;
    INFO "Count of IGNORED rows for ES Cells: "                                       .$self->counter_ignored_es_cells;
    INFO "---";
    INFO "Count of FAILED rows for ES Cell report to public flag updates: "           .$self->counter_failed_es_cell_rtp_updates;
    INFO "Count of FAILED rows for ES Cell ikmc project ID updates: "                 .$self->counter_failed_es_cell_ikmc_proj_id_updates;
    INFO "Count of FAILED rows for ES Cell allele symbol superscript flag updates: "  .$self->counter_failed_es_cell_allele_symb_updates;
    INFO "Count of FAILED rows for ES Cell allele ID updates: "                       .$self->counter_failed_es_cell_allele_id_updates;
    INFO "Count of FAILED rows for ES Cell targeting vector ID updates: "             .$self->counter_failed_es_cell_targ_vect_updates;
    INFO "-------------- Tarmits update End ---------------";

    return;
}

sub _check_gene_against_tarmits {
    my ( $self ) = @_;

    DEBUG "====================== gene ============================";
    DEBUG "Checking gene MGI ID: ".$self->curr_gene_mgi_id;

    for my $design_id ( sort keys %{ $self->es_clones->{ $self->curr_gene_mgi_id }->{ 'designs' } } ) {
        $self->curr_design_id ( $design_id );

        # initialise fields
        $self->curr_design ( undef );

        $self->_check_design_against_tarmits();
    }

    DEBUG "==================== end gene ============================";

    return;
}

sub _check_design_against_tarmits {
    my ( $self ) = @_;

    DEBUG "-----------------------design-----------------------------";
    DEBUG "Processing Design ID: ".$self->curr_design_id;

    $self->curr_design( $self->es_clones->{ $self->curr_gene_mgi_id }->{ 'designs' }->{ $self->curr_design_id } );

    unless ( defined $self->curr_design && defined $self->curr_design->{ 'design_details' } ) {
        ERROR "Failed to get design details, cannot continue to check alleles for gene ID: ".$self->curr_gene_mgi_id;
        return;
    }

    # Cycle through the targeting vectors in the allele
    for my $targeting_vector_name ( sort keys %{ $self->es_clones->{ $self->curr_gene_mgi_id }->{ 'designs' }->{ $self->curr_design_id }->{ 'targeting_vectors' } } ) {
        $self->curr_targeting_vector_name ( $targeting_vector_name );

        DEBUG "-----------------------vector-----------------------------";
        DEBUG "Processing Targeting vector: ".$targeting_vector_name;

        # initialise fields
        $self->curr_targeting_vector( undef );
        $self->curr_targeting_vector_id ( undef );

        # for each targeting vector with accepted clones (dre or no-dre) within the design return existing id or insert a new allele
        my $curr_vector_hash = $self->es_clones->{ $self->curr_gene_mgi_id }->{ 'designs' }->{ $self->curr_design_id }->{ 'targeting_vectors' }->{ $targeting_vector_name };

        $self->curr_allele_dre_id ( undef );
        $self->curr_allele_no_dre_id ( undef );

        # NON-dre allele should always be checked/created as the targeting vector connects to that allele
        $self->_check_for_existing_no_dre_allele( $curr_vector_hash );
        unless ( defined $self->curr_allele_no_dre_id ) {
            ERROR "Failed to determine id for no dre allele, for gene ID: ".$self->curr_gene_mgi_id;
            return;
        }
        INFO $self->curr_gene_mgi_id.": No Dre Allele ID: ".$self->curr_allele_no_dre_id;

        # dre allele optional and only created if we have dre clones
        if ( $curr_vector_hash->{ 'count_clones_dre' } > 0 ) {
            $self->_check_for_existing_dre_allele( $curr_vector_hash );
            unless ( defined $self->curr_allele_dre_id ) {
                ERROR "Failed to determine id for no dre allele, for gene ID: ".$self->curr_gene_mgi_id;
                return;
            }
            INFO $self->curr_gene_mgi_id.": Dre Allele ID: ".$self->curr_allele_dre_id;
        }

        # drill down to check targeting vector
        $self->_check_targeting_vector_against_tarmits();

        DEBUG "---------------------end vector-----------------------------";
    }

    DEBUG "---------------------end design-----------------------------";

    return;
}

sub _check_for_existing_no_dre_allele {
    my ( $self, $curr_vector_hash ) = @_;

    # initialise fields
    $self->curr_allele_no_dre_genbank_exists ( 0 );
    $self->curr_allele_no_dre_genbank_db_id ( undef );
    $self->curr_allele_no_dre_genbank_checked ( 0 );
    $self->curr_allele_no_dre_genbank_vector_checked ( 0 );

    DEBUG "Cassette: " . $curr_vector_hash->{ 'cassette' };
    DEBUG "Backbone: " . $curr_vector_hash->{ 'backbone' };

    # my $find_no_dre_allele_results = $self->_check_for_existing_allele( $cassette );
    my $find_no_dre_allele_results = $self->_check_for_existing_allele( $curr_vector_hash->{ 'cassette' }, $curr_vector_hash->{ 'backbone' } );

    if ( defined $find_no_dre_allele_results && scalar @{ $find_no_dre_allele_results } > 0 ) {

        # allele already exists in Tarmits
        $self->inc_counter_found_no_dre_alleles;

        # fetch allele id for use when looking at targeting vectors
        $self->curr_allele_no_dre_id ( $find_no_dre_allele_results->[0]->{ 'id' } );

        DEBUG "Found existing no dre allele match, allele ID: ".$self->curr_allele_no_dre_id;

        # check whether the genbank files are in tarmits
        $self->_check_no_dre_genbank_files();
    }
    else
    {
        # did not find allele in Tarmits, insert it
        $self->inc_counter_not_found_no_dre_alleles;

        $self->_insert_no_dre_allele ( $curr_vector_hash->{ 'cassette' }, $curr_vector_hash->{ 'backbone' }, $curr_vector_hash->{ 'cassette_type' } );

        if( defined $self->curr_allele_no_dre_id ) {
            DEBUG "The no dre allele ID after insert: ".$self->curr_allele_no_dre_id;
        }
        else {
            ERROR "FAILED to get no dre allele ID after insert";
        }
    }

    return;
}

sub _check_for_existing_dre_allele {
    my ( $self, $curr_vector_hash ) = @_;

    # initialise fields
    $self->curr_allele_dre_genbank_exists ( 0 );
    $self->curr_allele_dre_genbank_db_id ( undef );
    $self->curr_allele_dre_genbank_checked ( 0 );

    # add cassette dre suffix
    my $modified_cassette = $curr_vector_hash->{ 'cassette' } .'_dre';

    DEBUG "Cassette: " . $modified_cassette;
    DEBUG "Backbone: " . $curr_vector_hash->{ 'backbone' };

    my $find_dre_allele_results = $self->_check_for_existing_allele( $modified_cassette, $curr_vector_hash->{ 'backbone' } );

    if ( defined $find_dre_allele_results && scalar @{ $find_dre_allele_results } > 0 ) {

        # allele already exists in Tarmits
        $self->inc_counter_found_dre_alleles;

        # fetch allele id for use when looking at targeting vectors
        $self->curr_allele_dre_id ( $find_dre_allele_results->[0]->{ 'id' } );

        DEBUG "Found existing dre allele match, allele ID: ".$self->curr_allele_dre_id;

        # check whether the genbank files are in tarmits
        $self->_check_dre_genbank_files();
    }
    else
    {
        # did not find allele in Tarmits, insert it
        $self->inc_counter_not_found_dre_alleles;

        $self->_insert_dre_allele( $modified_cassette, $curr_vector_hash->{ 'backbone' }, $curr_vector_hash->{ 'cassette_type' } );

        if( defined $self->curr_allele_dre_id ) {
            DEBUG "The dre allele ID after insert: ".$self->curr_allele_dre_id;
        }
        else {
            ERROR "FAILED to get dre allele ID after insert";
        }
    }
    return;
}

sub _check_for_existing_allele {
    my ( $self, $cassette, $backbone ) = @_;

    # Create selection criteria hash to be used to determine if the allele already exists in Tarmits
    my $find_allele_params = {
        'project_design_id_eq'     => $self->curr_design_id,
        'gene_mgi_accession_id_eq' => $self->curr_gene_mgi_id,
        'assembly_eq'              => $self->curr_design->{ 'design_details' }->{ 'genomic_position' }->{ 'assembly' },
        'chromosome_eq'            => $self->curr_design->{ 'design_details' }->{ 'genomic_position' }->{ 'chromosome' },
        'strand_eq'                => $self->curr_design->{ 'design_details' }->{ 'genomic_position' }->{ 'strand' },
        'cassette_eq'              => $cassette,
        'backbone_eq'              => $backbone,
        'homology_arm_start_eq'    => $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'homology_arm' }->{ 'start' },
        'homology_arm_end_eq'      => $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'homology_arm' }->{ 'end' },
        'cassette_start_eq'        => $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'cassette' }->{ 'start' },
        'cassette_end_eq'          => $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'cassette' }->{ 'end' },
    };

    if ( defined $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'start' } ) {
        $find_allele_params->{ 'loxp_start_eq' } = $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'start' };
    }
    if ( defined $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'end' } ) {
        $find_allele_params->{ 'loxp_end_eq' } = $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'end' };
    }

    # access Tarmits to see if we can locate the allele
    my $find_allele_results = $self->tm->find_allele( $find_allele_params );

    return $find_allele_results;
}

sub _insert_no_dre_allele {
    my ( $self, $cassette, $backbone, $cassette_type ) = @_;

    DEBUG "Inserting no Dre allele";

    my $insert_allele_params = $self->_generate_insert_allele_params( $cassette, $backbone, $cassette_type );

    try {
        my $insert_allele_results = $self->tm->create_allele( $insert_allele_params );

        if ( $insert_allele_results->{ 'project_design_id' } == $self->curr_design_id ) {
            $self->inc_counter_no_dre_allele_inserts;

            # store allele id for use for targeting vector inserts
            $self->curr_allele_no_dre_id ( $insert_allele_results->{ 'id' } );
            INFO "Inserted no dre allele ID: ".$self->curr_allele_no_dre_id." successfully, continuing.";
        }
        else {
            $self->inc_counter_failed_no_dre_allele_inserts;
            WARN "Check on inserted no dre allele failed for gene: ".$self->curr_gene_mgi_id." design id:".$self->curr_design_id;
        }

    } catch {
        $self->inc_counter_failed_no_dre_allele_inserts;
        ERROR "FAILED no dre allele insert for gene: ".$self->curr_gene_mgi_id." design id: ". $self->curr_design_id;
        ERROR "Exception: ".$_;
    };

    return;
}

sub _insert_dre_allele {
    my ( $self, $modified_cassette, $backbone, $cassette_type ) = @_;

    DEBUG "Inserting Dre allele";

    my $insert_allele_params = $self->_generate_insert_allele_params( $modified_cassette, $backbone, $cassette_type );

    try {
        my $insert_allele_results = $self->tm->create_allele( $insert_allele_params );

        if ( $insert_allele_results->{ 'project_design_id' } == $self->curr_design_id ) {
            $self->inc_counter_dre_allele_inserts;
            # store allele id for use for targeting vector inserts
            $self->curr_allele_dre_id ( $insert_allele_results->{ 'id' } );
            INFO "Inserted dre allele ID: ".$self->curr_allele_dre_id." successfully, continuing.";
        }
        else {
            $self->inc_counter_failed_dre_allele_inserts;
            WARN "Check on inserted dre allele failed for gene: ".$self->curr_gene_mgi_id." design id:".$self->curr_design_id;
        }

    } catch {
        $self->inc_counter_failed_dre_allele_inserts;
        ERROR "FAILED dre allele insert for gene: ".$self->curr_gene_mgi_id." design id: ". $self->curr_design_id;
        ERROR "Exception: ".$_;
    };

    return;
}

sub _generate_insert_allele_params {
    my ( $self, $cassette, $backbone, $cassette_type ) = @_;

    DEBUG "Inserting allele";

    my $insert_allele_params = {
        'project_design_id'        => $self->curr_design_id,
        'gene_mgi_accession_id'    => $self->curr_gene_mgi_id,
        'assembly'                 => $self->curr_design->{ 'design_details' }->{ 'genomic_position' }->{ 'assembly' },
        'chromosome'               => $self->curr_design->{ 'design_details' }->{ 'genomic_position' }->{ 'chromosome' },
        'strand'                   => $self->curr_design->{ 'design_details' }->{ 'genomic_position' }->{ 'strand' },
        'cassette'                 => $cassette,
        'backbone'                 => $backbone,
        'homology_arm_start'       => $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'homology_arm' }->{ 'start' },
        'homology_arm_end'         => $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'homology_arm' }->{ 'end' },
        'cassette_start'           => $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'cassette' }->{ 'start' },
        'cassette_end'             => $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'cassette' }->{ 'end' },
        'cassette_type'            => $cassette_type,
        'mutation_type_name'       => $self->curr_design->{ 'design_details' }->{ 'mutation_details' }->{ 'mutation_type' },
        'mutation_method_name'     => $self->curr_design->{ 'design_details' }->{ 'mutation_details' }->{ 'mutation_method' },
        'floxed_start_exon'        => $self->curr_design->{ 'design_details' }->{ 'mutation_details' }->{ 'floxed_start_exon' },
        'floxed_end_exon'          => $self->curr_design->{ 'design_details' }->{ 'mutation_details' }->{ 'floxed_end_exon' },
    };

    # leave mutation subtype blank
    #'mutation_subtype_name'    => $self->curr_design->{ 'design_details' }->{ 'mutation_details' }->{ 'mutation_subtype' },

    if ( defined $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'start' } ) {
        $insert_allele_params->{ 'loxp_start' } = $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'start' };
    }
    if ( defined $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'end' } ) {
        $insert_allele_params->{ 'loxp_end' } = $self->curr_design->{ 'design_details' }->{ 'molecular_co_ords' }->{ 'loxp' }->{ 'end' };
    }

    return $insert_allele_params;
}

sub _check_targeting_vector_against_tarmits {
    my ($self ) = @_;

    DEBUG "Check targeting vector - name = ".$self->curr_targeting_vector_name.":";

    $self->curr_targeting_vector ( $self->es_clones->{ $self->curr_gene_mgi_id }->{ 'designs' }->{ $self->curr_design_id }->{ 'targeting_vectors' }->{ $self->curr_targeting_vector_name } );

    # List of unique targeting vector features
    my $find_tv_params = {
        'name_eq' => $self->curr_targeting_vector_name,
    };

    # return type should be an array of hashes
    my $tv_find_results = $self->tm->find_targeting_vector( $find_tv_params );

    # targeting vector id needed for es cell clone checks
    $self->curr_targeting_vector_id ( undef );

    if ( defined $tv_find_results && scalar @{ $tv_find_results } > 0 ) {

        # fetch targeting vector id for use when looking at es cell clones
        $self->curr_targeting_vector_id ( $tv_find_results->[0]->{ 'id' } );

        unless ( defined $self->curr_targeting_vector_id ) {
            ERROR "Targeting vector ID not found for vector name: ".$self->curr_targeting_vector_name;
            # Do not continue for this targeting vector
            return;
        }

        # targeting vector already exists in Tarmits
        $self->inc_counter_found_tvs;
        DEBUG "Found targeting vector match, ID: ".$self->curr_targeting_vector_id;

        # if force updates is on
        if ( $self->force_updates ) {

            # check whether the targeting vector is connected to the correct allele; if not update it
            my $current_tv_allele_id = $tv_find_results->[0]->{ 'allele_id' };

            if( $current_tv_allele_id != $self->curr_allele_no_dre_id ) {
                DEBUG "Targeting vectors current allele ID <" . $current_tv_allele_id . "> does not match expected ID <" . $self->curr_allele_no_dre_id . ">, update it";
                unless ( $self->_update_targ_vect_allele_id() ) {
                    ERROR "Failed to update targeting vector allele id for vector name: ".$self->curr_targeting_vector_name;
                    # do not continue down to clones for this targeting vector
                    return;
                }
            }

            # update the ikmc project ID for this targeting vector
            unless ( $self->_update_targ_vect_ikmc_project_id() ) {
                ERROR "Failed to update targeting vector ikmc project id for vector name: ".$self->curr_targeting_vector_name;
            }
        }

        # check targeting vectors report to public flag matches that in LIMS2
        if ( $tv_find_results->[0]->{ 'report_to_public' } == 0 ) {
            unless ( $self->_update_targ_vect_report_to_public_flag() ) {
                ERROR "Failed to update targeting vector report to public flag for vector name: ".$self->curr_targeting_vector_name;
                # do not continue down to clones for this targeting vector
                return;
            }
        }
    }
    else
    {
        # did not find targeting vector in Tarmits, insert it
        $self->inc_counter_not_found_tvs;
        $self->curr_targeting_vector_id ( $self->_insert_targeting_vector() );
    }

    unless ( $self->curr_targeting_vector_id ) {
        # do not continue down to clones for this targeting vector
        return;
    }

    INFO "Processing ES clones in targeting vector ID:".$self->curr_targeting_vector_id;

    # cycle through each clone for the targeting vector
    for my $curr_clone_name ( sort keys %{ $self->curr_targeting_vector->{ 'clones' } } ) {
        $self->curr_clone_name ( $curr_clone_name );

        DEBUG "- - - - - - - - - - - es cell - - - - - - - - - - - - - - -";
        DEBUG "Checking es cell with clone name : " . $curr_clone_name;

        # initialise fields
        $self->curr_es_cell_clone_id( undef );
        $self->curr_clone( undef );
        $self->curr_clone_accepted( 0 );
        $self->curr_clone_has_dre( 0 );

        # check each es cell clone
        $self->_check_es_cell_against_tarmits();

        DEBUG "- - - - - - - - - - end es cell - - - - - - - - - - - - - -";
    }

    return;
}

sub _update_targ_vect_allele_id {
    my ( $self ) = @_;

    my $update_ok = 0;

    my $new_allele_id = $self->curr_allele_no_dre_id;

    try {
        my $update_allele_id_params = {
            'allele_id' => $new_allele_id,
        };

        # update takes the id of the item plus the updated parameters
        my $tv_update_results = $self->tm->update_targeting_vector( $self->curr_targeting_vector_id, $update_allele_id_params );

        if ( defined $tv_update_results && ( $tv_update_results->{ 'id' } == $self->curr_targeting_vector_id ) ) {
            $self->inc_counter_tv_allele_id_updates;
            INFO "Updated targeting vector ID: ".$self->curr_targeting_vector_id." allele ID to: ".$new_allele_id;
            $update_ok = 1;
        }
        else {
            $self->inc_counter_failed_tv_allele_id_updates;
            DEBUG "FAILED Check on update of targeting vector allele ID failed for gene ID: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", targeting vector id: ".$self->curr_targeting_vector_id;
        }
    }
    catch {
        $self->inc_counter_failed_tv_allele_id_updates;
        ERROR "FAILED Targeting vector allele ID update for gene ID: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name;
        ERROR "Exception: ".$_;
    };

    return $update_ok;
}

sub _update_targ_vect_ikmc_project_id {
    my ( $self ) = @_;

    my $update_ok = 0;

    # use no dre allele for targeting vector ikmc project id
    my $ikmc_project_id = $self->_create_ikmc_project_id( $self->curr_allele_no_dre_id );

    try {
        my $update_ikmc_proj_id_params = {
            'ikmc_project_id' => $ikmc_project_id,
        };

        # update takes the id of the item plus the updated parameters
        my $tv_update_results = $self->tm->update_targeting_vector( $self->curr_targeting_vector_id, $update_ikmc_proj_id_params );

        if ( defined $tv_update_results && ( $tv_update_results->{ 'id' } == $self->curr_targeting_vector_id ) ) {
            $self->inc_counter_tv_ikmc_proj_id_updates;
            INFO "Updated targeting vector ID: ".$self->curr_targeting_vector_id." ikmc project ID to: ".$ikmc_project_id;
            $update_ok = 1;
        }
        else {
            $self->inc_counter_failed_tv_ikmc_proj_id_updates;
            DEBUG "FAILED Check on update of targeting vector ikmc project ID failed for gene ID: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", targeting vector id: ".$self->curr_targeting_vector_id;
        }
    }
    catch {
        $self->inc_counter_failed_tv_ikmc_proj_id_updates;
        ERROR "FAILED Targeting vector ikmc project ID update for gene ID: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name;
        ERROR "Exception: ".$_;
    };

    return $update_ok;
}

sub _update_targ_vect_report_to_public_flag {
    my ( $self ) = @_;

    my $update_ok = 0;

    # update report to public flag to true
    DEBUG "Targeting Vector report to public is currently false, need to update it to true";

    try {
        my $update_tv_params = {
            'report_to_public' => $self->curr_targeting_vector->{ 'targeting_vector_details' }->{ 'report_to_public' },
        };

        # update takes the id of the item plus the updated parameters
        my $tv_update_results = $self->tm->update_targeting_vector( $self->curr_targeting_vector_id, $update_tv_params );

        if ( defined $tv_update_results && ( $tv_update_results->{ 'id' } == $self->curr_targeting_vector_id ) ) {
            $self->inc_counter_tv_rtp_updates;
            INFO "Updated targeting vector ID: ".$self->curr_targeting_vector_id." report to public flag, continuing";
            $update_ok = 1;
        }
        else {
            $self->inc_counter_failed_tv_rtp_updates;
            DEBUG "FAILED Check on update of targeting vector report to public failed for gene ID: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", targeting vector id: ".$self->curr_targeting_vector_id;
        }
    }
    catch {
        $self->inc_counter_failed_tv_rtp_updates;
        ERROR "FAILED Targeting vector report to public update for gene ID: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name;
        ERROR "Exception: ".$_;
    };

    return $update_ok;
}

sub _insert_targeting_vector {
    my ( $self ) = @_;

    DEBUG "No targeting vector match, inserting new one";

    # set up targeting vector insert parameters
    # NB insert targeting vector against no-dre allele only
    my $insert_tv_params = {
        'name'                  => $self->curr_targeting_vector_name,
        'allele_id'             => $self->curr_allele_no_dre_id,
        'ikmc_project_id'       => $self->_create_ikmc_project_id( $self->curr_allele_no_dre_id ),
        'intermediate_vector'   => $self->curr_targeting_vector->{ 'targeting_vector_details' }->{ 'intermediate_vector' },
        'pipeline_id'           => $self->curr_targeting_vector->{ 'targeting_vector_details' }->{ 'pipeline_id' },
        'report_to_public'      => $self->curr_targeting_vector->{ 'targeting_vector_details' }->{ 'report_to_public' },
    };

    try {
        my $results_tv_insert = $self->tm->create_targeting_vector( $insert_tv_params );

        if ( defined $results_tv_insert && ( $results_tv_insert->{ 'name' } eq $self->curr_targeting_vector_name ) ) {
            $self->inc_counter_tv_inserts;

            # store targeting vector id for use for es cell clone checks
            $self->curr_targeting_vector_id ( $results_tv_insert->{ 'id' } );
            INFO "Inserted targeting vector ID: ".$self->curr_targeting_vector_id." successfully";
        }
        else {
            $self->inc_counter_failed_tv_inserts;
            WARN "Check on inserted targeting vector failed for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name;
        }
    }
    catch {
        $self->inc_counter_failed_tv_inserts;
        ERROR "FAILED Targeting vector insert for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name;
        ERROR "Exception: ".$_;
    };

    # do not continue down to clones for this targeting vector
    return $self->curr_targeting_vector_id;
}

sub _create_ikmc_project_id {
    my ( $self, $allele_id ) = @_;

    # default to no dre allele id
    unless ( $allele_id ) {
        $allele_id = $self->curr_allele_no_dre_id;
    }

    my $ikmc_proj_id = ( $self->curr_targeting_vector->{ 'targeting_vector_details' }->{ 'pipeline_name' } ).'_'.$allele_id;

    DEBUG "create_ikmc_proj_id set to: ".$ikmc_proj_id;

    return $ikmc_proj_id;
}

## no critic ( Subroutines::ProhibitExcessComplexity )
sub _check_es_cell_against_tarmits {
    my ( $self ) = @_;

    DEBUG "Checking ES cell, clone name: ".$self->curr_clone_name;

    $self->curr_clone ( $self->es_clones->{ $self->curr_gene_mgi_id }->{ 'designs' }->{ $self->curr_design_id }->{ 'targeting_vectors' }->{ $self->curr_targeting_vector_name }->{ 'clones' }->{ $self->curr_clone_name } );
    $self->curr_clone_accepted ( $self->curr_clone->{ 'info' }->{ 'clone_accepted' } );

    if ( exists $self->curr_clone->{ 'es_cell_details' }->{ 'ep_recombinase' } && ( $self->curr_clone->{ 'es_cell_details' }->{ 'ep_recombinase' } eq 'Dre' ) ) {
        $self->curr_clone_has_dre ( 1 );
        DEBUG "Clone has Dre";
    }
    else {
        DEBUG "Clone does not have Dre";
    }

    # List of unique clone parameters for select
    my $find_clone_params = {
        'name_eq' => $self->curr_clone_name,
    };

    DEBUG "Check if the clone already exists";

    # return type should be an array of hashes
    my $clone_find_results = $self->tm->find_es_cell( $find_clone_params );

    if ( defined $clone_find_results && scalar @{ $clone_find_results } > 0 ) {
        DEBUG "Clone exists in Tarmits";

        # es cell clone already exists in Tarmits
        $self->inc_counter_found_es_cells;

        # fetch es cell clone id
        $self->curr_es_cell_clone_id ( $clone_find_results->[0]->{ 'id' } );
        my $clone_curr_db_allele_id = $clone_find_results->[0]->{ 'allele_id' };

        if ( defined  $self->curr_es_cell_clone_id ) {
            DEBUG "Found ES cell clone match, ID: ".$self->curr_es_cell_clone_id;
        }

        # optional forced updates
        if ( $self->force_updates ) {
            DEBUG "Force updates: checking whether need to update allele ID";
            DEBUG "Force updates: clone has current database allele id : " . $clone_curr_db_allele_id;
            if( $self->curr_allele_dre_id ) { DEBUG "Force updates: calculated dre allele id : " . $self->curr_allele_dre_id; }
            if( $self->curr_allele_no_dre_id ) { DEBUG "Force updates: calculated NON dre allele id : " . $self->curr_allele_no_dre_id; }

            if ( $self->curr_clone_has_dre && ( $clone_curr_db_allele_id != $self->curr_allele_dre_id ) ) {
                DEBUG "Identified need to update allele ID from " . $clone_curr_db_allele_id . " to dre allele id " . $self->curr_allele_dre_id;
                # need to update clone allele ID as pointing at the wrong allele
                unless ( $self->_update_clone_allele_id( $self->curr_allele_dre_id ) ) {
                    ERROR "Failed to update es cell clone allele id for clone name: " . $self->curr_clone_name;
                }
            }

            if ( !$self->curr_clone_has_dre && ( $clone_curr_db_allele_id != $self->curr_allele_no_dre_id ) ) {
                DEBUG "Identified need to update allele ID from " . $clone_curr_db_allele_id . " to NON dre allele id " . $self->curr_allele_no_dre_id;
                # need to update clone allele ID as pointing at the wrong allele
                unless ( $self->_update_clone_allele_id( $self->curr_allele_no_dre_id ) ) {
                    ERROR "Failed to update es cell clone allele id for clone name: " . $self->curr_clone_name;
                }
            }

            DEBUG "Force updates: updating ikmc project ID";

            # update the ikmc project ID for this es cell clone
            if (!$self->_update_clone_ikmc_project_id() ) {
                ERROR "Failed to update es cell clone ikmc project id for clone name: ".$self->curr_clone_name;
            }

            DEBUG "Force updates: updating allele symbol superscript";

            #   update the allele symbol superscript
            if (!$self->_update_clone_allele_symbol_superscript() ) {
                ERROR "Failed to update es cell clone allele symbol superscript for clone name: ".$self->curr_clone_name;
            }

            if (!$self->_update_clone_targeting_vector() ) {
                ERROR "Failed to update es cell clone targeting vector for clone name: ".$self->curr_clone_name;
            }
        }

        # if report to public flag matches clone accepted flag do nothing, but if different then update
        DEBUG "Checking report to public flag";

        my $tarmits_clone_report_to_public_string = $clone_find_results->[0]->{ 'report_to_public' };
        my $tarmits_clone_report_to_public = 0;
        if ( $tarmits_clone_report_to_public_string eq 'true' ) { $tarmits_clone_report_to_public = 1; }

        DEBUG "Tarmits clone report to public is currently: ".$tarmits_clone_report_to_public;

        if ( $tarmits_clone_report_to_public != $self->curr_clone_accepted ) {
            DEBUG "LIMS2 clone accepted flag ( ".$self->curr_clone_accepted." ) not equal to Tarmits report to public flag ( ".$tarmits_clone_report_to_public."), updating Tarmits";

            $self->_update_clone_report_to_public_flag();
        }
        else {
            DEBUG "Did not need to update report to public flag";
        }
    }
    else
    {
        DEBUG "Clone does not exist in Tarmits";

        # did not find es cell clone in Tarmits, insert it but ONLY if accepted in LIMS2
        if ( $self->curr_clone_accepted ) {
            $self->inc_counter_not_found_es_cells;
            DEBUG "Clone accepted in LIMS2 but not found in Tarmits, inserting";
            $self->_insert_clone ();
        }
        else {
            $self->inc_counter_ignored_es_cells;
            DEBUG "Clone not accepted in LIMS2 and not in Tarmits: IGNORING";
            return;
        }
    }

    # check the genbank files exist for the allele, if not insert them now we have a current alleles,
    # targeting vector and es cell clone
    unless ( defined $self->curr_es_cell_clone_id ) { return; }

    $self->_insert_or_update_genbank_files ();

    return;
}
## use critic

sub _update_clone_ikmc_project_id {
    my ( $self ) = @_;

    my $update_ok = 0;

    my $allele_id = $self->_select_current_clone_allele_id();

    my $ikmc_project_id = $self->_create_ikmc_project_id( $allele_id );

    try {
        my $update_ikmc_proj_id_params = {
            'ikmc_project_id' => $ikmc_project_id,
        };

        # update takes the id of the item plus the updated parameters
        my $clone_update_resultset = $self->tm->update_es_cell( $self->curr_es_cell_clone_id, $update_ikmc_proj_id_params );

        if ( defined $clone_update_resultset && ( $clone_update_resultset->{ 'id' } == $self->curr_es_cell_clone_id ) ) {
            $self->inc_counter_es_cell_ikmc_proj_id_updates;
            INFO "Updated ikmc project ID for ES cell clone ID: ".$self->curr_es_cell_clone_id." to value: ".$ikmc_project_id.", continuing";
            $update_ok = 1;
        }
        else {
            $self->inc_counter_failed_es_cell_ikmc_proj_id_updates;
            WARN "Check on update of ikmc project ID for ES cell clone failed for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", es cell clone name: ".$self->curr_clone_name.", ikmc project ID: ".$ikmc_project_id;
        }
    }
    catch {
        $self->inc_counter_failed_es_cell_ikmc_proj_id_updates;
        ERROR "FAILED to update ikmc project ID for ES Cell clone for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", es cell clone name: ".$self->curr_clone_name.", ikmc project ID: ".$ikmc_project_id;
        ERROR "Exception: ".$_;
    };

    return $update_ok;
}

sub _update_clone_report_to_public_flag {
    my ( $self ) = @_;

    DEBUG "ES Cell clone report to public flag does not match state in LIMS2, attempting to update";

    try {
        my $update_es_cell_params = {
            'report_to_public' => $self->curr_clone_accepted,
        };

        # update takes the id of the item plus the updated parameters
        my $clone_update_resultset = $self->tm->update_es_cell( $self->curr_es_cell_clone_id, $update_es_cell_params );

        if ( defined $clone_update_resultset && ( $clone_update_resultset->{ 'id' } == $self->curr_es_cell_clone_id ) ) {
            if ( $self->curr_clone_accepted ) {
                $self->inc_counter_es_cell_rtp_updates_to_true;
            }
            else {
                $self->inc_counter_es_cell_rtp_updates_to_false;
            }

            INFO "Updated report to public for ES cell clone ID: ".$self->curr_es_cell_clone_id." to value: ".$self->curr_clone_accepted.", continuing";
        }
        else {
            $self->inc_counter_failed_es_cell_rtp_updates;
            WARN "Check on update of report to public for ES cell clone failed for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", es cell clone name: ".$self->curr_clone_name.", es cell accepted: ".$self->curr_clone_accepted;
        }
    }
    catch {
        $self->inc_counter_failed_es_cell_rtp_updates;
        ERROR "FAILED to update report to public for ES Cell clone for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", es cell clone name: ".$self->curr_clone_name.", es cell accepted: ".$self->curr_clone_accepted;
        ERROR "Exception: ".$_;
    };

    return;
}

sub _update_clone_allele_symbol_superscript {
    my ( $self ) = @_;

    DEBUG "Updating clone mgi allele symbol superscript";

    my $update_ok = 0;

    try {
        my $update_es_cell_params = {
            'mgi_allele_symbol_superscript' => $self->curr_clone->{ 'es_cell_details' }->{ 'mgi_allele_symbol_superscript' },
        };

        # update takes the id of the item plus the updated parameters
        my $clone_update_resultset = $self->tm->update_es_cell( $self->curr_es_cell_clone_id, $update_es_cell_params );

        if ( defined $clone_update_resultset && $clone_update_resultset != 0 ) {
            $self->inc_counter_es_cell_allele_symb_updates;
            INFO "Updated allele symbol superscript for ES cell clone ID: ".$self->curr_es_cell_clone_id." to ".$self->curr_clone->{ 'es_cell_details' }->{ 'mgi_allele_symbol_superscript' };
            $update_ok = 1;
        }
        else {
            $self->inc_counter_failed_es_cell_allele_symb_updates;
            WARN "Check on update of allele symbol superscript for ES cell clone failed for gene: ".$self->curr_gene_mgi_id.", es cell clone name: ".$self->curr_clone_name;
        }
    }
    catch {
        $self->inc_counter_failed_es_cell_allele_symb_updates;
        ERROR "FAILED allele symbol superscript update for ES Cell clone for gene: ".$self->curr_gene_mgi_id.", es cell clone name: ".$self->curr_clone_name;
        ERROR "Exception: ".$_;
    };

    return $update_ok;
}

sub _update_clone_targeting_vector {
    my ( $self ) = @_;

    my $update_ok = 0;

    # using this method because the clone has been incorrectly linked to the wrong targeting vector

    try {
        my $update_clone_params = {
            'targeting_vector_id'           => $self->curr_targeting_vector_id,
        };

        # update takes the id of the item plus the updated parameters
        my $clone_update_resultset = $self->tm->update_es_cell( $self->curr_es_cell_clone_id, $update_clone_params );

        if ( defined $clone_update_resultset && ( $clone_update_resultset->{ 'id' } == $self->curr_es_cell_clone_id ) ) {
            $self->inc_counter_es_cell_targ_vect_updates;
            INFO "Updated targeting vector ID for ES cell clone ID: " . $self->curr_es_cell_clone_id . " to value: " . $self->curr_targeting_vector_id;
            $update_ok = 1;
        }
        else {
            $self->inc_counter_failed_es_cell_targ_vect_updates;
            WARN "Check on update of targeting vector ID for ES cell clone failed for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", es cell clone name: ".$self->curr_clone_name;
        }
    }
    catch {
        $self->inc_counter_failed_es_cell_targ_vect_updates;
        ERROR "FAILED to update targeting vector ID for ES Cell clone for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", es cell clone name: ".$self->curr_clone_name;
        ERROR "Exception: ".$_;
    };

    return $update_ok;
}

sub _update_clone_allele_id {
    my ( $self, $new_allele_id ) = @_;

    my $update_ok = 0;

    # using this method because the clone has been incorrectly linked to the wrong allele

    try {
        my $update_clone_params = {
            'allele_id'           => $new_allele_id,
        };

        # update takes the id of the item plus the updated parameters
        my $clone_update_resultset = $self->tm->update_es_cell( $self->curr_es_cell_clone_id, $update_clone_params );

        if ( defined $clone_update_resultset && ( $clone_update_resultset->{ 'id' } == $self->curr_es_cell_clone_id ) ) {
            $self->inc_counter_es_cell_allele_id_updates;
            INFO "Updated allele ID for ES cell clone ID: " . $self->curr_es_cell_clone_id . " to value: " . $new_allele_id;
            $update_ok = 1;
        }
        else {
            $self->inc_counter_failed_es_cell_allele_id_updates;
            WARN "Check on update of allele ID for ES cell clone failed for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", es cell clone name: ".$self->curr_clone_name;
        }
    }
    catch {
        $self->inc_counter_failed_es_cell_allele_id_updates;
        ERROR "FAILED to update allele ID for ES Cell clone for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", es cell clone name: ".$self->curr_clone_name;
        ERROR "Exception: ".$_;
    };

    return $update_ok;
}

sub _select_current_clone_allele_id {
    my ( $self ) = @_;

    # allele id depends on whether dre or no-dre
    my $allele_id;
    if( $self->curr_clone_has_dre ) {
        DEBUG "Clone has Dre applied";
        $allele_id = $self->curr_allele_dre_id;
    }
    else {
        DEBUG "Clone has not had Dre applied";
        $allele_id = $self->curr_allele_no_dre_id;
    }

    return $allele_id
}

sub _insert_clone {
    my ( $self ) = @_;

    DEBUG "Inserting new es clone";

    # allele id depends on whether dre or no-dre
    my $allele_id = $self->_select_current_clone_allele_id();

    DEBUG "Allele ID to insert: ".$allele_id;

    my $insert_es_cell_params = {
        'name'                          => $self->curr_clone_name,
        'allele_id'                     => $allele_id,
        'ikmc_project_id'               => $self->_create_ikmc_project_id( $allele_id ),
        'targeting_vector_id'           => $self->curr_targeting_vector_id,
        'parental_cell_line'            => $self->curr_clone->{ 'es_cell_details' }->{ 'parental_cell_line' },
        'pipeline_id'                   => $self->curr_clone->{ 'es_cell_details' }->{ 'pipeline_id' },
        'report_to_public'              => $self->curr_clone->{ 'info' }->{ 'clone_accepted' },
        'mgi_allele_symbol_superscript' => $self->curr_clone->{ 'es_cell_details' }->{ 'mgi_allele_symbol_superscript' },
    };
    # 'production_qc_five_prime_screen'  => $self->curr_clone->{ 'qc_metrics' }->{ 'five_prime_screen' },
    # 'production_qc_three_prime_screen' => $self->curr_clone->{ 'qc_metrics' }->{ 'three_prime_screen' },
    # 'production_qc_loxp_screen'        => $self->curr_clone->{ 'qc_metrics' }->{ 'loxp_screen' },
    # 'production_qc_loss_of_allele'     => $self->curr_clone->{ 'qc_metrics' }->{ 'loss_of_allele' },
    # 'production_qc_vector_integrity'   => $self->curr_clone->{ 'qc_metrics' }->{ 'vector_integrity' },

    try {
        my $results_es_cell_insert = $self->tm->create_es_cell( $insert_es_cell_params );

        if ( defined $results_es_cell_insert && ( $results_es_cell_insert->{ 'name' } eq $self->curr_clone_name ) ) {
            $self->inc_counter_es_cell_inserts;
            # store es cell clone id
            $self->curr_es_cell_clone_id ( $results_es_cell_insert->{ 'id' } );
            INFO "Inserted es cell clone ID: ".$self->curr_es_cell_clone_id;
        }
        else {
            $self->inc_counter_failed_es_cell_inserts;
            WARN "Check on inserted es cell clone failed for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", es cell clone name: ".$self->curr_clone_name;
        }
    } catch {
        $self->inc_counter_failed_es_cell_inserts;
        ERROR "Failed ES Cell clone insert for gene: ".$self->curr_gene_mgi_id.", design: ".$self->curr_design_id.", targeting vector: ".$self->curr_targeting_vector_name.", es cell clone name: ".$self->curr_clone_name;
        ERROR "Exception: ".$_;
    };

    return;
}

sub _check_no_dre_genbank_files {
    my ( $self ) = @_;

    DEBUG "Checking genbank files for no dre allele ID: ".$self->curr_allele_no_dre_id;

    my $tarmits_obj;
    try {
        my $find_allele_params = {
            'allele_id' => $self->curr_allele_no_dre_id,
        };

        $tarmits_obj = $self->tm->find_genbank_file( $find_allele_params );

        # check tarmits object contains valid genbank files
        if ( defined $tarmits_obj && scalar @{ $tarmits_obj } > 0 ) {
            # check allele ID
            my $tarmits_allele_id = @{ $tarmits_obj }[0]->{ 'allele_id' };
            DEBUG "Tarmits allele ID retrieved: ".$tarmits_allele_id;

            # if ok set flag for allele
            if ( defined $tarmits_allele_id && ( $tarmits_allele_id eq $self->curr_allele_no_dre_id ) ) {
                # store the database ID field for genbank updates
                $self->curr_allele_no_dre_genbank_db_id ( @{ $tarmits_obj }[0]->{ 'id' } );

                DEBUG "Retrieved genbank data matches on allele ID: ".$tarmits_allele_id;
                $self->curr_allele_no_dre_genbank_exists ( 1 );
            }
        }
        else {
            # allele genbank exists flag stays false, so genbank data will be inserted on first clone
            DEBUG "Did not find genbank files for no dre allele ID: ".$self->curr_allele_no_dre_id;
        }

        $self->inc_counter_successful_no_dre_genbank_checks;
    }
    catch {
        $self->inc_counter_failed_no_dre_genbank_checks;
        WARN "Error when trying to fetch allele genbank files for no dre allele ID: ".$self->curr_allele_no_dre_id;
        WARN "Exception: ".$_;
    };

    return;
}

sub _check_dre_genbank_files {
    my ( $self ) = @_;

    DEBUG "Checking genbank files for dre allele ID: ".$self->curr_allele_dre_id;

    my $tarmits_obj;
    try {
        my $find_allele_params = {
            'allele_id' => $self->curr_allele_dre_id,
        };

        $tarmits_obj = $self->tm->find_genbank_file( $find_allele_params );

        # check tarmits object contains valid genbank files
        if ( defined $tarmits_obj && scalar @{ $tarmits_obj } > 0 ) {
            # check allele ID
            my $tarmits_allele_id = @{ $tarmits_obj }[0]->{ 'allele_id' };
            DEBUG "Tarmits allele ID retrieved: ".$tarmits_allele_id;

            # if ok set flag for allele
            if ( defined $tarmits_allele_id && ( $tarmits_allele_id eq $self->curr_allele_dre_id ) ) {
                # store the database ID field for genbank updates
                $self->curr_allele_dre_genbank_db_id ( @{ $tarmits_obj }[0]->{ 'id' } );

                DEBUG "Retrieved genbank data matches on allele ID: ".$tarmits_allele_id;
                $self->curr_allele_dre_genbank_exists ( 1 );
            }
        }
        else {
            # allele genbank exists flag stays false, so genbank data will be inserted on first clone
            DEBUG "Did not find genbank files for dre allele ID: ".$self->curr_allele_dre_id;
        }

        $self->inc_counter_successful_dre_genbank_checks;
    }
    catch {
        $self->inc_counter_failed_dre_genbank_checks;
        WARN "Error when trying to fetch allele genbank files for dre allele ID: ".$self->curr_allele_dre_id;
        WARN "Exception: ".$_;
    };

    return;
}

sub _insert_or_update_genbank_files {
    my ( $self ) = @_;

    if ( $self->curr_clone_has_dre ) {
        DEBUG "Insert or update genbank files: clone has Dre";
        DEBUG "Insert or update genbank files: curr_allele_no_dre_genbank_checked = ".$self->curr_allele_no_dre_genbank_checked;
        DEBUG "Insert or update genbank files: curr_allele_no_dre_genbank_vector_checked = ".$self->curr_allele_no_dre_genbank_vector_checked;
        DEBUG "Insert or update genbank files: curr_allele_dre_genbank_checked = ".$self->curr_allele_dre_genbank_checked;

        # need to check / update / insert non-dre allele with vector genbank file
        unless ( $self->curr_allele_no_dre_genbank_checked || $self->curr_allele_no_dre_genbank_vector_checked ) {
            DEBUG "Insert or update genbank files: no dre vector";
            $self->_insert_or_update_no_dre_allele_vector_genbank_file();
        }

        # need to check / update / insert dre allele with clone genbank file
        unless ( $self->curr_allele_dre_genbank_checked ) {
            DEBUG "Insert or update genbank files: dre clone";
            $self->_insert_or_update_dre_allele_clone_genbank_file();
        }
    }
    else {
        # need to check / update / insert non-dre allele with both vector and clone genbank files
        unless ( $self->curr_allele_no_dre_genbank_checked ) {
            DEBUG "Insert or update genbank files: no dre vector and clone";
            $self->_insert_or_update_no_dre_allele_vector_and_clone_genbank_files();
        }
    }

    return;
}

sub _insert_or_update_dre_allele_clone_genbank_file {
    my ( $self ) = @_;

    unless ( defined $self->curr_allele_dre_id ) {
        ERROR "Attempt to create genbank dre clone file but missing dre allele ID";
        return;
    }

    if ( $self->curr_allele_dre_genbank_exists && $self->curr_allele_dre_genbank_db_id ) {
        if ( $self->force_updates ) {
            DEBUG "Force updates: update genbank data dre clone";

            # create appropriate genbank file
            my $escell_bioseq_string = $self->_create_allele_bioseq_string();

            unless ( $escell_bioseq_string ) {
                $self->inc_counter_failed_dre_genbank_file_updates;
                # set flag so only attempt update once per allele
                $self->curr_allele_dre_genbank_checked ( 1 );
                ERROR "Failed to create Clone bioseq string for allele ID: ".$self->curr_allele_dre_id;
                return;
            }

            my $genbank_data = {};
            $genbank_data->{ 'allele_id' }          = $self->curr_allele_dre_id;
            $genbank_data->{ 'escell_clone' }       = $escell_bioseq_string;

            # update the allele genbank data
            my $dre_db_id = $self->curr_allele_dre_genbank_db_id;
            DEBUG "Existing genbank data database ID: ".$dre_db_id." for Allele ID: ".$genbank_data->{ 'allele_id' };

            if ( $self->_update_genbank_files( $dre_db_id, $genbank_data ) ) {
                # set flag so only update once per allele
                $self->curr_allele_dre_genbank_checked ( 1 );
                # $self->curr_allele_dre_genbank_exists ( 1 );
                $self->inc_counter_successful_dre_genbank_file_updates;
                DEBUG "Updated dre genbank DB ID :".$dre_db_id;
            }
            else {
                $self->inc_counter_failed_dre_genbank_file_updates;
            }
        }
        else {
            # do nothing
            return;
        }
    }
    else {
        DEBUG "Insert genbank files dre clone";

        # create appropriate genbank files
        my $escell_bioseq_string = $self->_create_allele_bioseq_string();

        unless ( $escell_bioseq_string ) {
            $self->inc_counter_failed_dre_genbank_file_inserts;
            # set flags so only attempt update once per allele
            $self->curr_allele_dre_genbank_checked ( 1 );
            ERROR "Failed to create Clone bioseq string for allele ID: ".$self->curr_allele_dre_id;
            return;
        }

        my $genbank_data = {};
        # allele ID may be dre or non-dre version depending on clone
        $genbank_data->{ 'allele_id' }          = $self->curr_allele_dre_id;
        $genbank_data->{ 'escell_clone' }       = $escell_bioseq_string;

        # insert the allele genbank data and return the database ID
        my $db_id = $self->_insert_genbank_files( $genbank_data );
        $self->curr_allele_dre_genbank_db_id ( $db_id );

        if ( $self->curr_allele_dre_genbank_db_id ) {
            DEBUG "Inserted dre genbank DB ID :".$self->curr_allele_dre_genbank_db_id;
            # set flags so only update once per allele
            $self->curr_allele_dre_genbank_checked ( 1 );
            $self->curr_allele_dre_genbank_exists ( 1 );
            $self->inc_counter_successful_dre_genbank_file_inserts;
        }
        else {
            $self->inc_counter_failed_dre_genbank_file_inserts;
        }
    }

    return;
}

sub _insert_or_update_no_dre_allele_vector_genbank_file {
    my ( $self ) = @_;

    unless ( defined $self->curr_allele_no_dre_id ) {
        ERROR "Attempt to create no dre vector genbank file but missing no dre allele ID";
        return;
    }

    if ( $self->curr_allele_no_dre_genbank_exists && defined $self->curr_allele_no_dre_genbank_db_id ) {
        if ( $self->force_updates ) {
            DEBUG "Force updates: update genbank data no-dre vector";

            # create appropriate genbank files
            my $vect_bioseq_string = $self->_create_vector_bioseq_string();

            unless ( $vect_bioseq_string ) {
                $self->inc_counter_failed_no_dre_genbank_file_updates;
                # set flag so only attempt update once per allele
                $self->curr_allele_no_dre_genbank_vector_checked ( 1 );
                ERROR "Failed to create Vector bioseq string for allele ID: ".$self->curr_allele_no_dre_id;
                return;
            }

            my $genbank_data = {};
            # allele ID may be dre or non-dre version depending on clone
            $genbank_data->{ 'allele_id' }          = $self->curr_allele_no_dre_id;
            $genbank_data->{ 'targeting_vector' }   = $vect_bioseq_string;

            # update the allele genbank data
            my $no_dre_db_id = $self->curr_allele_no_dre_genbank_db_id;
            DEBUG "Existing genbank data database ID: ".$no_dre_db_id." for Allele ID: ".$genbank_data->{ 'allele_id' };
            if ( $self->_update_genbank_files( $no_dre_db_id, $genbank_data ) == 1 ) {
                DEBUG "Updated no dre genbank DB ID :".$no_dre_db_id;
                # set flag so only update once per allele
                $self->curr_allele_no_dre_genbank_vector_checked ( 1 );
                $self->curr_allele_no_dre_genbank_exists ( 1 );

                $self->inc_counter_successful_no_dre_genbank_file_updates;
            }
            else {
                $self->inc_counter_failed_no_dre_genbank_file_updates;
            }
        }
        else {
            # do nothing
            return;
        }
    }
    else {
        # create appropriate genbank files
        my $vect_bioseq_string = $self->_create_vector_bioseq_string();

        unless ( $vect_bioseq_string ) {
            $self->inc_counter_failed_no_dre_genbank_file_inserts;
            # set flags so only attempt update once per allele
            $self->curr_allele_no_dre_genbank_vector_checked ( 1 );
            ERROR "Failed to create Vector bioseq string for allele ID: ".$self->curr_allele_no_dre_id;
            return;
        }

        my $genbank_data = {};
        # allele ID may be dre or non-dre version depending on clone
        $genbank_data->{ 'allele_id' }          = $self->curr_allele_no_dre_id;
        $genbank_data->{ 'targeting_vector' }   = $vect_bioseq_string;

        # insert the allele genbank data and return the database ID
        my $db_id =  $self->_insert_genbank_files( $genbank_data );
        $self->curr_allele_no_dre_genbank_db_id ( $db_id );

        if ( $self->curr_allele_no_dre_genbank_db_id ) {
            DEBUG "Inserted no dre genbank DB ID :".$self->curr_allele_no_dre_genbank_db_id;
            # set flags so only update once per allele
            $self->curr_allele_no_dre_genbank_vector_checked ( 1 );
            $self->curr_allele_no_dre_genbank_exists ( 1 );

            $self->inc_counter_successful_no_dre_genbank_file_inserts;
        }
        else {
            $self->inc_counter_failed_no_dre_genbank_file_inserts;
        }
    }

    return;
}

sub _insert_or_update_no_dre_allele_vector_and_clone_genbank_files {
    my ( $self ) = @_;

    unless ( defined $self->curr_allele_no_dre_id ) {
        ERROR "Attempt to create genbank files but missing no dre allele ID";
        return;
    }

    if ( $self->curr_allele_no_dre_genbank_exists && defined $self->curr_allele_no_dre_genbank_db_id ) {
        if ( $self->force_updates ) {
            DEBUG "Force updates: update genbank data both no-dre vector and clone";
            $self->_update_genbank_files_no_dre_vector_and_clone();
        }
        else {
            # if vector already updated we still need to update clone
            if ( $self->curr_allele_no_dre_genbank_vector_checked ) {

                # vector may already have been updated, safe to override with vector and clone
                $self->_update_genbank_files_no_dre_vector_and_clone();
            }
            else {
                # do nothing
                return;
            }
        }
    }
    else {
        # create appropriate genbank files
        my $vect_bioseq_string = $self->_create_vector_bioseq_string();
        my $escell_bioseq_string = $self->_create_allele_bioseq_string();

        unless ( $vect_bioseq_string && $escell_bioseq_string ) {
            $self->inc_counter_failed_no_dre_genbank_file_inserts;
            # set flags so only attempt update once per allele
            $self->curr_allele_no_dre_genbank_checked ( 1 );
            ERROR "Failed to create both Vector and Clone bioseq strings for allele ID: ".$self->curr_allele_no_dre_id;
            return;
        }

        my $genbank_data = {};
        # allele ID may be dre or non-dre version depending on clone
        $genbank_data->{ 'allele_id' }          = $self->curr_allele_no_dre_id;
        $genbank_data->{ 'targeting_vector' }   = $vect_bioseq_string;
        $genbank_data->{ 'escell_clone' }       = $escell_bioseq_string;

        # insert the allele genbank data and return the database ID
        my $db_id = $self->_insert_genbank_files( $genbank_data );
        $self->curr_allele_no_dre_genbank_db_id ( $db_id );

        if ( $self->curr_allele_no_dre_genbank_db_id ) {
            DEBUG "Inserted no dre genbank DB ID :".$self->curr_allele_no_dre_genbank_db_id;
            # set flags so only update once per allele
            $self->curr_allele_no_dre_genbank_checked ( 1 );
            $self->curr_allele_no_dre_genbank_exists ( 1 );

            $self->inc_counter_successful_no_dre_genbank_file_inserts;
        }
        else {
            $self->inc_counter_failed_no_dre_genbank_file_inserts;
        }
    }

    return;
}

sub _update_genbank_files_no_dre_vector_and_clone {
    my ( $self ) = @_;

    # create appropriate genbank files
    my $vect_bioseq_string = $self->_create_vector_bioseq_string();
    my $escell_bioseq_string = $self->_create_allele_bioseq_string();

    unless ( $vect_bioseq_string && $escell_bioseq_string ) {
        $self->inc_counter_failed_no_dre_genbank_file_updates;
        # set flag so only attempt update once per allele
        $self->curr_allele_no_dre_genbank_checked ( 1 );
        ERROR "Failed to create both Vector and Clone bioseq strings for allele ID: ".$self->curr_allele_no_dre_id;
        return;
    }

    my $genbank_data = {};
    # allele ID may be dre or non-dre version depending on clone
    $genbank_data->{ 'allele_id' }          = $self->curr_allele_no_dre_id;
    $genbank_data->{ 'targeting_vector' }   = $vect_bioseq_string;
    $genbank_data->{ 'escell_clone' }       = $escell_bioseq_string;

    # update the allele genbank data
    my $no_dre_db_id = $self->curr_allele_no_dre_genbank_db_id;
    DEBUG "Existing genbank data database ID: ".$no_dre_db_id." for Allele ID: ".$genbank_data->{ 'allele_id' };
    if ( $self->_update_genbank_files( $no_dre_db_id, $genbank_data ) ) {
        DEBUG "Updated no dre genbank DB ID :".$no_dre_db_id;
        # set flag so only update once per allele
        $self->curr_allele_no_dre_genbank_checked ( 1 );
        $self->curr_allele_no_dre_genbank_exists ( 1 );

        $self->inc_counter_successful_no_dre_genbank_file_updates;
    }
    else {
        $self->inc_counter_failed_no_dre_genbank_file_updates;
    }

    return;
}

sub _insert_genbank_files {
    my ( $self, $genbank_data ) = @_;

    DEBUG "Inserting genbank files for allele ID: ".$genbank_data->{ 'allele_id' };

    my $genbank_db_id = 0;
    my $tarmits_hash_result;
    try {
        $tarmits_hash_result = $self->tm->create_genbank_file( $genbank_data );

        DEBUG "Successfully inserted genbank files for allele ID: ".$genbank_data->{ 'allele_id' };

        # fetch genbank database id
        if ( defined $tarmits_hash_result && $tarmits_hash_result->{ 'allele_id' } > 0 ) {
            # check allele ID
            my $tarmits_allele_id = $tarmits_hash_result->{ 'allele_id' };
            DEBUG "Tarmits allele ID returned from insert: ".$tarmits_allele_id;

            $genbank_db_id = $tarmits_hash_result->{ 'id' };
            DEBUG "Returned genbank DB ID: ".$genbank_db_id;
        }
    }
    catch {
        WARN "Unable to insert genbank files for allele ID: ".$genbank_data->{ 'allele_id' };
        WARN "Exception: ".$_;
    };

    return $genbank_db_id;
}

sub _update_genbank_files {
    my ( $self, $db_id, $genbank_data ) = @_;

    DEBUG "Updating genbank files for allele ID: ".$genbank_data->{ 'allele_id' }." and database ID: ".$db_id;

    my $success = 0;
    my $tarmits_hash_result;
    try {
        $tarmits_hash_result = $self->tm->update_genbank_file( $db_id, $genbank_data );

        if ( defined $tarmits_hash_result && ( $tarmits_hash_result->{ 'id' } == $db_id ) ) {
            DEBUG "Successfully updated genbank files for allele ID: ".$genbank_data->{ 'allele_id' }." and database ID: ".$db_id;
            $success = 1;
        }
        else {
            ERROR "Returned database ID after genbank update does not match expected ID";
        }
    }
    catch {
        WARN "Unable to update genbank files for allele ID: ".$genbank_data->{ 'allele_id' };
        WARN "Exception: ".$_;
    };

    return $success;
}

sub _create_allele_bioseq_string {
    my ( $self ) = @_;

    unless ( defined $self->curr_es_cell_clone_id ) {
        ERROR "Attempt to update genbank files but missing es clone ID";
        return;
    }

    my $es_cell_lims2_well_id = $self->curr_clone->{ 'info' }->{ 'clone_well_id' };

    unless ( defined $es_cell_lims2_well_id && $es_cell_lims2_well_id > 0 ) {
        ERROR "Error constructing genbank data, lims2 es cell well id not set";
        return;
    }

    # create es cell genbank file as string using EngSeqParams
    my $escell_bioseq_string = try {
        my ( $escell_method, $escell_output_well_id, $escell_params ) = generate_well_eng_seq_params( $self->model, { 'well_id' => $es_cell_lims2_well_id } );
        my $escell_builder       = EngSeqBuilder->new;
        my $escell_bioseq        = $escell_builder->$escell_method( %{ $escell_params });
        # NB do not need to check for Dre application here because the generate_well_eng_seq_params does this for you
        # NB see EngSeqBuilder::SiteSpecificRecombination apply_dre( would send it the $escell_bioseq object and it would modify it );
        return _stringify_bioseq( $escell_bioseq );
    } catch {
        ERROR "FAILED creation of Allele BioSeq string for clone well ID: " . $es_cell_lims2_well_id;
        ERROR "Exception: ".$_;
        return;
    };

    return $escell_bioseq_string;
}

sub _create_vector_bioseq_string {
    my ( $self ) = @_;

    unless ( defined $self->curr_targeting_vector_id ) {
        ERROR "Attempt to create vector bioseq files but missing targeting vector well ID";
        return;
    }

    my $vector_lims2_well_id = $self->curr_targeting_vector->{ 'info' }->{ 'targeting_vector_well_id' };

    # validate we have both well ids required for genbank file creation
    unless ( defined $vector_lims2_well_id && $vector_lims2_well_id > 0 ) {
        ERROR "Error constructing genbank vector data, lims2 vector well id not set";
        return;
    }

    # create vector genbank file as string
    my $vect_bioseq_string = try {
        my ( $vect_method, $vect_output_well_id, $vect_params ) = generate_well_eng_seq_params( $self->model, { 'well_id' => $vector_lims2_well_id } );
        my $vect_builder         = EngSeqBuilder->new;
        my $vect_bioseq          = $vect_builder->$vect_method( %{ $vect_params });
        return _stringify_bioseq( $vect_bioseq );
    } catch {
        ERROR "FAILED creation of Vector BioSeq string for vector well ID: " . $vector_lims2_well_id;
        ERROR "Exception: ".$_;
        return;
    };

    return $vect_bioseq_string;
}

sub _stringify_bioseq {
    my $seq = shift;
    my $str = '';
    my $io  = Bio::SeqIO->new(
        -fh     => IO::String->new($str),
        -format => 'genbank',
    );
    $io->write_seq($seq);
    return $str;
}

sub _refactor_selected_clones {
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

            $results_refactored{ $current_gene_id }->{ 'gene_details' } = { %gene_details };

        }

        next RESULTS_LOOP if $is_error;

        my $curr_gene_hash = $results_refactored{ $current_gene_id };

        # if current design id doesn't exist in hash then add it
        my $current_design_id = $result->{ 'design_id' };

        unless ( exists $curr_gene_hash->{ 'designs' }->{ $current_design_id } ) {

            #skip if already im error list
            next RESULTS_LOOP if ( exists $self->failed_design_selects->{ $current_gene_id } );

            try {

                # fetch design object
                my $design = $self->model->c_retrieve_design( { 'id' => $result->{ 'design_id' }, 'species' => $self->species } );
                my $design_info = $design->info;

                # fetch hashref of oligos from design info
                my $design_oligos =$design_info->oligos;

                # build design details hash and add it into main hash
                my $design_details = $self->_select_lims2_design_details ( $result, $design_info, $design_oligos );
                $curr_gene_hash->{ 'designs' }->{ $current_design_id }->{ 'design_details' } = $design_details;

            } catch {
                $self->inc_counter_failed_no_dre_allele_selects;
                WARN "FAILED Design selection for gene: ".$result->{ 'design_gene_id' }." and design id: ". $result->{ 'design_id' };
                TRACE "Exception: ".$_;

                # add details to failed hash for report
                $self->failed_design_selects->{ $current_gene_id } = $current_design_id;

                # set flag to trigger next loop cycle (cannot next here as out of scope)
                $is_error = 1;
            };
        }

        next RESULTS_LOOP if $is_error;

        my $curr_design_hash = $curr_gene_hash->{ 'designs' }->{ $current_design_id };

        # if vector info doesn't exist in allele hash then add it
        my $targeting_vector_id = $result->{ 'targeting_vector_plate_name' }.'_'.$result->{ 'targeting_vector_well_name' };
        my $intermediate_vector_id = $result->{ 'int_plate_name' }.'_'.$result->{ 'int_well_name' };

        unless ( exists $curr_design_hash->{ 'targeting_vectors' }->{ $targeting_vector_id } ) {
            my $targ_vector_details = $self->_select_lims2_targeting_vector_details ( $result, $targeting_vector_id, $intermediate_vector_id );
            $curr_design_hash->{ 'targeting_vectors' }->{ $targeting_vector_id } = $targ_vector_details;
        }

        next RESULTS_LOOP if $is_error;

        my $curr_targ_vector_hash = $curr_design_hash->{ 'targeting_vectors' }->{ $targeting_vector_id };

        # create clone id
        my $es_clone_id = ( $result->{ 'clone_plate_name' } ) . '_' . ( $result->{ 'clone_well_name' } );

        # if the clone does not already exist in the main hash then add it in
        unless ( exists $curr_targ_vector_hash->{ 'clones' }->{ $es_clone_id } ) {
            my $new_clone = $self->_select_lims2_es_clone_details ( $result, $es_clone_id, $targeting_vector_id );
            $curr_targ_vector_hash->{ 'clones' }->{ $es_clone_id } = $new_clone;

            $self->_set_allele_symbol_superscript( $curr_targ_vector_hash, $es_clone_id );

            $self->_increment_vector_counters( $result->{ 'ep_recombinase' }, $es_clone_id, $curr_targ_vector_hash );
        }
    }

    return \%results_refactored;
}

sub _set_allele_symbol_superscript {
    my ( $self, $curr_targ_vector_hash, $es_clone_id ) = @_;

    my $clone_details = $curr_targ_vector_hash->{ 'clones' }->{ $es_clone_id }->{ 'es_cell_details' };

    my $prefix = 'tm1';
    # adjust prefix depending on cassette type
    if ( $curr_targ_vector_hash->{ 'cassette' } =~ m/neo/i ) {
        $prefix = 'tm2';
    }

    my $allele_ss = "";

    # Check if Neo or Puro cassette to set tm1 or tm2
    if ( $clone_details->{ 'ep_recombinase' } eq 'Dre' ) {
        $allele_ss = $prefix . '.1(EGFP_CreERT2)Wtsi'; # for Dre
    }
    else {
        $allele_ss = $prefix . '(EGFP_CreERT2)Wtsi'; # for non Dre
    }

    # DEBUG "Setting mgi_allele_symbol_superscript to $allele_ss";

    $clone_details->{ 'mgi_allele_symbol_superscript' } = $allele_ss;

    return;
}

# count accepted clones for targeting vector for use when deciding whether to insert alleles
sub _increment_vector_counters {
    my ( $self, $ep_recombinase, $es_clone_id, $curr_targ_vector_hash ) = @_;

    if ( $ep_recombinase eq 'Dre' ) {
        $curr_targ_vector_hash->{ 'count_clones_dre' } += 1;
    }
    else {
        $curr_targ_vector_hash->{ 'count_clones_no_dre' } += 1;
    }

    return;
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

    #   Floxed Exon                                     -> from designs.target_transcript
    try {
        if ( defined $design_info->first_floxed_exon ) {
            $new_mutation_details{ 'floxed_start_exon' } = $design_info->first_floxed_exon->stable_id;
        }
        if ( defined $design_info->last_floxed_exon ) {
            $new_mutation_details{ 'floxed_end_exon' }   = $design_info->last_floxed_exon->stable_id;
        }
    } catch {
        WARN "FAILED to fetch floxed exons for gene: ".$design_details{ 'info' }->{ 'design_gene_symbol' }." design id: ". $design_details{ 'project_design_id' };
        WARN "Exception: ".$_;
    };

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

    my %targ_vector_details;

    $targ_vector_details{ 'count_clones_no_dre'}             = 0;
    $targ_vector_details{ 'count_clones_dre'}                = 0;

    $targ_vector_details{ 'info' }->{ 'targeting_vector_plate_id' }   = $result->{ 'targeting_vector_plate_id' };
    $targ_vector_details{ 'info' }->{ 'targeting_vector_plate_name' } = $result->{ 'targeting_vector_plate_name' };
    $targ_vector_details{ 'info' }->{ 'targeting_vector_well_id' }    = $result->{ 'targeting_vector_well_id' };
    $targ_vector_details{ 'info' }->{ 'targeting_vector_well_name' }  = $result->{ 'targeting_vector_well_name' };
    $targ_vector_details{ 'info' }->{ 'vector_cassette_promotor' }    = $result->{ 'vector_cassette_promotor' };
    #$targ_vector_details{ '' }    = $result->{ '' };

    my %new_targeting_vectors;
    # Targeting Vectors (multiple rows)
    # Pipeline             - e.g. EUCOMMToolsCre          -> hardcoded
    $new_targeting_vectors{ 'pipeline_name' }           = 'EUCOMMToolsCre';
    $new_targeting_vectors{ 'pipeline_id' }             = 8;

    # IKMC project ID      - e.g. 125168                  -> create this from pipeline and allele id if not found in LIMS2 e.g. EUCOMMToolsCre_23456
    $new_targeting_vectors{ 'ikmc_project_id' }         = $result->{ 'htgt_project_id' };

    # Targeting vector     - e.g. ETPG0008_Z_3_B03        -> from summaries.final_pick_plate_name and _well_name
    $new_targeting_vectors{ 'targeting_vector' }        = $targeting_vector_id;

    # Intermediate vector  - e.g. ETPCS0008_A_1_C03       -> from summaries.int_plate_name and _well_name
    $new_targeting_vectors{ 'intermediate_vector' }     = $intermediate_vector_id;

    # Report to public     - e.g. boolean, tick or cross  -> set to true
    $new_targeting_vectors{ 'report_to_public' }        = 1;

    $targ_vector_details{ 'targeting_vector_details' }  = { %new_targeting_vectors };

    #   Cassette          - e.g. pL1L2_GT0_LF2A          -> summaries.final_pick_cassette_name
    $targ_vector_details{ 'cassette' }                  = $result->{ 'vector_cassette_name' };

    #   Cassette Type     - e.g. Promotorless            -> cassettes.promoter
    if ( $result->{ 'vector_cassette_promotor' } ) {
      $targ_vector_details{ 'cassette_type' }           = 'Promotor Driven';
    }
    else {
      $targ_vector_details{ 'cassette_type' }           = 'Promotorless';
    }

    #   Backbone          - e.g. L3L4_pD223_DTA_T_spec   -> summaries.final_pick_backbone_name
    $targ_vector_details{ 'backbone' }                  = $result->{ 'vector_backbone_name' };

    return \%targ_vector_details;
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
    $es_cell_details{ 'pipeline_name' }                 = 'EUCOMMToolsCre';
    $es_cell_details{ 'pipeline_id' }                   = 8;

    #   ES Cell                   - e.g. CEPD0026_4_B10          -> from summaries.ep_pick_plate_name and _well_name
    $es_cell_details{ 'es_clone_id' }                   = $es_clone_id;

    #   Targeting Vector          - e.g. ETPG0008_Z_3_B03        -> from summaries.final_pick_plate_name and _well_name
    $es_cell_details{ 'targeting_vector' }              = $targeting_vector_id;

    #   MGI Allele ID             - e.g. empty...                -> TODO: add MGI Allele ID
    $es_cell_details{ 'mgi_allele_id' }                 = 'tbc';

    #   Parental Cell Line        - e.g. JM8.N4                  -> from summaries.ep_first_cell_line_name
    $es_cell_details{ 'parental_cell_line' }            = $result->{ 'cell_line' };

    #   IKMC Project ID           - e.g. 125168                  -> create this from pipeline and allele id if not found in LIMS2 e.g. EUCOMMToolsCre_23456
    $es_cell_details{ 'ikmc_project_id' }               = $result->{ 'htgt_project_id' };

    # electroporation Recombinase ID
    $es_cell_details{ 'ep_recombinase' }                = $result->{ 'ep_recombinase' };

    $new_clone->{ 'es_cell_details' }                   = { %es_cell_details };

    return;
}

sub _get_es_clone_qc_metric_details {
    my ( $self, $new_clone ) = @_;

    my %qc_metrics = ();
    #   QC Metrics
    #     Production Centre Screen
    # TODO: fill in QC metrics
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
sub _run_select_query {
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
sub _sql_select_st_es_clones {
    my ( $self, $sponsor_id ) = @_;

    my $species_id     = $self->species;
    my $mgi_gene_id    = $self->gene_id;

my $sql_query_top =  <<"SQL_TOP_END";
WITH project_requests AS (
SELECT p.id AS project_id,
 p.htgt_project_id,
 ps.sponsor_id,
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
INNER JOIN targeting_profile_alleles pa ON pa.targeting_profile_id = p.targeting_profile_id
INNER JOIN cassette_function cf ON cf.id = pa.cassette_function
JOIN project_sponsors ps ON ps.project_id = p.id
WHERE ps.sponsor_id   = '$sponsor_id'
AND p.targeting_type = 'single_targeted'
AND p.species_id     = '$species_id'
SQL_TOP_END

my $sql_query_optional =  <<"SQL_OPTIONAL_END";
AND p.gene_id        = '$mgi_gene_id'
SQL_OPTIONAL_END

my $sql_query_btm =  <<"SQL_BTM_END";
)
SELECT pr.project_id
, pr.htgt_project_id
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
, s.ep_well_recombinase_id AS ep_recombinase
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
, pr.htgt_project_id
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
, s.ep_well_recombinase_id
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
        $sql_query = $sql_query_top.$sql_query_optional.$sql_query_btm;
    }
    else {
        $sql_query = $sql_query_top.$sql_query_btm;
    }

    return $sql_query;
}


1;

__END__