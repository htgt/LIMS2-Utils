package LIMS2::Util::FixtureDataLoad;

use warnings FATAL => 'all';

=head1 NAME

LIMS2::Util::FixtureDataLoad

=head1 DESCRIPTION

Base class for loading test fixture data

=cut

use Moose;
use LIMS2::Model;
use LIMS2::Model::DBConnect;

use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

# 2 database schemas

has source_db => (
    is      => 'ro',
    isa     => 'Str',
    default => 'LIMS2_LIVE',
);

has source_model => (
    is       => 'rw',
    isa      => 'LIMS2::Model',
    init_arg => undef,
);

has dest_db => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has dest_model => (
    is       => 'rw',
    isa      => 'LIMS2::Model',
    init_arg => undef,
);

has persist => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

sub BUILD {
    my $self = shift;

    local $ENV{ LIMS2_DB } = $self->dest_db;
    # connect as tests user to make sure we are writing to a test database
    my $dest_schema = LIMS2::Model::DBConnect->connect( 'LIMS2_DB', 'tests' );
    my $dest_model = LIMS2::Model->new( user => 'lims2', schema => $dest_schema );
    $self->dest_model( $dest_model );

    local $ENV{ LIMS2_DB } = $self->source_db;
    # to allow setup of two database connections we need to clear connectors between connections
    ## no critic(ProtectPrivateSubs)
    LIMS2::Model::DBConnect->_clear_connectors;
    ## use critic

    my $source_schema = LIMS2::Model::DBConnect->connect( 'LIMS2_DB', 'lims2' );
    my $source_model = LIMS2::Model->new( user => 'lims2', schema => $source_schema );
    $self->source_model( $source_model );
}

sub create_user {
    my ( $self, $user ) = @_;

    $self->dest_model->schema->resultset('User')->find_or_create(
        { $user->get_columns }
    );

    return;
}

sub get_dbix_row_data {
    my ( $self, $row ) = @_;

    my %data = $row->get_columns;

    # if record is linked to a user via created_by then make sure
    # the user record exists in the destination db
    if ( exists $data{created_by} ) {
        my $user = $row->created_by;
        $self->dest_model->schema->resultset('User')->find_or_create(
            { $user->get_columns }
        );
    }

    return \%data;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
