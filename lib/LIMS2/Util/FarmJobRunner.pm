package LIMS2::Util::FarmJobRunner;

use warnings FATAL => 'all';

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class::MoreCoercions qw( File );
use MooseX::Params::Validate;

with 'MooseX::Log::Log4perl';

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

has default_processors => (
    is      => 'rw',
    isa     => 'Num',
    default => 1,
);

#source this file to setup env variables to run in farm
# TODO work out the parameter to pass to this file here
has bsub_wrapper => (
    is      => 'rw',
    isa     => File,
    coerce  => 1,
    default => sub{ file( '/nfs/team87/farm3_lims2_vms/conf/run_in_farm3' ) },
);

#to make testing easier
has dry_run => (
    is      => 'rw',
    isa     => 'Bool',
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
        processors      => { isa => 'Int', optional => 1, default => $self->default_processors },
        err_file        => { isa => File,  optional => 1, coerce => 1 },
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
        '-M', $args{ memory_required },
        '-n', $args{ processors },
        '-R',
              '"select[mem>' . $args{memory_required}
            . '] rusage[mem=' . $args{memory_required}
            . '] span[hosts=1]"',
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

    return \@cmd if $self->dry_run;

    my $output = $self->_run_cmd( @cmd );
    my ( $job_id ) = $output =~ /Job <(\d+)>/;
    ### $job_id

    return $job_id;
}

#take an array with bsub commands and produce the final command
#to give to _run_cmd
sub _wrap_bsub {
    my ( $self, @bsub ) = @_;

    #which returns undef if it cant find the file
    #which( $self->bsub_wrapper )
        #or confess "Couldn't locate " . $self->bsub_wrapper;

    #TODO move this logic sp12 Thu 19 Dec 2013 09:23:07 GMT
    my $lims2_env
        = $ENV{LIMS2_DB} eq 'LIMS2_LIVE'    ? 'live'
        : $ENV{LIMS2_DB} eq 'LIMS2_STAGING' ? 'staging'
        : $ENV{LIMS2_REST_CLIENT_CONFIG}    ? $ENV{LIMS2_REST_CLIENT_CONFIG}
        :                                     undef;
    confess "Must be in live or staging environment, if in devel must have LIMS2_REST_CLIENT_CONFIG set"
        unless $lims2_env;

    my $cmd
        = 'source /etc/profile;'
        . 'source ' . $self->bsub_wrapper->stringify . " $lims2_env;"
        . join( " ", @bsub );

    # temp wrap in ssh to farm3-login, until vms can submit to farm3 directly
    my @wrapped_cmd = ( 'ssh', '-o CheckHostIP=no', '-o BatchMode=yes', 'farm3-login');
    push @wrapped_cmd, $cmd;

    return @wrapped_cmd;
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

    $self->log->debug( "CMD: " . join(' ', @cmd) );
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
    default_processors => 2,
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

NOTE: Temporary hack to get it working in farm3 ( by sshing command to farm3-login )

Helper module for running bsub jobs from LIMS2/The VMs.
Sets the appropriate environment for using our perlbrew install in /software.

The default queue is normal, and the default memory required is 2000 MB.

=head1 TODO

Write a jobarray wrapper that will take a yaml file or something, so that we can support params,
and wrap anything into a jobarray.

=head1 AUTHOR

Alex Hodgkins

=cut
