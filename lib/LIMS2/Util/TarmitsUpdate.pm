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
use TryCatch;
use LIMS2::Model::Util::EngSeqParams qw( generate_custom_eng_seq_params );
use Bio::SeqIO;

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

# Initially this script was written to transfer any designs
# but it turns out it is only needed for ncRNA targeting designs
# (those which target cpg islands) so instead of rewriting
# I am adding am flag to provide some special behaviour for these cases
has cpg_islands_only => (
    is       => 'ro',
    isa      => 'Bool',
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

# Parse file downloaded from ftp://ftp.informatics.jax.org/pub/reports/MGI_MRK_Coord.rpt
# (it is large so I pre-filtered this with grep to include only lines with Cpgi symbols on them)
# tab delimited. 1st column is the MGI:xxxxx ID, 4th column is the Cpgixxxx symbol
has mgi_ids_report => (
    is     => 'ro',
    isa    => 'Str',
    required => 0,
);

has mgi_id_for_cpgi => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy_build => 1,
);

sub _build_mgi_id_for_cpgi{
    my $self = shift;
    my $report_path = $self->mgi_ids_report
        or die "attribute mgi_ids_report has not been set";

    open (my $fh, "<", $report_path)
        or die "Cannot open mgi_ids_report at $report_path - $!";

    $self->log->info("Loading Cpgi to MGI ID mapping file $report_path");
    my $ids = {};
    foreach my $line (<$fh>){
        my @values = split "\t", $line;
        $ids->{$values[3]} = $values[0];
    }
    $self->log->info("Cpgi to MGI ID mapping loaded");

    return $ids;
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
    'Sanger MGP' => 'Sanger MGP',
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
        'design_gene_id',
        'design_gene_symbol',
        'design_type',
        'final_cassette_name',
        'final_backbone_name',
        'final_cassette_cre',
        'final_cassette_promoter',
        'final_cassette_conditional',
        'final_cassette_resistance',
    ],
    vector => [
        'design_id',
        'final_plate_name',
        'final_well_name',
        'final_well_accepted',
        'int_plate_name',
        'int_well_name',
    ],
    es_cell => [
        'design_id',
        'design_gene_id',
        'design_gene_symbol',
        'experiments', # use this to get sponsors
        'ep_pick_plate_name',
        'ep_pick_well_name',
        'final_plate_name',
        'final_well_name',
        'crispr_ep_well_cell_line',
        'ep_first_cell_line_name',
        'ep_pick_well_accepted',
        'int_recombinase_id',
        'final_recombinase_id',
        'ep_pick_well_recombinase_id',
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
        find_method   => 'find_genbank_file',
        build_search_data => \&build_genbank_search,
        build_object_data => \&build_genbank_data,
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

    my $targrep_sponsor;
    if($self->cpg_islands_only){
        $targrep_sponsor = 'Sanger MGP';
    }
    else{
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
        $targrep_sponsor = $SPONSORS{ $sponsors[0] }
            or die "No targrep sponsor found for ".$sponsors[0];
    }
    $self->set_design_sponsor($design->id, $targrep_sponsor);

    my $targrep_design_type = $DESIGN_TYPES{ $lims2_summary->design_type };

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
    };

    if($self->cpg_islands_only){
        # find MGI:xxx accession for Cpgi symbol
        my $cpgi_symbol = $lims2_summary->design_gene_id;
        $cpgi_symbol =~ s/^CGI_/Cpgi/;
        my $mgi_id = $self->mgi_id_for_cpgi->{$cpgi_symbol}
            or die "No MGI ID found for symbol $cpgi_symbol";

        $data->{gene_mgi_accession_id} = $mgi_id;
    }
    else{
        $data->{gene_mgi_accession_id} = $lims2_summary->design_gene_id;
    }

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

sub build_genbank_search{
    my ($self, $lims2_summary, $allele_id) = @_;
    my $search = {
        allele_id => $allele_id,
    };
    return $search;
}

sub build_genbank_data{
    my ($self, $lims2_summary, $allele_id) = @_;

    my $design = $self->lims2_model->schema->resultset("Design")->find({ id => $lims2_summary->design_id });

    my $data = {
        allele_id => $allele_id,
    };
    #Generate a sequence file from a user specified design, cassette and backbone combination.
    #If a backbone is specified vector sequence is produced, if not then allele sequence is
    #returned. In addition one or more recombinases can be specified.
    my $input_params = {
        design_id => $lims2_summary->design_id,
        cassette  => $lims2_summary->final_cassette_name,
    };

    $data->{escell_clone}     = $self->generate_seq($input_params,$design);

    # Add backbone to generate targ vec sequence
    $input_params->{backbone} = $lims2_summary->final_backbone_name;
    $data->{targeting_vector} = $self->generate_seq($input_params,$design);

    return $data;
}

