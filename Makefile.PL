
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Utilities for LIMS2",
  "AUTHOR" => "Ray Miller <rm7\@sanger.ac.uk>",
  "BUILD_REQUIRES" => {
    "English" => 0,
    "File::Find" => 0,
    "File::Temp" => 0,
    "Test::More" => "0.88",
    "Test::Most" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "LIMS2-Util",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "LIMS2::Util",
  "PREREQ_PM" => {
    "Bio::EnsEMBL::Registry" => 0,
    "Carp" => 0,
    "Class::Data::Inheritable" => 0,
    "Const::Fast" => 0,
    "Hash::MoreUtils" => 0,
    "IO::File" => 0,
    "IO::String" => 0,
    "Iterator::Simple" => 0,
    "JSON" => 0,
    "LIMS2::Exception" => 0,
    "LWP::UserAgent" => 0,
    "Moose" => 0,
    "MooseX::ClassAttribute" => 0,
    "MooseX::Types::URI" => 0,
    "Scalar::Util" => 0,
    "Sub::Exporter" => 0,
    "Template::Plugin" => 0,
    "Try::Tiny" => 0,
    "URI" => 0,
    "YAML::Any" => 0,
    "base" => 0,
    "namespace::autoclean" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "VERSION" => "0.003",
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



