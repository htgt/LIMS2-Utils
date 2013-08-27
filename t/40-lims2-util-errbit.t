#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;

my $trace = <<END;
Caught exception in LIMS2::WebApp::Controller::User::QC->index "useful error message at /nfs/users/nfs_a/ah19/LIMS2-WebApp/script/../lib/LIMS2/WebApp/Controller/User/QC.pm line 53, <DATA> line 998. 
    LIMS2::WebApp::Controller::User::QC::index('LIMS2::WebApp::Controller::User::QC=HASH(0x7b53c18)', 'LIMS2::WebApp=HASH(0x7892728)') called at /opt/t87/global/software/perl/lib/perl5/Catalyst/Action.pm line 65 
    Catalyst::Action::execute('Catalyst::Action=HASH(0x7d14ba8)', 'LIMS2::WebApp::Controller::User::QC=HASH(0x7b53c18)', 'LIMS2::WebApp=HASH(0x7892728)') called at /opt/t87/global/software/perl/lib/perl5/Catalyst.pm line 1691 eval {...} called at /opt/t87/global/software/perl/lib/perl5/Catalyst.pm line 1691 
    Catalyst::execute('LIMS2::WebApp=HASH(0x7892728)', 'LIMS2::WebApp::Controller::User::QC', 'Catalyst::Action=HASH(0x7d14ba8)') called at /opt/t87/global/software/perl/lib/perl5/Catalyst/Action.pm line 60
END

my $trace_hash = {
    full_error => 'Caught exception in LIMS2::WebApp::Controller::User::QC->index "useful error message at /nfs/users/nfs_a/ah19/LIMS2-WebApp/script/../lib/LIMS2/WebApp/Controller/User/QC.pm line 53, <DATA> line 998. ',
    backtrace  => [
        {
            number => "53",
            file   => "/nfs/users/nfs_a/ah19/LIMS2-WebApp/script/../lib/LIMS2/WebApp/Controller/User/QC.pm",
            method => "index"
        },
        {
            number => "65",
            file   => "/opt/t87/global/software/perl/lib/perl5/Catalyst/Action.pm",
            method => "LIMS2::WebApp::Controller::User::QC::index('LIMS2::WebApp::Controller::User::QC=HASH(0x7b53c18)', 'LIMS2::WebApp=HASH(0x7892728)')",
        },
        {
            number => "1691",
            file   => "/opt/t87/global/software/perl/lib/perl5/Catalyst.pm",
            method => "Catalyst::Action::execute('Catalyst::Action=HASH(0x7d14ba8)', 'LIMS2::WebApp::Controller::User::QC=HASH(0x7b53c18)', 'LIMS2::WebApp=HASH(0x7892728)')",
        },
        {
            number => "60",
            file   => "/opt/t87/global/software/perl/lib/perl5/Catalyst/Action.pm",
            method => "Catalyst::execute('LIMS2::WebApp=HASH(0x7892728)', 'LIMS2::WebApp::Controller::User::QC', 'Catalyst::Action=HASH(0x7d14ba8)')",
        }
    ],
    method     => 'index',
    class      => 'LIMS2::WebApp::Controller::User::QC',
    message    => 'useful error message',
};

use_ok 'LIMS2::Util::Errbit';

{
    lives_ok { die unless defined $ENV{LIMS2_ERRBIT_CONFIG} } 'Env var is set';

    #check we can create an instance
    ok my $errbit = LIMS2::Util::Errbit->new_with_config, 'Create regular instance';

    ok my $data = $errbit->process_error( $trace ), 'Process data works';

    is_deeply $trace_hash, $data, 'processed error is correct';

    #need an actual (or mock i guess) catalyst object to actually test submission

}

done_testing;