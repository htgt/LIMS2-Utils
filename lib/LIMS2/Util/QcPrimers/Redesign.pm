package LIMS2::Util::QcPrimers::Redesign;

=head1 NAME

LIMS2::Util::QcPrimers::Redesign

=head1 DESCRIPTION


=cut

use Moose;
use WebAppCommon::Util::EnsEMBL;
use DDP;
use LIMS2::Exception;

use namespace::autoclean;

extends 'LIMS2::Util::QcPrimers';

#
# Override attributes from parent LIMS2:Util::QcPrimers class
#

# overwrite ( we probably never want to overwrite, just mark original primer as rejected )
has '+overwrite' => (
    init_arg => undef,
);

# set this to true to always, we do not want to regenerate a already existing primer
has '+check_for_rejection' => (
    init_arg => undef,
    default  => 1,
);

#
# User Input
#

has design => (
    is  => 'ro',
);

has crispr => (
    is  => 'ro',
);

has primer_types => (
    is       => 'ro',
    isa      => 'ArrayRef[Str]',
    required => 1,
);

# only for sequencing primers
has poly_base_type => (
    is  => 'ro',
    isa => 'Str',
);

#
# Calculated Attributes
#

has primer_sets => (
    is  => 'rw',
    isa => 'HashRef',
);

has failed_primers => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
);

has primer3_task => (
    is       => 'rw',
    isa      => 'Str',
    init_arg => undef,
);

# NOTE sequence_included_region will only ever take one value but we are keeping
# it as a array to keep the code dealing with these values uniform
has [ 'sequence_included_region', 'sequence_excluded_regions' ] => (
    is       => 'rw',
    isa      => 'ArrayRef',
    init_arg => undef,
);

has ensembl_util => (
    is         => 'ro',
    isa        => 'WebAppCommon::Util::EnsEMBL',
    lazy_build => 1,
);

sub _build_ensembl_util {
    my $self = shift;
    return WebAppCommon::Util::EnsEMBL->new( species => $self->crispr->species_id );
}

=head2 BUILD

desc

=cut
sub BUILD {
    my ( $self ) = @_;

    if ( !$self->crispr && !$self->design ) {
        die('Must specify a design or crispr');
    }

    if ( $self->poly_base_type && $self->design ) {
        if ( $self->design ) {
            # TODO work out way of doing this for designs if its ever needed...
            die( 'Sorry, can currently only redesign polyN primers fails for crisprs' );
        }
        my $primer_type_count = @{ $self->primer_types };
        if ( $primer_type_count > 1 ) {
            # SEQUENCE_INCLUDED_REGION only takes one value so we can only redesign
            # one primer at a time using this option
            die( 'Can only redesign 1 primer at a time for poly base fail reasons' );
        }
    }

    return;
}

=head2 redesign_primers

desc

=cut
sub redesign_primers {
    my ( $self ) = @_;
    $self->log->info( 'Redesigning '
            . $self->primer_project_name
            . ' primers '
            . join( ',', @{ $self->primer_types } ) );

    # process the primers name sets from the config file into a hash of useful data
    $self->process_primer_name_sets;
    # check we have one or two primers, if two must be matched pair
    # also check they exist for the profile
    $self->process_primer_types;
    # grab failed primer(s), mostly one but may be name of a pair
    $self->grab_failed_primers;

    if ( $self->poly_base_type ) {
        $self->calculate_sequence_include_regions;
        $self->log->info( 'Sequence include region: ' . p( $self->sequence_included_region ) )
    }
    else {
        $self->calculate_sequence_exclude_regions;
        $self->log->info( 'Sequence excluded regions: ' . p( $self->sequence_excluded_regions ) )
    }

    # NOTE this will mark all non validated primers of the type we are redesigning to rejected
    if ( $self->persist_primers ) {
        $self->model->txn_do(
            sub {
                for my $failed_primer_types ( keys %{ $self->failed_primers } ) {
                    $self->log->warn( "Marking all non validated $failed_primer_types primers as rejected" );
                    for my $failed_primer ( @{ $self->failed_primers->{$failed_primer_types} } ) {
                        $failed_primer->update( { is_rejected => 1 } )
                            unless $failed_primer->is_rejected;
                    }
                }
            }
        );
    }

    my ( $primer_data, $seq );
    if ( $self->primer_project_name eq 'crispr_sequencing' ) {
        ( $primer_data, $seq ) = $self->crispr_sequencing_primers( $self->crispr );
    }
    elsif ( $self->primer_project_name eq 'crispr_pcr' ) {
        my $seq_primers = $self->find_crispr_sequencing_primers();
        ( $primer_data, $seq ) = $self->crispr_PCR_primers( $seq_primers, $self->crispr );
    }
    elsif ($self->primer_project_name eq 'mgp_recovery'
        || $self->primer_project_name eq 'short_arm_vectors' )
    {
        ( $primer_data, $seq ) = $self->crispr_group_genotyping_primers( $self->crispr );
    }
    elsif ( $self->primer_project_name eq 'design_genotyping' ) {
        ( $primer_data, $seq ) = $self->design_genotyping_primers( $self->design );
    }
    else {
        die( "Not setup to redesign primers for primer project: " . $self->primer_project_name );
    }

    return( $primer_data, $seq );
}

