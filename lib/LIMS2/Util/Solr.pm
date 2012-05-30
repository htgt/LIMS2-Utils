package LIMS2::Util::Solr;

use strict;
use warnings FATAL => 'all';

use Moose;
use MooseX::Types::URI qw( Uri );
use LWP::UserAgent;
use Hash::MoreUtils qw( slice );
use URI;
use JSON;
use LIMS2::Exception;
use namespace::autoclean;

has default_attrs => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [ qw( marker_symbol mgi_accession_id ) ] }
);

has solr_uri => (
    is      => 'ro',
    isa     => Uri,
    coerce  => 1,
    default => sub { URI->new('http://www.sanger.ac.uk/mouseportal/solr/select') }
);

has solr_rows => (
    is      => 'ro',
    isa     => 'Int',
    default => 10
);

has ua => (
    is         => 'ro',
    isa        => 'LWP::UserAgent',
    lazy_build => 1,
    handles    => [ 'get' ]
);

sub _build_ua {
    return LWP::UserAgent->new();
}

sub query {
    my ( $self, $search_str, $attrs ) = @_;

    $attrs ||= $self->default_attrs;

    my $uri = $self->solr_uri->clone;

    my $start = 0;

    my @results;

    while( 1 ) {
        $uri->query_form( q => $search_str, wt => 'json', rows => $self->solr_rows, start => $start );
        my $response = $self->get($uri);
        unless ( $response->is_success ) {
            LIMS2::Exception->throw( "Solr search for '$search_str' failed: " . $response->message );
        }
        my $result = decode_json( $response->content );
        my $num_found = $result->{response}{numFound};
        push @results, map { +{ slice $_, @{$attrs} } } @{ $result->{response}{docs} };
        $start += $self->solr_rows;
        last if $start >= $num_found;
    }

    return \@results;
}

__PACKAGE__->meta->make_immutable;

1;
