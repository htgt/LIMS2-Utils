package LIMS2::Util::Errbit;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::Errbit::VERSION = '0.063';
}
## use critic


use strict;
use warnings;

use Moose;
use MooseX::Types::URI qw( Uri );

use HTTP::Request;
use LWP::UserAgent;
use Template;

use Log::Log4perl qw(:easy);

with qw( MooseX::SimpleConfig MooseX::Log::Log4perl );
#with "MooseX::Log::Log4perl";

BEGIN {
    #try not to override the lims2 logger
    unless ( Log::Log4perl->initialized ) {
        Log::Log4perl->easy_init( { level => $DEBUG } );
    }
}

has '+configfile' => ( default => $ENV{ LIMS2_ERRBIT_CONFIG } );

has url => (
    is       => 'ro',
    isa      => Uri,
    coerce   => 1,
    required => 1,
);

has api_key => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has user_agent => (
    is       => 'ro',
    isa      => 'LWP::UserAgent',
    default  => sub { LWP::UserAgent->new },
    required => 1,
);

has model => (
    is      => 'rw',
    isa     => 'Str',
    default => 'Golgi'
);

has xml_template => (
    is         => 'rw',
    isa        => 'Str',
    builder    => '_build_xml_template'
);

#template toolkit instance
has tt => (
    is => 'ro',
    isa => 'Template',
    default => sub { Template->new(PRE_CHOMP  => 1) || die Template->error(), "\n"; }
);

#used in place of real data if we can't extract the data
has unknown_line => (
    traits   => [ 'Hash' ],
    is       => 'ro',
    isa      => 'HashRef',
    default  => sub { return { method => "unknown", file => "unknown" } }
);

#if an error doesn't start with Caught exception then we'll skip it.
#this is because in lims2 any validation errors cause an internal server error 
has skip_unknown_errors => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1
);

=item _build_xml_template

Returns an xml string intended to be processed by template toolkit

=cut
sub _build_xml_template {
    my ( $self ) = @_;

    #template toolkit xml data
    #you can see all the valid fields here: http://help.airbrake.io/kb/api-2/notifier-api-version-23
    return <<'END';
<?xml version="1.0" encoding="UTF-8"?>
<notice version="2.3">
  <api-key>[% api_key FILTER xml %]</api-key>
  <notifier>
    <name>Airbrake Notifier</name>
    <version>3.1.6</version>
    <url>http://api.airbrake.io</url>
  </notifier>
  <error>
    <class>Exception</class>
    <message>[% message FILTER xml %]</message>
    <backtrace>
    [% FOR line IN backtrace %]
      <line method="[% line.method FILTER xml %]" file="[% line.file FILTER xml %]" number="[% line.number FILTER xml %]" />
    [% END %]
    </backtrace>
  </error>
  <request>
    <url>[% url FILTER xml %]</url>
    <component>[% class FILTER xml %]</component>
    <action>[% method FILTER xml %]</action>
    <cgi-data>
      <var key="FULL_ERROR">[% full_error FILTER xml %]</var>
    [% FOR pair IN request.pairs  %]
      <var key="[% pair.key FILTER xml %]">[% pair.value FILTER xml %]</var>
    [% END %]
    </cgi-data>
  </request>
  <server-environment>
    <environment-name>[% db FILTER xml %]</environment-name>
    <app-version>[% version FILTER xml %]</app-version>
  </server-environment>
</notice>
END
}

=item submit_errors

Given a catalyst object and an arrayref of errors this method processes them and submits an 
individual errbit error for each one. Adds any submission errors to the arrayref of errors.

Always returns undef.

=cut
sub submit_errors {
    my ( $self, $c, $errors ) = @_;

    confess "Catalyst object must be provided" unless $c;

    #allow a non array ref
    unless ( ref $errors eq 'ARRAY' ) {
        $self->log->warn( 'submit_errors expects an arrayref, attempting to force' );
        $errors = [ $errors ];
    }

    my @failed_responses;

    #one request per error
    for my $error ( @{ $errors } ) {
        $self->log->debug( "Processing $error" );

        #skip errors that don't look valid if the option is set
        if ( $self->skip_unknown_errors && $error !~ /^Caught exception/ ) {
            $self->log->warn( "$error is not a valid exception, skipping." );
            next;
        }

        my $data = $self->process_error( $error );

        #set the errbit parameters unrelated to the error
        $data->{api_key} = $self->api_key;
        $data->{url}     = $c->req->uri->as_string;
        $data->{version} = $c->model($self->model)->software_version;
        $data->{db}      = $c->model($self->model)->database_name;
        $data->{request} = $self->_req_as_hash( $c->req );

        #put the variables into our xml template
        my $processed_xml;
        $self->tt->process( \($self->xml_template), $data, \$processed_xml );

        #$self->log->error( $processed_xml ) && die;

        my $response = $self->_submit_request( $processed_xml );

        #we'll add the failed responses to errors after we've finished looping it
        push @failed_responses, $response unless $response->is_success;
    }

    #add any failures to errors arrayref so the calling application can display it
    for my $res ( @failed_responses ) {
        push @{$errors}, "Errbit request not successful: " . $res->status_line
                       . "<br/>" . $res->as_string;
    }

    return;
}

