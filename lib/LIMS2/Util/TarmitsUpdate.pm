package LIMS2::Util::TarmitsUpdate;

=head

Methods to find accepted EP_PICK(es cells) and FINAL(targeting vetor) wells in
LIMS2 and create, update or delete in Tarmits as required.

This is the LIMS2 equivalent of HTGT::Utils::TargRep::Update

=cut

use Moose;
use feature qw(say);
use List::MoreUtils qw(uniq);
use Data::Dumper;
use Try::Tiny;

with qw( MooseX::Log::Log4perl );

has lims2_model => (
    is       => 'ro',
    isa      => 'LIMS2::Model',
    required => 1,
);

has tarmits_api => (
    is       => 'ro',
    isa      => 'LIMS2::Util::Tarmits',
    required => 1,
);

# Gene symbols to do update for (optional)
has genes => (
    is      => 'ro',
    isa     => 'ArrayRef',
    traits  => ['Array'],
    handles => { has_genes => 'count', },
    default => sub{ [] },
);

has commit => (
    is       => 'ro',
    isa      => 'Bool',
    default  => 0,
    required => 1,
);

has optional_checks => (
    is       => 'ro',
    isa      => 'Bool',
    default  => 0,
    required => 1,
);

has stats => (
    is  => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);

has hide_non_distribute => (
    is       => 'ro',
    isa      => 'Bool',
    default  => 0,
    required => 1,
);

has alleles => (
    is      => 'ro',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        seen_allele      => 'exists',
        allele_processed => 'set',
        get_allele_id    => 'get',
    }
);

has design_sponsors => (
    is      => 'ro',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        get_design_sponsor => 'get',
        set_design_sponsor => 'set',
    }
);

has targeting_vectors => (
    is      => 'ro',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        seen_targeting_vector      => 'exists',
        targeting_vector_processed => 'set',
        get_targeting_vector_id    => 'get',
    }
);

has es_cells => (
    is      => 'ro',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        seen_es_cell      => 'exists',
        es_cell_processed => 'set',
    }
);

has pipeline_ids => (
    is      => 'ro',
    isa     => 'HashRef',
    traits  => ['Hash'],
    handles => {
        get_pipeline_id => 'get',
    },
    lazy_build => 1,
);

sub _build_pipeline_ids{
    my $self = shift;
    # find_pipeline
    my @pipelines = @{ $self->tarmits_api->get_pipelines };
    print Dumper(@pipelines);
    return { map { $_->{name} => $_->{id} } @pipelines };
}

# Map of LIMS2 design_types to targrep mutation_types
my %DESIGN_TYPES = (
    conditional        => 'Conditional Ready',
    deletion           => 'Deletion',
    insertion          => 'Insertion',
    'artificial-intron'  => 'Artificial Intron',
    'intron-replacement' => undef,
    'cre-bac'            => undef,
    gibson               => undef,
    'gibson-deletion'    => 'Deletion',
    nonsense             => undef,
);

# Map of LIMS2 sponsors to targrep pipeline name
my %SPONSORS = (
    'Cre Knockin' => 'EUCOMMToolsCre',
    'Cre BAC'     => 'EUCOMMToolsCre',
    'MGP Recovery' => 'Sanger MGP',
    'EUCOMMTools Recovery' => 'EUCOMMTools',
);

my %LIMS2_SUMMARY_COLUMNS = (
    allele_unique => [ # FIXME: what should we use as mutation_type? is design_type ok?
        'design_id',
        'design_type',
        'final_cassette_name',
        'final_backbone_name',
    ],
    allele => [    # FIXME: what should we use as mutation_type? is design_type ok?
        'design_id',
        'design_gene_symbol',
        'design_type',
        'final_cassette_name',
        'final_backbone_name',
        'final_cassette_cre',
        'final_cassette_promoter',
        'final_cassette_conditional',
        'final_cassette_resistance',
    ],
    vector => [ # FIXME: where to find ikmc project_id? get sponsor
        'final_plate_name',
        'final_well_name',
        'final_well_accepted',
        'int_plate_name',
        'int_well_name',
    ],
    es_cell => [ # FIXME: ikmc project id? allele symbol, e.g. tm1a(KOMP)Wtsi
        'experiments', # use this to get sponsors
        'ep_pick_plate_name',
        'ep_pick_well_name',
        'final_plate_name',
        'final_well_name',
        'crispr_ep_well_cell_line',
        'ep_pick_well_accepted',
    ],
);

