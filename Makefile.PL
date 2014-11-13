
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Utilities for LIMS2",
  "AUTHOR" => "Ray Miller <rm7\@sanger.ac.uk>",
  "BUILD_REQUIRES" => {
    "English" => 0,
    "File::Find" => 0,
    "Test::More" => "0.88",
    "Test::Most" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "LIMS2-Util",
  "EXE_FILES" => [
    "bin/fixture_data_bacs.pl",
    "bin/fixture_data_crisprs.pl",
    "bin/fixture_data_designs.pl",
    "bin/fixture_data_helper.pl",
    "bin/fixture_data_plate_wells.pl",
    "bin/tarmits_feed_wrapper.pl",
    "bin/post.sh",
    "bin/update_gene_solr_index.pl",
    "bin/generate_crispr_group_genotyping_primers.pl",
    "bin/generate_fp_report_cache.pl"
  ],
  "LICENSE" => "perl",
  "NAME" => "LIMS2::Util",
  "PREREQ_PM" => {
    "Bio::EnsEMBL::Registry" => 0,
    "Bio::Perl" => 0,
    "Carp" => 0,
    "Class::Data::Inheritable" => 0,
    "Config::Any" => 0,
    "Const::Fast" => 0,
    "Data::Dumper" => 0,
    "EngSeqBuilder" => 0,
    "File::Temp" => 0,
    "Getopt::Long" => 0,
    "HTGT::QC::Util::GeneratePrimersAttempts" => 0,
    "HTML::Entities" => 0,
    "HTTP::Request" => 0,
    "Hash::MoreUtils" => 0,
    "IO::File" => 0,
    "IO::String" => 0,
    "IPC::Run" => 0,
    "Iterator::Simple" => 0,
    "JSON" => 0,
    "LIMS2::Exception" => 0,
    "LIMS2::Model" => 0,
    "LIMS2::Model::Constants" => 0,
    "LIMS2::Model::DBConnect" => 0,
    "LIMS2::Model::Util::DesignInfo" => 0,
    "LIMS2::Model::Util::DesignTargets" => 0,
    "LIMS2::Model::Util::EngSeqParams" => 0,
    "LIMS2::Model::Util::QCResults" => 0,
    "LIMS2::REST::Client" => 0,
    "LIMS2::Test" => 0,
    "LWP::Simple" => 0,
    "LWP::UserAgent" => 0,
    "List::MoreUtils" => 0,
    "List::Util" => 0,
    "Log::Log4perl" => 0,
    "Moose" => 0,
    "Moose::Util::TypeConstraints" => 0,
    "MooseX::ClassAttribute" => 0,
    "MooseX::Log::Log4perl" => 0,
    "MooseX::SimpleConfig" => 0,
    "MooseX::Types::Path::Class" => 0,
    "MooseX::Types::Path::Class::MoreCoercions" => 0,
    "MooseX::Types::URI" => 0,
    "Path::Class" => 0,
    "Perl6::Slurp" => 0,
    "Pod::Usage" => 0,
    "Readonly" => 0,
    "Scalar::Util" => 0,
    "Sub::Exporter" => 0,
    "Sys::Hostname" => 0,
    "Template" => 0,
    "Template::Plugin" => 0,
    "TraceServer" => 0,
    "Try::Tiny" => 0,
    "URI" => 0,
    "WWW::Mechanize" => 0,
    "YAML::Any" => 0,
    "base" => 0,
    "namespace::autoclean" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "VERSION" => "0.051",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



