#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use Getopt::Long;
use Log::Log4perl ':easy';
use Pod::Usage;
use LIMS2::Util::FixtureDataLoad::Bacs;

my $log_level = $DEBUG;
my $persist = 0;
GetOptions(
    'help'     => sub { pod2usage( -verbose    => 1 ) },
    'man'      => sub { pod2usage( -verbose    => 2 ) },
    'debug'    => sub { $log_level = $DEBUG },
    'verbose'  => sub { $log_level = $INFO },
    'persist'  => \$persist,
    'bac=s'    => \my $bac_name,
) or pod2usage(2);

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %x %m%n' } );

LOGDIE('You must specify a bac with --bac' ) unless $bac_name;

my $bac_loader = LIMS2::Util::FixtureDataLoad::Bacs->new(
    source_db => 'LIMS2_LIVE',
    dest_db   => 'LIMS2_SP12',
);

$bac_loader->dest_model->txn_do(
    sub {
        $bac_loader->retrieve_or_create_bac( $bac_name );
        if ( !$persist ) {
            DEBUG('Rollback');
            $bac_loader->dest_model->txn_rollback;
        }
    }
);

__END__

=head1 NAME

fixture_data_bacs.pl - load one bac from one database to another.

=head1 SYNOPSIS

  fixture_data_designs.pl [options]

      --help            Display a brief help message
      --man             Display the manual page
      --debug           Debug output
      --verbose         Verbose output
      --persist         Commit the new data, default is to rollback
      --bac             Bac Name of bac you wish to transfer

=head1 DESCRIPTION

Transfer one bac, plus all its associated data from one database to another.
Used to help generate fixture data for test.

=head1 BUGS

None reported... yet.

=head1 TODO

=cut
