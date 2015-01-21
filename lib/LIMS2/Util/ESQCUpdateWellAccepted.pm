package LIMS2::Util::ESQCUpdateWellAccepted;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::ESQCUpdateWellAccepted::VERSION = '0.056';
}
## use critic


=head1 NAME

LIMS2::Util::ESQCUpdateWellAccepted

=head1 DESCRIPTION

Takes a qc_run done against a EP_PICK plate. For each well gathers the valid primers from
the qc run plus any primer band information stored against the well itself. With this list
of primers we can work out if the EP PICK well should be marked as accepted or not.

=cut

use Moose;

use LIMS2::Exception;
use LIMS2::Model::Util::QCResults qw( retrieve_qc_run_results_fast );
use Try::Tiny;
use List::MoreUtils qw( any );
use URI;
use Log::Log4perl;

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
    return retrieve_qc_run_results_fast( $self->qc_run, $self->model );
}

# Used to calculate if a wel has mixed reads or not
has qc_run_results_by_well => (
    is         => 'ro',
    isa        => 'HashRef',
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
    isa      => 'Str',
    required => 1,
);

has base_qc_url => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has commit => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has accepted_wells => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub{ [] },
    traits  => [ 'Array' ],
    handles => {
        add_accepted_well => 'push',
        has_accepted_wells => 'count',
    }
);

=head2 update_well_accepted

Run the code that will update the well accepted values

=cut
sub update_well_accepted {
    my $self = shift;

    $self->log->info( 'Analysing results from qc_run: ' . $self->qc_run->id );

    unless ( $self->qc_run->profile eq 'standard-es-cell' ) {
        $self->log->warn('Qc Run does not use standard-es-cell profile : ' . $self->qc_run->profile );
        return ( [], 'Can only set epd wells accepted flag from standard-es-cell qc profile' );
    }

    my $error;
    $self->model->txn_do(
        sub {
            try{
                for my $qc_data ( @{ $self->qc_run_results } ) {
                    $self->update_well( $qc_data );
                }

                unless ( $self->commit ) {
                    $self->log->warn( 'Run in non-commit mode, rolling back changes' );
                    $self->model->txn_rollback;
                }
            }
            catch {
                $self->log->error( "Error: $_" );
                $error = $_;
                $self->model->txn_rollback;
            };
        }
    );

    if ( $error ) {
        return ( [], $error );
    }
    elsif ( $self->has_accepted_wells ) {
        return ( $self->accepted_wells, undef );
    }
    else {
        return ( [], 'No wells passed qc checks' );
    }

    return;
}

=head2 update_well

Check a individual ep pick well to see if it should be marked as accepted.

=cut
sub update_well {
    my ( $self, $well_qc_data ) = @_;
    my $plate_name = $well_qc_data->{plate_name};
    my $well_name = uc( $well_qc_data->{well_name} );
    Log::Log4perl::NDC->remove;
    Log::Log4perl::NDC->push( $plate_name . '_' . $well_name );

    my $epd_well = try {
        $self->model->retrieve_well(
            {   plate_name => $plate_name,
                well_name  => $well_name,
            }
        );
    };

    LIMS2::Exception->throw( "Can not locate well: $plate_name $well_name") unless $epd_well;

    # grap LR PCR primers from well and merge with valid primers list from qc
    my @valid_primers = @{ $well_qc_data->{valid_primers} };
    my @valid_lrpcr_primers = map { uc( $_->primer_band_type->id ) }
        grep { $_->pass =~ /pass/ } $epd_well->well_primer_bands;
    push @valid_primers, @valid_lrpcr_primers;

    # overall pass = ( five_arm_pass OR three_arm_pass ) AND loxp_pass
    if ( ( $self->five_arm_pass( \@valid_primers ) || $self->three_arm_pass( \@valid_primers ) )
        && $self->loxp_pass( \@valid_primers ) )
    {
        $self->log->info( 'Well is being marked accepted' );
        $self->add_accepted_well( $plate_name . '_' . $well_name );
        $epd_well->update( { accepted => 1 } );

        $self->log->info( '. creating well_qc_sequencing_result record for well ( pass )' );
        $self->add_well_qc_sequencing_result_for_well( $epd_well, \@valid_primers, 1, $well_name, $plate_name );
    }
    else {
        $self->log->info( 'Well does not meet accepted criteria' );
        if ( $epd_well->accepted ) {
            $self->log->info( '. but it has already been marked as accepted, do nothing' );
            return;
        }
        $self->log->info( '. creating well_qc_sequencing_result record for well ( failed )' );

        $self->add_well_qc_sequencing_result_for_well( $epd_well, \@valid_primers, 0, $well_name, $plate_name );
    }

    return;
}

