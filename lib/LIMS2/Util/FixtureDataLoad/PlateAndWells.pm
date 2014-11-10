package LIMS2::Util::FixtureDataLoad::PlateAndWells;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::FixtureDataLoad::PlateAndWells::VERSION = '0.050';
}
## use critic


use warnings FATAL => 'all';

=head1 NAME

LIMS2::Util::FixtureDataLoad::PlateAndWells

=head1 DESCRIPTION

Load Plate and Well fixture data.

=cut

use Moose;
use Try::Tiny;
use Scalar::Util qw( blessed );
use LIMS2::Util::FixtureDataLoad::Designs;
use LIMS2::Util::FixtureDataLoad::Crisprs;
use LIMS2::Util::FixtureDataLoad::Bacs;
use namespace::autoclean;

extends qw( LIMS2::Util::FixtureDataLoad );

has total_attempted => (
    is                => 'ro',
    isa               => 'Num',
    traits            => [ 'Counter' ],
    default           => 0,
    handles           => {
        inc_attempted => 'inc',
    }
);

has total_unloaded => (
    is               => 'ro',
    isa              => 'Num',
    traits           => [ 'Counter' ],
    default          => 0,
    handles          => {
        inc_unloaded => 'inc',
    }
);

has design_loader => (
    is         => 'ro',
    isa        => 'LIMS2::Util::FixtureDataLoad::Designs',
    lazy_build => 1,
    handles    => [ 'retrieve_or_create_design' ],
);

sub _build_design_loader {
    my $self = shift;

    my $design_loader = LIMS2::Util::FixtureDataLoad::Designs->new(
        source_model => $self->source_model,
        dest_model   => $self->dest_model,
    );

    return $design_loader;
}

has crispr_loader => (
    is         => 'ro',
    isa        => 'LIMS2::Util::FixtureDataLoad::Crisprs',
    lazy_build => 1,
    handles    => [ 'retrieve_or_create_crispr' ],
);

sub _build_crispr_loader {
    my $self = shift;

    my $crispr_loader = LIMS2::Util::FixtureDataLoad::Crisprs->new(
        source_model => $self->source_model,
        dest_model   => $self->dest_model,
    );

    return $crispr_loader;
}

has bac_loader => (
    is         => 'ro',
    isa        => 'LIMS2::Util::FixtureDataLoad::Bacs',
    lazy_build => 1,
    handles    => [ 'retrieve_or_create_bac' ],
);

sub _build_bac_loader {
    my $self = shift;

    my $bac_loader = LIMS2::Util::FixtureDataLoad::Bacs->new(
        source_model => $self->source_model,
        dest_model   => $self->dest_model,
    );

    return $bac_loader;
}

has process_aux_data_dispatches => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
);

sub _build_process_aux_data_dispatches {
    my $self = shift;

    my %process_aux_data_dispatches = (
        'create_di'              => sub { $self->create_process_aux_data_create_di( @_ ) },
        'create_crispr'          => sub { $self->create_process_aux_data_create_crispr( @_ ) },
        'int_recom'              => sub { $self->create_process_aux_data_int_recom( @_ ) },
        '2w_gateway'             => sub { $self->create_process_aux_data_2w_gateway( @_ ) },
        '3w_gateway'             => sub { $self->create_process_aux_data_3w_gateway( @_ ) },
        'legacy_gateway'         => sub { $self->create_process_aux_data_legacy_gateway( @_ ) },
        'final_pick'             => sub { $self->create_process_aux_data_final_pick( @_ ) },
        'recombinase'            => sub { $self->create_process_aux_data_recombinase( @_ ) },
        'cre_bac_recom'          => sub { $self->create_process_aux_data_cre_bac_recom( @_ ) },
        'rearray'                => sub { $self->create_process_aux_data_rearray( @_ ) },
        'dna_prep'               => sub { $self->create_process_aux_data_dna_prep( @_ ) },
        'clone_pick'             => sub { $self->create_process_aux_data_clone_pick( @_ ) },
        'clone_pool'             => sub { $self->create_process_aux_data_clone_pool( @_ ) },
        'first_electroporation'  => sub { $self->create_process_aux_data_first_electroporation( @_ ) },
        'second_electroporation' => sub { $self->create_process_aux_data_second_electroporation( @_ ) },
        'freeze'                 => sub { $self->create_process_aux_data_freeze( @_ ) },
        'xep_pool'               => sub { $self->create_process_aux_data_xep_pool( @_ ) },
        'dist_qc'                => sub { $self->create_process_aux_data_dist_qc( @_ ) },
    );

    return \%process_aux_data_dispatches;
}