=head2 process_primer_types

desc

=cut
sub process_primer_types {
    my ( $self ) = @_;
    $self->log->debug('working out primer types ..');

    my $primer_name = $self->primer_types->[0];
    my $primer_info = $self->primer_sets->{ $primer_name };
    unless ( $primer_info ) {
        die( "Do not recognise primer type $primer_name for profile " . $self->primer_project_name );
    }
    my $primer_name_set = { $primer_info->{type} => $primer_name };

    my $primer_type_count = @{ $self->primer_types };
    if ( $primer_type_count == 1 ) {
        $self->primer3_task( $primer_info->{task} );
    }
    elsif ( $primer_type_count == 2 ) {
        # check both primers belong to pair
        my $other_primer_name = $self->primer_types->[1];
        my $other_primer_info = $self->primer_sets->{$other_primer_name};
        unless ( $primer_info->{pair} == $other_primer_info->{pair} ) {
            die( "$primer_name and $other_primer_name do not belong to a primer pair" );
        }
        $self->primer3_task( 'pick_pcr_primers' ); # the default
        $primer_name_set->{ $other_primer_info->{type} } = $other_primer_name;
    }
    else {
        die( "You can only specify 1 or 2 failed primers, not $primer_type_count" );
    }

    $self->log->info( 'Primer3 task is: ' . $self->primer3_task );
    # update primer_name_sets to the primer(s) we want to generate
    $self->primer_name_sets( [ $primer_name_set ] );

    return;
}

=head2 grab_failed_primers

desc

=cut
sub grab_failed_primers {
    my ( $self ) = @_;
    $self->log->debug('Grabbing failed primers..');

    if ( $self->crispr ) {
        for my $type ( @{ $self->primer_types } ) {
            my $failed_primer_rs = $self->crispr->crispr_primers(
                {
                    primer_name  => $type,
                    is_validated => 0,
                }
            );
            $self->set_failed_primer( $failed_primer_rs, $type );
        }
    }

    if ( $self->design ) {
        for my $type ( @{ $self->primer_types } ) {
            my $failed_primer_rs = $self->design->genotyping_primers(
                {
                    genotyping_primer_type_id => $type,
                    is_validated              => 0,
                }
            );
            $self->set_failed_primer( $failed_primer_rs, $type );
        }
    }

    return;
}

=head2 process_primer_name_sets

desc

=cut
sub process_primer_name_sets {
    my ( $self ) = @_;
    $self->log->debug( 'process primer name sets' );

    my %primer3_tasks = (
        forward  => 'pick_left_only',
        reverse  => 'pick_right_only',
        internal => 'pick_hyb_probe_only',
    );
    my %primer_sets;
    my $pair = 1;
    for my $set ( @{ $self->primer_name_sets } ) {
        foreach my $type ( qw( forward reverse internal ) ) {
            next unless exists $set->{$type};
            $primer_sets{ $set->{$type} } = {
                task => $primer3_tasks{ $type },
                type => $type,
                pair => $pair,
            };
        }
        $pair++;
    }
    $self->primer_sets( \%primer_sets );

    return;
}

=head2 set_failed_primer

desc

=cut
sub set_failed_primer {
    my ( $self, $failed_primer_rs, $type ) = @_;

    my $count = $failed_primer_rs->count;
    if ( $count == 0 ) {
        die( "No non validated primer of type $type found" );
    }
    $self->log->debug( "Found $count non validated primers of type $type" );

    $self->failed_primers->{$type} = [ $failed_primer_rs->all ];
    return;
}

=head2 calculate_sequence_include_regions

ONLY FOR CRISPR PRIMERS FOR NOW

