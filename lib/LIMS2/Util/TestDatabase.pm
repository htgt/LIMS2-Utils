package LIMS2::Util::TestDatabase;

use warnings FATAL => 'all';

=head1 NAME

LIMS2::Util::TestDatabase

=head1 DESCRIPTION

Useful tasks to carry out on test database

=cut

use Moose;
use LIMS2::Model;
use LIMS2::Test qw( wipe_test_data load_static_files load_dynamic_files mech );
use Config::Any;
use LIMS2::Model::DBConnect;
use Path::Class;
use File::Temp;
use IPC::Run 'run';
use Const::Fast;

use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

const my $HOST => 'htgt-db';
const my $PORT => 5441;

has db_name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has model => (
    is         => 'rw',
    isa        => 'LIMS2::Model',
    lazy_build => 1,
);

has dir => (
    is       => 'rw',
    isa      => 'Path::Class::Dir',
    coerce   => 1,
    trigger  => \&_init_output_dir
);

# create directory if it does not exist
sub _init_output_dir {
    my ( $self, $dir ) = @_;

    $dir->mkpath();
    return;
}

sub _build_model {
    my $self = shift;

    local $ENV{ LIMS2_DB } = $self->db_name;
    # connect as tests user to make sure we are writing to a test database
    my $schema = LIMS2::Model::DBConnect->connect( 'LIMS2_DB', 'tests' );
    my $model = LIMS2::Model->new( user => 'tests', schema => $schema );

    return $model;
}

has test_mech => (
    is         => 'ro',
    isa        => 'Test::WWW::Mechanize::Catalyst',
    lazy_build => 1,
);

sub _build_test_mech {
    my $self = shift;

    return mech( $self->model );
}

has db_config => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
);

sub _build_db_config {
    my $self = shift;

    die( 'LIMS2_DBCONNECT_CONFIG env variable not set' )
        unless exists $ENV{LIMS2_DBCONNECT_CONFIG};

    my $config_file_name = $ENV{LIMS2_DBCONNECT_CONFIG};
    my $config = Config::Any->load_files( { files => [$config_file_name], use_ext => 1, flatten_to_hash => 1 } );

    my $config_data = $config->{ $config_file_name };

    unless( exists $config_data->{ $self->db_name } ) {
        die( "db_connect config file does not hold data for db: " . $self->db_name );
    }

    return $config_data->{ $self->db_name };
}

