package LIMS2::Util::FixtureDataLoad::Bacs;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::FixtureDataLoad::Bacs::VERSION = '0.064';
}
## use critic


use warnings FATAL => 'all';

=head1 NAME

LIMS2::Util::FixtureDataLoad::Bacs

=head1 DESCRIPTION

Load bac clone fixture data

=cut

use Moose;
use Try::Tiny;
use namespace::autoclean;

extends qw( LIMS2::Util::FixtureDataLoad );

sub retrieve_or_create_bac {
    my ( $self, $bac_name ) = @_;
    Log::Log4perl::NDC->push( "[bac: $bac_name]" );

    $self->log->info( "Retrieve or create bac" );

    return if $self->retrieve_destination_bac($bac_name);

    try{
        $self->create_destination_bac( $bac_name );
    }
    catch {
        $self->log->error("Error creating bac: $_");
    };

    Log::Log4perl::NDC->pop;

    return;
}

sub retrieve_destination_bac {
    my ( $self, $bac_name ) = @_;
    $self->log->debug( "Attempting to retrieve bac from destination DB" );

    my $bac = $self->dest_model->schema->resultset( 'BacClone' )->find( { name => $bac_name } );
    $self->log->info( "bac already exists in the destination DB" ) if $bac;

    return $bac;
}

sub create_destination_bac {
    my ( $self, $bac_name ) = @_;

    my $bac = $self->source_model->schema->resultset( 'BacClone' )->find( { name => $bac_name } );
    unless ( $bac ) {
        $self->log->logdie( 'Could not retrieve bac from source' );
    }
    my $bac_data = $self->build_bac_data( $bac );

    $self->dest_model->create_bac_clone( $bac_data );
    $self->log->info( "bac created" );

    return;
}

sub build_bac_data {
    my ( $self, $bac ) = @_;
    $self->log->debug( 'Build bac data' );

    # fetch data as hash from existing bac object
    my $bac_data = $bac->as_hash( 0 );
    delete( $bac_data->{id} );

    return $bac_data;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
