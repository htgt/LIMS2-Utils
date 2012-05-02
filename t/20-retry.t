#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;

use_ok 'LIMS2::Util::Retry', qw( retry constantly exponential );

is retry( sub { 1 } ), 1, 'retry sub, scalar context';

is_deeply [ retry( sub { qw( a b c ) } ) ], [ qw( a b c ) ], 'retry sub, list context';

{   
    my $n_attempts = 0;

    throws_ok { retry( sub {
                           $n_attempts++;
                           die "Died";
                       }, ntries => 3, backoff => constantly(1) )
            } qr/Died/, 'retry with constant backoff';

    is $n_attempts, 3, 'tried 3 times before dieing';
}

{
    my $n_attempts = 0;

    throws_ok { retry( sub {
                           $n_attempts++;
                           die "Died";
                       }, ntries => 2, backoff => exponential(1,2) )
            } qr/Died/, 'retry with exponential backoff';

    is $n_attempts, 2, 'tried 2 times before dieing';
}

{
    my $n_attempts = 0;

    lives_ok {
        my $res = retry( sub {
                             $n_attempts++;
                             if ( $n_attempts == 3 ) {
                                 return 7;
                             }
                             else {
                                 die "Died";
                             }
                         }
                     );
        is $res, 7, 'result is 7';
    } 'retry 3 times, succeed on 3rd attempt';

    is $n_attempts, 3, 'failed twice, succeeded on 3rd attempt';
}


done_testing;