const my %TABLE_NAMES => (
amplicons                                   =>  'Amplicon',
amplicon_loci                               =>  'AmpliconLoci',
amplicon_types                              =>  'AmpliconType',
assemblies                                  =>  'Assembly',
bac_clones                                  =>  'BacClone',
bac_clone_loci                              =>  'BacCloneLocus',
bac_libraries                               =>  'BacLibrary',
backbones                                   =>  'Backbone',
barcode_events                              =>  'BarcodeEvent',
barcode_states                              =>  'BarcodeState',
cached_reports                              =>  'CachedReport',
cassettes                                   =>  'Cassette',
cassette_function                           =>  'CassetteFunction',
cell_lines                                  =>  'CellLine',
cell_line_external                          =>  'CellLineExternal',
cell_line_internal                          =>  'CellLineInternal',
cell_line_repositories                      =>  'CellLineRepository',
chromosomes                                 =>  'Chromosome',
colony_count_types                          =>  'ColonyCountType',
crisprs                                     =>  'Crispr',
crispr_damage_types                         =>  'CrisprDamageType',
crispr_es_qc_runs                           =>  'CrisprEsQcRuns',
crispr_es_qc_wells                          =>  'CrisprEsQcWell',
crispr_groups                               =>  'CrisprGroup',
crispr_group_crisprs                        =>  'CrisprGroupCrispr',
crispr_loci_types                           =>  'CrisprLociType',
crispr_loci                                 =>  'CrisprLocus',
crispr_off_target_summaries                 =>  'CrisprOffTargetSummary',
crispr_off_targets                          =>  'CrisprOffTargets',
crispr_pairs                                =>  'CrisprPair',
crispr_plate_appends                        =>  'CrisprPlateAppend',
crispr_plate_appends_type                   =>  'CrisprPlateAppendsType',
crispr_primers                              =>  'CrisprPrimer',
crispr_primer_types                         =>  'CrisprPrimerType',
crispr_primers_loci                         =>  'CrisprPrimersLoci',
crispr_storage                              =>  'CrisprStorage',
crispr_tracker_rnas                         =>  'CrisprTrackerRna',
crispr_validation                           =>  'CrisprValidation',
crispresso_submissions                      =>  'CrispressoSubmission',
designs                                     =>  'Design',
design_amplicons                            =>  'DesignAmplicon',
design_append_aliases                       =>  'DesignAppendAlias',
design_attempts                             =>  'DesignAttempt',
design_comments                             =>  'DesignComment',
design_comment_categories                   =>  'DesignCommentCategory',
design_oligos                               =>  'DesignOligo',
design_oligo_appends                        =>  'DesignOligoAppend',
design_oligo_loci                           =>  'DesignOligoLocus',
design_oligo_types                          =>  'DesignOligoType',
design_targets                              =>  'DesignTarget',
design_types                                =>  'DesignType',
dna_templates                               =>  'DnaTemplate',
experiments                                 =>  'Experiment',
fp_picking_list                             =>  'FpPickingList',
fp_picking_list_well_barcode                =>  'FpPickingListWellBarcode',
gene_design                                 =>  'GeneDesign',
gene_types                                  =>  'GeneType',
genotyping_primers                          =>  'GenotypingPrimer',
genotyping_primer_types                     =>  'GenotypingPrimerType',
genotyping_primers_loci                     =>  'GenotypingPrimersLoci',
genotyping_result_types                     =>  'GenotypingResultType',
guided_types                                =>  'GuidedType',
hdr_template                                =>  'HdrTemplate',
indel_histogram                             =>  'IndelHistogram',
lab_heads                                   =>  'LabHead',
messages                                    =>  'Message',
miseq_alleles_frequency                     =>  'MiseqAllelesFrequency',
miseq_classification                        =>  'MiseqClassification',
miseq_design_presets                        =>  'MiseqDesignPreset',
miseq_experiment                            =>  'MiseqExperiment',
miseq_plate                                 =>  'MiseqPlate',
miseq_primer_presets                        =>  'MiseqPrimerPreset',
miseq_projects                              =>  'MiseqProject',
miseq_project_well                          =>  'MiseqProjectWell',
miseq_project_well_exp                      =>  'MiseqProjectWellExp',
miseq_status                                =>  'MiseqStatus',
miseq_well_experiment                       =>  'MiseqWellExperiment',
mutation_design_types                       =>  'MutationDesignType',
nucleases                                   =>  'Nuclease',
old_projects                                =>  'OldProject',
old_project_alleles                         =>  'OldProjectAllele',
pipelines                                   =>  'Pipeline',
plates                                      =>  'Plate',
plate_comments                              =>  'PlateComment',
plate_types                                 =>  'PlateType',
primer_band_types                           =>  'PrimerBandType',
priorities                                  =>  'Priority',
processes                                   =>  'Process',
process_bac                                 =>  'ProcessBac',
process_backbone                            =>  'ProcessBackbone',
process_cassette                            =>  'ProcessCassette',
process_cell_line                           =>  'ProcessCellLine',
process_crispr                              =>  'ProcessCrispr',
process_crispr_group                        =>  'ProcessCrisprGroup',
process_crispr_pair                         =>  'ProcessCrisprPair',
process_crispr_tracker_rna                  =>  'ProcessCrisprTrackerRna',
process_design                              =>  'ProcessDesign',
process_global_arm_shortening_design        =>  'ProcessGlobalArmShorteningDesign',
process_guided_type                         =>  'ProcessGuidedType',
process_input_well                          =>  'ProcessInputWell',
process_nuclease                            =>  'ProcessNuclease',
process_output_well                         =>  'ProcessOutputWell',
process_parameters                          =>  'ProcessParameter',
process_recombinase                         =>  'ProcessRecombinase',
process_types                               =>  'ProcessType',
programmes                                  =>  'Programme',
projects                                    =>  'Project',
project_experiment                          =>  'ProjectExperiment',
project_recovery_class                      =>  'ProjectRecoveryClass',
project_sponsors                            =>  'ProjectSponsor',
qc_alignments                               =>  'QcAlignment',
qc_alignment_regions                        =>  'QcAlignmentRegion',
qc_eng_seqs                                 =>  'QcEngSeq',
qc_runs                                     =>  'QcRun',
qc_run_seq_project                          =>  'QcRunSeqProject',
qc_run_seq_wells                            =>  'QcRunSeqWell',
qc_run_seq_well_qc_seq_read                 =>  'QcRunSeqWellQcSeqRead',
qc_seq_projects                             =>  'QcSeqProject',
qc_seq_reads                                =>  'QcSeqRead',
qc_templates                                =>  'QcTemplate',
qc_template_wells                           =>  'QcTemplateWell',
qc_template_well_backbone                   =>  'QcTemplateWellBackbone',
qc_template_well_cassette                   =>  'QcTemplateWellCassette',
qc_template_well_crispr_primers             =>  'QcTemplateWellCrisprPrimer',
qc_template_well_genotyping_primers         =>  'QcTemplateWellGenotypingPrimer',
qc_template_well_recombinase                =>  'QcTemplateWellRecombinase',
qc_test_results                             =>  'QcTestResult',
recombinases                                =>  'Recombinase',
recombineering_result_types                 =>  'RecombineeringResultType',
requesters                                  =>  'Requester',
roles                                       =>  'Role',
schema_versions                             =>  'SchemaVersion',
sequencing_primer_types                     =>  'SequencingPrimerType',
sequencing_projects                         =>  'SequencingProject',
sequencing_project_backups                  =>  'SequencingProjectBackup',
sequencing_project_primers                  =>  'SequencingProjectPrimer',
sequencing_project_templates                =>  'SequencingProjectTemplate',
species                                     =>  'Species',
species_default_assembly                    =>  'SpeciesDefaultAssembly',
sponsors                                    =>  'Sponsor',
strategies                                  =>  'Strategy',
summaries                                   =>  'Summary',
targeting_profiles                          =>  'TargetingProfile',
targeting_profile_alleles                   =>  'TargetingProfileAllele',
trivial_offset                              =>  'TrivialOffset',
users                                       =>  'User',
user_preferences                            =>  'UserPreference',
user_role                                   =>  'UserRole',
wells                                       =>  'Well',
well_accepted_override                      =>  'WellAcceptedOverride',
well_assembly_qc                            =>  'WellAssemblyQc',
well_chromosome_fail                        =>  'WellChromosomeFail',
well_colony_counts                          =>  'WellColonyCount',
well_comments                               =>  'WellComment',
well_dna_quality                            =>  'WellDnaQuality',
well_dna_status                             =>  'WellDnaStatus',
well_genotyping_results                     =>  'WellGenotypingResult',
well_het_status                             =>  'WellHetStatus',
well_lab_number                             =>  'WellLabNumber',
well_primer_bands                           =>  'WellPrimerBand',
well_qc_sequencing_result                   =>  'WellQcSequencingResult',
well_recombineering_results                 =>  'WellRecombineeringResult',
well_t7                                     =>  'WellT7',
well_targeting_neo_pass                     =>  'WellTargetingNeoPass',
well_targeting_pass                         =>  'WellTargetingPass',
well_targeting_puro_pass                    =>  'WellTargetingPuroPass'                      ,
);

