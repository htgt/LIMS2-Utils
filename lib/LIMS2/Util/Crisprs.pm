package LIMS2::Util::Crisprs;

use strict;
use warnings;

use Moose;

use LIMS2::Model;
use LIMS2::Model::Util::DesignInfo;
use LIMS2::Util::EnsEMBL;

use Data::Dumper;
use YAML::Any;
use Bio::Perl;
use IPC::Run qw( run );
use Try::Tiny;
use Path::Class;
use List::MoreUtils qw ( uniq );

use Log::Log4perl qw(:easy);
with 'MooseX::Log::Log4perl';

BEGIN {
    Log::Log4perl->easy_init( { level => $DEBUG } );
}

#we hammer the ensembl db so set these env vars to use the sanger only mirror:
#export LISM2_ENSEMBL_HOST=ens-livemirror.internal.sanger.ac.uk
#export LIMS2_ENSEMBL_USER=ensro

#you'll need /software/team87/brave_new_world/app/exonerate-2.2.0-x86_64/bin in your path
#if you want to run this

#run with:
#perl -I /nfs/users/nfs_a/ah19/LIMS2-Utils/lib -I /nfs/users/nfs_a/ah19/LIMS2-WebApp/lib -we 'use LIMS2::Util::Crisprs; my $c = LIMS2::Util::Crisprs->new( species => "human" ); $c->find_crisprs( "ENSE00002136880" ); $c->run_exonerate; $c->process_exonerate; $c->create_csv;'

has exons => (
    traits   => [ 'Hash' ],
    is       => 'rw',
    isa      => 'HashRef',
    default  => sub { {} },
    handles  => {
        add_exon_data       => 'set',
        get_exon_data       => 'get',
        exon_already_exists => 'exists',
        exons_loaded        => 'count',
    },
);

has seeds => (
    traits   => [ 'Hash' ],
    is       => 'ro',
    isa      => 'HashRef',
    default  => sub { {} },
    handles => {
        add_seed_data => 'set',
        get_seed_data => 'get',
        seeds_loaded  => 'count',
    },
);

has ensembl => (
    is         => 'ro',
    isa        => 'LIMS2::Util::EnsEMBL',
    lazy_build => 1,
);

has species => (
    is       => 'rw',
    isa      => 'Str',
    #default  => 'mouse',
    required => 1
);

#the number of bp at the end of a site to remove to get the seed
#that is, $self->crispr_length - $self->non_seed_length = SEED_LENGTH
has non_seed_length => (
    is       => 'rw',
    isa      => 'Int',
    default  => 7,
    required => 1
);

has crispr_length => (
    is       => 'rw',
    isa      => 'Int',
    default => 22
);

has exonerate_min_score => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

has model => (
    is         => 'ro',
    isa        => 'LIMS2::Model',
    lazy_build => 1,
);

has base_dir => (
    is      => 'rw',
    isa     => 'Path::Class::Dir',
    coerce  => 1,
    default => sub { dir( '/nfs/users/nfs_a/ah19/work/crispr/' ); },
);

has outlier_limit => (
    is      => 'rw',
    isa     => 'Int',
    default => 20,
);

has strands => (
    traits     => [ 'Hash' ],
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
    handles    => {
        strand_exists => 'exists',
    }
);

has files => (
    traits     => [ 'Hash' ],
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
    handles    => {
        get_filename => 'get',
        set_filename => 'set',
    }
);

has strip_utr => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

sub _build_model {
    my $self = shift;

    return LIMS2::Model->new( user => 'tasks' );
}

sub _build_exonerate_min_score {
    my $self = shift;

    #this is the length of the seed multiplied by the exonerate match score
    return ($self->crispr_length - $self->non_seed_length) * 5;
}

sub _build_ensembl {
    my $self = shift;

    return LIMS2::Util::EnsEMBL->new( species => $self->species );
}

#used to identify which strand a site is on. we specify both in case the strand is 0
#and we incorrectly label it.
#we may also want to go from the text name back to the strand so we store that too
sub _build_strands {
    return {
        '1'  => { name => 'global_forward', symbol => '+' },
        '-1' => { name => 'global_reverse', symbol => '-' },
        'global_forward' => { name => '1', symbol => '+' },
        'global_reverse' => { name => '-1', symbol => '-' }
    };
}

