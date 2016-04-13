#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Log::Log4perl qw( :easy );
use LIMS2::Util::Tarmits;
use Data::Dumper;

Log::Log4perl->easy_init($DEBUG);

my ($input) = @ARGV;

open (my $fh, "<", $input) or die "Cannot open file $input - $!";

my $objects = {
    allele => {},
    targeting_vector => {},
    es_cell => {},
};

my $tarmits = LIMS2::Util::Tarmits->new_with_config;

my @object_headers;
my @headers;
my @line_nums;

while (my $line  = <$fh>){
	chomp $line;
	my @items = split /\t/, $line;
	if($. == 1){
		DEBUG "Processing Object headers: $line";
        @object_headers = @items;
	}
	elsif($. == 2){
		DEBUG "Processing Headers: $line";
		@headers = @items;
	}
	else{
		DEBUG "Processing items on line $.: $line";
		push @line_nums, $.;
		foreach my $index (0..$#items){
			next unless my $object_type = $object_headers[$index];
            my $key = $headers[$index];
            $objects->{$object_type}->{$.} ||= {};
            $objects->{$object_type}->{$.}->{$key} = $items[$index];
		}
	}
}

DEBUG "Getting pipeline name->ID mapping from targ_rep";
my @pipelines = @{ $tarmits->get_pipelines };
my $pipeline_ids = { map { $_->{name} => $_->{id} } @pipelines };

my $allele_ids = {};
foreach my $line (@line_nums){
    my $allele_data = $objects->{allele}->{$line};
    my $allele_key = join "-", $allele_data->{gene_mgi_accession_id}, $allele_data->{cassette}, $allele_data->{backbone},
    $allele_data->{mutation_type_name};

    unless($allele_ids->{$allele_key}){
    	my $allele_search = {
            project_design_id_eq  => $allele_data->{project_design_id},
            cassette_eq           => $allele_data->{cassette},
            backbone_eq           => $allele_data->{backbone},
            mutation_type_name_eq => $allele_data->{mutation_type_name},
        };
        my @existing = @{ $tarmits->find_allele($allele_search) };
        if(@existing){
        	my $id = $existing[0]->{id};
        	DEBUG "Found existing allele with ID $id. Skipping line $line";
            $allele_ids->{$allele_key} = "SKIP";
            next;
        }
    	DEBUG "Creating allele with data:";
    	DEBUG Dumper($allele_data);
    	my $result = $tarmits->create_allele($allele_data)
    	    or die "Could not create allele - $!";
    	$allele_ids->{$allele_key} = $result->{id};
    }

    next if $allele_ids->{$allele_key} eq "SKIP";

    my $targvec_data = $objects->{targeting_vector}->{$line};
    $targvec_data->{allele_id} = $allele_ids->{$allele_key};
    $targvec_data->{pipeline_id} = $pipeline_ids->{ $targvec_data->{pipeline_id} };
    DEBUG "Creating targvec with data:";
    DEBUG Dumper($targvec_data);
    my $targvec_result = $tarmits->create_targeting_vector($targvec_data)
        or die "Could not create targeting vector - $!";
    my $targvec_id = $targvec_result->{id};

    my $cell_data = $objects->{es_cell}->{$line};
    $cell_data->{allele_id} ||= $allele_ids->{$allele_key};
    $cell_data->{targeting_vector_id} ||= $targvec_id;
    $cell_data->{pipeline_id} = $pipeline_ids->{ $cell_data->{pipeline_id} };

    my $es_cell_names = delete $cell_data->{names};
    my @names = split /\s*,\s*/, $es_cell_names;
    foreach my $name (@names){
    	$cell_data->{name} = $name;
    	DEBUG "Creating ES cell with data:";
    	DEBUG Dumper($cell_data);
    	my $cell_result = $tarmits->create_es_cell($cell_data)
    	    or die "Could not create es cell - $!";
    	my $cell_id = $cell_result->{id};
    }
}