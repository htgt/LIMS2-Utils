#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use LIMS2::Util::QcPrimers;
use LIMS2::Model;
use Getopt::Long;
use Log::Log4perl ':easy';
use Path::Class;
use Pod::Usage;
use Try::Tiny;
use Perl6::Slurp;
use YAML::Any;

my $log_level = $WARN;
my $persist = 0;
my ( $dir_name, $crispr_group_id, $crispr_group_file, $project_name );
GetOptions(
    'help'                => sub { pod2usage( -verbose => 1 ) },
    'man'                 => sub { pod2usage( -verbose => 2 ) },
    'debug'               => sub { $log_level = $DEBUG },
    'verbose'             => sub { $log_level = $INFO },
    'dir=s'               => \$dir_name,
    'crispr-group-id=i'   => \$crispr_group_id,
    'crispr-group-file=s' => \$crispr_group_file,
    'persist-primers'     => \$persist,
    'project-name=s'      => \$project_name,
) or pod2usage(2);

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %x %m%n' } );

pod2usage('Must specify a project --project-name') unless $project_name;
pod2usage('Must specify a work dir --dir') unless $dir_name;

my $base_dir = dir( $dir_name )->absolute;
$base_dir->mkpath;
my $model = LIMS2::Model->new( user => 'tasks' );

my $primer_util = LIMS2::Util::QcPrimers->new(
    base_dir            => $base_dir,
    model               => $model,
    persist_primers     => $persist,
    primer_project_name => $project_name,
);

my @crispr_group_ids;
if ( $crispr_group_id ) {
    push @crispr_group_ids, $crispr_group_id;
}
elsif ( $crispr_group_file ) {
    @crispr_group_ids = slurp $crispr_group_file, { chomp => 1 };
}
else {
    pod2usage( 'Provide crispr group ids, --crispr-group-id or -crispr-group-file' );
}

my @failed;
for my $id ( @crispr_group_ids ) {
    Log::Log4perl::NDC->remove;
    Log::Log4perl::NDC->push( $id );

    my $crispr_group = try{ $model->retrieve_crispr_group( { id => $id } ) };
    die( "Unable to find crispr group with id $id" )
        unless $crispr_group;

    # Primer util returns primer_data arrayref and Bio::Seq object
    my ( $primer_data, $seq ) = $primer_util->crispr_group_genotyping_primers( $crispr_group );
    my $picked_primers = $primer_data->[0];

    dump_output( $picked_primers, $seq, $crispr_group );

    push @failed, $id unless $picked_primers;
}

print Dump( { failed => \@failed } );

=head2 dump_output

Write out the generated primers plus other useful information in YAML format.

=cut
sub dump_output {
    my ( $picked_primers, $seq, $crispr_group  ) = @_;

    unless ( $picked_primers ) {
        $picked_primers = { no_primers => 1 };
    }

    $picked_primers->{crispr_group_id}    = $crispr_group->id;
    $picked_primers->{gene_id}            = $crispr_group->gene_id;
    $picked_primers->{chromosome}         = $crispr_group->chr_name;
    $picked_primers->{species}            = $crispr_group->species;
    $picked_primers->{crispr_group_start} = $crispr_group->start;
    $picked_primers->{crispr_group_end}   = $crispr_group->end;

    my $count = 1;
    for my $cp ( @{ $crispr_group->ranked_crisprs } ) {
        $picked_primers->{'crispr_' . $count . '_start'} = $cp->start;
        $picked_primers->{'crispr_' . $count . '_end'}   = $cp->end;
        $picked_primers->{'crispr_' . $count . '_seq'}   = $cp->seq;
        $count++;
    }

    $picked_primers->{search_seq} = $seq->seq if $seq;

    print Dump( $picked_primers );

    return;
}


__END__

=head1 NAME

generate_crispr_group_genotyping_primers.pl - Generate genotyping primers for crispr groups

=head1 SYNOPSIS

  generate_crispr_group_genotyping_primers.pl [options]

      --help                      Display a brief help message
      --man                       Display the manual page
      --debug                     Debug output
      --verbose                   Verbose output
      --dir                       Name of work directory
      --crispr-group-id           ID of crispr group
      --crispr-group-file         File with multiple crispr group ids
      --persist-primers           Persist the generated primers to LIMS2
      --project-name              Name of project we are generating primers for

Specify a project name, currently following values are accepted: mgp_recovery, short_arm_vectors

Crispr group IDs can either be specified individually or in a text file with one ID per line.

Provide a directory name where the output files will be stored.

By default the primers will not be persisted to LIMS2.

=head1 DESCRIPTION

Generate genotyping primers for crispr groups, which can be involved in the following projects:

=over

=item mgp_recovery

=item short_arm_vectors

=back

=cut
