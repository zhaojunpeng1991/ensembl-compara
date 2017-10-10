#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2017] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use warnings;
use strict;

use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Compara::Utils::CopyData qw(:table_copy);
use Getopt::Long;

my ( $help, $reg_conf, $master, $new, $dry_run, @mlss_ids );
GetOptions(
    "help"       => \$help,
    "reg_conf=s" => \$reg_conf,
    "master=s"   => \$master,
    "new=s"      => \$new,
    "dry_run!"   => \$dry_run,
    "mlss_id=i@" => \@mlss_ids,
);

my @tables = (
	'dnafrag',
	'genome_db',
	'method_link_species_set',
	'method_link_species_set_tag',
	'method_link_species_set_attr',
	'species_set',
	'species_set_header',
	'species_set_tag'
);

my $registry = 'Bio::EnsEMBL::Registry';
$registry->load_all($reg_conf, 0, 0, 0, "throw_if_missing") if $reg_conf;

my $master_dba = Bio::EnsEMBL::Compara::DBSQL::DBAdaptor->go_figure_compara_dba( $master );
my $new_dba = Bio::EnsEMBL::Compara::DBSQL::DBAdaptor->go_figure_compara_dba( $new );

my (%mlss_ids, %ss_ids, %gdb_ids);

my $master_mlss_adaptor = $master_dba->get_MethodLinkSpeciesSetAdaptor;
foreach my $mlss_id ( @mlss_ids ) {
	my $master_mlss = $master_mlss_adaptor->fetch_by_dbID($mlss_id); 
	$mlss_ids{$mlss_id} = $master_mlss->name;
	
	my $master_ss   = $master_mlss->species_set;
	my $ss_id = $master_ss->dbID;
	$ss_ids{$ss_id} = $master_ss->name;
	
	my @gdb_id_list = map { $_->dbID } @{ $master_ss->genome_dbs };
	foreach my $gdb ( @{$master_ss->genome_dbs} ) {
		$gdb_ids{$gdb->dbID} = $gdb->name;
	}
}

summarise_copy_data( \%mlss_ids, \%ss_ids, \%gdb_ids );
exit(1) if ( $dry_run );
my $helper = Bio::EnsEMBL::Utils::SqlHelper->new(-DB_CONNECTION => $new_dba->dbc);
$helper->transaction(
    -RETRY => 0,
    -PAUSE => 0,
    -CALLBACK => sub{ perform_copy( \%mlss_ids, \%ss_ids, \%gdb_ids ) },
);


sub summarise_copy_data {
	# my ( $mlss_ids, $ss_ids, $gdb_ids ) = @_;

	foreach my $mlss_name ( values %mlss_ids ) {
		print "Will be copying method_link_species_set '$mlss_name'\n";
	}

	foreach my $ss_name ( values %ss_ids ) {
		print "Will be copying species_set '$ss_name'\n";
	}

	foreach my $gdb_name ( values %gdb_ids ) {
		print "Will be copying genome_db '$gdb_name' + dnafrags\n";
	}
}

sub perform_copy {
	my ( $mlss_ids, $ss_ids, $gdb_ids ) = @_;
	# copy tables with method_link_species_set_id field
	my $mlss_id_list = join(',', keys %$mlss_ids);
	foreach my $table ( 'method_link_species_set','method_link_species_set_tag','method_link_species_set_attr' ) {
		my $mlss_where = "SELECT * FROM $table WHERE method_link_species_set_id IN ($mlss_id_list)";
		# print "Will be copying : $mlss_where\n";
		copy_data($master_dba->dbc, $new_dba->dbc,
	        $table,
	        $mlss_where
	    );
	}

	# copy tables with species_set_id field
	my $ss_id_list = join(',', keys %$ss_ids);
	foreach my $table ( 'species_set','species_set_header','species_set_tag' ) {
		my $ss_where = "SELECT * FROM $table WHERE species_set_id IN ($ss_id_list)";
		# print "Will be copying : $ss_where\n";
		copy_data($master_dba->dbc, $new_dba->dbc,
	        $table,
	        $ss_where
	    );
	}

	# copy tables with genome_db_id field
	my $gdb_id_list = join( ',', keys %$gdb_ids );
	foreach my $table ( 'genome_db', 'dnafrag' ) {
		my $gdb_where = "SELECT * FROM $table WHERE genome_db_id IN ($gdb_id_list)";
		# print "Will be copying : $gdb_where\n";
		copy_data($master_dba->dbc, $new_dba->dbc,
	        $table,
	        $gdb_where
	    );
	}
	1;
}
