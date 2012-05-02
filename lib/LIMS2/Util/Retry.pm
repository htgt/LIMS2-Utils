package LIMS2::Util::Retry;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ qw( retry constantly exponential ) ]
};

use Try::Tiny;

sub constantly {
    my ( $delay ) = @_;
    $delay ||= 1;
    return sub { $delay };
}

sub exponential {
    my ( $delay, $backoff ) = @_;
    $delay   ||= 1;
    $backoff ||= 2;
    return sub {
        my $this_delay = $delay;
        $delay *= $backoff;
        return $this_delay;
    };    
}

sub retry (&@) {
    my ( $thunk, %opts ) = @_;

    my $ntries  = $opts{ntries}  || 3;
    my $backoff = $opts{backoff} || constantly(1);

    my $err;

    while ( 1 ) {        
        undef $err;
        if ( wantarray ) {
            my @res = try { $thunk->() } catch { $err = $_ };
            return @res unless defined $err;            
        }
        elsif ( not defined wantarray ) {
            try { $thunk->() } catch { $err = $_ };
            return unless defined $err;
        }
        else {
            my $res = try { $thunk->() } catch { $err = $_ };
            return $res unless defined $err;
        }
        last unless --$ntries;
        sleep $backoff->();
    }

    die $err;    
}

1;

__END__
