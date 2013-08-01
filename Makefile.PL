#!/usr/bin/env perl

use inc::Module::Install 1.02;

name 'LIMS2-Utils';
all_from 'lib/LIMS2/Util.pm';

install_script glob('script/*.pl');
auto_install;
WriteAll;