sub _build_files {
    my $self = shift;

    my $genome_file;
    if ( $self->species eq "mouse" ) {
        $genome_file = '/lustre/scratch110/blastdb/Ensembl/Mouse/GRCm38/unmasked/toplevel.fa';
    }
    elsif ( $self->species eq "human" ) {
        $genome_file = '/lustre/scratch110/blastdb/Ensembl/Human/GRCh37/genome/unmasked/toplevel.primary.single_chrY_without_Ns.unmasked.fa';
    }
    else {
        confess "INVALID SPECIES: " . $self->species . "\n";
    }

    return {
        sites        => $self->base_dir->file( 'crispr_cas_sites.yaml' ),
        fasta        => $self->base_dir->file( 'crispr_seqs.fa' ),
        exonerate    => $self->base_dir->file( 'exonerate_output.txt' ),
        final_output => $self->base_dir->file( 'crispr_analysis_complete.yaml' ),
        csv          => $self->base_dir->file( 'crisprs.csv' ),
        db           => $self->base_dir->file( 'crispr_db_output.yaml' ),
        genome       => $genome_file
    }
}

#
# NOTE:
# the seq we display in the yaml file is relative to the orientation of the exon.
# that is, a -ve stranded exon will have the sequence for global -ve strand.
# the sequence returned by an exon is relative to the transcript from which you are calling it.
#


#
# ISSUES:
    #
    # all N matches on human. they aren't valid. to do with the without_Ns .fa
    #
#

#example usage:
#use LIMS2::Util::Crisprs;
#my $crispr_util = LIMS2::Util::Crisprs->new( species => "mouse" );
#$crispr_util->find_crisprs( 103 ); #or find_crisprs( [103, 104, 105] )
#or find_crisprs( "ENSMUSE00001107660" )
#$crispr_util->run_exonerate();
#$crispr_util->process_exonerate();
#


#ids can either be design ids or ensembl exon ids
sub find_crisprs {
    my ( $self, $ids ) = @_;

    #if we just get a single id put it into an array ref
    unless ( ref $ids eq 'ARRAY' ) {
        $ids = [ $ids ];
    }

    for my $id ( uniq @{ $ids } ) {
        $self->log->info( "Finding sites for $id:" );
        try {
            if ( $id =~ /^ENS/ ) { #ensembl exon id
                $self->get_single_exon_data( $id );
            }
            elsif ( $id =~ /^\d+$/) { #design id
                $self->get_single_design_data( $id );
            }
            else {
                confess "Invalid id '$id'";
            }
        }
        catch {
            $self->log->warn( "Skipping $id: $_" );
        }
    }

    YAML::Any::DumpFile( $self->get_filename( 'sites' ), $self->exons );

    #make the seeds fasta file too
    $self->write_seeds();

    return 1; #shut up perlcritic
}

#we wouldn't want to have to do process_exonerate again, so allow loading of the final file
sub load_crisprs_from_yaml {
    my ( $self ) = @_;

    $self->exons( YAML::Any::LoadFile( $self->get_filename('final_output') ) );
    return 1; #shut up perlcritic
}

sub get_single_exon_data {
    my ( $self, $exon_stable_id ) = @_;

    my $gene = $self->ensembl->get_gene_from_exon_id( $exon_stable_id );

    #get exon object from $self->ensembl
    $self->log->info( "Fetching exon $exon_stable_id" );

    #get exon slice
    my $exon_slice = $self->ensembl->slice_adaptor->fetch_by_exon_stable_id( $exon_stable_id );

    #we need the marker symbol to make sure any transcripts we get are for the right gene
    my $exon_gene = $self->ensembl->gene_adaptor->fetch_by_exon_stable_id( $exon_stable_id )->external_name;
    my $best_transcript = $self->ensembl->get_best_transcript( $exon_slice, $exon_gene );

    #we dont use get_exon_rank as there's no point looping this twice
    my $rank = 1;
    for my $exon ( @{ $best_transcript->get_all_Exons } ) {
        if ( $exon->stable_id eq $exon_stable_id ) {
            #we're just doing a single exon so we don't have a design
            $self->_add_exon_data( $gene, $exon, $rank, $best_transcript );
            last;
        }

        $rank++;
    }

    return 1; #shut up perlcritic
}

