package LIMS2::Util::TraceServer;

use strict;
use warnings;

use Moose;

use TraceServer;
use Try::Tiny;
use File::Temp;

use Log::Log4perl qw(:easy);

with "MooseX::Log::Log4perl";

BEGIN {
    #try not to override the lims2 logger
    unless ( Log::Log4perl->initialized ) {
        Log::Log4perl->easy_init( { level => $DEBUG } );
    }
}

has traceserver => (
    is => 'ro',
    isa => 'TraceServer',
    lazy_build => 1,
);

sub _build_traceserver {
    my $self = shift;

    my $ts;
    try {
        $ts = TraceServer->new
    }
    catch {
        die "Could not load TraceServer: $_";
    };

    #oracle stuff breaks the sig int handler, reset it here
    $SIG{INT} = 'DEFAULT';

    return $ts;
}

has format => (
    is      => 'rw',
    isa     => 'Str',
    default => sub { 'SCF' },
);

=item get_trace

Given a trace name return the binary SCF data in a string

=cut
sub get_trace {
    my ( $self, $name ) = @_;

    return $self->_get_trace( $name )->get_data( $self->format );
}

=item _get_trace

Get a TraceServer::Trace object given a read name

=cut
sub _get_trace {
    my ( $self, $name ) = @_;

    die "read $name doesn't exist" unless $self->traceserver->read_exists( $name );

    my $read = $self->traceserver->get_read_by_name( $name );
    my $trace = $read->get_trace;

    return $trace;
}

sub write_temp_file {
    my ( $self, $trace_data ) = @_;

    my $fh = File::Temp->new;
    binmode( $fh, ":raw" );

    print $fh $trace_data;

    #return to start of the file
    seek $fh, 0, 0 or die "Seek failed: $!";

    return $fh;
}

sub print_trace {
    my ( $self, $outfile,  $trace_data ) = @_;

    open my $out, '>:raw', $outfile;
    print $out $trace_data;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME

LIMS2::Util::TraceServer

=head1 DESCRIPTION

Helper module for submitting errbit errors from catalyst. If an error occurs it will be added
to the errors arrayref passed to submit_errors.

You must set the LIMS2_ERRBIT_CONFIG to a config file.

=head1 SYNOPSIS

  use LIMS2::Util::Errbit;

  #then within a catalyst method:

  my $errbit = LIMS2::Util::Errbit->new_with_config;

  #make a copy of the errors as we modify them
  my @errors = @{ $c->error };

  try {
    #requires catalyst object and list of errors.
    $errbit->submit_errors( $c, \@errors );
  }
  catch {
    $c->log->error( @_ );
  };

=head1 AUTHOR

Alex Hodgkins

=cut
