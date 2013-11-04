package LIMS2::Util::FarmJobRunner;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $LIMS2::Util::FarmJobRunner::VERSION = '0.022';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class::MoreCoercions qw( File );
use MooseX::Params::Validate;

use Try::Tiny;
use Path::Class;
use File::Which qw( which );
use IPC::Run;

#both of these can be overriden per job.
has default_queue => (
    is      => 'rw',
    isa     => 'Str',
    default => 'normal',
);

has default_memory => (
    is      => 'rw',
    isa     => 'Num',
    default => 2000,
);

#this is the file that sets the appropriate environment for running farm jobs.
has bsub_wrapper => (
    is => 'rw',
    isa => File,
    coerce => 1,
    default => sub{ file( 'run_in_perlbrew' ) } #this is in LIMS2-Webapp/scripts
);

#to make testing easier
has dry_run => (
    is => 'rw',
    isa => 'Bool',
    default => 0
);

#allow an array of job refs or just a single one.
subtype 'ArrayRefOfInts',
    as 'ArrayRef[Int]';

coerce 'ArrayRefOfInts',
    from 'Int',
    via { [ $_ ] };

sub submit_pspec {
    my ( $self ) = @_;

    return (
        out_file        => { isa => File, coerce => 1 },
        cmd             => { isa => 'ArrayRef' },
        #the rest are optional
        queue           => { isa => 'Str', optional => 1, default => $self->default_queue },
        memory_required => { isa => 'Int', optional => 1, default => $self->default_memory },
        err_file        => { isa => File, optional => 1, coerce => 1 },
        dependencies    => { isa => 'ArrayRefOfInts', optional => 1, coerce => 1 },
    );
}

#set all common options for bsub and run the user specified command. 
sub submit {
    my ( $self ) = shift;

    my %args = validated_hash( \@_, $self->submit_pspec );

    my @bsub = (
        'bsub',
        '-q', $args{ queue },
        '-o', $args{ out_file },
        '-M', $args{ memory_required } * 1000, #farm -M is weird and not in MB or GB
        '-R', '"select[mem>' . $args{ memory_required } . '] rusage[mem=' . $args{ memory_required } . ']"',
        '-G', 'team87-grp',
    );

    #add the optional parameters if they're set
    if ( exists $args{ err_file } ) {
        push @bsub, ( '-e', $args{ err_file } );
    }

    if ( exists $args{ dependencies } ) {
        push @bsub, $self->_build_job_dependency( $args{ dependencies } );
    }

    #
    #TODO: add ' around cmd
    #

    #add the actual command at the very end.
    push @bsub, @{ $args{ cmd } };

    my @cmd = $self->_wrap_bsub( @bsub ); #this is the end command that will be run

    return @cmd if $self->dry_run;

    my $output = $self->_run_cmd( @cmd );
    my ( $job_id ) = $output =~ /Job <(\d+)>/;

    return $job_id;
}

#take an array with bsub commands and produce the final command
#to give to _run_cmd
sub _wrap_bsub {
    my ( $self, @bsub ) = @_;

    #which returns undef if it cant find the file
    which( $self->bsub_wrapper )
        or confess "Couldn't locate " . $self->bsub_wrapper;

    return (
        $self->bsub_wrapper,
        join " ", @bsub,
    );
}

sub _build_job_dependency {
    my ( $self, $dependencies ) = @_;

    #make sure we got an array
    confess "_build_job_dependency expects an ArrayRef"
        unless ref $dependencies eq 'ARRAY';

    #return an empty list so nothing gets added to the bsub if we dont have any
    return () unless @{ $dependencies };

    #this creates a list of dependencies, for example 'done(12) && done(13) && done(14)'
    return ( '-w', '"' . join( " && ", map { 'done(' . $_ . ')' } @{ $dependencies } ) . '"' );
}

sub _run_cmd {
    my ( $self, @cmd ) = @_;

    my $output;

    try {
        IPC::Run::run( \@cmd, '<', \undef, '>&', \$output )
                or die "$output";
    }
    catch {
        confess "Command failed: $_";
    };

    return $output;
}

__PACKAGE__->meta->make_immutable;

1;

=pod

=head1 NAME

LIMS2::Util::FarmJobRunner

=head1 SYNOPSIS

  use LIMS2::Util::FarmJobRunner;

  my $runner = LIMS2::Util::FarmJobRunner->new;

  #alternatively, override default parameters:
  $runner = LIMS2::Util::FarmJobRunner->new( {
    default_queue  => "basement",
    default_memory => "3000",
    bsub_wrapper   => "custom_environment_setter.pl"
  } );

  #required parameters
  my $job_id = $runner->submit( 
    out_file => "/nfs/users/nfs_a/ah19/bsub_output.out", 
    cmd      => [ "echo", "test" ] 
  );

  #all optional parameters set
  my $next_job_id = $runner->submit( 
    out_file        => "/nfs/users/nfs_a/ah19/bsub_output2.out",
    err_file        => "/nfs/users/nfs_a/ah19/bsub_output2.err",
    queue           => "short",
    memory_required => 4000,
    dependencies    => $job_id,
    cmd             => [ "echo", "test" ] 
  );

  #multiple dependencies 
  $runner->submit( 
    out_file     => "/nfs/users/nfs_a/ah19/bsub_output3.out",
    dependencies => [ $job_id, $next_job_id ],
    cmd          => [ "echo", "test" ] 
  );

=head1 DESCRIPTION

Helper module for running bsub jobs from LIMS2/The VMs. 
Sets the appropriate environment for using our perlbrew install in /software.

The default queue is normal, and the default memory required is 2000 MB.

=head1 TODO

Write a jobarray wrapper that will take a yaml file or something, so that we can support params,
and wrap anything into a jobarray.

=head1 AUTHOR

Alex Hodgkins

=cut