sub copy_plate_to_destination_db {
    my ( $self, $plate_name, $well_name ) = @_;
    Log::Log4perl::NDC->push( $plate_name );

    my $source_plate = $self->source_model->schema->resultset('Plate')->find(
        { name     => $plate_name },
        { prefetch => 'wells' }
    );
    $self->log->logdie( "Can not find plate in source database" ) unless $source_plate;

    $self->log->info( "Copying plate" );

    my $plate_dest = try {
        $self->retrieve_or_create_plate( $source_plate );
    }
    catch {
        $self->log->error('Unable to retrieve or create plate ' . $_);
        undef;
    };

    return unless $plate_dest;

    for my $curr_well ( $source_plate->wells ) {
        # match the well name input if supplied
        next if $well_name && $well_name ne $curr_well->name;
        $self->inc_attempted;

        try {
            $self->copy_well_to_destination_db( $plate_dest, $curr_well );
            $self->inc_unloaded;
        }
        catch {
            $self->log->error( $_ );
        };
    }

    $self->log->info( 'Unloaded: ' . $self->total_unloaded . ' of ' . $self->total_attempted . ' wells' );
    Log::Log4perl::NDC->remove;
    return;
}

sub copy_well_to_destination_db {
    my ( $self, $plate_dest, $well_orig ) = @_;
    Log::Log4perl::NDC->remove();
    Log::Log4perl::NDC->push( $plate_dest->name . '_' . $well_orig->name );
    $self->log->info( "Copying well" );

    my $well_dest = $self->retrieve_destination_well( $plate_dest, $well_orig );
    return if $well_dest;

    # Find the parent wells (if any, typically 1 e.g. XEP has many), returns ArrayRef
    my $parent_wells = $self->find_parent_wells( $well_orig );

    for my $parent_well ( @{ $parent_wells } ) {
        # recursively set up parent wells first if they don't exist
        $self->copy_well_to_destination_db(
            $self->retrieve_or_create_plate( $parent_well->plate ),
            $parent_well
        );
    }
    Log::Log4perl::NDC->remove();
    Log::Log4perl::NDC->push( $plate_dest->name . '_' . $well_orig->name );

    # fetch the process and plate types
    my $well_orig_process_type = $well_orig->output_processes->first->type_id;
    my $well_orig_plate_type   = $well_orig->plate->type_id;

    # construct well data for creation of well and processes
    my $well_data = $self->build_well_data( $well_orig, $parent_wells, $well_orig_process_type );

    # If this is a create_di process, ensure the design exists before attempting to create the well
    if ( $well_orig_process_type eq 'create_di' ) {
        my $design_id = $well_data->{process_data}{design_id};
        $self->retrieve_or_create_design( $design_id );

        my @bac_names = map{ $_->{bac_name} } @{ $well_data->{process_data}{bacs} };
        $self->retrieve_or_create_bac( $_ ) for @bac_names;
    }
    elsif ( $well_orig_process_type eq 'create_crispr' ) {
        my $crispr_id = $well_data->{process_data}{crispr_id};
        $self->retrieve_or_create_crispr( $crispr_id );
    }

    $self->log->info( "Process $well_orig_process_type, plate type $well_orig_plate_type");
    $well_orig = $self->create_well_in_destination_db( $well_orig, $well_data );

    return $well_orig;
}

sub retrieve_or_create_plate {
    my ( $self, $plate ) = @_;
    Log::Log4perl::NDC->remove();
    Log::Log4perl::NDC->push( $plate->name );
    return $self->retrieve_destination_plate( $plate ) || $self->create_destination_plate( $plate, $self->build_plate_data( $plate ) );
}

