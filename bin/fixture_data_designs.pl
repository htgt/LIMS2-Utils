#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use Getopt::Long;
use Log::Log4perl ':easy';
use Pod::Usage;
use LIMS2::Util::FixtureDataLoad::Designs;

my $log_level = $DEBUG;
my $persist = 0;
GetOptions(
    'help'     => sub { pod2usage( -verbose    => 1 ) },
    'man'      => sub { pod2usage( -verbose    => 2 ) },
    'debug'    => sub { $log_level = $DEBUG },
    'verbose'  => sub { $log_level = $INFO },
    'persist'  => \$persist,
    'design=i' => \my $design_id,
) or pod2usage(2);

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %x %m%n' } );

LOGDIE('You must specify a design with --design' ) unless $design_id;

my $design_loader = LIMS2::Util::FixtureDataLoad::Designs->new(
    source_db => 'LIMS2_LIVE',
    dest_db   => 'LIMS2_SP12',
);

$design_loader->dest_model->txn_do(
    sub {
        $design_loader->retrieve_or_create_design( $design_id );
        if ( !$persist ) {
            DEBUG('Rollback');
            $design_loader->dest_model->txn_rollback;
        }
    }
);

__END__

=head1 NAME

fixture_data_designs.pl - load one design from one database to another.

=head1 SYNOPSIS

  fixture_data_designs.pl [options]

      --help            Display a brief help message
      --man             Display the manual page
      --debug           Debug output
      --verbose         Verbose output
      --persist         Commit the new data, default is to rollback
      --design          Design ID of design you wish to transfer

=head1 DESCRIPTION

Transfer one design, plus all its associated data from one database to another.
Used to help generate fixture data for test.

=head1 BUGS

None reported... yet.

=head1 TODO

=cut
