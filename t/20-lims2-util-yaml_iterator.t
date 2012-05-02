#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Const::Fast;
use File::Temp qw( tempfile );
use IO::File;
use IO::String;
use Test::Most;
use YAML::Any;

use_ok 'LIMS2::Util::YAMLIterator';

const my @DATA => (
    {
        a => 1,
        b => 2
    },
    {
        a => 3,
        b => 4
    },
    {
        a => 5,
        b => 6
    }
);

const my $YAML_STR => "# This\n# is\n# a\n# comment\n" . Dump( @DATA ) . "# so\n# is this";


my ( $fh, $filename ) = tempfile();
$fh->print( $YAML_STR );
$fh->seek( 0, 0 );

test_it( $fh, 'construct iterator from GLOB' );
test_it( $filename, 'construct iterator from filename' );
test_it( \$YAML_STR, 'construct iterator from scalar reference' );
test_it( IO::File->new( $filename, O_RDONLY ), 'construct iterator from IO::File' );
test_it( IO::String->new( $YAML_STR ), 'construct iterator from IO::String' );

done_testing;

sub test_it {
    my ( $input, $desc ) = @_;

    ok my $it = iyaml( $input ), $desc;
    for ( 0 .. 2 ) {
        is_deeply $it->next, $DATA[$_], "record $_";
    }
    ok ! $it->next, 'iterator is exhausted';
}