sub get_single_design_data {
    my ( $self, $design_id ) = @_;

    my $design = $self->model->retrieve_design( { id => $design_id } );
    my $design_info = LIMS2::Model::Util::DesignInfo->new( design => $design );

    my ( $exons, $total_sites ) = ( 0, 0 ); #we'll keep a running total
    for my $exon ( @{ $design_info->floxed_exons } ) {
        #populate the hashref with all the exon data (crispr sites, seq, etc.)
        my $rank = $design_info->get_exon_rank( $design_info->target_transcript, $exon->stable_id );
        $self->_add_exon_data( $design_info->target_gene, $exon, $rank, $design_info->target_transcript );

        $exons++;
        $total_sites += $self->get_exon_data( $exon->stable_id )->{ total_sites };
    }

    $self->log->info( "\tFound $total_sites matches in $exons exons." );

    return 1; #shut up perlcritic
}

sub _add_exon_data {
    my ( $self, $gene, $exon, $rank, $transcript ) = @_; #transcript is optional, only needed for strip_utr

    return if $self->exon_already_exists( $exon->stable_id );

    #we have to be passed rank as we dont have a design_info here,
    #and we don't want one so this can be used without a design.

    #data is a hashref that we store the data in
    confess "Strand is " . $exon->seq_region_strand . " (must be 1 or -1)"
        unless $self->strand_exists( $exon->seq_region_strand );

    #we need to know which strand is which for the output
    my $strand        = $self->strands->{ $exon->seq_region_strand }->{ name };
    my $comp_strand   = $self->strands->{ $exon->seq_region_strand * -1 }->{ name }; #the opposite one
    my $matches       = {};
    my $total_matches = 0;

    #add all the matches for both strands

    #see if we need to strip utr from the exon sequence or not.
    my $seq;
    if ( $self->strip_utr ) {
        confess "Can't strip UTR without a transcript"
            unless $transcript;

        #only take the coding_region_start to coding_region_end so we don't get any UTR
        $seq = $exon->seq->subseq( $exon->coding_region_start($transcript),
                                   $exon->coding_region_end($transcript) );
    }
    else { #otherwise just take the sequence as is
        $seq = $exon->seq->seq;
    }

    while ( $seq =~ /([CTGA]{19}[CTGA]GG)/g ) {
        #$-[0] is match start, $+[0] is match_end
        push @{ $matches->{$strand} } => $self->_create_match_hashref( $1, $exon, $-[0], $+[0] );
        $total_matches++;

        #a hack to move the next search position backwards to just after the GG/CC
        #to make sure we get any overlapping crisprs
        pos($seq) -= ($self->crispr_length - 2);
    }

    while ( $seq =~ /(CC[CTGA][CTGA]{19})/g ) {
        push @{ $matches->{$comp_strand} },
            $self->_create_match_hashref( revcom( $1 )->seq, $exon, $-[0], $+[0] );
        $total_matches++;

        #same as above
        pos($seq) -= ($self->crispr_length - 2);
    }

    #add all the data we just collected to our hash.
    $self->add_exon_data( $exon->stable_id => {
        gene        => $gene->external_name,
        ens_gene_id => $gene->stable_id,
        seq         => $seq,
        strand      => $exon->strand,
        chromosome  => $exon->seq_region_name,
        matches     => $matches,
        total_sites => $total_matches, #easier than going into the matches hash
        rank        => $rank,
    } );

    #this function adds them directly to the global seeds hashref
    $self->add_match_seeds( $exon, $matches );

    return 1; #shut up perlcritic
}