my %VALIDATION_AND_METHODS = (
    allele => {
        fields => [
            qw(
                cassette_type
                mutation_type_name
                mutation_subtype_name
                mutation_method_name
                project_design_id
            )
        ],
        optional_fields => [
            qw(
                floxed_start_exon
                floxed_end_exon
            )
        ],
        update        => \&update_allele,
        update_method => 'update_allele',
        create_method => 'create_allele',
        find_method   => 'find_allele',
        build_search_data => \&build_allele_search,
        build_object_data => \&build_allele_data,

    },
    genbank_file => {
        fields => [
            qw(
                escell_clone
                targeting_vector
            )
        ],
        update        => \&update_genbank,
        update_method => 'update_genbank_file',
        create_method => 'create_genbank_file',
    },
    es_cell => {
        fields => [
            qw(
                targeting_vector_id
                ikmc_project_id
                parental_cell_line
                pipeline_id
                report_to_public
                production_qc_five_prime_screen
                production_qc_three_prime_screen
            )
        ],
        sanger_epd  => [
             qw(
                mgi_allele_symbol_superscript
                production_qc_loxp_screen
                production_qc_loss_of_allele
             )
        ],
        update        => \&update_es_cell,
        update_method => 'update_es_cell',
        create_method => 'create_es_cell',
        find_method   => 'find_es_cell',
        build_search_data => \&build_es_cell_search,
        build_object_data => \&build_es_cell_data,
    },
    distribution_qc => {
        fields => [
            qw(
                five_prime_sr_pcr
                three_prime_sr_pcr
                karyotype_low
                karyotype_high
                copy_number
                loa
                loxp
                lacz
                chr1
                chr8a
                chr8b
                chr11a
                chr11b
                chry
            )
        ],
        update        => \&update_distribution_qc,
        update_method => 'update_distribution_qc',
        create_method => 'create_distribution_qc',
    },
    targeting_vector => {
        fields => [
            qw(
                ikmc_project_id
                intermediate_vector
                pipeline_id
                report_to_public
            )
        ],
        update        => \&update_targeting_vector,
        update_method => 'update_targeting_vector',
        create_method => 'create_targeting_vector',
        find_method   => 'find_targeting_vector',
        build_search_data => \&build_targvec_search,
        build_object_data => \&build_targvec_data,
    },
);

# METHODS TO BUILD PARAMS FROM LIMS2 SUMMARY RESULTS
# To use in searching tarmits or provie data for creating new tarmits entry
sub _build_name{
    my ($plate_type, $lims2_summary) = @_;
    my $plate_col = $plate_type."_plate_name";
    my $well_col = $plate_type."_well_name";
    return $lims2_summary->$plate_col."_".$lims2_summary->$well_col;
}

sub build_allele_search{
    my ($self, $lims2_summary) = @_;
    my $targrep_design_type = $DESIGN_TYPES{ $lims2_summary->design_type };
    my $search = {
        project_design_id_eq  => $lims2_summary->design_id,
        cassette_eq           => $lims2_summary->final_cassette_name,
        backbone_eq           => $lims2_summary->final_backbone_name,
        mutation_type_name_eq => $targrep_design_type,
    };
    return $search;
}

