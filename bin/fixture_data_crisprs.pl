#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use Getopt::Long;
use Log::Log4perl ':easy';
use Pod::Usage;
use LIMS2::Util::FixtureDataLoad::Crisprs;

my $log_level = $DEBUG;
my $persist = 0;
GetOptions(
    'help'          => sub { pod2usage( -verbose    => 1 ) },
    'man'           => sub { pod2usage( -verbose    => 2 ) },
    'debug'         => sub { $log_level = $DEBUG },
    'verbose'       => sub { $log_level = $INFO },
    'persist'       => \$persist,
    'crispr=i'      => \my $crispr_id,
    'crispr_pair=i' => \my $crispr_pair_id,
) or pod2usage(2);

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %x %m%n' } );

LOGDIE('You must specify a crispr or crispr pair' ) if !$crispr_id && !$crispr_pair_id;

my $crispr_loader = LIMS2::Util::FixtureDataLoad::Crisprs->new(
    source_db => 'LIMS2_LIVE',
    dest_db   => 'LIMS2_SP12',
    persist   => $persist,
);

if ( $crispr_id ) {
    $crispr_loader->retrieve_or_create_crispr( $crispr_id );
}

if ( $crispr_pair_id ) {
    $crispr_loader->retrieve_or_create_crispr_pair( $crispr_pair_id );
}

__END__

=head1 NAME

fixture_data_crisprs.pl - load one crispr from one database to another.

=head1 SYNOPSIS

  fixture_data_crisprs.pl [options]

      --help            Display a brief help message
      --man             Display the manual page
      --debug           Debug output
      --verbose         Verbose output
      --persist         Commit the new data, default is to rollback
      --crispr          Crispr ID of crispr you wish to transfer
      --crispr_pair     Crispr Pair ID of crispr_pair you wish to transfer

=head1 DESCRIPTION

Transfer one crispr, plus all its associated data from one database to another.
Used to help generate fixture data for test.

=head1 BUGS

None reported... yet.

=head1 TODO

=cut
