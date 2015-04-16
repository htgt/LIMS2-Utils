#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use LIMS2::Util::QcPrimers::Redesign;
use LIMS2::Model::Util::Crisprs qw( gene_ids_for_crispr );
use LIMS2::Model;
use Getopt::Long;
use Log::Log4perl ':easy';
use Path::Class;
use Pod::Usage;
use Try::Tiny;
use YAML::Any;
use Text::CSV;
use IO::Handle;

my $log_level = $WARN;
my $persist = 0;
my ( $dir_name, @failed_primer_types, $crispr_id, $crispr_pair_id, $crispr_group_id, $design_id, $redesign_file, $project_name, $poly );
GetOptions(
    'help'                 => sub { pod2usage( -verbose    => 1 ) },
    'man'                  => sub { pod2usage( -verbose    => 2 ) },
    'debug'                => sub { $log_level = $DEBUG },
    'verbose'              => sub { $log_level = $INFO },
    'dir=s'                => \$dir_name,
    'failed-primer-type=s' => \@failed_primer_types,
    'crispr-id=i'          => \$crispr_id,
    'crispr-pair-id=i'     => \$crispr_pair_id,
    'crispr-group-id=s'    => \$crispr_group_id,
    'design-id=i'          => \$design_id,
    'redesign-file=s'      => \$redesign_file,
    'persist-primers'      => \$persist,
    'project-name=s'       => \$project_name,
    'poly=s'               => \$poly,
) or pod2usage(2);

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %m%n' } );

pod2usage('Must specify a work dir --dir') unless $dir_name;

my $base_dir = dir( $dir_name )->absolute;
$base_dir->mkpath;
my $model = LIMS2::Model->new( user => 'tasks' );
my $gene_finder =  sub { $model->find_genes( @_ ) };

my @TARGET_COLUMN_HEADERS = qw(
gene_id
gene_name
species
crispr_id
crispr_pair_id
crispr_group_id
design_id
redesign_primer_fail
chromosome
redesign_primers
primer_project_name
poly_base_type
forward_primer_name
forward_primer_seq
forward_primer_length
forward_primer_gc_content
forward_primer_tm
forward_primer_start
forward_primer_end
reverse_primer_name
reverse_primer_seq
reverse_primer_length
reverse_primer_gc_content
reverse_primer_tm
reverse_primer_start
reverse_primer_end
);

my $output = IO::Handle->new_from_fd( \*STDOUT, 'w' );
my $target_output_csv = Text::CSV->new( { eol => "\n" } );
$target_output_csv->print( $output, \@TARGET_COLUMN_HEADERS );

if ( $redesign_file ) {
    process_redesign_file( $redesign_file );
    exit;
}
else {
    pod2usage('Must specify a project --project-name') unless $project_name;
    pod2usage('Must specify a project --failed-primer-type') unless @failed_primer_types;
    my %params = (
        base_dir            => $base_dir,
        model               => $model,
        persist_primers     => $persist,
        primer_project_name => $project_name,
        primer_types        => \@failed_primer_types,
    );
    $params{poly_base_type} = $poly if $poly;

    ## no critic(ControlStructures::ProhibitCascadingIfElse)
    if ( $crispr_id ) {
        $params{crispr} = $model->retrieve_crispr( { id => $crispr_id } );
        $params{target_type} = 'crispr';
    }
    elsif ( $crispr_pair_id ) {
        $params{crispr} = $model->retrieve_crispr_pair( { id => $crispr_pair_id } );
        $params{target_type} = 'crispr_pair';
    }
    elsif ( $crispr_group_id ) {
        $params{crispr} = $model->retrieve_crispr_group( { id => $crispr_group_id } );
        $params{target_type} = 'crispr_group';
    }
    elsif ( $design_id ) {
        $params{design} = $model->retrieve_design( { id => $design_id } );
        $params{target_type} = 'design';
    }
    else {
        pod2usage( 'Provide crispr id or design id or data file' );
    }
    ## use critic

    redesign_primer( \%params );
}

sub redesign_primer {
    my ( $params, $gene_name ) = @_;
    my $primer_util = LIMS2::Util::QcPrimers::Redesign->new( %{ $params } );
    my ( $primer_data, $seq ) = $primer_util->redesign_primers;
    my $picked_primers = $primer_data->[0];
    dump_output( $picked_primers, $params, $gene_name, $primer_util );
    return;
}

