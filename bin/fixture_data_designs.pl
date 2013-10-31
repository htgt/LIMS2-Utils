#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use Getopt::Long;
use Log::Log4perl ':easy';
use Pod::Usage;
use LIMS2::Util::FixtureDataLoad::Designs;

my $log_level = $INFO;
my $persist = 0;
my $source_db;
GetOptions(
    'help'        => sub { pod2usage( -verbose    => 1 ) },
    'man'         => sub { pod2usage( -verbose    => 2 ) },
    'debug'       => sub { $log_level = $DEBUG },
    'persist'     => \$persist,
    'design=i'    => \my $design_id,
    'source-db=s' => \$source_db,
    'dest-db=s'   => \my $dest_db,
) or pod2usage(2);

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %x %m%n' } );

LOGDIE('You must specify a design with --design' ) unless $design_id;
LOGDIE('You must specify a destination database --dest-db' ) if !$dest_db;
$source_db ||= 'LIMS2_LIVE';

my $design_loader = LIMS2::Util::FixtureDataLoad::Designs->new(
    source_db => $source_db,
    dest_db   => $dest_db,
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
      --persist         Commit the new data, default is to rollback
      --design          Design ID of design you wish to transfer
      --source-db       Name of source database, defaults to LIMS2_LIVE
      --dest-db         Name of destination database.

=head1 DESCRIPTION

Transfer one design, plus all its associated data from one database to another.
Used to help generate fixture data for test.

=head1 BUGS

None reported... yet.

=head1 TODO

=cut