=cut
sub calculate_sequence_include_regions {
    my ( $self ) = @_;
    $self->log->info( 'Calculate sequence include region' );

    my $chromosome = $self->crispr->chr_name;
    # There will only ever be one primer here, we can only have
    # one value for sequence included region option
    for my $primer_type ( keys %{ $self->failed_primers } ) {
        # take first primer, I think any failed primer will do here
        my $primer = $self->failed_primers->{$primer_type}[0];
        my $primer_info = $primer->as_hash;

        if ( $self->primer_sets->{ $primer_type }{ type } eq 'forward' ) {
            my $polyn_locations = $self->find_poly_base_locations(
                $primer_info->{locus}{chr_start}, # start
                $self->crispr->start,             # end
                $chromosome,                      # chromosome
            );

            $self->sequence_included_region(
                [   {   start => $polyn_locations->[-1]{end},
                        end   => $self->crispr->start,
                    }
                ]
            );
        }
        elsif ( $self->primer_sets->{ $primer_type }{ type } eq 'reverse' ) {
            my $polyn_locations = $self->find_poly_base_locations(
                $self->crispr->end,               # start
                $primer_info->{locus}{chr_end},   # end
                $chromosome,                      # chromosome
            );

            $self->sequence_included_region(
                [   {   start => $self->crispr->end,
                        end   => $polyn_locations->[0]{start},
                    }
                ]
            );
        }
        else {
            die( 'Currently can not use poly_base option with internal primers' );
        }
    }


    return;
}

=head2 calculate_sequence_exclude_regions

desc

=cut
sub calculate_sequence_exclude_regions {
    my ( $self ) = @_;
    $self->log->info( 'Calculate sequence excluded region' );
    my @sequence_excluded_regions;

    for my $primer_type ( keys %{ $self->failed_primers } ) {
        for my $primer ( @{ $self->failed_primers->{$primer_type} } ) {
            my $primer_info = $primer->as_hash;
            push @sequence_excluded_regions, {
                start => $primer_info->{locus}{chr_start},
                end   => $primer_info->{locus}{chr_end},
            };
        }
    }

    $self->sequence_excluded_regions( \@sequence_excluded_regions );

    return;
}

=head2 find_poly_base_locations

desc

=cut
sub find_poly_base_locations {
    my ( $self, $start, $end, $chromosome ) = @_;
    $self->log->info('Searching for Poly base sequence');

    my $slice = $self->ensembl_util->get_slice( $start, $end, $chromosome );
    my $seq = $slice->seq;
    my $poly_base = $self->poly_base_type;
    $self->log->debug("Searching for Poly $poly_base regions in $seq");

    my @poly_base_positions;
    my $regex = qr/(($poly_base)(\2{5,}))/;
    while ( $seq =~ /$regex/g ) {
        # make into genomic coordinates
        $self->log->debug( "Found Poly $poly_base region: $1" );
        push @poly_base_positions, {
            start => ( $-[0] + $start ),
            end   => ( $+[0] + $start ),
        };
    }

    unless( @poly_base_positions ) {
        die( "Can not find Poly $poly_base run of bases" );
    }

    return \@poly_base_positions;
}

=head2 find_crispr_sequencing_primers

desc

=cut
sub find_crispr_sequencing_primers {
    my ( $self ) = @_;

    # Currently this method returns the first non-rejected sequencing primer pair
    # if we don't have good PCR primers they should not have rejected the
    # sequencing primers so we should be able to find some.
    my $sf1_primer = $self->crispr->current_primer( 'SF1' )->as_hash;
    my $sr1_primer = $self->crispr->current_primer( 'SR1' )->as_hash;
    my $start = $sf1_primer->{locus}{chr_start} + 1;
    my $end = $sr1_primer->{locus}{chr_end} + 1;
    # NOTE the SF1 primer may not always be before the SR1...
    if ( $start > $end ) {
        my $tmp = $start;
        $start  = $end;
        $end    = $tmp;
    }

    # data structure needed to feed into crispr_PCR_primers method on LIMS2::Util::QcPrimers
    return [
        {
            forward => { oligo_start => $start },
            reverse => { oligo_end   => $end },
        },
    ];
}

around [
    qw( get_new_crispr_primer_finder_params
        get_new_crispr_PCR_primer_finder_params
        get_new_design_primer_finder_params )
    ] => sub {
    my $orig = shift;
    my $self = shift;

    my $params = $self->$orig(@_);

    $params->{primer3_task}     = $self->primer3_task;
    $params->{excluded_regions} = $self->sequence_excluded_regions if $self->sequence_excluded_regions;
    $params->{included_regions} = $self->sequence_included_region if $self->sequence_included_region;

    return $params;
};

__PACKAGE__->meta->make_immutable;

1;

__END__