## no critic(InputOutput::RequireBriefOpen)
sub process_redesign_file {
    my ( $file_name ) = @_;

    my %common_params = (
        base_dir            => $base_dir,
        model               => $model,
        persist_primers     => $persist,
    );

    my $input_csv = Text::CSV->new();
    open ( my $input_fh, '<', $file_name ) or die( "Can not open $file_name " . $! );
    $input_csv->column_names( @{ $input_csv->getline( $input_fh ) } );

    while ( my $data = $input_csv->getline_hr( $input_fh ) ) {
        my %params = %common_params;

        $params{poly_base_type} = $data->{poly} if $data->{poly};
        $params{primer_types} = [ split( /,/, $data->{failed_primer_types} ) ];
        $params{primer_project_name} = $data->{primer_project_name};
        ## no critic(ControlStructures::ProhibitCascadingIfElse)
        if ( $data->{crispr_id} ) {
            $params{crispr} = $model->retrieve_crispr( { id => $data->{crispr_id} } );
            $params{target_type} = 'crispr';
        }
        elsif ( $data->{crispr_pair_id} ) {
            $params{crispr} = $model->retrieve_crispr_pair( { id => $data->{crispr_pair_id} } );
            $params{target_type} = 'crispr_pair';
        }
        elsif ( $data->{crispr_group_id} ) {
            $params{crispr} = $model->retrieve_crispr_group( { id => $data->{crispr_group_id} } );
            $params{target_type} = 'crispr_group';
        }
        elsif ( $data->{design_id} ) {
            $params{design} = $model->retrieve_design( { id => $data->{design_id} } );
            $params{target_type} = 'design';
        }
        else {
            die( 'No design or crispr in csv file' );
        }
        ## use critic
        redesign_primer( \%params, $data->{gene_name} );
    }
    return;
}
## use critic


=head2 dump_output

Write out the generated primers plus other useful information in YAML format.

=cut
sub dump_output {
    my ( $picked_primers, $params, $gene_name, $primer_util ) = @_;

    my %output_data;
    unless ( $picked_primers ) {
        $output_data{redesign_primer_fail} = 'yes';
    }
    $output_data{redesign_primers}    = join( '|', @{ $params->{primer_types} });
    $output_data{primer_project_name} = $params->{primer_project_name};
    $output_data{poly_base_type}      = $params->{poly_base_type};
    $output_data{gene_name}           = $gene_name;

    if ( my $crispr = $params->{crispr} ) {
        my $gene_ids = gene_ids_for_crispr( $gene_finder, $crispr );
        my $target_type = $params->{target_type};
        $output_data{ $target_type . '_id'} = $crispr->id;
        $output_data{gene_id}   = join( '|', @{ $gene_ids } );
        $output_data{species}   = $crispr->species_id;
        $output_data{chromosome} = $crispr->chr_name;
    }
    else {
        my $di = $params->{design}->info;
        $output_data{design_id} = $di->design->id;
        $output_data{gene_id}   = $di->target_gene->stable_id;
        $output_data{chromosome} = $di->chr_name;
        $output_data{species}   = $params->{design}->species_id;
    }

    my $primer_names = $primer_util->primer_name_sets->[0];
    for my $direction ( qw( forward reverse ) ) {
        next unless exists $picked_primers->{$direction};
        $output_data{ $direction . '_primer_name' } = $primer_names->{$direction};
        $output_data{ $direction . '_primer_seq' } = $picked_primers->{$direction}{oligo_seq};
        $output_data{ $direction . '_primer_length' } = $picked_primers->{$direction}{oligo_length};
        $output_data{ $direction . '_primer_gc_content' } = $picked_primers->{$direction}{gc_content};
        $output_data{ $direction . '_primer_tm' } = $picked_primers->{$direction}{melting_temp};
        $output_data{ $direction . '_primer_start' } = $picked_primers->{$direction}{oligo_start};
        $output_data{ $direction . '_primer_end' } = $picked_primers->{$direction}{oligo_end};
    }

    $target_output_csv->print( $output, [ @output_data{ @TARGET_COLUMN_HEADERS } ] );
    return;
}

__END__

=head1 NAME

redesign_primers.pl - redesign failed primers for crisprs or designs

=head1 SYNOPSIS

  redesign_primers.pl [options]
      --help                      Display a brief help message
      --man                       Display the manual page
      --debug                     Debug output
      --verbose                   Verbose output
      --dir                       Name of work directory
      --failed-primer-types       Name of failed primers ( can specify up to 2 )
      --crispr-group-id           ID of crispr group
      --crispr-pair-id            ID of crispr pair
      --crispr-id                 ID of single crispr
      --design-id                 Design ID
      --redesign-file             File with primer redesign details
      --persist-primers           Persist the generated primers to LIMS2
      --project-name              Name of project we are generating primers for
      --poly                      Is primer being redesign because of PolyN bases

By default the primers will not be persisted to LIMS2.

=head1 DESCRIPTION

Redesign failing primers for crisprs or designs, marked the failed primers as rejected
and stores the new primers in LIMS2.

Currently the valid primer project names are:

=over

=item mgp_recovery

=item short_arm_vectors

=item crispr_pcr

=item crispr_sequencing

=item design_genotyping

=back

=cut
