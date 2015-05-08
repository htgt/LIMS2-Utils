#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use LIMS2::Util::TraceServer;
use IO::File;

my $trace_name = $ARGV[0];
die ( 'Must provide trace name' ) unless $trace_name;

my $trace_server = LIMS2::Util::TraceServer->new;
my $trace = $trace_server->get_trace( $trace_name );

my $trace_fh = IO::File->new( $trace_name . '.scf', "w" );
print $trace_fh $trace;

__END__

=head1 NAME

get_trace.pl - Download trace file from Trace Server

=head1 SYNOPSIS

  fixture_data_designs.pl [read name]

=head1 DESCRIPTION

Downloads a scf file for given read name.

=cut
