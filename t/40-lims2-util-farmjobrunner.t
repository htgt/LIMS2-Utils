#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;
use Const::Fast;

const my $data => {
    queue   => "basement",
    memory  => "3000",
    wrapper => "custom_environment_setter.pl"
};

use_ok 'LIMS2::Util::FarmJobRunner';

{
    #check we can create and change default values
    ok my $runner = LIMS2::Util::FarmJobRunner->new, 'Create regular instance';

    lives_ok { $runner->default_queue( $data->{ queue } ) } "Set default queue";
    ok $runner->default_queue eq $data->{ queue }, 'Check set queue matches';

    lives_ok { $runner->default_memory( $data->{ memory } ) } "Set default memory";
    ok $runner->default_memory eq $data->{ memory }, 'Check set memory matches';

    lives_ok { $runner->bsub_wrapper( $data->{ wrapper } ) } "Set bsub wrapper";
    ok $runner->bsub_wrapper eq $data->{ wrapper }, 'Check set wrapper matches';

}

{
    #check we can create a custom instance and the values are set.
    ok my $runner = LIMS2::Util::FarmJobRunner->new( {
        default_queue  => "basement",
        default_memory => "3000",
        bsub_wrapper   => "custom_environment_setter.pl"
    } ), 'Create modified instance';

    ok $runner->default_queue eq $data->{ queue }, 'Check default queue matches';
    ok $runner->default_memory eq $data->{ memory }, 'Check default memory matches';
    ok $runner->bsub_wrapper eq $data->{ wrapper }, 'Check bsub wrapper matches';
}

{
    ok my $runner = LIMS2::Util::FarmJobRunner->new( { dry_run => 1 } ), "Check dry run works";

    #_wrap_bsub

    ok my ( $bsub, $cmd ) = $runner->_wrap_bsub( "echo", "test" ), "Check wrap bsub runs";
    ok $bsub eq $runner->bsub_wrapper, "Check wrap bsub first return value";
    ok $cmd eq "echo test", "Check wrap bsub second return value";

    #_build_job_dependency

    dies_ok { $runner->_build_job_dependency() } "Empty param dies";
    dies_ok { $runner->_build_job_dependency(2345) } "Non array ref param dies";
    ok ! $runner->_build_job_dependency( [] ), "Check empty list is allowed";

    ok my ( $flag, $value ) = $runner->_build_job_dependency( [124] ), "Check list with single entry";
    ok $flag eq "-w", "Check flag is correct";
    ok $value eq "done(124)", "Check value is correct";

    ok my ( $mflag, $mvalue ) = $runner->_build_job_dependency( [124, 256] ), "Check list with multiple entries";
    ok $mflag eq "-w", "Check flag is correct";
    ok $mvalue eq "done(124) && done(256)", "Check value is correct";

    #_run_cmd

    ok $runner->_run_cmd( "echo", "test" ) eq "test\n", "Check output of run cmd";
    dies_ok { $runner->_run_cmd( "not_a_real_command" ) } "Check death on invalid command";

    #submit
    ok my ( $wrapper, $final_cmd ) = $runner->submit( 
        out_file => "test.out", 
        cmd      => [ "echo", "test" ]  
    ), "Submit runs with only required parameters";

    ok $wrapper eq $runner->bsub_wrapper, "First part of cmd is correct";
    ok $final_cmd =~ /-o test.out/, "Out file specified"; 
    ok $final_cmd =~ /echo test/, "Command specified";

    ok my ( $optional_wrapper, $optional_final_cmd ) = $runner->submit(
        out_file        => "test.out", 
        cmd             => [ "echo", "test" ], 
        err_file        => "test.err",
        queue           => "short",
        memory_required => 4000,
        dependencies    => 9999,
    ), "Submit with optional parameters works";

    #check all the stuff we specified is in the cmd string
    ok $optional_wrapper eq $runner->bsub_wrapper, "First part of cmd is correct";
    ok $optional_final_cmd =~ /-o test\.out/, "Out file specified"; 
    ok $optional_final_cmd =~ /echo test/, "Command specified";
    ok $optional_final_cmd =~ /-e test\.err/, "Error file specified";
    ok $optional_final_cmd =~ /-q short/, "Queue specified";
    ok $optional_final_cmd =~ /4000/, "Memory specified";
    ok $optional_final_cmd =~ /-w done\(9999\)/, "Dependency specified";

}

done_testing;