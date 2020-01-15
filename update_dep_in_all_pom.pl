##############################################################################
##### declare uses

## basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;
use Carp qw(cluck confess); # to use instead of (warn die)

# required for the script
use Date::Calc(qw(Today_and_Now Delta_DHMS Add_Delta_Days Add_Delta_DHMS));
use Getopt::Long;
use File::stat;
use File::Find;
use File::Path;
use File::Copy;
use File::Basename;
use File::Spec::Functions;
use FindBin;
use lib $FindBin::Bin;
use XML::DOM;

# custom perl module(s)
use Perforce;



#############################################################################
##### declare vars
#for script it self
use vars qw (
	$CURRENT_DIR
	$OBJECT_MODEL
	$BUILD_MODE
	%all_areas
	%impacted_areas
	@areas_to_update
	$p4
	@StartScript
	$StartDateTime
	$StopDateTime
);

# parameter/options
use vars qw (
	$param_client_spec
	$param_src_dir
	$param_ini_file
	$param_dependency_to_update
	$param_areas_to_update
	$param_current_version
	$param_next_version
	$param_model
	$param_build_mode
	$param_current_dependency_version
	$param_replace_dependency_version
	$opt_List
	$opt_Update
	$opt_Add
	$opt_Remove
	$opt_Help
);



#############################################################################
##### declare functions
sub sap_init_vars();
sub sap_search_all_poms_in_src_dir();
sub sap_check_no_opened_file();
sub sap_list_impacted_poms_for_update();
sub sap_get_dependencies_from($$);
sub sap_search_impacted_areas();
sub sap_search_obsolete_areas();
sub sap_get_depot_path($);
sub sap_update_poms();
sub sap_add_dependency();
sub sap_remove_dependency();
sub sap_clean_poms();
sub sap_windows_path($);
sub sap_search_if_new_dep_already_in($$$);
sub sap_display_usage($);



#############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
	"c=s"		=>\$param_client_spec,
	"s=s"		=>\$param_src_dir,
	"i=s"		=>\$param_ini_file,
	"d=s"		=>\$param_dependency_to_update,
	"a=s"		=>\$param_areas_to_update,
	"cv=s"		=>\$param_current_version,
	"nv=s"		=>\$param_next_version,
	"cdv=s"		=>\$param_current_dependency_version,
	"rdv=s"		=>\$param_replace_dependency_version,
	"64!"		=>\$param_model,
	"m=s"		=>\$param_build_mode,
	"L=s"		=>\$opt_List,
	"U"  		=>\$opt_Update,
	"A"  		=>\$opt_Add,
	"R"  		=>\$opt_Remove,
	"help|h|?"	=>\$opt_Help,

);
sap_display_usage("") if($opt_Help);



#############################################################################
##### init vars
$StartDateTime = sprintf("at %s\n", scalar localtime);
chomp $StartDateTime;
if($param_current_dependency_version) {
	($param_dependency_to_update,$param_current_version) = split ':' , $param_current_dependency_version ;
}
unless($opt_List && ($opt_List =~ /^help$/i)) {
	sap_init_vars();
	sap_search_all_poms_in_src_dir();
}



#############################################################################
##### MAIN

print "
#### START of $0 $StartDateTime ####

";

sap_check_no_opened_file() unless($opt_List && ($opt_List =~ /^help$/i));

