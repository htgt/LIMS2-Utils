package LIMS2::Util::TestDatabase;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::TestDatabase::VERSION = '0.080';
}
## use critic


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
well_dna_status              => 'WellDnaStatus',
well_dna_quality             => 'WellDnaQuality',
well_recombineering_results  => 'WellRecombineeringResults',
well_qc_sequencing_result    => 'WellQcSequencingResult',
process_bac                  => 'ProcessBac',
process_recombinase          => 'ProcessRecombinase',
process_output_well          => 'ProcessOutputWell',
process_input_well           => 'ProcessInputWell',
process_design               => 'ProcessDesign',
process_crispr               => 'ProcessCrispr',
process_cassette             => 'ProcessCassette',
process_backbone             => 'ProcessBackbone',
process_cell_line            => 'ProcessCellLine',
processes                    => 'Process',
genotyping_primers           => 'GenotypingPrimer',
design_comments              => 'DesignComment',
design_oligo_loci            => 'DesignOligoLocus',
design_oligos                => 'DesignOligo',
gene_design                  => 'GeneDesign',
designs                      => 'Design',
bac_clone_loci               => 'BacCloneLocus',
bac_clones                   => 'BacClone',
crispr_off_targets           => 'CrisprOffTargets',
crispr_off_target_summaries  => 'CrisprOffTargetSummaries',
crispr_loci                  => 'CrisprLocus',
crisprs                      => 'Crispr',
crispr_pairs                 => 'CrisprPair',
crispr_designs               => 'CrisprDesign',
crispr_plate_appends         => 'CrisprPlateAppends',
crispr_plate_appends_type    => 'CrisprPlateAppendsType',
crispr_es_qc_runs            => 'CrisprEsQcRun',
crispr_es_qc_wells           => 'CrisprEsQcWell',
qc_alignment_regions         => 'QcAlignmentRegion',
qc_alignments                => 'QcAlignment',
qc_test_results              => 'QcTestResult',
qc_run_seq_project           => 'QcRunSeqProject',
qc_run_seq_well_qc_seq_read  => 'QcRunSeqWellQcSeqRead',
qc_seq_reads                 => 'QcSeqRead',
qc_run_seq_wells             => 'QcRunSeqWell',
qc_seq_projects              => 'QcSeqProject',
qc_runs                      => 'QcRun',
qc_template_well_cassette    => 'QcTemplateWellCassette',
qc_template_well_backbone    => 'QcTemplateWellBackbone',
qc_template_well_recombinase => 'QcTemplateWellRecombinase',
qc_template_wells            => 'QcTemplateWell',
qc_templates                 => 'QcTemplate',
qc_eng_seqs                  => 'QcEngSeq',
well_accepted_override       => 'WellAcceptedOverride',
well_comments                => 'WellComment',
well_chromosome_fail         => 'WellChromosomeFail',
well_targeting_pass          => 'WellTargetingPass',
well_targeting_puro_pass     => 'WellTargetingPuroPass',
well_genotyping_results      => 'WellGenotypingResult',
well_recombineering_results  => 'WellRecombineeringResult',
well_colony_counts           => 'WellColonyCount',
well_primer_bands            => 'WellPrimerBand',
well_lab_number              => 'wellLabNumber',
wells                        => 'Well',
plate_comments               => 'PlateComment',
plates                       => 'Plate',
projects                     => 'Project',
user_preferences             => 'UserPreference',
user_role                    => 'UserRole',
users                        => 'User',
summaries                    => 'Summary',
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
