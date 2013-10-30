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
    'dir=s'    => \my $dir_name,
    'clean'    => \my $clean,
) or pod2usage(2);

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %m%n' } );

LOGDIE('You must specify a db name with --db' ) unless $db_name;

if ( $clean ) {
    my $test_database = LIMS2::Util::TestDatabase->new( db_name => $db_name );

    $test_database->model->txn_do(
        sub {
            $test_database->setup_clean_database;
        }
    );
}
else {
    LOGDIE('You must specify a directory name with --dir' ) unless $dir_name;

    my $test_database = LIMS2::Util::TestDatabase->new(
        db_name => $db_name,
        dir     => $dir_name,
    );

    $test_database->dump_fixture_data;
}


__END__

=head1 NAME

test_database.pl - setup of test database and dumping of test data

=head1 SYNOPSIS

  test_database.pl [options]

      --help            Display a brief help message
      --man             Display the manual page
      --debug           Debug output
      --db              Name of test database
      --dir             Name of dir test data will be dumped to
      --clean           Run clean script to have only reference data into database

=head1 DESCRIPTION

Interface to 2 actions that can be carried out on a test database.

Dump data from all non reference tables into csv files.

The clean option wipes all the non reference data from the test database and checks
the reference data is up to date.

=head1 BUGS

None reported... yet.

=head1 TODO

=cut
