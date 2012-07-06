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

has solr_max_rows => (
    is      => 'ro',
    isa     => 'Int',
    default => 500
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
    my ( $self, $search_term, $attrs, $page ) = @_;

    $attrs ||= $self->default_attrs;

    my $uri = $self->solr_uri->clone;

    my $search_str = $self->build_search_str( $search_term );

    my @results;

    if ( defined $page ) {
        my $start = ( $page - 1 ) * $self->solr_rows;
        my $result = $self->do_solr_query( $uri, $search_str, $start );
        push @results, map { +{ slice $_, @{$attrs} } } @{ $result->{response}{docs} };
    }
    else {
        my $start = 0;
        while( 1 ) {
            my $result = $self->do_solr_query( $uri, $search_str, $start );
            my $num_found = $result->{response}{numFound};
            if ( $num_found > $self->solr_max_rows ) {
                LIMS2::Execpiton->throw( "Too many results ($num_found) returned for '$search_str'" );
            }
            push @results, map { +{ slice $_, @{$attrs} } } @{ $result->{response}{docs} };
            $start += $self->solr_rows;
            last if $start >= $num_found;
        }
    }

    return \@results;
}

sub do_solr_query {
    my ( $self, $uri, $search_str, $start ) = @_;

    $uri->query_form( q => $search_str, wt => 'json', rows => $self->solr_rows, start => $start );
    my $response = $self->get($uri);
    unless ( $response->is_success ) {
        LIMS2::Exception->throw( "Solr search for '$search_str' failed: " . $response->message );
    }

    return decode_json( $response->content );
}

sub build_search_str {
    my ( $self, $search_term ) = @_;

    my $reftype = ref $search_term;

    if ( $reftype ) {
        if ( $reftype eq ref [] ) {
            return sprintf( '%s:%s', $search_term->[0], $self->quote_str( $search_term->[1] ) );
        }
        LIMS2::Exception->throw( "Cannot build search string from $reftype" );
    }

    return $self->quote_str($search_term);
}

sub quote_str {
    my ( $self, $str ) = @_;

    $str =~ s/"/\"/g;

    return sprintf '"%s"', $str;
}

__PACKAGE__->meta->make_immutable;

1;