if($opt_List) {
	if($opt_List =~ /^help$/i) {
		print "
-L=help    : to display this sub help
-L=all     : to display all pom files and their dependencies
-L=impacts : to display impacted areas
-L=nodep   : to display all poms without any dependency
-L=obs     : to display area obsolete (unused or not updated)
";
		exit 0;
	}  elsif($opt_List =~ /^all$/i)  {
		print "\nList All area(s) :\n";
		print   "==================\n\n";
		my $nb_pom_files = 0;
		foreach my $tmp_area (sort keys %all_areas) {
			next if($param_areas_to_update && !(grep /^$tmp_area$/ , @areas_to_update) );
			(my $area = $tmp_area) =~ s-\_XXX\_-\/-;
			my $windows_pom_path = sap_windows_path("$param_src_dir/$area/pom.xml");
			my $DepotFile = sap_get_depot_path("$param_src_dir/$area");
			print "$area - $windows_pom_path - $DepotFile\n";
			$nb_pom_files++;
			my $nb_dep = 0;
			foreach my $ArtifactId (sort keys %{$all_areas{$tmp_area}{dependencies}}) {
				print "\t$ArtifactId\n";
				foreach my $Version (sort @{$all_areas{$tmp_area}{dependencies}{$ArtifactId}{versions}}) {
					print "\t\t$Version\n";
					$nb_dep++;
				}
			}
			if($nb_dep > 0) {
				print "nb dependencies of $area : $nb_dep\n";
			}  else  {
				print "no dependency found for $area ($windows_pom_path)\n";
			}
			print "\n";
		}
		print "\nnb total of pom files : $nb_pom_files\n";
	}  elsif($opt_List =~ /^impacts$/i)  {
		sap_search_impacted_areas();
		print "\nList impacted area(s) :\n";
		print   "=======================\n\n";
		my $nb_pom_files = 0;
		foreach my $tmp_area (sort keys %impacted_areas) {
			next if($param_areas_to_update && !(grep /^$tmp_area$/ , @areas_to_update) );
			(my $area = $tmp_area) =~ s-\_XXX\_-\/-;
			my $windows_pom_path = sap_windows_path("$param_src_dir/$area/pom.xml");
			my $DepotFile = sap_get_depot_path("$param_src_dir/$area");
			print "$area - $windows_pom_path - $DepotFile\n";
			my $nb_dep = 0;
			foreach my $ArtifactId (sort keys %{$impacted_areas{$tmp_area}{dependencies}}) {
				print "\t$ArtifactId\n";
				foreach my $Version (sort @{$impacted_areas{$tmp_area}{dependencies}{$ArtifactId}{versions}}) {
					print "\t\t$Version\n";
					$nb_dep++;
				}
			}
			$nb_pom_files++ if( $nb_dep >0);
			foreach my $ArtifactId (sort keys %{$impacted_areas{$tmp_area}{other}}) {
				foreach my $Version (sort @{$impacted_areas{$tmp_area}{other}{$ArtifactId}{versions}}) {
					if($nb_dep == 0) {
						print "\t\tWARNING : other version found : $Version , the pom file will not be updated\n";
					}  else  {
						print "\t\tWARNING : other version found : $Version , this version will not be updated\n";
					}
				}
			}
			print "\n";
		}
		print "\n\nnb impacted pom files : $nb_pom_files\n";
	}  elsif($opt_List =~ /^nodep$/i)  {
		print "\nList area(s) without any dependency :\n";
		print   "=====================================\n\n";
		my $nb_pom_files = 0;
		foreach my $tmp_area (sort keys %all_areas) {
			next if($param_areas_to_update && !(grep /^$tmp_area$/ , @areas_to_update) );
			(my $area = $tmp_area) =~ s-\_XXX\_-\/-;
			my $windows_pom_path = sap_windows_path("$param_src_dir/$area/pom.xml");
			my $DepotFile = sap_get_depot_path("$param_src_dir/$area");
			my $nb_dep = 0;
			foreach my $ArtifactId (sort keys %{$all_areas{$tmp_area}{dependencies}}) {
				foreach my $Version (sort @{$all_areas{$tmp_area}{dependencies}{$ArtifactId}{versions}}) {
					$nb_dep++;
				}
			}
			if($nb_dep == 0) {
				$nb_pom_files++;
				print "$area - $windows_pom_path - $DepotFile\n";
			}
		}
		print "\n\nnb pom files : $nb_pom_files\n";
	}  elsif($opt_List =~ /^obs$/i)  {
		sap_search_obsolete_areas();
	}  else  {
		print "
ERROR : $opt_List unkown, available values:
-L=help    : to display this sub help
-L=all     : to display all pom files and their dependencies
-L=impacts : to display impacted areas
-L=nodep   : to display all poms without any dependency
-L=obs     : to display area obsolete (unused or not updated)
";
		exit 1;
	}
	print "\n";
}

if($opt_Update) {
	sap_search_impacted_areas();
	sap_update_poms();
}

if($opt_Add) {
	sap_add_dependency();
}

if($opt_Remove) {
	sap_search_impacted_areas();
	sap_remove_dependency();
}