sub build_allele_data{
    my ($self, $lims2_summary) = @_;

    my $design = $self->lims2_model->schema->resultset("Design")->find({ id => $lims2_summary->design_id });

    # Find the design sponsor and store it for later use in vector and es cell creation
    my $projects_rs = $self->lims2_model->schema->resultset("Project")->search({
        gene_id => {
            '-in' => $design->gene_ids,
        }
    });
    my @sponsors = uniq map { $_->sponsor_ids } $projects_rs->all;
    if(@sponsors > 1){
        die "Multiple sponsors for design ".$design->id." don't know how to set targrep pipeline";
    }
    my $targrep_sponsor = $SPONSORS{ $sponsors[0] }
        or die "No targrep sponsor found for ".$sponsors[0];
    $self->set_design_sponsor($design->id, $targrep_sponsor);

    my $targrep_design_type = $DESIGN_TYPES{ $lims2_summary->design_type };
    my $gene_id = join ",", $design->gene_ids;
    my $cassette_type = ( $lims2_summary->final_cassette_promoter ? 'Promotor Driven' : 'Promotorless' );
    my $data = {
        project_design_id  => $lims2_summary->design_id,
        cassette           => $lims2_summary->final_cassette_name,
        cassette_type      => $cassette_type,
        backbone           => $lims2_summary->final_backbone_name,
        mutation_type_name => $targrep_design_type,
        mutation_method_name => 'Targeted Mutation',
        assembly           => $design->info->default_assembly,
        strand             => ( $design->chr_strand > 0 ? '+' : '-' ),
        chromosome         => $design->chr_name,
        gene_mgi_accession_id => $gene_id,
    };

    # Add design feature coordinates
    my @design_feature_fields = map { $_."_start", $_."_end" } qw(homology_arm cassette loxp);
    foreach my $field (@design_feature_fields){
        my $targrep_field = $field;
        if($design->chr_strand < 0){
            # swap start and end for -ve strand designs
            if($field =~ /start$/){
               $targrep_field =~ s/start$/end/;
            }
            else{
                $targrep_field =~ s/end$/start/;
            }
        }
        $data->{$targrep_field} = $design->info->$field;
    }

    return $data;
}

sub build_es_cell_search{
    my ($self, $lims2_summary) = @_;
    my $name = _build_name('ep_pick',$lims2_summary);
    return { name_eq => $name };
}

sub build_es_cell_data{
    my ($self, $lims2_summary, $allele_id) = @_;

    my $targvec_name = _build_name('final',$lims2_summary);
    my $targeting_vector_id = $self->get_targeting_vector_id($targvec_name)
        or die "Cannot find ID for targeting vector $targvec_name";
    my $sponsor = $self->get_design_sponsor( $lims2_summary->design_id );

    my $data = {
        name                  => _build_name('ep_pick',$lims2_summary),
        allele_id             => $allele_id,
        targeting_vector_id   => $targeting_vector_id,
        parental_cell_line    => $lims2_summary->crispr_ep_well_cell_line,
        pipeline_id           => $self->get_pipeline_id($sponsor),
        report_to_public      => 1, # I am assuming all accepted cell lines should be reported to public
    };

    return $data;
}

sub build_targvec_search{
    my ($self, $lims2_summary) = @_;
    my $name = _build_name('final', $lims2_summary);
    return { name_eq => $name };
}

sub build_targvec_data{
    my ($self, $lims2_summary, $allele_id) = @_;

    my $sponsor = $self->get_design_sponsor( $lims2_summary->design_id );
    my $data = {
        name                => _build_name('final',$lims2_summary),
        intermediate_vector => _build_name('int',$lims2_summary),
        allele_id           => $allele_id,
        pipeline_id           => $self->get_pipeline_id($sponsor),
        report_to_public    => 1,
    };
}

sub lims2_to_tarmits{
	my $self = shift;

	$self->process_alleles( $self->get_alleles );

    $self->report_stats;
    return;
}

