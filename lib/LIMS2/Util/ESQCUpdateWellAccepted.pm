package LIMS2::Util::ESQCUpdateWellAccepted;

=head1 NAME

LIMS2::Util::ESQCUpdateWellAccepted

=head1 DESCRIPTION


=cut

use Moose;

use LIMS2::Model;
use LIMS2::Exception;
use LIMS2::Model::Util::QCResults qw( retrieve_qc_run_results_fast retrieve_qc_run_seq_well_results );
use Try::Tiny;
use URI;

use namespace::autoclean;

with 'MooseX::Log::Log4perl';

has model => (
    is  => 'ro',
    isa => 'LIMS2::Model',
);

has qc_run => (
    is       => 'ro',
    isa      => 'LIMS2::Model::Schema::Result::QcRun',
    required => 1,
);

has qc_run_results => (
    is         => 'ro',
    isa        => 'ArrayRef',
    lazy_build => 1,
);

sub _build_qc_run_results {
    my $self = shift;
    return retrieve_qc_run_results_fast( $self->qc_run, $self->model->schema );
}

has qc_run_results_by_well => (
    is         => 'ro',
    isa        => 'ArrayRef',
    lazy_build => 1,
);

sub _build_qc_run_results_by_well {
    my $self = shift;

    my %results_by_well;
    for my $data ( @{ $self->qc_run_results }) {
        push @{ $results_by_well{ uc( substr( $data->{well_name}, -3 ) ) } }, $data;
    }

    return \%results_by_well;
}

has user => (
    is       => 'ro',
    isa      => 'LIMS2::Model::Schema::Result::User',
    required => 1,
);

has base_qc_url => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

# INITIAL CHECKs
# qc run linked to epd plate
# it is es qc ( profile limit ? )

# DATA
# lrpcr data for each ep_pick well ( well_primer_bands, type_id lr_pcr_pass )
# qc primer data

# LOGIC
# loxp_pass = '(GR AND (LR OR LF OR LRR)) OR ((TR AND (B_R2R OR B_LFR)) AND (GF AND (Art5 OR R1R)))'
# five_arm_pass = '(GF AND (Art5 OR R1R))'
# three_arm_pass = 'GR AND (A_R2R OR A_LR OR Z_LRR OR A_LF OR A_LRR OR A_LFR OR Z_LR)'
# overall pass = five_arm_pass or three_arm_pass AND loxp_pass

# ACCEPTED
# mark well as accepted
# add a link to the qc test result via the well_qc_sequencing_result table
use Smart::Comments;
sub test {
    my $self = shift;


    # TODO: CHECK

    for my $datum ( @{ $data } ) {
        # TODO rollback / commits
        if ( @{ $datum->{valid_primers} } ) {
            $self->well_check( $datum );
        }
    }

    return;
}

sub well_check {
    my ( $self, $well_qc_data ) = @_;

    my $plate_name = $well_qc_data->{plate_name};
    my $well_name = lc( $well_qc_data->{well_name} );
    my $epd_well = try {
            $self->model->retrieve_well(
            {
                plate_name => $plate_name,
                well_name  => uc( $well_name ),
            }
        );
    };

    unless ( $epd_well ) {
        LIMS2::Exceptions->throw( "Can not locate well: $plate_name $well_name");
    }
    my @valid_primers = @{ $well_qc_data->{valid_primers} };
    my @valid_lrpcr_primers = map { uc( $_->primer_band_type->id ) }
        grep { $_->pass =~ /pass/ } $epd_well->well_primer_bands;
    push @valid_primers, @valid_lrpcr_primers;

    # does well 'pass'
    if ( ( $self->five_arm_pass( \@valid_primers ) || $self->three_arm_pass( \@valid_primers ) )
        && $self->loxp_pass( \@valid_primers ) )
    {
        # mark epd well as accepted
        $epd_well->update( { accepted => 1 } );

        # TODO what to do about already existing well_qc_sequencing_results??
        # -- must delete it ,can only have one result according to schema
        my $result = $epd_well->well_qc_sequencing_result;
        $result->delete if $result;

        my $view_params = {
            well_name  => $well_name,
            plate_name => $plate_name,
            qc_run_id  => $self->qc_run->id,
        };

        my $url = URI->new($self->base_qc_url);
        $url->query_form($view_params);
        $self->model->create_well_qc_sequencing_result(
            {
                well_id         => $epd_well->id,
                valid_primers   => join( ',', @valid_primers ),
                mixed_reads     => @{ $self->results_by_well->{ $well_name } } > 1 ? 1 : 0,
                pass            => 1,
                test_result_url => $url->as_string,
                created_by      => $user->name,
            }, $epd_well,
        );
    }
    else {
        # log something
    }

    ### well : $epd_well->as_string
    ### valid primers : @valid_primers
    return;
}

sub five_arm_pass {
    my ( $self, $valid_primers ) = @_;

}

sub three_arm_pass {
    my ( $self, $valid_primers ) = @_;

}

sub loxp_pass {
    my ( $self, $valid_primers ) = @_;

}

__PACKAGE__->meta->make_immutable;

1;

__END__
