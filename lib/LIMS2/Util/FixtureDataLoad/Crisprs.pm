package LIMS2::Util::FixtureDataLoad::Crisprs;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::FixtureDataLoad::Crisprs::VERSION = '0.038';
}
## use critic


use warnings FATAL => 'all';

=head1 NAME

LIMS2::Util::FixtureDataLoad::Crisprs

=head1 DESCRIPTION

Load crispr or crispr_pair fixture data

=cut

use Moose;
use Try::Tiny;
use namespace::autoclean;

extends qw( LIMS2::Util::FixtureDataLoad );

sub retrieve_or_create_crispr {
    my ( $self, $crispr_id ) = @_;
    Log::Log4perl::NDC->push( "[crispr: $crispr_id]" );

    $self->log->info( "Retrieve or create crispr" );

    return if $self->retrieve_destination_crispr($crispr_id);

    try{
        $self->create_destination_crispr( $crispr_id );
    }
    catch {
        $self->log->error("Error creating crispr: $_");
    };

    Log::Log4perl::NDC->pop;

    return;
}

sub retrieve_or_create_crispr_pair {
    my ( $self, $crispr_pair_id ) = @_;
    Log::Log4perl::NDC->push( "crispr pair: $crispr_pair_id" );

    $self->log->info( "Retrieve or create crispr_pair" );

    return if $self->retrieve_destination_crispr_pair($crispr_pair_id);

    try{
        $self->create_destination_crispr_pair( $crispr_pair_id );
    }
    catch {
        $self->log->error("Error creating crispr_pair: $_");
    };

    Log::Log4perl::NDC->pop;

    return;
}

sub retrieve_destination_crispr {
    my ( $self, $crispr_id ) = @_;
    $self->log->debug( "Attempting to retrieve crispr from destination DB" );

    my $crispr = $self->dest_model->schema->resultset( 'Crispr' )->find( { id => $crispr_id } );

    $self->log->info( "Crispr already exists in the destination DB" ) if $crispr;

    return $crispr;
}

sub retrieve_destination_crispr_pair {
    my ( $self, $crispr_pair_id ) = @_;
    $self->log->debug( "Attempting to retrieve crispr_pair from destination DB" );

    my $crispr_pair = $self->dest_model->schema->resultset( 'CrisprPair' )->find( { id => $crispr_pair_id } );
    $self->log->info( "Crispr Pair already exists in the destination DB" ) if $crispr_pair;

    return $crispr_pair;
}

sub create_destination_crispr {
    my ( $self, $crispr_id ) = @_;

    my $crispr = $self->source_model->schema->resultset( 'Crispr' )->find( { id => $crispr_id } );
    unless ( $crispr ) {
        $self->log->logdie( 'Could not retrieve crispr from source' );
    }
    $self->_create_crispr( $crispr );

    return;
}

sub create_destination_crispr_pair {
    my ( $self, $crispr_pair_id ) = @_;

    my $crispr_pair = $self->source_model->schema->resultset( 'CrisprPair' )->find( { id => $crispr_pair_id } );
    unless ( $crispr_pair ) {
        $self->log->logdie( 'Could not retrieve crispr_pair from source' );
    }

    $self->log->info('Create left and right crispr of crispr pair');
    unless ( $self->retrieve_destination_crispr( $crispr_pair->right_crispr_id ) ) {
        $self->_create_crispr( $crispr_pair->right_crispr );
    }
    unless ( $self->retrieve_destination_crispr( $crispr_pair->left_crispr_id ) ) {
        $self->_create_crispr( $crispr_pair->left_crispr );
    }

    $self->log->info( 'Copy crispr_pair' );
    my $crispr_pair_data = $self->get_dbix_row_data( $crispr_pair );
    $self->dest_model->schema->resultset('CrisprPair')->create( $crispr_pair_data );

    return;
}

sub _create_crispr {
    my ( $self, $crispr ) = @_;
    $self->log->info( "Create crispr and related data" );

    my $crispr_data = $self->get_dbix_row_data( $crispr );
    $self->log->debug( 'Copy crispr' );
    $self->dest_model->schema->resultset('Crispr')->create( $crispr_data );

    $self->log->debug( 'Copy crispr off target data' );
    for my $ot ( $crispr->off_targets->all ) {
        my $datum = $self->get_dbix_row_data( $ot );
        $self->dest_model->schema->resultset('CrisprOffTargets')->create( $datum  );
    }

    $self->log->debug( 'Copy crispr off target summary data' );
    for my $ots ( $crispr->off_target_summaries->all ) {
        my $datum = $self->get_dbix_row_data( $ots );
        $self->dest_model->schema->resultset('CrisprOffTargetSummary')->create( $datum  );
    }

    $self->log->debug( 'Copy crispr loci data' );
    for my $locus ( $crispr->loci->all ) {
        my $datum = $self->get_dbix_row_data( $locus );
        ## no critic(ProtectPrivateSubs)
        my $chr_id = $self->dest_model->_chr_id_for( $datum->{assembly_id}, $locus->chr->name );
        ## use critic
        $datum->{chr_id} = $chr_id;
        $self->dest_model->schema->resultset('CrisprLocus')->create( $datum  );
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
