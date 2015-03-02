package LIMS2::Util::FixtureDataLoad::Designs;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::FixtureDataLoad::Designs::VERSION = '0.064';
}
## use critic


use warnings FATAL => 'all';

=head1 NAME

LIMS2::Util::FixtureDataLoad::Designs

=head1 DESCRIPTION

Load design fixture data

=cut

use Moose;
use Try::Tiny;
use namespace::autoclean;

extends qw( LIMS2::Util::FixtureDataLoad );

sub retrieve_or_create_design {
    my ( $self, $design_id ) = @_;
    Log::Log4perl::NDC->push( "[design: $design_id]" );

    $self->log->info( "Retrieve or create design" );

    return if $self->retrieve_destination_design($design_id);

    try{
        $self->create_destination_design( $design_id );
    }
    catch {
        $self->log->error("Error creating design: $_");
    };

    Log::Log4perl::NDC->pop;

    return;
}

sub retrieve_destination_design {
    my ( $self, $design_id ) = @_;
    $self->log->debug( "Attempting to retrieve design from destination DB" );

    my $design = $self->dest_model->schema->resultset( 'Design' )->find( { id => $design_id } );
    $self->log->info( "Design already exists in the destination DB" ) if $design;

    return $design;
}

sub create_destination_design {
    my ( $self, $design_id ) = @_;

    my $design = $self->source_model->schema->resultset( 'Design' )->find( { id => $design_id } );
    unless ( $design ) {
        $self->log->logdie( 'Could not retrieve design from source' );
    }
    my $design_data = $self->build_design_data( $design );

    $self->find_or_create_user( $design->created_by );
    # need to find or create user "unknown" because that is for some reason
    # the user who is hard coded to create the design oligos
    my $unknown_user = $self->source_model->schema->resultset( 'User' )->find( { name => 'unknown' } );
    $self->find_or_create_user( $unknown_user  );

    $self->dest_model->c_create_design( $design_data );
    $self->log->info( "Design created" );

    return;
}

sub build_design_data {
    my ( $self, $design ) = @_;
    $self->log->debug( 'Build design data' );

    # fetch data as hash from existing design object
    my $design_data = $design->as_hash( 0 );

    # create gene_design data
    my @genes;
    for my $g ( $design->genes->all ) {
        push @genes, {
            gene_id      => $g->gene_id,
            gene_type_id => $g->gene_type_id,
        };
    }
    $design_data->{gene_ids} = \@genes;

    # format oligo loci data
    for my $oligo ( @{ $design_data->{oligos} } ) {
        $oligo->{design_id} = $design->id;
        delete( $oligo->{id} );
        my $loci = delete( $oligo->{locus} );
        delete( $loci->{species} );
        $oligo->{loci} = [ $loci ];
    }

    # delete unwanted information
    for my $gp ( @{ $design_data->{genotyping_primers} } ) {
        delete $gp->{id};
        delete $gp->{locus};
        delete $gp->{species};
    }
    delete( $design_data->{assigned_genes} );
    delete( $design_data->{oligos_fasta} );
    delete( $_->{id} ) for @{ $design_data->{comments} };

    return $design_data;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