#get all the information we want for a given site.
sub _create_match_hashref {
    my ( $self, $crispr_site, $exon, $match_start, $match_end ) = @_;

    my %match = (
        crispr_site => $crispr_site,
        off_targets => { Exonic => [], Intronic => [], Intergenic => [] },
    );

    #determine the appropriate start and end relative to the exon
    #these are confusing to think about and hard to explain. a diagram is realistically required.
    #basically if its on the negative our seq is 'backwards', but the start/end remain the same
    #so to get the actual location we have to go from the end.
    if ( $exon->seq_region_strand eq "-1" ) {
        $match{start} = ( $exon->seq_region_end - $match_end ) + 1;
        $match{end}   = $exon->seq_region_end - $match_start;
    }
    #this way is much more straightforward. we just add the offset to the start of the exon
    #we take -1 from the end as ensembl region functions are inclusive.
    elsif ( $exon->seq_region_strand == 1 ) {
        $match{start} = $exon->seq_region_start + $match_start;
        $match{end}   = ( $exon->seq_region_start + $match_end ) - 1;
    }
    else {
        confess "Invalid strand: " . $exon->seq_region_strand;
    }

    #
    # Uncomment the following to test if every sequence we get is correct:
    #
    # print "Testing seq against ensembl.\n";
    # my $seq = $self->ensembl->slice_adaptor->fetch_by_region(
    #     'chromosome',
    #     $exon->seq_region_name,
    #     $match{start},
    #     $match{end},
    #     $exon->seq_region_strand,
    # )->seq;
    # confess "ERROR: Seqs don't match:\n$seq\n$crispr_site\n"
    #     unless $seq eq $crispr_site or $seq eq revcom( $crispr_site )->seq;

    return \%match;
}

#for a given set of matches, identify each seed and add them to a provided seeds hash.
sub add_match_seeds {
    my ( $self, $exon, $all_matches ) = @_;

    #all_matches is the matches grouped by strand

    #add all the seed sequences to $self->seeds

    while ( my ( $strand, $matches ) = each %{ $all_matches } ) {

        #this will be the name for each read in the fasta file.
        my $exon_id = join( ":", $exon->stable_id,
                            $exon->seq_region_start,
                            $exon->seq_region_end,
                            $strand );

        my $site_id = 0; #this array index of each site within the matches array, so we can refer back.
        for my $seq ( @{ $matches } ) {
            #chop off the first 7 chars and the pam site. So we end up with base pairs 8-19
            my $seed_no_pam = substr $seq->{crispr_site}, $self->non_seed_length, -3;

            #when we write the fasta file we'll add all 4 possible pam sites. ([ACTG]GG)
            #this is an array beacuse multiple exons may have the same crispr seed within them
            push @{ $self->seeds->{$seed_no_pam} }, $exon_id . ":" . $site_id++;
        }
    }

    return 1; #shut up perlcritic
}

# create a fasta file with all the sites we identified.
sub write_seeds {
    my ( $self ) = @_;

    $self->log->info( "Writing seeds fasta file" );

    confess "No seeds found" unless $self->seeds_loaded;

    my $fh = $self->get_filename( 'fasta' )->openw;

    while ( my ( $seed_seq, $seed_exons ) = each %{ $self->seeds } ) {
        #with a sequence this short exonerate does not like the N we need in the pam site,
        #and wont match anything. so instead we create a new read for each possible value of N.
        for my $n ( qw( A C G T ) ) {
            #don't forget a seed can have multiple exons
            print $fh ">" . join( ",", @{ $seed_exons } ) . "\n";
            print $fh $seed_seq . $n . "GG\n";
        }
    }

    $self->log->info( "Seeds fasta file written successfully" );

    return 1; #shut up perlcritic
}

sub run_exonerate {
    my ( $self ) = @_;

    #make sure the previous step has been run at some point
    confess "Fasta file " . $self->get_filename( 'fasta' ) . " not found!"
        unless -e $self->get_filename( 'fasta' );

    #change showalignment to yes to see more detailed output.
    my @cmd = (
        'exonerate',
        '-m', 'a:l',
        '--score', $self->exonerate_min_score,
        '--showcigar', 'yes',
        '--showvulgar', 'no',
        '--showalignment', 'no',
        $self->get_filename( 'fasta' ), #this is what we're aligning
        $self->get_filename( 'genome' ),
    );

    $self->log->info( "Running exonerate" );

    run( \@cmd, '<', \undef, '>', $self->get_filename( 'exonerate' )->stringify )
        or die "Exonerate failed. See " . $self->get_filename( 'exonerate' ) . " for details\n";

    $self->log->info( "Exonerate complete" );

    return 1; #shut up perlcritic

    #if you want to run exonerate manually:
    #run exonerate -m a:l --score 80 --showcigar yes --showvulgar no --showalignment yes /nfs/users/nfs_a/ah19/crispr/crispr_seqs.fa /lustre/scratch110/blastdb/Users/vvi/KO_MOUSE/GRCm38/toplevel.fa
}