sub get_alleles{
	my $self = shift;

	my %where = (
        '-and' => [
            'design_type' => { '!=', 'nonsense'},
            '-or' => [
                ep_pick_well_accepted => 1,
                final_well_accepted   => 1,
            ]
        ]
	);



	if ($self->has_genes){
		$where{design_gene_symbol} = { '-in' => $self->genes };
	}

    my @all_columns = uniq @{ $LIMS2_SUMMARY_COLUMNS{allele} },
                           @{ $LIMS2_SUMMARY_COLUMNS{vector} },
                           @{ $LIMS2_SUMMARY_COLUMNS{es_cell} };

	my $alleles_rs = $self->lims2_model->schema->resultset('Summary')->search(
        \%where,
        {
            select => \@all_columns,
            distinct => 1
        }
    );

    return $alleles_rs;
}

sub process_alleles{
	my ($self, $alleles_rs) = @_;
	foreach my $allele ($alleles_rs->all){
        my $key = join ":", map { $allele->$_ } @{ $LIMS2_SUMMARY_COLUMNS{allele_unique} };
        $self->log->info("--------- ALLELE: $key ------");

        my $allele_id = $self->get_allele_id($key);

        if($allele_id){
            $self->log->info("allele already processed");
        }
        else{
            foreach my $col (@{ $LIMS2_SUMMARY_COLUMNS{allele} }){
                $self->log->info("$col: ".$allele->$col);
            }

            $allele_id = $self->find_create_update('allele', $allele); # FIXME: find/create/update allele and return ID
            $self->allele_processed($key, $allele_id);
        }

        if($allele->final_well_accepted){
            $self->process_vector($allele_id, $allele);
        }

        if($allele->ep_pick_well_accepted){
            $self->process_es_cell($allele_id, $allele);
        }
	}
	return;
}

sub process_vector{
    my ($self, $allele_id, $item) = @_;

    my $vector_name = _build_name('final',$item);

    $self->log->info("  --- VECTOR: $vector_name ---");
    if($self->seen_targeting_vector($vector_name)){
        $self->log->info("  vector already processed");
    }
    else{
        foreach my $col (@{ $LIMS2_SUMMARY_COLUMNS{vector} }){
            $self->log->info("  $col: ".$item->$col);
        }
        my $vector_id = $self->find_create_update('targeting_vector',$item, $allele_id);
        $self->targeting_vector_processed($vector_name,$vector_id);
    }

    return;
}

sub process_es_cell{
    my ($self, $allele_id, $item) = @_;

    my $es_cell_name = _build_name('ep_pick',$item);

    $self->log->info("  --- ES CELL: $es_cell_name ---");
    if($self->seen_es_cell($es_cell_name)){
        $self->log->info("  es_cell already processed");
    }
    else{
        foreach my $col (@{ $LIMS2_SUMMARY_COLUMNS{es_cell} }){
            $self->log->info("  $col: ".$item->$col);
        }

        my $es_cell_id = $self->find_create_update('es_cell',$item, $allele_id);
        $self->es_cell_processed($es_cell_name,$es_cell_id);
    }

    return;
}

#
#COMMON FUNCTIONS FOR ALLELES / TARGETING VECTORS OR ES CELLS
#

sub find_create_update{
    my ($self, $object_type, $lims2_object, $allele_id) = @_;

    my $search_data = $VALIDATION_AND_METHODS{$object_type}{build_search_data}->($self,$lims2_object);
    my $find_method = $VALIDATION_AND_METHODS{$object_type}{find_method};

    my @existing = @{ $self->tarmits_api->$find_method($search_data) };

    my $object_data = $VALIDATION_AND_METHODS{$object_type}{build_object_data}->($self,$lims2_object,$allele_id);
    if(@existing == 0){
        my $tarmits_object = $self->create($object_type, $object_data);
        $self->log->info("Created new $object_type with ID ".$tarmits_object->{id});
        return $tarmits_object->{id};
    }
    elsif(@existing == 1){
        my $tarmits_object = $self->check_and_update($object_type, $existing[0], $object_data,);
        $self->log->info("Checked existing $object_type with ID ".$tarmits_object->{id});
        return $tarmits_object->{id};
    }
    else{
        $self->log->error(scalar(@existing)." $object_type entries in tarmits matching search. don't know what to do");
        return;
    }

    return;
}

