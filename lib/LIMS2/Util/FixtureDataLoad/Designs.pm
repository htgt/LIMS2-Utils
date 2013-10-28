package LIMS2::Util::FixtureDataLoad::Designs;

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
    Log::Log4perl::NDC->push( $design_id );

    $self->log->info( "Retrieve or create design $design_id" );

    return if $self->retrieve_destination_design($design_id);

    try{
        $self->dest_model->txn_do(
            sub {
                $self->create_destination_design( $design_id );
                if ( !$self->persist ) {
                    $self->log->debug('Rollback');
                    $self->dest_model->txn_rollback;
                }
            }
        );
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

    my $design = try {
        $self->dest_model->schema->resultset( 'Design' )->find( { 'id' => $design_id } );
    }
    catch {
        $_->throw() unless $_->not_found;
        undef;
    };
    $self->log->info( "Design already exists in the destination DB" ) if $design;

    return $design;
}

sub create_destination_design {
    my ( $self, $design_id ) = @_;

    my $design = $self->source_model->schema->resultset( 'Design' )->find( { 'id' => $design_id } );
    unless ( $design ) {
        $self->log->logdie( 'Could not retrieve design from source' );
    }
    my $design_data = $self->build_design_data( $design );

    $self->dest_model->create_design( $design_data );
    $self->log->info( "Design created" );

    return;
}

sub build_design_data {
    my ( $self, $design ) = @_;
    $self->log->debug( 'Build design data' );

    # requirements as per Design plugin create method
    # my $design_data = {
    #     species                 => $design->species,
    #     id                      => $design->id,
    #     type                    => $design->type,
    #     created_at              => $design->created_at,
    #     created_by              => $design->created_by->id,
    #     phase                   => $design->phase,
    #     validated_by_annotation => $design->validated_by_annotation,
    #     name                    => $design->name,
    #     target_transcript       => $design->target_transcript,
    #     oligos                  => $design->oligos,
    #     genotyping_primers      => $design->genotyping_primers,
    #     comments                => $design->comments,
    #     gene_ids                => $design->gene_ids,
    #     cassette_first          => 
    # };

    # fetch data as hash from existing design object
    my $design_data = $design->as_hash( 0 );
    $self->create_user( $design->created_by );

    my @genes;
    for my $g ( $design->genes->all ) {
        push @genes, {
            gene_id      => $g->gene_id,
            gene_type_id => $g->gene_type_id,
        };
        $self->create_user( $g->created_by );
    }
    $design_data->{gene_ids} = \@genes;
    delete( $design_data->{assigned_genes} );

    delete( $design_data->{oligos_fasta} );

    for my $oligo ( @{ $design_data->{oligos} } ) {
        $oligo->{design_id} = $design->id;
        delete( $oligo->{id} );
        my $loci = delete( $oligo->{locus} );
        delete( $loci->{species} );
        $oligo->{loci} = [ $loci ];
    }

    delete( $_->{id} ) for @{ $design_data->{genotyping_primers} };
    delete( $_->{id} ) for @{ $design_data->{comments} };

    return $design_data;
}


__PACKAGE__->meta->make_immutable;

1;

__END__