sub process_exonerate {
    my ( $self ) = @_;

    $self->log->info( "Processing exonerate output" );

    confess "Exon data not loaded; you must populate the exons hash first."
        unless $self->exons_loaded;

    #this is the output file from exonerate
    my $fh = $self->get_filename( 'exonerate' )->openr;

    while ( my $line = <$fh> ) {
        next unless $line =~ /^cigar/; #we only care about the cigar string

        #exon id could have multiple exons in it just f y i
        my ( $exon_id, $start, $end, $strand, $chromosome, $location ) = $self->_process_cigar( $line );

        #get an ensembl slice so we can attempt identify where we've hit.
        $self->log->debug( "Fetching slice: " . $start . " - " . $end . " ($strand)" );
        my $slice = $self->ensembl->slice_adaptor->fetch_by_region(
            $location, #chromosome or scaffold
            $chromosome,
            $start,
            $end,
            $strand . "1" #slice ignores this with no warning if you just give -/+. the 1 is crucial
        );

        confess "Error getting slice on chromosome $chromosome\n"
            unless $slice;

        #$self->log->trace( $slice->seq . " (".$slice->strand.") " . " has " .
        #      scalar @{ $slice->get_all_Exons } . " exons and " .
        #      @{ $slice->get_all_Transcripts }  . " transcripts" );

        #stash all the information in a hashref
        $self->add_off_target( {
            exons       => scalar @{ $slice->get_all_Exons },
            transcripts => scalar @{ $slice->get_all_Transcripts },
            chromosome  => $chromosome,
            start       => $start,
            end         => $end,
            strand      => $slice->strand,
            seq         => $slice->seq,
            crispr_site => $exon_id,
        } );
    }

    YAML::Any::DumpFile( $self->get_filename( 'final_output' ), $self->exons );

    $self->log->info( "Exonerate output processed successfully." );

    return 1; #shut up perlcritic
}

#extract all the very specific things we need from the cigar string
sub _process_cigar {
    my ( $self, $cigar_line ) = @_;

    #cigar strings look like:
    #  0           1       2 3  4        5          6      7    8
    #cigar: QUERY_MATCH_ID 0 16 + TARGET_MATCH_ID 125808 125792 - 80  M 16
    #non obvious ones are: 6(match start), 7(match end), 8(match strand)
    my @cigar = split " ", $cigar_line;

    #exon id is our query id
    my ( $exon_id, $match_strand ) = ( $cigar[1], $cigar[8] );

    my ( $match_start, $match_end ) = ( $cigar[6], $cigar[7] );
    #adjust the match start and match end for ensembl's fetch_by_region function
    #negative stranded alignments will be backwards as they were rev comped
    if ( $match_end < $match_start ) {
        #swap match start and match end, and add 7 to the end to give us the full crispr site.
        #we add instead of subtract as we want to take from the start of the -ve strand

        #The Ns are what we're taking, and the dashes what we already have:
        #
        # +1 ----------------NNNNNNN
        # -1 NNNNNNN----------------
        #
        ( $match_start, $match_end ) = ( $match_end, $match_start + $self->non_seed_length );
    }
    else {
        #
        # +1 NNNNNNN----------------
        # -1 ----------------NNNNNNN
        #
        #go back 7 bp to start of the site as we're on +ve strand
        $match_start -= $self->non_seed_length;
    }

    #slice starts from 1 not 0, so this offsets the 0 based values we get from exonerate
    $match_start += 1;

    #this is "TARGET_MATCH_ID", and looks something like chromosome:GRCm38:11:1:122082543:1
    #or scaffold:GRCm38:GL456221.1:1:206961:1
    my @target = split ":", $cigar[5];
    my ( $match_chromosome, $match_location) = ( $target[2], $target[0] ); #location is scaffold/chromosome

    return ( $exon_id, $match_start, $match_end, $match_strand, $match_chromosome, $match_location );
}

