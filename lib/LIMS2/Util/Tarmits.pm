package LIMS2::Util::Tarmits;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::Tarmits::VERSION = '0.050';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Moose;
use Moose::Util::TypeConstraints;
use LWP::UserAgent;
use namespace::autoclean;
use JSON;
use Readonly;
require URI;

use Log::Log4perl qw(:easy);

#
# Note:
#   this module is duplicated in svn at:
#   htgt-utils-targrep/trunk/lib/HTGT/Utils/Tarmits.pm
#

with qw( MooseX::SimpleConfig MooseX::Log::Log4perl );

BEGIN {
    unless ( Log::Log4perl->initialized ) {
        Log::Log4perl->easy_init( { level => $DEBUG } );
    }
}

#we have to make a subtype instead of just using URI as it has no coercions.
subtype 'LIMS2::Util::Tarmits::URI' => as class_type('URI');
coerce 'LIMS2::Util::Tarmits::URI' => from 'Str' => via { URI->new($_) };

#this is for new_with_config and comes from MooseX::SimpleConfig
has '+configfile' => ( default => $ENV{LIMS2_TARMITS_CLIENT_CONFIG} );

has 'base_url' => (
    is       => 'ro',
    isa      => 'LIMS2::Util::Tarmits::URI',
    coerce   => 1,
    required => 1
);

has 'proxy_url' => (
    is     => 'ro',
    isa    => 'LIMS2::Util::Tarmits::URI',
    coerce => 1
);

has [ qw( username password ) ] => (
    is       => 'ro',
    isa      => 'Str',
    required => 1
);

has 'realm' => (
    is      => 'ro',
    isa     => 'Str',
    default => 'iMits'
);

has 'ua' => (
    is         => 'ro',
    isa        => 'LWP::UserAgent',
    lazy_build => 1
);

sub _build_ua {
    my $self = shift;

    # Set proxy
    my $ua = LWP::UserAgent->new();
    $ua->proxy( http => $self->proxy_url )
        if defined $self->proxy_url;

    # Set credentials
    if ( $self->username ) {
        $ua->credentials( $self->base_url->host_port, $self->realm, $self->username, $self->password );
    }

    return $ua;
}

#
#   Private methods
#
sub uri_for {
    my ( $self, $path, $params, $targ_rep ) = @_;
    my $uri;

    if ( $targ_rep ) {
        $uri = URI->new_abs( 'targ_rep/' . $path, $self->base_url );
    }
    else {
        $uri = URI->new_abs( $path, $self->base_url );
    }

    if ($params) {
        $uri->query_form($params);
    }

    return $uri;
}

sub request {
    my ( $self, $method, $rel_url, $data, $targ_rep ) = @_;

    my ( $uri, $request );

    if ( $method eq 'GET' or $method eq 'DELETE' ) {
        $uri = $self->uri_for( $rel_url, $data, $targ_rep );
        $request = HTTP::Request->new( $method, $uri, [ content_type => 'application/json' ] );
    }
    elsif ( $method eq 'PUT' or $method eq 'POST' ) {
        $uri = $self->uri_for($rel_url, undef, $targ_rep );
        $request = HTTP::Request->new( $method, $uri, [ content_type => 'application/json' ], to_json($data) );
    }
    else {
        confess "Method $method unknown when requesting URL $uri";
    }

    $self->log->debug("$method request for $uri");
    if ( $data ) {
        $self->log->debug( sub { "Request data: " . to_json( $data ) } );
    }
    my $response = $self->ua->request($request);
    if ( $response->is_success ) {
        # DELETE method does not return JSON.
        return $method eq 'DELETE' ? 1 : from_json( $response->content );
    }

    my $err_msg = "$method $uri: " . $response->status_line;

    if ( my $content = $response->content ) {
        $err_msg .= "\n $content";
    }

    confess $err_msg;
}

{
    my $meta = __PACKAGE__->meta;
    my $targ_rep = 1;

    foreach my $key ( qw( allele targeting_vector es_cell genbank_file distribution_qc ) ) {
        $meta->add_method(
            "find_$key" => sub {
                my ( $self, $params ) = @_;
                return $self->request( 'GET', sprintf( '%ss.json', $key ), $params, $targ_rep );
            }
        );

        $meta->add_method(
            "update_$key" => sub {
                my ( $self, $id, $params ) = @_;
                return $self->request( 'PUT', sprintf( '%ss/%d.json', $key, $id ), { "targ_rep_$key" => $params }, $targ_rep );
            }
        );

        $meta->add_method(
            "create_$key" => sub {
                my ( $self, $params ) = @_;
                return $self->request( 'POST', sprintf( '%ss.json', $key ), { "targ_rep_$key" => $params }, $targ_rep );
            }
        );

        $meta->add_method(
            "delete_$key" => sub {
                my ( $self, $id ) = @_;
                return $self->request( 'DELETE', sprintf( '%ss/%d.json', "targ_rep_$key", $id ), undef, $targ_rep );
            }
        );
    }

    $meta->make_immutable;
}

sub find_mi_attempt {
    my ( $self, $params ) = @_;
    my $targ_rep = 0;

    return $self->request( 'GET', sprintf( '%ss.json', 'mi_attempt' ), $params, $targ_rep );
}

1;

__END__
