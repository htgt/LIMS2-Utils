package LIMS2::Util::WGE;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::WGE::VERSION = '0.035';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Moose;
use LIMS2::Exception;
use Path::Class;
use MooseX::Types::Path::Class;
use Try::Tiny;
use LIMS2::REST::Client;
use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

has rest_client_config => (
    is      => 'ro',
    isa     => 'Path::Class::File',
    default => sub { file( $ENV{WGE_REST_CLIENT_CONFIG} //
                           '/nfs/team87/farm3_lims2_vms/conf/wge-live-rest-client.conf' ) }
);

has rest_client => (
    is         => 'ro',
    isa        => 'LIMS2::REST::Client',
    lazy_build => 1,
);

#maps a species id to a species name
has species_data => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
);

sub _build_species_data {
    my $self = shift;

    return $self->rest_client->GET( 'get_all_species' );
}

sub _build_rest_client {
    my $self = shift;

    return LIMS2::REST::Client->new_with_config(
        configfile => $self->rest_client_config->stringify
    );
}

sub get_crispr {
    my ( $self, $id, $assembly ) = @_;

    LIMS2::Exception::Validation->throw( "Assembly must be provided" )
        unless $assembly;

    my $wge_crispr = $self->_get_crispr( $id );

    my $crispr = {
        species => $self->species_data->{$wge_crispr->{species_id}},
        off_target_algorithm => 'bwa',
        type                 => 'Exonic',
        wge_crispr_id        => $wge_crispr->{id},
        locus                => {
            chr_name   => $wge_crispr->{chr_name},
            chr_start  => $wge_crispr->{chr_start},
            chr_end    => $wge_crispr->{chr_end},
            chr_strand => $wge_crispr->{pam_right} ? 1 : -1,
            assembly   => $assembly,
        },
        pam_right => $wge_crispr->{pam_right},
        seq      => $wge_crispr->{seq},
        off_target_summary => $wge_crispr->{off_target_summary},
    };

    return $crispr;
}

#I have put this in a separate method in case someone doesn't want
#the data converted to the LIMS2 db structure
sub _get_crispr {
    my ( $self, $id ) = @_;

    my $crispr_data;
    try {
        $crispr_data = $self->rest_client->GET( 'crispr', { id => $id } );
    }
    catch {
        $self->log->debug( "Error retrieving WGE CRISPR: \n" . $_ );
        LIMS2::Exception->throw( "Invalid WGE crispr id: $id" );
    };

    return $crispr_data;
}

sub get_crispr_pair {
    my ( $self, $left_id, $right_id, $species ) = @_;

    my $crispr_pair_data;
    try {
        $crispr_pair_data = $self->rest_client->GET( 'find_or_create_crispr_pair', {
            left_id  => $left_id,
            right_id => $right_id,
            species  => $species,
        } );

        #get lims2 species
        $crispr_pair_data->{species} = $self->species_data->{$crispr_pair_data->{species_id}}
    }
    catch {
        $self->log->debug( "Error retrieving CRISPR pair: \n" . $_ );
        LIMS2::Exception->throw( "Invalid WGE pair id: ${left_id}_${right_id}" );
    };

    return $crispr_pair_data;
}

__PACKAGE__->meta->make_immutable;

1;