sub add_off_target {
    my ( $self, $off_target ) = @_;

    #ENSMUSE00001065010:102360147:102360220:forward:1
    #there could be multiple exons per site, separated by a ,
    for my $crispr_site ( split ",", $off_target->{ crispr_site } ) {
        my ( $exon_id, $exon_start, $exon_end, $strand, $site_id ) = split ":", $crispr_site;

        #make sure the exon we have an off target for exists
        confess "$exon_id does not exist in the output"
            unless ( $self->exon_already_exists( $exon_id ) );

        #find the appropriate exact crispr site
        my $exon_data = $self->get_exon_data( $exon_id );
        my $site = (@{ $exon_data->{ matches }{ $strand } })[ $site_id ];

        #skip the off-target that is the original crispr site.
        next if $site->{ start }           eq $off_target->{ start }
             && $site->{ end }             eq $off_target->{ end }
             && $exon_data->{ chromosome } eq $off_target->{ chromosome }
             && $site->{ crispr_site }     eq $off_target->{ seq };

        #we store off targets by their type
        my $type;
        if( $off_target->{ exons } > 0 ) {
            $type = "Exonic";
        }
        elsif ( $off_target->{ transcripts } > 0 ) {
            $type = "Intronic";
        }
        else {
            $type = "Intergenic";
        }

        $self->log->debug( "Adding $type off-target for $exon_id" );
        $self->log->debug( $site->{ crispr_site } . " has off_target" );
        $self->log->debug( $off_target->{ seq } );

        push @{ $site->{ off_targets }{ $type } }, $off_target;
    }

    return 1; #shut up perlcritic
}

sub create_db_yaml {
    my ( $self ) = @_;

    $self->log->info( "Creating DB YAML" );

    confess "Exon data not loaded; you must populate the exons hash first."
        unless $self->exons_loaded;

    my @crisprs;

    #so many loops
    while ( my ( $exon_id, $exon ) = each %{ $self->exons } ) {
        while ( my ( $strand, $matches ) = each %{ $exon->{ matches } } ) {
            for my $match ( @{ $matches } ) {

                #THESE NAMES ARE TOO LONG
                my $total_exon_off_targets   = scalar @{ $match->{off_targets}{Exonic} };
                my $total_intron_off_targets = scalar @{ $match->{off_targets}{Intronic} };
                my $total_other_off_targets  = scalar @{ $match->{off_targets}{Intergenic} };

                #if either of these are true its an outlier
                my $outlier = $total_exon_off_targets > $self->outlier_limit ||
                              ($total_intron_off_targets + $total_other_off_targets) > $self->outlier_limit;

                my %crispr_site = (
                    seq                  => $match->{ crispr_site },
                    off_target_algorithm => "strict",
                    type                 => "Exonic",
                    off_target_outlier   => $outlier,
                    off_target_summary   => "{Exons: $total_exon_off_targets, "
                                          . "Introns: $total_intron_off_targets, "
                                          . "Intergenic: $total_other_off_targets}", #stored as yaml
                    locus => {
                        chr_name   => $exon->{ chromosome },
                        chr_start  => $match->{ start },
                        chr_end    => $match->{ end },
                        chr_strand => $self->strands->{ $strand }->{ name }, #get strand as number
                    }
                );

                #we're just adding a ref to the list so we can keep adding to it.
                push @crisprs, \%crispr_site;

                #if there are too many exonic off targets we won't store any off targets.
                next if ( $total_exon_off_targets > $self->outlier_limit );

                #see if we should store intronic/intergenic too
                my @to_store = ( 'Exonic' );
                if ( ( $total_intron_off_targets + $total_other_off_targets ) < $self->outlier_limit ) {
                    push @to_store, 'Intronic', 'Intergenic';
                }

                #add all the off targets that we're interested in
                for my $type ( @to_store ) {
                    for my $off_target ( @{ $match->{ off_targets }{ $type } } ) {
                        #we only want a subset of the off-target info
                        push @{ $crispr_site{ off_targets } },
                                {
                                    chr_name   => $off_target->{ chromosome },
                                    chr_start  => $off_target->{ start },
                                    chr_end    => $off_target->{ end },
                                    chr_strand => int $off_target->{ strand }, #strip +
                                    type       => $type,
                                    #seq       => $off_target->{ seq },
                                };
                    }
                }
            }
        }
    }

    YAML::Any::DumpFile( $self->get_filename( 'db' ), @crisprs );

    $self->log->info( "DB YAML created successfully." );

    return 1; #shut up perlcritic
}