=head2 setup_clean_database

Wipe the test database and make sure it has the current reference data

=cut
sub setup_clean_database {
    my ( $self ) = @_;

    $self->log->info( 'Wiping data from database: ' . $self->db_name );
    wipe_test_data( $self->model, $self->test_mech );
    $self->log->info( 'Loading reference data into: ' . $self->db_name );
    load_static_files( $self->model, $self->test_mech );

    return;
}

=head2 class_specific_fixture_data

Load up a fresh set of class specific fixture data

=cut
sub class_specific_fixture_data {
    my ( $self, $class_name ) = @_;

    $self->log->info( 'Wiping data from database: ' . $self->db_name );
    wipe_test_data( $self->model, $self->test_mech );
    $self->log->info( 'Loading reference data into: ' . $self->db_name );
    load_static_files( $self->model, $self->test_mech );

    my $class_dir;
    ( $class_dir = $class_name ) =~ s/::/\//g;
    $class_dir =~ s/LIMS2\//LIMS2\/t\//;
    my $fixture_dir= '/static/test/fixtures/' . $class_dir;
    $self->log->info( "Loading class fixture data: $fixture_dir" );
    load_dynamic_files( $self->model, $self->test_mech, $fixture_dir );

    return;
}

=head2 dump_fixture_data

Once fixture data has been loaded into database this
will dump out the data into csv files, one per table.

=cut
sub dump_fixture_data {
    my ( $self ) = @_;

    $self->log->info( 'Dumping fixture data from ' . $self->db_name );

    my $password = $self->db_config->{roles}{tests}{password};
    my $user = $self->db_config->{roles}{tests}{user};
    local $ENV{ PGPASSWORD } = $password;

    my $command_fh = $self->create_psql_command_file;

    my @psql_command = (
        'psql',
        '--host',   $HOST,
        '--port',   $PORT,
        '--dbname', lc( $self->db_name ),
        '-U',       $user,
        '-f',       $command_fh,
    );

    $self->log->debug( 'Running command: ' . join(' ', @psql_command ) );

    my ( $out, $err ) = ( "", "" );
    run( \@psql_command,
        '<', \undef,
        '>', \$out,
        '2>', \$err,
    ) or die( "Failed to run psql command: $err" );

    $self->log->error( "Error running psql command: $err" ) if $err;

    $self->remove_empty_records;

    return;
}

=head2 create_psql_command_file

Create file with the \copy psql command that will dump the
required database tables as csv files.

=cut
sub create_psql_command_file {
    my ( $self  ) = @_;

    my $dirname = $self->dir->stringify;
    my $command_fh = File::Temp->new( DIR => $dirname );

    for my $table_name ( keys %TABLE_NAMES ) {
        my $resultset_name = $TABLE_NAMES{ $table_name };
        my $filename = $dirname . '/' . $resultset_name . '.csv';
        $command_fh->print( "\\copy $table_name to '$filename' ( format csv, header 1 );\n" );
    }

    return $command_fh;
}

=head2 remove_empty_records

Remove csv files that have no records ( just a header line )

=cut
sub remove_empty_records {
    my ( $self ) = @_;

    for my $file ( $self->dir->children ) {
        my ( $count, $err ) = ( "", "" );
        run( [ 'wc', '-l' ],
            '<', $file->stringify,
            '>', \$count,
            '2>', \$err,
        ) or die( "Failed to run psql command: $err" );
        chomp( $count );

        if ( $count <= 1 ) {
            $self->log->debug( "Removing empty file $file " );
            $file->remove;
        }
    }

    return;
}


__PACKAGE__->meta->make_immutable;

1;

__END__
