package LIMS2::Util::YAMLIterator;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::YAMLIterator::VERSION = '0.030';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => ['iyaml'],
    groups  => { default => ['iyaml'] }
};

use Carp qw( confess );
use IO::File;
use IO::String;
use Scalar::Util qw( blessed );
use YAML::Any qw( Load );
use Iterator::Simple qw( iterator );
use Const::Fast;

const my $COMMENT_RX   => qr/^#/;
const my $DOC_START_RX => qr/^---/;

sub iyaml {
    my $input = shift;

    my $ifh = _read($input);

    my $line = $ifh->getline;

    # Skip everything up to the first document start
    while ( defined $line and $line !~ $DOC_START_RX ) {
        $line = $ifh->getline;
    }

    return iterator {
        my $document = $line;
        while ( defined( $line = $ifh->getline ) ) {
            last if $line =~ $DOC_START_RX;
            $document .= $line;
        }
        if ($document) {
            return Load($document);
        }
        return;
    };
}

sub _read {
    my $input = shift;

    if ( blessed($input) and $input->can('getline') ) {
        return $input;
    }

    if ( ref $input eq 'GLOB' and *$input{"IO"} ) {
        return *$input{"IO"};
    }

    if ( ref $input eq 'SCALAR' ) {
        return IO::String->new( ${$input} );
    }

    if ( !ref $input ) {
        return IO::File->new( $input, O_RDONLY )
            || confess "open $input: $!";
    }

    confess ref($input) . ' not supported';
}

1;

__END__