sub retrieve_destination_plate {
    my ( $self, $source_plate ) = @_;
    $self->log->debug( 'Retrieving plate' );

    my $plate_dest = $self->dest_model->schema->resultset('Plate')->find(
        { name     => $source_plate->name },
        { prefetch => 'wells' }
    );

    $self->log->debug( 'Plate already exists in the destination DB' )
        if $plate_dest;

    return $plate_dest;
}

sub build_plate_data {
    my ( $self, $plate ) = @_;

    my %plate_data = (
        name        => $plate->name,
        type        => $plate->type_id,
        description => $plate->description,
        created_by  => $plate->created_by->name,
        species     => $plate->species_id,
        is_virtual  => $plate->is_virtual ? 1 : 0,
    );

    return \%plate_data;
}

sub create_destination_plate {
    my ( $self, $plate, $plate_data ) = @_;

    $self->log->info( "Attempting to create plate, type $plate_data->{type}");

    #TODO plate comments sp12 Tue 29 Oct 2013 09:07:25 GMT
    $self->find_or_create_user( $plate->created_by );
    my $plate_dest = $self->dest_model->create_plate( $plate_data );

    return $plate_dest;
}

sub retrieve_destination_well {
    my ( $self, $plate, $well ) = @_;

    my $well_dest = $plate->wells->find( { name => $well->name } );

    $self->log->debug( "Well already exists in the destination DB") if $well_dest;

    return $well_dest;
}

sub create_well_in_destination_db {
    my ( $self, $well, $well_data ) = @_;

    $self->log->info( "Creating well process type $well_data->{process_data}{type}" );
    $self->find_or_create_user( $well->created_by );
    my $well_dest = $self->dest_model->create_well( $well_data );

    return $well_dest;
}

sub build_well_data {
    my ( $self, $input_well, $input_parent_wells, $input_well_process_type ) = @_;

    my $plate = $input_well->plate;

    my %well_data = (
        plate_name => $plate->name,
        well_name  => $input_well->name,
        created_by => $input_well->created_by->name,
    );

    # fetch details from parent wells for process data
    my @parent_well_details;
    if ( $input_parent_wells ) {
    	for my $parent_well ( @$input_parent_wells ) {
    		push @parent_well_details, {
                plate_name => $parent_well->plate->name,
                well_name  => $parent_well->name
            };
    	}
    }

    my %process_data = (
        'type' => $input_well_process_type,
    );

    if ( @parent_well_details ) {
        $process_data{input_wells} = \@parent_well_details;
    }

    $self->log->debug("Setting up process data for process type $input_well_process_type" );
    $self->process_aux_data_dispatches->{ $input_well_process_type }->( $input_well, \%process_data );
    $well_data{process_data} = \%process_data;

    return \%well_data;
}

sub create_process_aux_data_create_di {
    my ( $self, $well, $process_data ) = @_;
    $self->log->debug('create_di well');

    my $process = $well->output_processes->first;

    if ( $process->process_design ) {
        $process_data->{design_id} = $process->process_design->design_id;
    }

    for my $process_bac ( $process->process_bacs->all ) {
        my $bac_clone = $process_bac->bac_clone;
        push @{ $process_data->{bacs} }, {
            bac_plate   => $process_bac->bac_plate,
            bac_name    => $bac_clone->name,
            bac_library => $bac_clone->bac_library_id,
        };
    }

    return;
}

sub create_process_aux_data_create_crispr{
    my ( $self, $well, $process_data ) = @_;
    $self->log->debug('create_crispr well');

    my $process = $well->output_processes->first;

    if ( $process->process_crispr ) {
        $process_data->{crispr_id} = $process->process_crispr->crispr_id;
    }

    return;
}

sub create_process_aux_data_int_recom{
    my ( $self, $well, $process_data ) = @_;
    $self->log->debug('int_recom well');

    my $process = $well->output_processes->first;
    $process_data->{cassette} = $process->process_cassette->cassette->name;
    $process_data->{backbone} = $process->process_backbone->backbone->name;

    return;
}

