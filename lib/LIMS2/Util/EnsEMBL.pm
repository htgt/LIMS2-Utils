package LIMS2::Util::EnsEMBL;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::EnsEMBL::VERSION = '0.052';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Moose;
use MooseX::ClassAttribute;
use Bio::EnsEMBL::Registry;
use namespace::autoclean;

# registry is a class variable to ensure that load_registry_from_db() is
# called only once

class_has registry => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1
);

sub _build_registry {

    Bio::EnsEMBL::Registry->load_registry_from_db(
        -host => $ENV{LIMS2_ENSEMBL_HOST} || 'ensembldb.ensembl.org',
        -user => $ENV{LIMS2_ENSEMBL_USER} || 'anonymous'
    );

    return 'Bio::EnsEMBL::Registry';
}

has species => (
    is       => 'rw',
    isa      => 'Str',
    default  => 'mouse',
    required => 1
);

sub db_adaptor {
    my ( $self, $species ) = @_;
    return $self->registry->get_DBAdaptor( $species || $self->species, 'core' );
}

sub gene_adaptor {
    my ( $self, $species ) = @_;
    return $self->registry->get_adaptor( $species || $self->species, 'core', 'gene' );
}

sub slice_adaptor {
    my ( $self, $species ) = @_;
    return $self->registry->get_adaptor( $species || $self->species, 'core', 'slice' );
}

sub transcript_adaptor {
    my ( $self, $species ) = @_;
    return $self->registry->get_adaptor( $species || $self->species, 'core', 'transcript' );
}

sub constrained_element_adaptor {
    my ($self) = @_;
    return $self->registry->get_adaptor( 'Multi', 'compara', 'ConstrainedElement' );
}

sub repeat_feature_adaptor {
    my ( $self, $species ) = @_;
    return $self->registry->get_adaptor( $species || $self->species, 'core', 'repeatfeature' );
}

sub exon_adaptor {
    my ( $self, $species ) = @_;
    return $self->registry->get_adaptor( $species || $self->species, 'core', 'exon' );
}

sub get_best_transcript {
    my ( $self, $ensembl_object, $marker_symbol ) = @_;

    #$ensembl_object can be an instance of any class with a get_all_Transcripts method
    confess ref $ensembl_object . " has no get_all_Transcripts method."
        unless $ensembl_object->can("get_all_Transcripts");

    #find the best transcript
    my $best_transcript;
    for my $transcript ( @{ $ensembl_object->get_all_Transcripts } ) {
        #skip non coding transcripts
        next unless $transcript->translation;

        #marker symbol is optional; it just makes sure you got a transcript for the right gene
        if ( $marker_symbol ) {
            next unless $transcript->get_Gene->external_name eq $marker_symbol;
        }

        #if we don't have a transcript already then we'll use the first coding one.
        unless ( $best_transcript ) {
            $best_transcript = $transcript;
            next;
        }

        if ( $transcript->translation->length > $best_transcript->translation->length ) {
            $best_transcript = $transcript;
        }
        elsif ( $transcript->translation->length == $best_transcript->translation->length ) {
            #only replace transcripts of equal translation length if the transcript is longer
            if ( $transcript->length > $best_transcript->length ) {
                $best_transcript = $transcript;
            }
        }
    }

    confess "Couldn't find a valid transcript."
        unless $best_transcript;

    return $best_transcript;
}

sub get_exon_rank {
    my ( $self, $transcript, $exon_stable_id ) = @_;

    my $rank = 1; #start from 1
    for my $exon ( @{ $transcript->get_all_Exons } ) {
        return $rank if $exon->stable_id eq $exon_stable_id;
        $rank++;
    }

    confess "Couldn't find $exon_stable_id in transcript.";
}

sub get_gene_from_exon_id {
    my ( $self, $exon_stable_id ) = @_;

    return $self->gene_adaptor->fetch_by_exon_stable_id( $exon_stable_id );
}

__PACKAGE__->meta->make_immutable;

1;

__END__