sub generate_seq{
    my ($self, $input_params, $design) = @_;

    my ( $method, $eng_seq_params )
        = generate_custom_eng_seq_params( $self->lims2_model, $input_params, $design );
    my $eng_seq = $self->lims2_model->eng_seq_builder->$method( %{$eng_seq_params} );

    return _stringify_bioseq($eng_seq);
}

sub _stringify_bioseq {
    my $seq = shift;
    my $str = '';
    my $io  = Bio::SeqIO->new(
        -fh     => IO::String->new($str),
        -format => 'genbank',
    );
    $io->write_seq($seq);
    return $str;
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
        parental_cell_line    => ( $lims2_summary->crispr_ep_well_cell_line
                                   || $lims2_summary->ep_first_cell_line_name ),
        pipeline_id           => $self->get_pipeline_id($sponsor),
        report_to_public      => 1, # I am assuming all accepted cell lines should be reported to public
        mgi_allele_symbol_superscript => $self->build_allele_symbol_superscript($lims2_summary),
        ikmc_project_id       => 'LIMS2_'.$lims2_summary->design_id,
    };

    return $data;
}

sub build_allele_symbol_superscript{
    my ($self,$lims2_summary) = @_;

    unless($self->cpg_islands_only){
        die "allele_symbol generation only implemented for ncRNA (cpg island) targeting at the moment";
    }

    my @recombinase_columns = qw(int_recombinase_id final_recombinase_id ep_pick_well_recombinase_id);

    if( grep { $lims2_summary->$_ } @recombinase_columns ){
         die "Found recombinases for gene ".$lims2_summary->design_gene_id
         .". allele_symbol generation not yet implemented for these cases";
    }

    my $symbol = "tm1(NCC)WCS";
    return $symbol;
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
        pipeline_id         => $self->get_pipeline_id($sponsor),
        report_to_public    => 1,
        ikmc_project_id     => 'LIMS2_'.$lims2_summary->design_id,
    };

    return $data;
}

sub lims2_to_tarmits{
	my $self = shift;

	$self->process_alleles( $self->get_alleles );

    $self->report_stats;
    return;
}

# only ncRNA designs need to be transferred to imits
# i.e. design_gene_id starts 'CGI_'
sub get_alleles{
	my $self = shift;

	my %where;

    if($self->cpg_islands_only){
        %where = (
            '-and' => [
                'design_species_id' => 'Mouse',
                'design_gene_id' => { 'like' => 'CGI_%' },
                '-or' => [
                    ep_pick_well_accepted => 1,
                    final_well_accepted   => 1,
                ]
            ]
    	);
    }
    else{
        %where = (
            '-and' => [
                'design_species_id' => 'Mouse',
                'design_type' => { '!=' => 'nonsense' },
                '-or' => [
                    ep_pick_well_accepted => 1,
                    final_well_accepted   => 1,
                ]
            ]
        );
    }

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

        if($self->seen_allele($key)){
            $self->log->info("allele already processed");
        }
        else{
            foreach my $col (@{ $LIMS2_SUMMARY_COLUMNS{allele} }){
                $self->log->info("$col: ".$allele->$col);
            }

            $allele_id = $self->find_create_update('allele', $allele);
            $self->allele_processed($key, $allele_id);

            if($allele_id){
                $self->find_create_update('genbank_file',$allele, $allele_id);
            }
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

    my $search_data = $VALIDATION_AND_METHODS{$object_type}{build_search_data}->($self,$lims2_object,$allele_id);
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
    catch($e){
        $self->stats->{$object_type}{update}--;
        $self->stats->{$object_type}{update_fail}++;
        $self->log->error("Unable to update $object_type: $object_name " . $e );
        return { id => $tarmits_data->{id} };
    }

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
    catch($e){
        $self->stats->{$object_type}{create}--;
        $self->stats->{$object_type}{create_fail}++;
        $self->log->error("Unable to create $object_type: $object_name " . $e );
        return { id => undef };
    }

    return $object;
}

sub report_stats{
    my ($self) = @_;
    foreach my $type (sort keys %{ $self->stats }){
        say "";
        say "Number of $type created: ".( $self->stats->{$type}->{create} || "");
        say "Number of $type updated: ".( $self->stats->{$type}->{update} || "");
        say "Number of $type create failed: ".( $self->stats->{$type}->{create_fail} || "");
        say "Number of $type update failed: ".( $self->stats->{$type}->{update_fail} || "");
    }
}

1;