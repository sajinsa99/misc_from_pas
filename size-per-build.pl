#############################################################################
# size-per-build.pl

#############################################################################
##### declare uses

## ensure good code quality
use strict;
use warnings;
use diagnostics;
use Carp qw(cluck confess);

# requied for the script
use File::Path;
use Time::Local;
use Getopt::Long;
use Data::Dumper;
use Date::Manip::Date;
use JSON qw( decode_json );
# for calculating current dir
use FindBin;
use lib $FindBin::Bin;



#############################################################################
##### declare vars
# system
use vars qw (
	$current_user
	$CURRENTDIR
	$SITE
	$current_day
	$LOG_DIR
);

# for the script itself
use vars qw (
	$Dropzone_Structure
	%to_check
	$default_json
	$drop_base_dir
	$json_dir
);

# options/parameters
use vars qw (
	$param_json_file
	$param_site
	$param_base_drz_dir
	$param_volume
	$param_project
	$param_buildname
	$opt_GO
);



#############################################################################
##### declare functions
sub sap_get_info_from_json();
sub sap_get_full_path_of_this_volume($);
sub sap_end_script();



#############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
	"j=s"       =>\$param_json_file,
	"s=s"       =>\$param_site,
	"d=s"       =>\$param_base_drz_dir,
	"v=s"       =>\$param_volume,
	"p=s"       =>\$param_project,
	"b=s"       =>\$param_buildname,
	"GO"        =>\$opt_GO,
);



#############################################################################
##### init vars

$current_user = `whoami`;
chomp $current_user;
$CURRENTDIR           = $FindBin::Bin;
$LOG_DIR              = $ENV{LOG_DIR}   || "/logs/clean-dropzone/";

# env vars
$ENV{SITE}          ||= $param_site || "Walldorf";
$ENV{PERL_PATH}     ||= "/softs/perl/latest/bin";  # could be just downloaded and unzipped from http://moo-repo.wdf.sap.corp:8080/static/monsoon/perl/ActivePerl-5.24.tar.gz

$SITE                 = $ENV{SITE}  || "Walldorf";

my $today    = Date::Manip::Date->new("today");
$current_day = $today->printf("%A");

# manage parameters
$json_dir     = "clean_rules";
$default_json = "$json_dir/$SITE.json";
if ( -e "$CURRENTDIR/$json_dir/${current_day}_$SITE.json" ) {
	$default_json = "$json_dir/${current_day}_$SITE.json";
}

if($param_json_file) {
	if($param_json_file !~ /build-results.json$/i) { # due to xmake builds, if find this file, exit
		exit 0;
	} else {
		$param_json_file ||= $default_json;
	}
} else {
	$param_json_file = $default_json
}
if($param_volume) {
	if($param_volume  =~ /^\d+$/) { # if -v=number, eg: if -v=3
		$param_volume = "volume$param_volume";
	}
}

sap_get_info_from_json();
$param_base_drz_dir  ||= $drop_base_dir || "/net/build-drops-wdf/dropzone";



#############################################################################
### MAIN

print "
start of $0
";

my $vRef = $Dropzone_Structure->{volumes};
for my $vElement (@$vRef) {
	my $vname = $vElement->{vname};
	# just to have shortname as variable
	next if($param_volume && ($param_volume ne $vname));
	my $v_dir = sap_get_full_path_of_this_volume($vname);
	if(opendir VOLUME_DIR , $v_dir) {
		while(defined(my $prjFound = readdir VOLUME_DIR)) {
			next if($prjFound =~ /^\./);                          # skip special folders '.' and '..' and '.something'
			next if( -l "$v_dir/$prjFound" ); # skip symlink to be sure
			next if( -f "$v_dir/$prjFound" ); # skip file to be sure
			next if($prjFound =~ /^toClean$/);                    # skip toClean folder
			next if($param_project && ($param_project ne $prjFound));
			if(opendir PROJECT_DIR , "$v_dir/$prjFound") {
				while(defined(my $buildFound = readdir PROJECT_DIR)) {
					next if($buildFound =~ /^\./);                                      # skip special folders '.' and '..' and '.something'
					next if( -l "$v_dir/$prjFound/$buildFound" );   # skip symlink to be sure
					next if( -f "$v_dir/$prjFound/$buildFound" );   # skip file to be sure
					next if( $param_buildname && ($param_buildname ne $buildFound) );
					$to_check{$vname}{$prjFound}{$buildFound} = 1;
				}
				closedir PROJECT_DIR;
			}
		}
		closedir VOLUME_DIR;
	}
}

if( ! -e "$LOG_DIR" ) {
	mkpath "$LOG_DIR";
}

print "\n";
foreach my $volume (keys %to_check) {
	print "$volume\n";
	my $v_dir = sap_get_full_path_of_this_volume($volume);
	foreach my $project ( keys %{$to_check{$volume}} ) {
		print "\t$project\n";
		foreach my $buildname (keys %{$to_check{$volume}{$project}} ) {
			print "\t\t$buildname\n";
			print "$v_dir/$project/$buildname\n";
			if($opt_GO) {
				my $cmd_line = "/usr/bin/bash $CURRENTDIR/get-size-buildname.sh $param_base_drz_dir $volume $project $buildname &";
				print "execute $cmd_line\n";
				system "$cmd_line";
				print "WARNING : this could take a while, please wait.\n";
				print "You can check in $LOG_DIR/size/${volume}_${project}_$buildname.log\n";
				print "to know if it is done, search DONE in $LOG_DIR/size/${volume}_${project}_$buildname.log\n\n"
			}
		}
	}
	print "\n";
}

print "\nps -ef | grep $current_user | grep -w du | grep -w sk | grep -v grep\n";
system "ps -ef | grep $current_user | grep -w du | grep -w sk | grep -v grep";
print "\n";
print "ps -ef | grep $current_user | grep -w du | grep -w sk | grep -v grep | wc -l\n";
system "ps -ef | grep $current_user | grep -w du | grep -w sk | grep -v grep | wc -l";

sap_end_script();



#############################################################################
### internal functions
sub sap_get_info_from_json() {
	# check syntax of json file
	if( -e $param_json_file) {
		my $json_text = do {
			open(my $json_fh,"<:encoding(UTF-8)",$param_json_file)
				or confess "\n\nCan't open \$json_file\": $!\n\n";
			local $/;
			<$json_fh>
		};
		my $json = JSON->new;
		$Dropzone_Structure = $json->decode($json_text);
		$drop_base_dir      =  $param_base_drz_dir
							|| $Dropzone_Structure->{drop_base_dir}
							|| "/net/build-drops-wdf/dropzone"
							;
	}
}

sub sap_get_full_path_of_this_volume($) {
	my ($this_volume) = @_ ;
	my $tmp_v_dir = "$param_base_drz_dir/.$this_volume";
	if( ! -d $tmp_v_dir ) {
		$tmp_v_dir = "$param_base_drz_dir/$this_volume";
	}
	return $tmp_v_dir;
}


sub sap_end_script() {
	print "
end of $0
";
	exit 0;
}
