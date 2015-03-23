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
has poly_base_fail => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
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

has sequence_excluded_regions => (
    is       => 'rw',
    isa      => 'ArrayRef',
    init_arg => undef,
);

has sequence_included_region => (
    is       => 'rw',
    isa      => 'HashRef',
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
    elsif ( $self->crispr && $self->design ) {
        die('Can not specify both a design and crispr');
    }

    if ( $self->poly_base_fail && $self->design ) {
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
    $self->log->info( 'Redesigning primers for ...' );

    # process the primers name sets from the config file into a hash of useful data
    $self->process_primer_name_sets;
    # check we have one or two primers, if two must be matched pair
    # also check they exist for the profile
    $self->process_primer_types;
    # grab failed primer(s), mostly one but may be name of a pair
    $self->grab_failed_primers;

    if ( $self->poly_base_fail ) {
        $self->calculate_sequence_include_regions;
        $self->log->info( 'Sequence include region: ' . p( $self->sequence_included_region ) )
    }
    else {
        $self->calculate_sequence_exclude_regions;
        $self->log->info( 'Sequence excluded regions: ' . p( $self->sequence_excluded_regions ) )
    }

    # TODO create new primers... call parent class method
    # how do I work out the method we need to call on the parent class to actually
    # create the primers:
    # - store the method name in the primer config file?
    # - store in in a hash?? ( like the PRIMER_PROJECT_CONFIG_FILES hash in the parent class )
    # - Can I work it out dynamically?
    # - ... anything else?

    #TODO mark the failed primers as rejected if they are already not marked as such

    # FOR NOW call method in run script
    return;
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
    elsif ( $count > 1 ) {
        die( "Multiple non validated primers of type $type found" );
    }
    $self->log->debug( "Found one primer of type $type" );

    $self->failed_primers->{$type} = $failed_primer_rs->first;
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
        my $primer = $self->failed_primers->{$primer_type};
        my $primer_info = $primer->as_hash;

        if ( $self->primer_sets->{ $primer_type }{ type } eq 'forward' ) {
            my $polyn_locations = $self->find_poly_base_locations(
                $primer_info->{locus}{chr_start}, # start
                $self->crispr->start,             # end
                $chromosome,                      # chromosome
            );

            $self->sequence_included_region(
                {
                    start => $polyn_locations->[-1]{end},
                    end   => $self->crispr->start,
                }
            );
        }
        elsif ( $self->primer_sets->{ $primer_type }{ type } eq 'reverse' ) {
            my $polyn_locations = $self->find_poly_base_locations(
                $self->crispr->end,               # start
                $primer_info->{locus}{chr_end},   # end
                $chromosome,                      # chromosome
            );

            $self->sequence_included_region(
                {
                    start => $self->crispr->end,
                    end   => $polyn_locations->[0]{start},
                }
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
        my $primer = $self->failed_primers->{$primer_type};
        my $primer_info = $primer->as_hash;
        push @sequence_excluded_regions, {
            start => $primer_info->{locus}{chr_start},
            end   => $primer_info->{locus}{chr_end},
        };
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

    my @poly_base_positions;
    while ( $seq =~ /([ACTG])(\1{4,})/g ) {
        # make into genomic coordinates
        push @poly_base_positions, {
            start => ( $-[0] + $start ),
            end   => ( $+[0] + $start ),
        };
    }

    unless( @poly_base_positions ) {
        die( 'Can not find polyN run of bases' );
    }

    return \@poly_base_positions;
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