$p4->Final() if($p4);
$StopDateTime = sprintf("at %s\n", scalar localtime);
chomp $StopDateTime;
print "\n#### STOP of $0 $StopDateTime ####\n";
printf("$0 took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartScript, Today_and_Now()))[1..3], scalar localtime);
print "\n";
exit 0;



#############################################################################
### internal functions
sub sap_init_vars() {
	@StartScript   = Today_and_Now();
	$CURRENT_DIR  = $FindBin::Bin;
	$OBJECT_MODEL = $param_model ? "64" : "32" if(defined $param_model);
	$ENV{OBJECT_MODEL} = $OBJECT_MODEL ||= $ENV{OBJECT_MODEL} || "32";
	$BUILD_MODE ||= $ENV{BUILD_MODE} || "release";
	if($ENV{BUILD_MODE}) {
		if( ($BUILD_MODE) && ($BUILD_MODE ne $ENV{BUILD_MODE}) ) {
			my $msg  = "-m=$BUILD_MODE is different than the environment variable";
			$msg    .= "BUILD_MODE=$ENV{BUILD_MODE}";
			$msg    .= ", to not mix, $0 exit now";
			sap_display_usage($msg);
		}
	}
	if("debug"=~/^$BUILD_MODE/i) {
		$BUILD_MODE="debug";
	}  elsif("release"=~/^$BUILD_MODE/i)  {
		$BUILD_MODE="release";
	}  elsif("releasedebug"=~/^$BUILD_MODE/i)  {
		$BUILD_MODE="releasedebug";
	}  else  {
		sap_display_usage("compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease|releasedebug]");
	}
	if($param_ini_file && -e $param_ini_file) {
		my $perl_cmd = "perl $CURRENT_DIR/rebuild.pl"
					 . " -i=$param_ini_file"
					 . " -om=$OBJECT_MODEL"
					 . " -m=$BUILD_MODE";
		$param_client_spec = `$perl_cmd -si=clientspec` unless($param_client_spec);
		chomp $param_client_spec;
		$param_src_dir	   = `$perl_cmd -si=src_dir`    unless($param_src_dir);
		chomp $param_src_dir;
		if ( ! -e $param_src_dir ) {
			sap_display_usage("$param_src_dir not found");
		}
		$p4 = new Perforce;
		eval { $p4->Login("-s") };
		$p4->SetClient($param_client_spec);
		confess("ERROR: cannot set client '$param_client_spec': ", @{$p4->Errors()}, " ") if($p4->ErrorCount());
	}  else  {
		unless($param_client_spec) {
			sap_display_usage("-c=clientspec missing, plese run $0 -c=clientspec");
		}  else  {
			$p4 = new Perforce;
			eval { $p4->Login("-s") };
			$p4->SetClient($param_client_spec);
			confess("ERROR: cannot set client '$param_client_spec': ", @{$p4->Errors()}, " ") if($p4->ErrorCount());
			unless($param_src_dir) {
				my @ClientSpecDescr = $p4->client("-o");
				(my $param_src_dir = $ClientSpecDescr[0]{Root}) =~ s-^\s+--; # get roo value
				($param_src_dir) =~ s-\\-\/-g;	#transform to unix style, supported under windows if no DOS command executed
				if ( ! -e $param_src_dir ) {
					sap_display_usage("$param_src_dir not found");
				}
			}
		}
	}
	if($param_areas_to_update) {
		(my $tmp = $param_areas_to_update) =~ s-\/-\_XXX\_-g;
		@areas_to_update = split ',' , $tmp;
	}
}

sub sap_search_all_poms_in_src_dir() {
	chdir $param_src_dir or confess "\nERROR : cannot chdir into $param_src_dir: $!\n\n";
	my @areas;
	if ( open LS1 , "ls */pom.xml |" ) {
		while(<LS1>) {
			chomp;
			my $pom_file = $_;
			my ($area) = $pom_file =~ /^(.+?)\/pom.xml$/;
			next if($param_areas_to_update && !(grep /^$area$/ , @areas_to_update) );
			push @areas , $area;
		}
		close LS1;
	}
	if ( open LS2 , "ls */*/pom.xml |" ) {    # for tp in multi version mode
		while(<LS2>) {
			chomp;
			my $pom_file = $_;
			my ($area,$version) = $pom_file =~ /^(.+?)\/(.+?)\/pom.xml$/;
			next if($version =~ /^export$/);			 # not a pom for the fetch.
			next if( -e "$param_src_dir/$area/pom.xml"); # not a pom for the fetch.
			my $tmp_area = "${area}_XXX_$version";
			next if($param_areas_to_update && !(grep /^$tmp_area$/ , @areas_to_update) );
			push @areas , $tmp_area;
		}
		close LS2;
	}
	foreach my $area (sort @areas) {
		next if($param_areas_to_update && !(grep /^$area$/ , @areas_to_update) );
		my $pom_file = "$area/pom.xml";
		($pom_file) =~ s-\_XXX\_-\/-;
		(my $tmp_path = $pom_file) =~ s-\/pom.xml$--i;
		$all_areas{$area}{path} = "$param_src_dir/$tmp_path";
		sap_get_dependencies_from($area,"$param_src_dir/$pom_file")
	}
}

sub sap_check_no_opened_file() {
	my $continue_script = 1;
	my @opened_files = @{$p4->opened()};
	$continue_script = 0 if(scalar @opened_files > 0);
	if($continue_script == 0) {
		$p4->Final() if($p4);
		print "\nWARNING : Some openeded files are detected for clientspec $param_client_spec :\n\n";
		my $nb_opened_files = 0;
		foreach my $opened_file (@opened_files) {
			print "$opened_file";
			$nb_opened_files++;
		}
		print "\nnb opened file(s) : $nb_opened_files\n";
		print "$0 will exit without doing anything.\n";
		print "Please submit or revert these files above before running $0.\n";
		$StopDateTime = sprintf("at %s\n", scalar localtime);
		chomp $StopDateTime;
		print "\n\n#### STOP of $0 $StopDateTime ####\n";
		printf("\n$0 took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartScript, Today_and_Now()))[1..3], scalar localtime);
		print "\n";
		exit 0;
	}
}


sub sap_get_dependencies_from($$) {
	my ($this_area,$this_pom_file) = @_ ;
	eval
	{
		my $POM = XML::DOM::Parser->new()->parsefile($this_pom_file);
		for my $DEPENDENCY (@{$POM->getElementsByTagName("dependency")}) {
			my $ArtifactId = $DEPENDENCY->getElementsByTagName("artifactId", 0)->item(0)->getFirstChild()->getData();
			my $Version    = $DEPENDENCY->getElementsByTagName("version",    0)->item(0)->getFirstChild()->getData();
			push @{$all_areas{$this_area}{dependencies}{$ArtifactId}{versions}} , $Version unless(grep /^$Version$/ , @{$all_areas{$this_area}{dependencies}{$ArtifactId}{versions}}) ;
		}
		$POM->dispose();
	};
}

sub sap_search_impacted_areas() {
	unless($param_current_version) {
		confess "\nERROR : -cv missing, pease use $0 -cv=version\n\n";
	}
	foreach my $area (sort keys %all_areas) {
		next if($param_areas_to_update && !(grep /^$area$/ , @areas_to_update) );
		foreach my $ArtifactId (sort keys %{$all_areas{$area}{dependencies}}) {
			next unless($param_dependency_to_update && $param_dependency_to_update =~ /^$ArtifactId$/);
			foreach my $Version (sort @{$all_areas{$area}{dependencies}{$ArtifactId}{versions}}) {
				if ($Version =~ /^$param_current_version$/) {
					push @{$impacted_areas{$area}{dependencies}{$ArtifactId}{versions}} , $Version unless(grep /^$Version$/ , @{$impacted_areas{$area}{dependencies}{$ArtifactId}{versions}} );
					$impacted_areas{$area}{path} = $all_areas{$area}{path};
				}  else  {
					push @{$impacted_areas{$area}{other}{$ArtifactId}{versions}} , $Version unless(grep /^$Version$/ , @{$impacted_areas{$area}{other}{$ArtifactId}{versions}} ) ;
				}
			}
		}
	}
}

sub sap_search_obsolete_areas() {
	my %unused_areas;
	foreach my $area (sort keys %all_areas) {
		next if($param_areas_to_update && !(grep /^$area$/ , @areas_to_update) );
		(my $final_area = $area) =~ s-\_XXX\_-\/-;
		my ($final_version_a) = $area =~ /\_XXX\_-(.+?)$/;
		foreach my $ArtifactId (sort keys %{$all_areas{$area}{dependencies}}) {
			foreach my $Version (sort @{$all_areas{$area}{dependencies}{$ArtifactId}{versions}}) {
				(my $finale_version_b = $Version) =~ s-\-SNAPSHOT$--;
				($finale_version_b) =~ s-\_XXX\_-\/-;
				if( ( ! -e "$param_src_dir/$ArtifactId/pom.xml")
				 && ( ! -e "$param_src_dir/$ArtifactId/$finale_version_b/pom.xml")
				 && ( ! -e "$param_src_dir/$ArtifactId/export")
				 && ( ! -e "$param_src_dir/$ArtifactId/$finale_version_b/export") ) {
				 	# in case of mapping for the fetch
				 	# eg : tp.apache.xerces.cpp/2.1.0_sap.1 -> tp.apache.xerces.cpp/2.1.0
				 	my $p4_result = `p4 client -o $param_client_spec | grep -w $ArtifactId | grep -w $finale_version_b`;
				 	chomp $p4_result;
				 	unless($p4_result) {
				 		push @{$unused_areas{$area}{unused}{$ArtifactId}} , $Version unless(grep /^$Version$/ , @{$unused_areas{$area}{unused}{$ArtifactId}} );
				 	}
				}
			}
		}
	}

	print "\nList of area(s)/version(s) not used/not updated :\n";
	print   "=================================================\n\n";
	my $nb_pom_files = 0;
	foreach my $tmp_area (sort keys %unused_areas) {
		next if($param_areas_to_update && !(grep /^$tmp_area$/ , @areas_to_update) );
		(my $area = $tmp_area) =~ s-\_XXX\_-\/-;
		my $windows_pom_path = sap_windows_path("$param_src_dir/$area/pom.xml");
		my $DepotFile = sap_get_depot_path("$param_src_dir/$area");
		print "$area - $windows_pom_path - $DepotFile\n";
		$nb_pom_files++;
		foreach my $ArtifactId (sort keys %{$unused_areas{$area}{unused}}) {
			print "\t$ArtifactId\n";
			foreach my $Version (sort @{$unused_areas{$area}{unused}{$ArtifactId}}) {
				print "\t\t$Version\n";
			}
		}
		print "\n";
	}
	print "\n\nnb impacted pom files : $nb_pom_files\n" if($nb_pom_files >0);
}

sub sap_update_poms() {
	my $replace_dependency;
	my $replace_version;
	if($param_replace_dependency_version) {
		($replace_dependency,$replace_version) = split ':' , $param_replace_dependency_version ;
		$param_next_version = $replace_version ;
	}
	unless($param_next_version) {
		confess "\nERROR : -nv missing, pease use $0 -nv=next version\n\n";
	}
	if($param_replace_dependency_version) {
		print "\nReplace the dependency $param_dependency_to_update from version $param_current_version, with $replace_dependency, version : $replace_version\n";
		print ("=" x (length("Replace the dependency $param_dependency_to_update from version $param_current_version, with $replace_dependency, version : $replace_version")),"\n\n");
	}  else  {
		print "\nUpdate the dependency $param_dependency_to_update from version $param_current_version to $param_next_version\n";
		print ("=" x (length("Update the dependency $param_dependency_to_update from version $param_current_version to $param_next_version")),"\n\n");
	}
	print "use client spec: $param_client_spec\n\n";
	my $nb_pom_files = 0;
	foreach my $tmp_area (sort keys %impacted_areas) {
		next if($param_areas_to_update && !(grep /^$tmp_area$/ , @areas_to_update) );
		(my $area = $tmp_area) =~ s-\_XXX\_-\/-;
		next unless($impacted_areas{$tmp_area}{path});
		my $area_dir = $impacted_areas{$tmp_area}{path};
		my $windows_pom_path = sap_windows_path("$impacted_areas{$tmp_area}{path}/pom.xml");
		chdir $area_dir or confess "\n\nERROR : cannot chdir into $area_dir: $!\n\n";
		my $DepotFile = sap_get_depot_path($area_dir);
		print "Update  $area  -  $windows_pom_path  -  $DepotFile\n";
		my $step = 0;
		$step++;
		print "\t[$step] p4 -c $param_client_spec sync -f $DepotFile\n";
		$p4->sync("-f", "$DepotFile");
		my $already_exist = 0;
		if( (defined $param_replace_dependency_version) && (defined $replace_dependency) && (defined $replace_version) ) {
			$already_exist = sap_search_if_new_dep_already_in("$impacted_areas{$tmp_area}{path}/pom.xml",$replace_dependency,$replace_version) ;
		}
		$step++;
		print "\t[$step] rm -f $impacted_areas{$tmp_area}{path}/pom.xml.orig\n";
		system "rm -f $impacted_areas{$tmp_area}{path}/pom.xml.orig";
		$step++;
		print "\t[$step] cp -f $impacted_areas{$tmp_area}{path}/pom.xml $impacted_areas{$tmp_area}{path}/pom.xml.orig\n";
		system "cp -f $impacted_areas{$tmp_area}{path}/pom.xml $impacted_areas{$tmp_area}{path}/pom.xml.orig";
		$step++;
		print "\t[$step] p4 -c $param_client_spec edit -t ktext $DepotFile\n";
		$p4->edit("-t ktext", $DepotFile);
		if(open my $POM_ORIG , '<' , "$impacted_areas{$tmp_area}{path}/pom.xml") {
			$step++;
			print "\t[$step] open $impacted_areas{$tmp_area}{path}/pom.xml\n";
			if(open my $POM_NEW , '>' , "$impacted_areas{$tmp_area}{path}/pom.xml.new") {
				$step++;
				print "\t[$step] create $impacted_areas{$tmp_area}{path}/pom.xml.new\n";
				my $is_a_dependency = 0 ;
				my $start_dep_line  = "";
				my $groupId_line    = "";
				my $artifactId_line = "";
				my $artifactId_Orig = "";
				my $find_artifact   = 0 ;
				my $version_line    = "";
				my $gav_line        = "";
				while(<$POM_ORIG>) {
					my $line = $_;
					if($line =~ /\<dependency\>/i) {
						$is_a_dependency = 1 ;
						$start_dep_line = $line ;
						next ;
					}
					if($is_a_dependency == 1) {
						if($line =~ /\<groupId\>/i) {
							$groupId_line = $line;
							next;
						}
						if($line =~ /\<artifactId\>(.+?)\<\/artifactId\>/i) {
							my $artifactID   = $1;
							$artifactId_Orig = $line;
							$artifactId_line = $line;
							if ($artifactID =~ /^$param_dependency_to_update$/) {
								if(defined $param_replace_dependency_version && defined $replace_dependency) {
									($artifactId_line) =~ s-$artifactID-$replace_dependency-;
								}
								$find_artifact = 1;
							}
							next;
						}
						if($line =~ /\<version\>(.+?)\<\/version\>/i) {
							my $version   = $1;
							$version_line = $line;
							if($version =~ /^$param_current_version$/) {
								if($find_artifact == 1) {
									if(defined $param_next_version) {
										($version_line) =~ s-$version-$param_next_version-;
									}
								}  else  {
									$artifactId_line = $artifactId_Orig ;
									$find_artifact   = 0 ;
								}
							}  else  {
								$artifactId_line = $artifactId_Orig ;
								$find_artifact   = 0 ;
							}
							next;
						}
						$gav_line = $start_dep_line . $groupId_line . $artifactId_line . $version_line ;
					}
					if($line =~ /\<\/dependency\>/i) {
						$gav_line .= $line ;
						if($find_artifact == 1) {
							$step++;
							if($already_exist == 1) {
								print "\t[$step] Dependency already exists $replace_dependency:$replace_version, just remove $param_dependency_to_update:$param_current_version\n";
								$gav_line = "";
							}  else  {
								if(defined $param_replace_dependency_version) {
									print "\t[$step] Replace the dependency $param_dependency_to_update from version $param_current_version, with $replace_dependency, version : $replace_version\n";
								}  else  {
									print "\t[$step] Update the dependency $param_dependency_to_update from version $param_current_version to $param_next_version\n";
								}
							}
						}
						print $POM_NEW $gav_line ;
						$is_a_dependency = 0 ;
						$start_dep_line  = "";
						$groupId_line    = "";
						$artifactId_line = "";
						$artifactId_Orig = "";
						$find_artifact   = 0 ;
						$version_line    = "";
						$gav_line        = "";
						next;
					}
					print $POM_NEW $line;
				}
				$step++;
				print "\t[$step] close $impacted_areas{$tmp_area}{path}/pom.xml.new\n";
				close $POM_NEW;
				
			}
			$step++;
			print "\t[$step] close $impacted_areas{$tmp_area}{path}/pom.xml\n";
			close $POM_ORIG;
			$step++;
			print "\t[$step] rename $impacted_areas{$tmp_area}{path}/pom.xml.new to $impacted_areas{$tmp_area}{path}/pom.xml\n";
			rename "$impacted_areas{$tmp_area}{path}/pom.xml.new","$impacted_areas{$tmp_area}{path}/pom.xml";
			print "done\n\n";
			$nb_pom_files++;
		}
	}
	print "\nnb pom files updated : $nb_pom_files\n";
	print "Please remind to submit or revert them yourself\n";
}

sub sap_add_dependency() {
	unless($param_next_version) {
		confess "\nERROR : -nv missing, pease use $0 -nv=next version\n\n";
	}
	my $groupID = "com.sap";
	if($param_dependency_to_update =~ /^tp\./) {
		$groupID .= ".tp";
	}
	print "\nAdd the dependency $param_dependency_to_update with version $param_next_version\n";
	print ("=" x (length("Add the dependency $param_dependency_to_update with version $param_next_version")),"\n\n");
	print "use client spec: $param_client_spec\n\n";
	my $nb_pom_files = 0;

	foreach my $tmp_area (sort keys %all_areas) {
		next if($param_areas_to_update && !(grep /^$tmp_area$/ , @areas_to_update) );
		(my $area = $tmp_area) =~ s-\_XXX\_-\/-;
		next unless($all_areas{$tmp_area}{path});
		my $area_dir = $all_areas{$tmp_area}{path};
		my $windows_pom_path = sap_windows_path("$all_areas{$tmp_area}{path}/pom.xml");
		chdir $area_dir or confess "\n\nERROR : cannot chdir into $area_dir: $!\n\n";
		my $DepotFile = sap_get_depot_path($area_dir);
		print "Update  $area  -  $windows_pom_path  -  $DepotFile\n";
		my $step = 0;
		$step++;
		print "\t[$step] p4 -c $param_client_spec sync -f $DepotFile\n";
		$p4->sync("-f", "$DepotFile");
		$step++;
		print "\t[$step] rm -f $all_areas{$tmp_area}{path}/pom.xml.orig\n";
		system "rm -f $all_areas{$tmp_area}{path}/pom.xml.orig";
		$step++;
		print "\t[$step] cp -f $all_areas{$tmp_area}{path}/pom.xml $all_areas{$tmp_area}{path}/pom.xml.orig\n";
		system "cp -f $all_areas{$tmp_area}{path}/pom.xml $all_areas{$tmp_area}{path}/pom.xml.orig";
		$step++;
		print "\t[$step] p4 -c $param_client_spec edit -t ktext $DepotFile\n";
		$p4->edit("-t ktext", $DepotFile);
		if(open my $POM_ORIG , '<' , "$all_areas{$tmp_area}{path}/pom.xml") {
			$step++;
			print "\t[$step] open $all_areas{$tmp_area}{path}/pom.xml\n";
			if(open my $POM_NEW , '>' , "$all_areas{$tmp_area}{path}/pom.xml.new") {
				$step++;
				print "\t[$step] create $all_areas{$tmp_area}{path}/pom.xml.new\n";
				my $end_dependencies = 0;
				while(<$POM_ORIG>) {
					my $line = $_;
					$end_dependencies = 1 if($line =~ /\<\/dependencies\>/);
					if($end_dependencies == 1) {
						print $POM_NEW "        <dependency>
            <groupId>$groupID</groupId>
            <artifactId>$param_dependency_to_update</artifactId>
            <version>$param_next_version</version>
        </dependency>\n";
						$end_dependencies = 0;
						$step++;
						print "\t[$step] add $param_dependency_to_update with version $param_next_version\n";
					}
					print $POM_NEW $line;
				}
				$step++;
				print "\t[$step] close $all_areas{$tmp_area}{path}/pom.xml.new\n";
				close $POM_NEW;
				
			}
			$step++;
			print "\t[$step] close $all_areas{$tmp_area}{path}/pom.xml\n";
			close $POM_ORIG;
			$step++;
			print "\t[$step] rename $all_areas{$tmp_area}{path}/pom.xml.new to $all_areas{$tmp_area}{path}/pom.xml\n";
			rename "$all_areas{$tmp_area}{path}/pom.xml.new","$all_areas{$tmp_area}{path}/pom.xml";
			print "done\n\n";
			$nb_pom_files++;
		}
	}
	print "\nnb pom files updated : $nb_pom_files\n";
	print "Please remind to submit or revert them yourself\n";
}

sub sap_remove_dependency() {
	print "\nRemove the dependency $param_dependency_to_update/$param_current_version\n";
	print ("=" x (length("Remove the dependency $param_dependency_to_update/$param_current_version")),"\n\n");
	print "use client spec: $param_client_spec\n\n";
	my $nb_pom_files = 0;
	foreach my $tmp_area (sort keys %impacted_areas) {
		next if($param_areas_to_update && !(grep /^$tmp_area$/ , @areas_to_update) );
		(my $area = $tmp_area) =~ s-\_XXX\_-\/-;
		next unless($impacted_areas{$tmp_area}{path});
		my $area_dir = $impacted_areas{$tmp_area}{path};
		my $windows_pom_path = sap_windows_path("$impacted_areas{$tmp_area}{path}/pom.xml");
		chdir $area_dir or confess "\n\nERROR : cannot chdir into $area_dir: $!\n\n";
		my $DepotFile = sap_get_depot_path($area_dir);
		print "Update  $area  -  $windows_pom_path  -  $DepotFile\n";
		my $step = 0;
		$step++;
		print "\t[$step] p4 -c $param_client_spec sync -f $DepotFile\n";
		$p4->sync("-f", "$DepotFile");
		$step++;
		print "\t[$step] rm -f $impacted_areas{$tmp_area}{path}/pom.xml.orig\n";
		system "rm -f $impacted_areas{$tmp_area}{path}/pom.xml.orig";
		$step++;
		print "\t[$step] cp -f $impacted_areas{$tmp_area}{path}/pom.xml $impacted_areas{$tmp_area}{path}/pom.xml.orig\n";
		system "cp -f $impacted_areas{$tmp_area}{path}/pom.xml $impacted_areas{$tmp_area}{path}/pom.xml.orig";
		$step++;
		print "\t[$step] p4 -c $param_client_spec edit -t ktext $DepotFile\n";
		$p4->edit("-t ktext", $DepotFile);
		my @orig_lines;

		if(open my $POM_ORIG , '<' , "$impacted_areas{$tmp_area}{path}/pom.xml") {
			@orig_lines = <$POM_ORIG>;
			close $POM_ORIG;
		}
		my $is_a_dependency = 0;
		my $find_artifact   = 0;
		my @final_lines     = ();
		my @current_gav     = ();
		$step++;
		print "\t[$step] parse $impacted_areas{$tmp_area}{path}/pom.xml\n";
		foreach my $line_orig (@orig_lines) {
			if($line_orig =~ /\<dependency\>/) {
				$is_a_dependency = 1;
				push @current_gav , $line_orig;
				next;
			}  elsif($line_orig =~ /\<groupId\>/)  {
				if($is_a_dependency == 1) {
					push @current_gav , $line_orig;
				}  else  {
					push @final_lines , $line_orig;
				}
				next;
			}  elsif($line_orig =~ /\<artifactId\>(.+?)\<\/artifactId\>/)  {
				if($1 =~ /^$param_dependency_to_update$/) {
					if($is_a_dependency == 1) {
						push @current_gav , $line_orig;
						$find_artifact = 1;
					}  else  {
						push @final_lines , $line_orig;
						$find_artifact = 0;
					}
				}  else  {
					if($is_a_dependency == 1) {
						push @current_gav , $line_orig;
						$find_artifact = 0;
					}  else  {
						push @final_lines , $line_orig;
						$find_artifact = 0;
					}
				}
				next;
			}  elsif($line_orig =~ /\<version\>(.+?)\<\/version\>/)  {
				if($1 =~ /^$param_current_version$/) {
					if($is_a_dependency == 1) {
						if($find_artifact == 1) {
							@current_gav =() ; # to skip
						}  else  {
							push @current_gav , $line_orig;
						}
					}  else  {
						push @final_lines , $line_orig;
					}
				}  else  {
					if($is_a_dependency == 1) {
						push @current_gav , $line_orig;
					}  else  {
						push @final_lines , $line_orig;
					}
				}
				next;
			}  elsif($line_orig =~ /\<\/dependency\>/)  {
				if(scalar @current_gav > 0) {
					foreach my $tmp (@current_gav) {
						push @final_lines , $tmp;
					}
					push @final_lines , $line_orig;
					@current_gav =() ;
				}
				next;
			}  else  {
				push @final_lines , $line_orig;
			}
		}
		if(open my $POM_NEW , '>' , "$all_areas{$tmp_area}{path}/pom.xml.new") {
			$nb_pom_files++;
			foreach my $line (@final_lines) {
				print $POM_NEW $line;
			}
			close $POM_NEW;
			$step++;
			print "\t[$step] close $all_areas{$tmp_area}{path}/pom.xml\n";
			$step++;
			print "\t[$step] rename $all_areas{$tmp_area}{path}/pom.xml.new to $all_areas{$tmp_area}{path}/pom.xml\n";
			rename "$all_areas{$tmp_area}{path}/pom.xml.new","$all_areas{$tmp_area}{path}/pom.xml";
			print "done\n\n";
		}
	}
	print "\nnb pom files updated : $nb_pom_files\n";
	print "Please remind to submit or revert them yourself\n";
}

sub sap_windows_path($) {
	my ($this_pom_file) = @_ ;
	my $tmp_windows_pom_path = $this_pom_file;
	($tmp_windows_pom_path) =~ s-\/-\\-g;
	return $tmp_windows_pom_path
}

sub sap_get_depot_path($) {
	my ($this_path) = @_ ;
	chdir $this_path or confess "\n\nERROR : cannot chdir into $this_path: $!\n\n";
	my $rafstat = $p4->fstat("$this_path/pom.xml");
	my $this_DepotFile;
	foreach (@{$rafstat}) {
		$this_DepotFile = $1 if(/depotFile\s+(.+\/pom.xml)$/);
	}
	chomp $this_DepotFile;
	return $this_DepotFile;
}

#$replace_dependency,$replace_version
sub sap_search_if_new_dep_already_in($$$) {
	my ($this_pom_file,$this_artifact,$this_version) = @_ ;
	my $found = 0;
	if(open my $POM_FILE , '<' , "$this_pom_file") {
		my $start_deps    = 0;
		my $find_artifact = 0;
		while(<$POM_FILE>) {
			chomp;
			my $line = $_;
			if($line =~ /\<\/dependencies\>/) {
				$start_deps = 0 ;
				last;
			}
			if($line =~ /\<dependencies\>/) {
				$start_deps = 1 ;
				next;
			}
			if( ($line =~ /\<artifactId\>(.+?)\<\/artifactId\>/) && ($start_deps ==1) ) {
				if($1 =~ /^$this_artifact$/) {
					$find_artifact = 1 ;
					next;
				}
			}
			if( ($line =~ /\<version\>(.+?)\<\/version\>/) && ($start_deps ==1) ) {
				my $this_version_in_pom = $1 ;
				if($find_artifact == 1) {
					if($this_version_in_pom =~ /^$this_version$/) {
						$found = 1 ;
						last;
					}
				}
			}
		}
		close $POM_FILE;
	}
	return $found
}

sub sap_display_usage($) {
	my ($msg) = @_ ;
	if($msg) {
		print STDERR "

\tERROR:
\t======
$msg
";
	$p4->Final() if($p4);
	exit 1;
	}
	print <<FIN_USAGE;

	Description : $0 can can update a common dependency of all pom files.
	Usage   : perl $0 [options]
	Example : perl $0 -h

 [options]
	-64      Force the 64 bits compilation (-64) or not (-no64), default is -no64 i.e 32 bits,
	         same usage than Build.pl -64
	-m       Choose a compile mode,
	         same usage than Build.pl -m=...
	-i       ini file
	         same usage than Build.pl -i=...
	-d       dependency (area or tp) to update
	-a       list of restricted areas to update, separated by commas,
	         no '*' is allowed
	-cv      current version of dependency to update/add/remove
	-nv      new/next version to update/add
	-cdv     dependency (area or tp) to update, with current version
	         eg: -cdv=tp.sun.jdk:1.5-SNAPSHOT
	-rdv     replace dependency set with -cdv=xxx:yyy with new dependency:version (works with -U)
	         eg: -cdv=tp.sun.jdk:1.5-SNAPSHOT -rdv=tp.sap.jvm:8.1-SNAPSHOT
	         perl -w update_dep_in_all_pom.pl -i=contexts\aurora43_cons_ml.ini -m=d -64 -cdv=tp.sun.jdk:1.5-SNAPSHOT -rdv=tp.sap.jvm:8.1-SNAPSHOT -U
	         => will replace tp.sun.jdk:1.5-SNAPSHOT with tp.sap.jvm:8.1-SNAPSHOT
	-L       List different configuration, type $0 -L=help for more details
	-U       Update pom files.
	         mandatory options : -cdv, -nv
	         optional options : -a
	         optional options : -rdv
	-A       Add new dependency
	         mandatory options : -nv
	         optional options : -a
	-R       Remove a dependency
	         mandatory options : -cv

	Notes : $0 won't do anything if somef opened files are detected.

FIN_USAGE
	exit;
}
