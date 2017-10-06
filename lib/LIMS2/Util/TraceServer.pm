package LIMS2::Util::TraceServer;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::TraceServer::VERSION = '0.082';
}
## use critic


use strict;
use warnings;

use Moose;

use Try::Tiny;
use File::Temp;
use LWP::UserAgent;
use Path::Class;

use Log::Log4perl qw(:easy);

with "MooseX::Log::Log4perl";

BEGIN {
    #try not to override the lims2 logger
    unless ( Log::Log4perl->initialized ) {
        Log::Log4perl->easy_init( { level => $DEBUG } );
    }
}

has fileserver_uri => (
    is => 'ro',
    isa => 'Str',
    lazy_build => 1,
);

sub _build_fileserver_uri {
    my $uri = $ENV{FILE_API_URL}
        or die "FILE_API_URL environment variable not set";
    return $uri;
}

has lims2_seq_dir => (
    is => 'ro',
    isa => 'Path::Class::Dir',
    lazy_build => 1,
);

sub _build_lims2_seq_dir {
    my $dir = dir( $ENV{LIMS2_SEQ_FILE_DIR} )
        or die "LIMS2_SEQ_FILE_DIR environment variable not set or not a directory";
    return $dir;
}

has traceserver_uri => (
    is => 'ro',
    isa => 'Str',
    lazy_build => 1,
);

sub _build_traceserver_uri {
    my $uri = $ENV{TRACE_SERVER_URI} || 'http://si-trace-web.internal.sanger.ac.uk:8888/';
    return $uri;
}

has user_agent => (
    is => 'ro',
    isa => 'LWP::UserAgent',
    default => sub { LWP::UserAgent->new() },
);

has format => (
    is      => 'rw',
    isa     => 'Str',
    default => sub { 'SCF' },
);

=item get_trace

Given a trace name return the binary SCF data in a string

=cut
sub get_trace {
    my ( $self, $name, $version ) = @_;

    my ($project_name) = ( $name =~ /^(\w*)[a-zA-Z]\d\d\..*/g );
    $project_name =~ s/_\d$//g;

    my $data_dir = $self->lims2_seq_dir->subdir($project_name);
    if($version){
        $data_dir = $data_dir->subdir($version);
    }
    my $scf_path = $data_dir->file($name.".scf")->stringify;

    my $lims2_scf_uri = $self->fileserver_uri.$scf_path;
    $self->log->debug("getting trace from uri $lims2_scf_uri");
    my $fileserver_response = $self->user_agent->get($lims2_scf_uri);
    if($fileserver_response->is_success){
        return $fileserver_response->content;
    }
    else{
        $self->log->debug("could not get scf from $lims2_scf_uri. trying traceserver");
    }

    my $uri = $self->traceserver_uri."get_trace/$name.scf";
    $self->log->debug("getting trace from $uri");
    my $response = $self->user_agent->get($uri);

    if($response->is_success){
        return $response->content;
    }

    die "Could not get trace for read $name from $uri - ".$response->status_line;
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

Helper module for retrieving traces from Sanger's Internal Trace Server http server

=head1 AUTHOR

Alex Hodgkins, Anna Farne

=cut