sub create_process_aux_data_2w_gateway{
    my ( $self, $well, $process_data ) = @_;
    $self->log->debug('2w_gateway well');

    my $process = $well->output_processes->first;

    if ( my $process_cassette = $process->process_cassette ) {
        $process_data->{cassette} = $process_cassette->cassette->name;
    }
    if ( my $process_backbone = $process->process_backbone ) {
        $process_data->{backbone} = $process_backbone->backbone->name;
    }

    my @recombinases = $process->process_recombinases->search( {} , { order_by => 'rank' } );

    if ( @recombinases ) {
        $process_data->{recombinase} = [ map { $_->recombinase_id } @recombinases ];
    }

    return;
}

sub create_process_aux_data_3w_gateway{
    my ( $self, $well, $process_data ) = @_;
    $self->log->debug('3w_gateway well');

    my $process = $well->output_processes->first;
    $process_data->{cassette} = $process->process_cassette->cassette->name;
    $process_data->{backbone} = $process->process_backbone->backbone->name;

    my @recombinases = $process->process_recombinases->search( {} , { order_by => 'rank' } );

    if ( @recombinases ) {
        $process_data->{recombinase} = [ map { $_->recombinase_id } @recombinases ];
    }

    return;
}

sub create_process_aux_data_legacy_gateway {
    my ( $self, $well, $process_data ) = @_;
    $self->log->debug('legacy_gateway well');

    my $process = $well->output_processes->first;
    if ( my $process_cassette = $process->process_cassette ) {
        $process_data->{cassette} = $process_cassette->cassette->name;
    }
    if ( my $process_backbone = $process->process_backbone ) {
        $process_data->{backbone} = $process_backbone->backbone->name;
    }

    my @recombinases = $process->process_recombinases->search( {} , { order_by => 'rank' } );

    if ( @recombinases ) {
        $process_data->{recombinase} = [ map { $_->recombinase_id } @recombinases ];
    }

    return;
}

sub create_process_aux_data_final_pick{
    my ( $self, $well, $process_data ) = @_;

    # no aux data
    return;
}

sub create_process_aux_data_recombinase{
    my ( $self, $well, $process_data ) = @_;
    $self->log->debug('recombinase well');

    my $process = $well->output_processes->first;

    my @recombinases = $process->process_recombinases->search( {} , { order_by => 'rank' } );

    if ( @recombinases ) {
        $process_data->{recombinase} = [ map { $_->recombinase_id } @recombinases ];
    }

    return;
}

sub create_process_aux_data_cre_bac_recom{
    my ( $self, $well, $process_data ) = @_;

    # no aux data
    return;
}

sub create_process_aux_data_rearray{
    my ( $self, $well, $process_data ) = @_;

    # no aux data
    return;
}

sub create_process_aux_data_dna_prep{
    my ( $self, $well, $process_data ) = @_;

    # no aux data
    return;
}

sub create_process_aux_data_clone_pick{
    my ( $self, $well, $process_data ) = @_;

    # no aux data
    return;
}

sub create_process_aux_data_clone_pool{
    my ( $self, $well, $process_data ) = @_;

    # no aux data
    return;
}

sub create_process_aux_data_first_electroporation{
    my ( $self, $well, $process_data ) = @_;
    $self->log->debug('first_electroporation well');

    my $cell_line = $well->first_cell_line;
    $self->log->debug('FEP cell line : ' . $cell_line->name) if $cell_line;;
    $self->log->logdie("No first_cell_line set for $well") unless $cell_line;

    $process_data->{cell_line} = $cell_line->name;

    return;
}

sub create_process_aux_data_second_electroporation{
    my ( $self, $well, $process_data ) = @_;

    # no aux data
    return;
}

sub create_process_aux_data_freeze{
    my ( $self, $well, $process_data ) = @_;

    # no aux data
    return;
}

sub create_process_aux_data_xep_pool{
    my ( $self, $well, $process_data ) = @_;

    # no aux data
    return;
}

sub create_process_aux_data_dist_qc{
    my ( $self, $well, $process_data ) = @_;

    # no aux data
    return;
}

sub find_parent_wells {
	my ( $self, $child_well ) = @_;
    my @processes = $child_well->parent_processes;

    return [ $processes[0]->input_wells->all ];
}

__PACKAGE__->meta->make_immutable;

1;

__END__