=item submit_request

Takes a processed xml string and sends it to the url set in $self->url.
Returns the response from the request

=cut
sub _submit_request {
    my ( $self, $xml ) = @_;

    $self->log->debug( "Sending request to " . $self->url );

    #create a http request object with the xml
    my $req = HTTP::Request->new( POST => $self->url );
    $req->content_type( 'application/xml' );
    $req->content( $xml );

    #now post it
    my $response = $self->user_agent->request( $req );

    $self->log->debug( "Response: " . $response->status_line );
    $self->log->debug( $response->as_string ) unless $response->is_success;

    return $response;
}

=item process_error

Top level function to process an error (as a string) into a hash.
Returns a hashref of all information it extracted

=cut
sub process_error {
    my ( $self, $error ) = @_;

    my @error_lines = split "\n", $error; #terrible name

    #first line is always the die output, even if there's no stack trace.
    my $data = $self->_process_exception_line( shift @error_lines );

    #if there's anything else in the list it will be the stack trace lines, so process accordingly
    #by adding all the supplementary trace data to the backtrace list
    push @{ $data->{backtrace} }, $self->_process_trace( \@error_lines );

    return $data;
}

=item _process_exception_line

Converts the first line of a perl die from within catalyst into a hash with calling method and line number.
Returns a hashref.

Error line looks like:
Caught exception in LIMS2::WebApp::Controller::User::QC->index "ERROR MSG" at /LIMS2/WebApp/Controller/User/QC.pm line 53.

=cut
sub _process_exception_line {
    my ( $self, $error ) = @_;

    #we store backtrace data as a list of lines
    my @backtrace;

    my $data = {
        full_error => $error,
        backtrace => \@backtrace, #we populate this below
    };

    #looks like this:
    #Caught exception in LIMS2::WebApp::Controller::User::QC->index "ERROR MSG 
    #at /opt/t87/global/software/LIMS2/WebApp/Controller/User/QC.pm line 53.
    ##no critic (ProhibitComplexRegexes)
    #if this regex changes you will also need to change the next statement in submit errors
    if ( $error =~ /^Caught exception in ([^\s]+)->([^\s]+) "(.+?) at ([^\s]+) line (\d+)/ ) {
        #there are more here than we actually use in case we need them later
        my ( $class, $method, $message, $file, $line ) = ( $1, $2, $3, $4, $5 );

        #add all the data we found.
        $data->{ message } = $message;
        $data->{ class }   = $class;
        $data->{ method }  = $method;

        #add a backtrace entry. this is a list of hashrefs that we convert to xml later
        push @backtrace, {
            method => $method,
            file   => $file,
            number => $line,
        };
    }
    else {
        #backtrace and line are required by errbit, so we have to just put rubbish data in
        $self->log->warn( "Couldn't extract information from $error" );
        push @backtrace, $self->unknown_line;
        $data->{ message } = $error; #we don't know what it is so display whole error
    }
    ##use critic

    return $data;
}

=item _process_trace

Converts the stack trace (if any) provided by a confess() statement into individual method calls. 
Returns an array (not arrayref, see process_error for usage) of hashrefs.

Stacktrace lines look like:
    LIMS2::QC::index('LIMS2::WebApp=HASH(0x7e1da28)') called at /opt/Catalyst/Action.pm line 65

=cut
sub _process_trace {
    my ( $self, $lines ) = @_;

    my @backtrace;

    for my $line ( @{ $lines } ) {
        #    LIMS2::QC::index('LIMS2::WebApp=HASH(0x7e1da28)') called at /opt/Catalyst/Action.pm line 65
        if( $line =~ /^\s+(.+?) called at ([^\s]+) line (\d+)/ ) {
            push @backtrace, {
                method => $1,
                file   => $2,
                number => $3,
            }
        }
        else {
            $self->log->warn( "Couldn't extract information from $line" );
            push @backtrace, $self->unknown_line;
        }
    }

    #return as an array so we can easily merge into the main hash
    return @backtrace;
}

=item _req_as_hash

Convert a catalyst request object into a hash with just the fields we're interested in.
Returns a hashref 

=cut
sub _req_as_hash {
    my ( $self, $req ) = @_;

    return {
        "IP_ADDRESS"  => $req->address,
        "URI_BASE"    => $req->base,
        "CLIENT_NAME" => $req->hostname,
        "REMOTE_HOST" => $req->uri->host,
        "METHOD"      => $req->method,
        "PATH"        => $req->path,
        "REFERER"     => $req->referer || '-',
        "HTTP_USER_AGENT" => $req->user_agent || '-',
        "ARGS"        => join(", ", @{$req->args}) || '-',
        "PARAMS"      => join(", ", map { "$_ => " . $req->parameters->{$_} } keys %{$req->parameters}) || '-',
    };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME

LIMS2::Util::Errbit

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