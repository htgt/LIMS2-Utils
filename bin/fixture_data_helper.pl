#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use Getopt::Long;
use Log::Log4perl ':easy';
use Pod::Usage;
use LIMS2::Util::TestDatabase;

my $log_level = $INFO;
my $persist = 0;
GetOptions(
    'help'     => sub { pod2usage( -verbose    => 1 ) },
    'man'      => sub { pod2usage( -verbose    => 2 ) },
    'debug'    => sub { $log_level = $DEBUG },
    'db=s'     => \my $db_name,
    'dump=s'   => \my $dump_dir,
    'clean'    => \my $clean,
    'class=s'  => \my $class,
) or pod2usage(2);

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %m%n' } );

LOGDIE('You must specify a db name with --db' ) unless $db_name;

LOGDIE( 'You must specify one of --class, --clean or --dump' ) if !$dump_dir && !$clean && !$class;
my $test_database = LIMS2::Util::TestDatabase->new( db_name => $db_name );

if ( $clean ) {
    $test_database->model->txn_do(
        sub {
            $test_database->setup_clean_database;
        }
    );
}

if ( $class ) {
    $test_database->model->txn_do(
        sub {
            $test_database->class_specific_fixture_data( $class );
        }
    );
}

if ( $dump_dir ) {
    $test_database->dir( $dump_dir );

    $test_database->dump_fixture_data;
}


__END__

=head1 NAME

fixture_data_helper.pl - setup of test database and dumping of test data

=head1 SYNOPSIS

  fixture_data_helper.pl [options]

      --help            Display a brief help message
      --man             Display the manual page
      --debug           Debug output
      --db              Name of test database
      --clean           Run clean script to have only reference data into database
      --class           Specify class fixture data you want to load into database
      --dump            Name of directory test data will be dumped to

The LIMS2_DBCONNECT_CONFIG env variable must be pointing to a config file with the details
of the test database you are using.

To load the test data files from your working LIMS2::WebApp directory make sure it is in the
PERL5LIB env variable. e.g. export PERL5LIB=~/workspace/LIMS2-Webapp/lib:$PERL5LIB

=head1 DESCRIPTION

Interface for actions that can be carried out on a test database.

The clean option wipes all the non reference data from the test database and checks
the reference data is up to date.

The dump option dumps data from all non reference tables into csv files in the specified
directory.

The class option loads up the specified classes fixture data into the database.

=head1 BUGS

None reported... yet.

=head1 TODO

=cut
