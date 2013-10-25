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

use Smart::Comments;

extends qw( LIMS2::Util::FixtureDataLoad );

sub retrieve_or_create_design {
    my ( $self, $design_id ) = @_;
    #Log::Log4perl::NDC->push( $design_id );

    $self->log->info( "Retrieve or create design $design_id" );

    $self->retrieve_destination_design($design_id)
        || $self->create_destination_design( $self->build_design_data($design_id) );

    #Log::Log4perl::NDC->pop;

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
    my ( $self, $design_data ) = @_;

    try{
        $self->dest_model->txn_do(
            sub {
                #$self->dest_model->create_design( $design_data );
                $self->dest_model->schema->resultset('Design')->create( $design_data );
                #$self->dest_model->txn_rollback;
            }
        );
        $self->log->info( "Design created" );
    }
    catch {
        $self->log->error( "Failed to create design: $_" );
    };

    return;
}

sub build_design_data {
    my ( $self, $design_id ) = @_;
    $self->log->debug( 'Build design data' );

    my $design = $self->source_model->schema->resultset( 'Design' )->find( { 'id' => $design_id } );

    unless ( $design ) {
        $self->log->logdie( 'Could not retrieve design from source' );
    }

    return $self->get_design_data( $design );
}

sub get_design_data {
    my ( $self, $design ) = @_;

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
    my $design_data = $design->as_hash( 1 );

    $design_data->{ gene_ids } = $design_data->{ assigned_genes };
    delete( $design_data->{ assigned_genes } );

    #each gene in gene_ids needs gene id and type id
    #gene_id      => $g->{gene_id},
    #gene_type_id => $g->{gene_type_id},

    $design_data->{ created_by } = 'test_user@example.org'; #$design->created_by->id;

    ##$design_data

    my %data = $design->get_columns;
    #TODO universal user creation sp12 Fri 25 Oct 2013 08:22:10 BST
    $data{created_by} = 1081;

    ### %data

    #return $design_data;
    return \%data;
}


__PACKAGE__->meta->make_immutable;

1;

__END__
