package LIMS2::Util::TraceServer;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::TraceServer::VERSION = '0.067';
}
## use critic


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
    ## no critic(RequireLocalizedPunctuationVars)
    $SIG{INT} = 'DEFAULT';
    ## use critic

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

    open my $out, '>:raw', $outfile or die "Couldn't open $outfile";
    print $out $trace_data;

    close $out;

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME

LIMS2::Util::TraceServer

=head1 DESCRIPTION

Helper module for using the TraceServer perl wrapper. TraceServer.pm must be in your perl5lib (it sits inside the oracle installation in /software for some reason)

=head1 AUTHOR

Alex Hodgkins

=cut