sub create_csv {
    my ( $self ) = @_;

    $self->log->info( "Creating CSV" );

    confess "Exon data not loaded; you must populate the exons hash first."
        unless $self->exons_loaded;

    my @rows;

    #add headers
    push @rows, join ",", qw(
        Gene
        Ensembl_Gene_ID
        Ensembl_Exon_ID
        Exon_Rank
        Exon_Strand
        Crispr_Seq
        Off_Targets_Exon
        Off_Targets_Intron
        Off_Targets_Intergenic
        Total_Off_Targets
        Forward_Oligo
        Reverse_Oligo
    );

    #sort the exons by gene and rank, we'll the crisprs within at the end.
    my @sorted = sort {
        $self->exons->{ $a }->{ gene } cmp $self->exons->{ $b }->{ gene } ||
        $self->exons->{ $a }->{ rank } <=> $self->exons->{ $b }->{ rank }
    } keys %{ $self->exons };

    for my $exon_id ( @sorted ) {
        my $exon = $self->get_exon_data( $exon_id );

        my $exon_data = join ",", $exon->{ gene },
                                  $exon->{ ens_gene_id },
                                  $exon_id,
                                  $exon->{ rank },
                                  $exon->{ strand };

        #
        # we currently have these as on the GLOBAL -ve/+ve strands
        #

        my %rows_to_add;
        #get all the match info for both strands, and take the summary info we want
        for my $strand ( keys %{ $exon->{ matches } } ) {
            my $symbol = $self->strands->{ $strand }{ symbol };

            for my $match ( @{ $exon->{ matches }{ $strand } } ) {
                #the oligo sequence doesnt include the pam site.
                my $site = substr($match->{ crispr_site }, 0, -3);
                #NOTE:
                #the oligos might not be correct. I don't know if we need to add a G 
                #to the oligo append sequence or not i need to get stuff farmed and 
                #this function isn't used currently so i'm leaving it like this. sorry
                my $forward_oligo = "ACCG" . $site;
                my $reverse_oligo = "AAAC" . revcom( $site )->seq;

                my $total_exon   = scalar @{ $match->{off_targets}{Exonic} };
                my $total_intron = scalar @{ $match->{off_targets}{Intronic} };
                my $total_other  = scalar @{ $match->{off_targets}{Intergenic} };

                #we may as well include a total
                my $total_off_targets = $total_exon + $total_intron + $total_other;

                #we now have all the data so add the row.
                #we store all the rows in a hash so that they're easy to sort, CSVs are a nightmare
                my $id = join ":", $total_exon, $total_intron, $total_other;
                push @{ $rows_to_add{$id} }, join ",", $exon_data,
                                                       $match->{ crispr_site } . " ($symbol)",
                                                       $total_exon,
                                                       $total_intron,
                                                       $total_other,
                                                       $total_off_targets,
                                                       $forward_oligo,
                                                       $reverse_oligo;
            }
        }

        if ( %rows_to_add ) {
            #sort the keys by num exons then introns then other, and add all the associated rows.
            push @rows, join( "\n", @{ $rows_to_add{$_} } )
                for sort { (split(":", $a))[0] <=> (split(":", $b))[0] ||
                           (split(":", $a))[1] <=> (split(":", $b))[1] ||
                           (split(":", $a))[2] <=> (split(":", $b))[2] } keys %rows_to_add;
        }
        else {
            push @rows, $exon_data; #add rows with no sites
        }
    }

    my $fh = $self->get_filename( 'csv' )->openw;
    print $fh join "\n", @rows;

    $self->log->info( "CSV created successfully." );

    return 1; #shut up perlcritic
}

__PACKAGE__->meta->make_immutable;

1;

__END__