=head2 add_well_qc_sequencing_result_for_well

Add a well_qc_sequencing_result record linked a ep_pick well.
This will contain a list of valid primers, a link to the relevant qc_run
result page and a pass or fail value.

=cut
sub add_well_qc_sequencing_result_for_well {
    my ( $self, $epd_well, $valid_primers, $pass, $well_name, $plate_name ) = @_;

    # If there is already a well_qc_sequencing_result row linked to this well
    # then we need to delete it and create a new one with the current qc data
    if ( my $result = $epd_well->well_qc_sequencing_result ) {
        $self->log->info( '.. deleting pre-existing well_qc_sequencing_result row first' );
        $result->delete;
    }

    my $view_params = {
        well_name  => lc( $well_name ),
        plate_name => $plate_name,
        qc_run_id  => $self->qc_run->id,
    };

    my $url = URI->new($self->base_qc_url);
    $url->query_form($view_params);
    $self->log->debug( '.. creating well_qc_sequencing_result' );

    $self->model->create_well_qc_sequencing_result(
        {
            well_id         => $epd_well->id,
            valid_primers   => join( ',', @{ $valid_primers } ),
            mixed_reads     => @{ $self->qc_run_results_by_well->{ $well_name } } > 1 ? 1 : 0,
            pass            => $pass,
            test_result_url => $url->as_string,
            created_by      => $self->user,
        }, $epd_well,
    );

    return;
}

=head2 five_arm_pass

Logic to work out if we can call a five arm pass on the well
GF AND (Art5 OR R1R)

=cut
sub five_arm_pass {
    my ( $self, $primers ) = @_;

    if ( has_primer( $primers, qr/GF/ )
        && ( has_primer( $primers, qr/R1R/ ) || has_primer( $primers, qr/Art5/ ) ) )
    {
        return 1;
    }

    return;
}

=head2 three_arm_pass

Logic to work out if we can call a three arm pass on the well
GR AND (A_R2R OR A_LR OR Z_LRR OR A_LF OR A_LRR OR A_LFR OR Z_LR)

=cut
sub three_arm_pass {
    my ( $self, $primers ) = @_;

    if (has_primer( $primers, qr/^GR/i )
        && (   has_primer( $primers, qr/R2R/i )
            || has_primer( $primers, qr/LRR?/ )
            || has_primer( $primers, qr/LFR/ ) )
        )
    {
        return 1;
    }

    return;
}

=head2 loxp_pass

Logic to work out if we can call a loxp pass on the well
GR AND (LR OR LF OR LRR)
OR
(TR AND (B_R2R OR B_LFR)) AND (GF AND (Art5 OR R1R))

=cut
sub loxp_pass {
    my ( $self, $primers ) = @_;

    if ( has_primer( $primers, qr/^GR/i )
        && ( has_primer( $primers, qr/LF/i ) || has_primer( $primers, qr/LRR?/i ) ) )
    {
        return 1;
    }
    elsif (
        (   has_primer( $primers, qr/TR/i )
            && ( has_primer( $primers, qr/R2R/ ) || has_primer( $primers, qr/LFR/i ) )
        )
        && ( has_primer( $primers, qr/GF/i )
            && ( has_primer( $primers, qr/Art5/i ) || has_primer( $primers, qr/R1R/i ) ) )
        )
    {
        return 1;
    }

    return;
}

sub has_primer {
    my ( $primer_list, $regex ) = @_;
    return any { $_ =~ $regex } @{ $primer_list };
}

__PACKAGE__->meta->make_immutable;

1;

__END__