sub check_and_update{
    my ($self, $object_type, $tarmits_data, $lims2_data) = @_;

    my @check_fields = @{ $VALIDATION_AND_METHODS{$object_type}{fields} };

    push @check_fields, @{ $VALIDATION_AND_METHODS{$object_type}{optional_fields} }
        if $self->optional_checks and exists $VALIDATION_AND_METHODS{$object_type}{optional_fields};

    my $object_name = $tarmits_data->{name} || $tarmits_data->{id};

    $self->log->info("Checking and updating $object_type $object_name");

    my %update_data;
    for my $field ( @check_fields ) {

        if ( !defined $lims2_data->{$field} ) {
            if ( $tarmits_data->{$field} ) {
                $self->log->warn( "$object_type $object_name field $field has no value in LIMS2"
                                  . ' but has following value in tarmits: ' . $tarmits_data->{$field} );
                $update_data{$field} = undef;
            }
        }
        else {
            if ( !defined $tarmits_data->{$field} ) {
                $self->log->info( "$object_type $object_name field $field not set in tarmits: " . $lims2_data->{$field} );
                $update_data{$field} = $lims2_data->{$field};
            }
            elsif ( $tarmits_data->{$field} ne $lims2_data->{$field} ) {
                if ($object_type eq 'genbank_file') {
                    $self->log->warn( "Incorrect $field for $object_type $object_name ");
                }
                else {
                    $self->log->warn( "Incorrect $field for $object_type $object_name : "
                                     . $tarmits_data->{$field} . ', lims2 value:' . $lims2_data->{$field} );
                }
                $update_data{$field} = $lims2_data->{$field};
            }
        }
    }
    my $object = $tarmits_data;
    $object = $self->update( $object_type, $object_name, $tarmits_data, \%update_data) if %update_data;
    return $object;
}

sub update {
    my ( $self, $object_type, $object_name, $tarmits_data, $update_data ) = @_;
    $self->stats->{$object_type}{update}++;

    my $update_method = $VALIDATION_AND_METHODS{$object_type}{update_method};

    my $object;
    try {
        $self->log->info( "Updating $object_type: $object_name" );
        $self->log->info("Object info: ".Dumper($update_data) );
        unless($self->commit){
            # return dummy object as we are not actually updating an entry
            return { id => $tarmits_data->{id} };
        }

        $object = $self->tarmits_api->$update_method( $tarmits_data->{id}, $update_data );
    }
    catch {
        $self->stats->{$object_type}{update}--;
        die ( "Unable to update $object_type: $object_name " . $_ );
    };

    return $object;
}

sub create {
    my ( $self, $object_type, $object_data ) = @_;

    $self->stats->{$object_type}{create}++;

    my $object;
    my $object_name = $object_data->{name} || "";
    my $create_method = $VALIDATION_AND_METHODS{$object_type}{create_method};

    try {
        $self->log->info( "Creating new $object_type: $object_name" );
        $self->log->debug( 'Object info: ' . Dumper($object_data) );
        unless($self->commit){
            # return dummy object as we are not actually creating an entry
            return { id => 1 };
        }

        $object = $self->tarmits_api->$create_method( $object_data );
    }
    catch {
        $self->stats->{$object_type}{create}--;
        die( "Unable to create $object_type: $object_name " . $_ );
    };

    return $object;
}

sub report_stats{
    my ($self) = @_;
    foreach my $type (sort keys %{ $self->stats }){
        say "Number of $type created: ".( $self->stats->{$type}->{create} || "");
        say "Number of $type updated: ".( $self->stats->{$type}->{update} || "");
    }
}

1;