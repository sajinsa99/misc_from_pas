#############################################################################
# cleans.pl

#############################################################################
##### declare uses

## ensure good code quality
use strict;
use warnings;
use diagnostics;

# required for the script
use File::Path;
use Time::Local;
use Getopt::Long;
use Data::Dumper;
use File::Basename;

use Sys::Hostname;
use Sort::Versions;
use Date::Manip::Date;
use JSON qw( decode_json );
# for calculatinbg current dir
use FindBin;
use lib $FindBin::Bin;



#############################################################################
##### declare vars
# PATH, environmment
use vars qw (
	$CURRENTDIR
	$SITE
	$CLEAN_SCRIPT_DIR
	$LOGS_DIR
	$MAILS_DIR
	$CSV_DIR
	$TEMP_DIR
	$PERL_PATH
);

# for the script itself
use vars qw (
	$alias_server_name
	$data_hRef
	$default_keep
	$default_inc_keep
	%Delete_requirements
	%List_revisions_to_delete
	%List_to_skip
	$current_day
	$default_json
	$default_yaml
	$drop_base_dir
	$mailFrom
	$mailTo
	$contact
	$json_dir
	@crons_hours
	$next_clean
	$next_clean_delta
	@skip_projects
	@skip_builds
	$hostName
	$NumberOfEmails
	$SMTP_SERVER
	$SCRIPT_SMTPFROM
	$SCRIPT_SMTPTO
	$CommandLine
	$nb_clean_process_ref
	$nb_clean_process_inpg
	$total_nb_move
	$total_nb_clean_process_inpg
	$nb_waitfor_insec
	$base_yaml_name
);

# parameters / options for variables not listed above
# options
use vars qw (
	$opt_help
	$opt_just_check_json
	$opt_just_list
	$opt_no_display_list
	$opt_no_display_info
	$opt_Stop_Cleans_Step
	$opt_Prepare_ReClean_Step
	$opt_Move_Step
	$opt_Clean_Step
	$opt_Refresh_Step
	$opt_debug
	$opt_clean_incrementals_only
	$opt_check_previous_fails
	$opt_scriptMail
);

# parameters
use vars qw (
	$param_site
	$param_json_file
	$param_yaml_file
	$default_json
	$param_volume
	$param_project
	$param_buildname
	$param_revision
	$param_keep
	$param_inc_keep
	$param_just_info
	$param_site
	$param_skip_projects
	$param_skip_builds
);

# Date/Time
use vars qw (
	$LocalSec
	$LocalMin
	$LocalHour
	$LocalDay
	$LocalMonth
	$LocalYear
	$wday
	$yday
	$isdst
	$Full_Date
);



#############################################################################
##### get options/parameters
$CommandLine = "$0 @ARGV";
$Getopt::Long::ignorecase = 0;
GetOptions(
	"help|?"    =>\$opt_help,
	"s=s"       =>\$param_site,
	"j=s"       =>\$param_json_file,
	"y=s"       =>\$param_yaml_file,
	"v=s"       =>\$param_volume,
	"p=s"       =>\$param_project,
	"b=s"       =>\$param_buildname,
	"r=s"       =>\$param_revision,
	"k=s"       =>\$param_keep,
	"ik=s"      =>\$param_inc_keep,
	"ji=s"      =>\$param_just_info,
	"jcj"       =>\$opt_just_check_json,        # just check json file and exit
	"jl"        =>\$opt_just_list,              # just list of revsision to keep/delete
	"ndl"       =>\$opt_no_display_list,        # not display list of revision to keep/delete
	"ndi"       =>\$opt_no_display_info,        # not display info
	"S"         =>\$opt_Stop_Cleans_Step,       # stop deletes on going
	"R"         =>\$opt_Refresh_Step,           # refresh toClean_folder
	"M"         =>\$opt_Move_Step,              # move revisions into toClean_folder
	"PRC"       =>\$opt_Prepare_ReClean_Step,   # if a clean was killed, machine rebooted, remove all "_delete_ongoing" to redo the clean
	"C"         =>\$opt_Clean_Step,             # clean revisions in toClean_folder
	"X"         =>\$opt_debug,                  # for debuging won't do any move/clean
	"cio"       =>\$opt_clean_incrementals_only,
	"sp=s"      =>\$param_skip_projects,
	"sb=s"      =>\$param_skip_builds,
	"jcpf"      =>\$opt_check_previous_fails,
	"sm=s"      =>\$opt_scriptMail,
);



#############################################################################
##### declare functions
sub check_user();
sub check_platform();
sub get_data_from_json_file();
sub build_infra_tree();
sub display_default_values();
sub display_infra_tree();
sub expand_this_directory($$);
sub get_crons();
sub determine_next_cron();
sub get_revisions_for_this_build_path($$);
sub generate_base_csv_filename($);
sub prepare_cleans();
sub move_in_toClean_folder($$$$);
sub prepare_revision_for_next_cron($$);
sub clean_in_toClean_folder();
sub unlink_revision($$$$$$$$);
sub kill_unlinks_ongoing();
sub display_info();
sub list_unlink_running_on_this_volume($);
sub display_size_of_this_volume($);
sub list_content_toClean_folder_for_this_volume($);
sub get_full_path_of_this_volume($);
sub get_start_time_of_this_pid($);
sub end_script();
sub display_usage();
sub search_symlinks_for_revision($$);
sub sendMailOnCleanIssue($$$$);
sub sendMailOnScriptIssue($@);



#############################################################################
##### init vars

$hostName   = hostname;
$CURRENTDIR = $FindBin::Bin;

$SITE            ||= $param_site || $ENV{CLEAN_SITE} || "Walldorf";
$TEMP_DIR          = $ENV{TEMP}  || $ENV{TMP}        || "$ENV{HOME}/tmp";
$CLEAN_SCRIPT_DIR  = $ENV{CLEAN_SCRIPT_DIR}          || $CURRENTDIR;
$PERL_PATH         = $ENV{CLEAN_PERL_PATH}           || "/softs/perl/latest";
$LOGS_DIR          = $ENV{CLEAN_LOGS_DIR}            || "/logs/clean-dropzone" ;
$CSV_DIR           = $ENV{CLEAN_CSV_DIR}             || "$LOGS_DIR/csv";
$MAILS_DIR         = $ENV{CLEAN_MAILS_DIR}           || "$LOGS_DIR/mails";

if( ! -e $TEMP_DIR ) {
	mkpath "$TEMP_DIR"  or die "ERROR : cannot mkpath '$TEMP_DIR' : $!";
}
if( ! -e "$LOGS_DIR") {
	mkpath "$LOGS_DIR"  or die "ERROR : cannot mkpath '$LOGS_DIR' : $!";
}
if( ! -e "$CSV_DIR") {
	mkpath "$CSV_DIR"   or die "ERROR : cannot mkpath '$CSV_DIR' : $!";
}
if( ! -e "$MAILS_DIR") {
	mkpath "$MAILS_DIR" or die "ERROR : cannot mkpath '$MAILS_DIR' : $!";
}

$SMTP_SERVER                  = $ENV{CLEAN_SMTP_SERVER}     || "mail.sap.corp";
if($opt_scriptMail) {
	$SCRIPT_SMTPFROM          = $ENV{CLEAN_SCRIPT_SMTPFROM} || 'bruno.fablet@sap.com' ;
	$SCRIPT_SMTPTO            = $ENV{CLEAN_SCRIPT_SMTPTO}   || 'bruno.fablet@sap.com' ;
	$NumberOfEmails           = 0;
	if( ($opt_scriptMail =~ /^die$/)  || ($opt_scriptMail =~ /^all$/) ){
		$SIG{__DIE__}       = sub { eval { sendMailOnScriptIssue("die"  , @_) } ; die(@_)  };
	}
	if( ($opt_scriptMail =~ /^warn$/) || ($opt_scriptMail =~ /^all$/) ){
		$SIG{__WARN__}      = sub { eval { sendMailOnScriptIssue("warn" , @_) } ; warn(@_) };
	}
}

# set Date/Time
( $LocalSec,
  $LocalMin,
  $LocalHour,
  $LocalDay,
  $LocalMonth,
  $LocalYear,
  $wday,
  $yday,
  $isdst
) = localtime time ;

# adapt to real current date,
$LocalYear   = $LocalYear  + 1900;
$LocalMonth  = $LocalMonth + 1;
# with a good format (2 digits for each info, except for the year)
$LocalDay    = "0$LocalDay"   if($LocalDay   < 10);
$LocalMonth  = "0$LocalMonth" if($LocalMonth < 10);
$LocalHour   = "0$LocalHour"  if($LocalHour  < 10);
$LocalMin    = "0$LocalMin"   if($LocalMin   < 10);
$LocalSec    = "0$LocalSec"   if($LocalSec   < 10);
$Full_Date   = "${LocalYear}_${LocalMonth}_$LocalDay"; # eg 2015_10_14

# env vars



if($opt_just_list && $opt_no_display_list) {
	print "\nERROR : you choosed -jl and -ndl, you have to choose between the 2 options.\n\n";
	exit 0,
}

$default_yaml = ($param_yaml_file) ? $param_yaml_file : "$CLEAN_SCRIPT_DIR/clean_rules/$SITE.yaml";
$base_yaml_name = basename $default_yaml;
($base_yaml_name) =~ s/\..+?$//i;
unless($param_json_file) {
	if( -e $default_yaml && -e "$CLEAN_SCRIPT_DIR/yaml2json.pl" ) {
		my $generatedJsonFile = "$CLEAN_SCRIPT_DIR/clean_rules/from_cron_json/${base_yaml_name}_${LocalYear}${LocalMonth}${LocalDay}${LocalHour}${LocalMin}${LocalSec}.json";
		if ( -e $generatedJsonFile) {
			system "rm -f $generatedJsonFile";
		}
		system "$PERL_PATH/bin/perl $CLEAN_SCRIPT_DIR/yaml2json.pl --y2j $default_yaml > $generatedJsonFile";
		if ( -e $generatedJsonFile) {
			$default_json  = $generatedJsonFile;
		}
	}
}
if( ! defined $default_json) {
	$default_json = ($param_json_file) ? $param_json_file : "$CLEAN_SCRIPT_DIR/clean_rules/$SITE.json";
}

if($param_volume) {
	if($param_volume  =~ /^\d+$/) { # if -v=number, eg: if -v=3
		$param_volume = "volume$param_volume";
	}
}

if($param_skip_projects) {
	@skip_projects =  split ',' , $param_skip_projects;
}
if($param_skip_builds) {
	@skip_builds   =  split ',' , $param_skip_builds;
}
get_data_from_json_file();

# for parallelization
$nb_clean_process_inpg       = 0;
$total_nb_clean_process_inpg = 0;
$total_nb_move               = 0;


#############################################################################
### MAIN

print "
start of $0

";

check_platform();
determine_next_cron();
display_usage()      if($opt_help);
display_default_values();
if($param_just_info) {
	display_info();
	end_script();
}
if($opt_just_list) {
	build_infra_tree();
	display_infra_tree();
	end_script();
}

if($opt_check_previous_fails) {
	opendir MAILDIR , "$MAILS_DIR" or die "ERROR : cannot opendir '$MAILS_DIR' : $!";
	while(defined(my $element = readdir MAILDIR)) {
		next if( $element =~ /^\./ );            # skip special folders '.' and '..' and '.something'
		if( -f "$MAILS_DIR/$element") {
			my $handleFile ;
			my $this_volume;
			my $this_project;
			my $this_build;
			my $this_revision;
			my $this_path;
			my $this_from;
			my $this_to;
			my $this_contact;
			if(open $handleFile , '<' ,"$MAILS_DIR/$element") {
				while(<$handleFile>) {
					chomp;
					if(/^volume\=(.+?)$/i) {
						$this_volume = $1;
					}
					if(/^project\=(.+?)$/i) {
						$this_project = $1;
					}
					if(/^build\=(.+?)$/i) {
						$this_build = $1;
					}
					if(/^revision\=(.+?)$/i) {
						$this_revision = $1;
					}
					if(/^path\=(.+?)$/i) {
						$this_path = $1;
					}
					if(/^from\=(.+?)$/i) {
						$this_from = $1;
					}
					if(/^to\=(.+?)$/i) {
						$this_to = $1;
					}
					if(/^contact\=(.+?)$/i) {
						$this_contact = $1;
					}
				}
				close $handleFile;
			}  else  {
				die "ERROR : cannot read '$MAILS_DIR/$element' : $!";
			}
			next if(defined $param_volume    && $param_volume    ne $this_volume);
			next if(defined $param_project   && $param_project   ne $this_project);
			next if(defined $param_buildname && $param_buildname ne $this_build);
			next if(defined $param_revision  && $param_revision  ne $this_revision);
			# last attempt to clean folder
			if( defined $this_path && -e "$this_path" ) {
				system "rm -f \"this_path\" >& /dev/null || true";

			}
			if ( defined $this_volume && defined $this_project && defined $this_build && defined $this_revision && defined $this_path && defined $this_from && defined $this_to && defined $this_contact ) {
				my $handleHtmlFile;
				(my $displayFrom = $this_from) =~ s-\@(.+?)$--i;
				my $htmlFile  = $this_volume . "_" . $this_project . "_" . $this_build . "_" . $this_revision . ".html" ;
				my $subject;
				if( -e $this_path ) {
					$subject   = "[dropzone clean issue] : still fail to clean path : $this_path ";
					if(open $handleHtmlFile , '>' ,"$htmlFile") {
						my $userName  = getpwuid($<);
						print $handleHtmlFile '
<html xmlns:o="urn:schemas-microsoft-com:office:office"
xmlns:w="urn:schemas-microsoft-com:office:word"
xmlns:x="urn:schemas-microsoft-com:office:excel"
xmlns:m="http://schemas.microsoft.com/office/2004/12/omml"
xmlns="http://www.w3.org/TR/REC-html40">
<head>
<meta http-equiv=Content-Type content="text/html; charset=windows-1252">
<meta name=ProgId content=Word.Document>
<meta name=Generator content="Microsoft Word 12">
<meta name=Originator content="Microsoft Word 12">
<link rel=File-List href="email_files/filelist.xml">
<link rel=Edit-Time-Data href="email_files/editdata.mso">
<body lang=FR link=blue vlink=purple style=\'tab-interval:35.4pt\'>
';
						print $handleHtmlFile "
Hello,<br/><br/>
WARNING : $this_path still exists.<br/>
Please double check on $hostName, as $userName, or please contact <a href=\"mailto:$this_contact\">$this_contact</a>.<br/>

<br/><br/>
Regards,<br/>
$displayFrom

				";
						close $handleHtmlFile ;
					}  else  {
						die "ERROR : cannot create '$htmlFile' : $!";
					}
				}  else  {
					$subject   = "[dropzone clean fixed] : clean $this_path fixed";
					if(open $handleHtmlFile , '>' ,"$htmlFile") {
						print $handleHtmlFile '
<html xmlns:o="urn:schemas-microsoft-com:office:office"
xmlns:w="urn:schemas-microsoft-com:office:word"
xmlns:x="urn:schemas-microsoft-com:office:excel"
xmlns:m="http://schemas.microsoft.com/office/2004/12/omml"
xmlns="http://www.w3.org/TR/REC-html40">
<head>
<meta http-equiv=Content-Type content="text/html; charset=windows-1252">
<meta name=ProgId content=Word.Document>
<meta name=Generator content="Microsoft Word 12">
<meta name=Originator content="Microsoft Word 12">
<link rel=File-List href="email_files/filelist.xml">
<link rel=Edit-Time-Data href="email_files/editdata.mso">
<body lang=FR link=blue vlink=purple style=\'tab-interval:35.4pt\'>
';
						print $handleHtmlFile "
Hello,<br/><br/>
Ultimately, the clean of $this_path is now fixed.<br/>
<br/><br/>
Regards,<br/>
$displayFrom

				";
						close $handleHtmlFile ;
					}  else  {
						die "ERROR : cannot create '$htmlFile' : $!";
					}
					system "rm -f $MAILS_DIR/$element >& /dev/null || true";
				}
				sendMailOnCleanIssue($this_from,$this_to,$subject,$htmlFile) if( -e "$htmlFile");
			}
		}
	}
	closedir MAILDIR;
	end_script();
}

# now need to be root for the cleans to avoid permissions
check_user();
if($opt_Move_Step) {
	build_infra_tree();
	prepare_cleans();
}
if($opt_Clean_Step || $opt_Refresh_Step) {
	clean_in_toClean_folder();
}
if($opt_Stop_Cleans_Step) {
	kill_unlinks_ongoing();
}
if($opt_Prepare_ReClean_Step) {
	clean_in_toClean_folder();
}
$param_just_info ||= "all";
display_info() unless($opt_no_display_info);
end_script();



#############################################################################
### internal functions
sub check_user() {
	# this script has to be run as root because we don't have passwords of psbuild or ablack or ...
	if( ($hostName !~ /^dewdfth13010/i) && ($hostName !~ /^dewdfth13014/i) ){
		my $username = `nice -n 19 whoami`;
		chomp $username;
		if($username ne "root") {
			die "ERROR : '$0' cannot be run as '$username', '$0' can be run ONLY as root : $!";
		}
	}
}

sub check_platform() {
	# this script has to be run under unix/linux.
	if($^O eq "MSWin32") {
		die "ERROR : '$0' cannot be run under '$^O', $0 can be run ONLY under an unix, and as root : $!";
	}
}

sub get_data_from_json_file() {
	if( -e $default_json) {
		print "read json file '$default_json'\n" if($opt_debug);
		my $json_text = do {
			open(my $json_fh,"<:encoding(UTF-8)",$default_json)
				or die "ERROR : cannot open '$default_json' : $!";
			local $/;
			<$json_fh>
		};
		my $json = JSON->new;
		$data_hRef = $json->decode($json_text);
		if($opt_just_check_json) {
			print "\njust check json syntax\n";
			print Dumper $data_hRef;
			print "\n";
			exit 0;
		}
		# set default and mandatory values
		$alias_server_name    = $data_hRef->{alias_server_name} || "build-drops-wdf";
		$drop_base_dir        = $data_hRef->{drop_base_dir}     || "/net/$alias_server_name/dropzone";
		$mailFrom             = (defined $data_hRef->{mailFrom}) ? $data_hRef->{mailFrom} : "";
		$mailTo               = (defined $data_hRef->{mailTo})   ? $data_hRef->{mailTo}   : "";
		$contact              = (defined $data_hRef->{contact})  ? $data_hRef->{contact}  : "";
		$default_keep         = (defined $param_keep)            ? $param_keep     : $data_hRef->{nb_keep} ;
		$default_inc_keep     = (defined $param_inc_keep)        ? $param_inc_keep : $data_hRef->{nb_keep_incremental}  ;
		$nb_clean_process_ref = (defined $data_hRef->{nb_clean_process_ref}) ? $data_hRef->{nb_clean_process_ref} : "" ;
		$nb_waitfor_insec     = (defined $data_hRef->{nb_waitfor_insec})     ? $data_hRef->{nb_waitfor_insec}     : 601 ;
	}  else  {
		die "ERROR : '$default_json' does not exists : $!";
	}
}

sub build_infra_tree() {
	print "build infra tree\n" if($opt_debug);
	# 1 build defaults values, by parsing the dropzone
	# I parse the dropzone to ensure to NOT miss projects/builds
	print "build defaults values\n" if($opt_debug);
	my $volume_hRef = $data_hRef->{volumes};
	for my $volume_Element (@$volume_hRef) {
		next if($param_volume && ($param_volume !~ /^$volume_Element->{volume_name}$/));
		# build defaults values for volumes
		my $volume_name      = $volume_Element->{volume_name};
		my $volume_keep      = (defined $volume_Element->{nb_keep})             ? $volume_Element->{nb_keep}             : $default_keep;
		$volume_keep         = (defined $param_keep)                            ? $param_keep                            : $volume_keep;
		my $volume_keep_inc  = (defined $volume_Element->{nb_keep_incremental}) ? $volume_Element->{nb_keep_incremental} : $default_inc_keep;
		$volume_keep_inc     = (defined $param_inc_keep )                       ? $param_inc_keep                        : $volume_keep_inc;
		my $volume_next_cron = (defined $volume_Element->{clean_on_next_cron})  ? $volume_Element->{clean_on_next_cron}  : "false";
		$Delete_requirements{volumes}{$volume_name}{nb_keep}             = $volume_keep;
		$Delete_requirements{volumes}{$volume_name}{nb_keep_incremental} = $volume_keep_inc;
		$Delete_requirements{volumes}{$volume_name}{clean_on_next_cron}  = $volume_next_cron;
		my @projects_of_this_volume = expand_this_directory("$drop_base_dir/.$volume_name","");
		my $treeshold;
		my $volume_mailFrom;
		my $volume_mailTo;
		my $volume_contact;
		if(defined $volume_Element->{treeshold}) {
			$treeshold = $volume_Element->{treeshold} ;
		}
		if(defined $volume_Element->{mailFrom}) {
			$volume_mailFrom  = $volume_Element->{mailFrom} ;
			$Delete_requirements{volumes}{$volume_name}{mailFrom} = $volume_mailFrom ;
		}
		if(defined $volume_Element->{mailTo}) {
			$volume_mailTo    = $volume_Element->{mailTo} ;
			$Delete_requirements{volumes}{$volume_name}{mailTo} = $volume_mailTo ;
		}
		if(defined $volume_Element->{contact}) {
			$volume_contact   = $volume_Element->{contact} ;
			$Delete_requirements{volumes}{$volume_name}{contact} = $volume_contact ;
		}
		# build defaults values for projects
		if( scalar @projects_of_this_volume > 0) {
			foreach my $this_project (@projects_of_this_volume) {
				next if($param_project       && ($param_project !~ /^$this_project$/));
				next if($param_skip_projects && (grep /^$this_project$/ , @skip_projects));
				$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{nb_keep}             = $volume_keep;
				$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{nb_keep_incremental} = $volume_keep_inc;
				$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{skip_clean}          = "false";
				$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{clean_on_next_cron}  = $volume_next_cron;
				# build defaults values for builds
				my @builds_of_this_project = expand_this_directory("$drop_base_dir/.$volume_name/$this_project","");
				if( scalar @builds_of_this_project > 0 ) {
					foreach my $this_build (@builds_of_this_project) {
						next if($param_buildname   && ($this_build =~ /\*/) );
						next if($param_buildname   && ($param_buildname !~ /^$this_build$/));
						next if($param_skip_builds && (grep /^$this_build$/ , @skip_builds));
						$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{nb_keep}             = $volume_keep;
						$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{nb_keep_incremental} = $volume_keep_inc;
						$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{skip_clean}          = "false";
						$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{clean_on_next_cron}  = $volume_next_cron;
						$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{build_path}          = "$drop_base_dir/.$volume_name/$this_project/$this_build";
					}
				}
			}
		}
		# 2 now override default values if required, by parsing json file
		print "now override default values if required for $volume_name\n" if($opt_debug);
		if( $volume_Element->{projects} ) {
			my $project_hRef = $volume_Element->{projects};
			for my $project_Element (@$project_hRef) {
				my $project_name      = $project_Element->{project_name};
				next if($param_project && ($param_project !~ /^$project_name$/));
				my $project_keep      = (defined $project_Element->{nb_keep})             ? $project_Element->{nb_keep}             : $volume_keep;
				$project_keep         = (defined $param_keep)                             ? $param_keep                             : $project_keep;
				my $project_keep_inc  = (defined $project_Element->{nb_keep_incremental}) ? $project_Element->{nb_keep_incremental} : $volume_keep_inc;
				$project_keep_inc     = (defined $param_inc_keep )                        ? $param_inc_keep                         : $project_keep_inc;
				my $project_skip      = ($project_Element->{skip_clean})                  ? $project_Element->{skip_clean}          : "false";
				my $project_next_cron = ($project_Element->{clean_on_next_cron})          ? $project_Element->{clean_on_next_cron}  : "false";
				my $project_mailFrom ;
				my $project_mailTo ;
				my $project_contact ;
				if(defined $project_Element->{mailFrom}) {
					$project_mailFrom  = $project_Element->{mailFrom} ;
				}
				if(defined $project_Element->{mailTo}) {
					$project_mailTo    = $project_Element->{mailTo} ;
				}
				if(defined $project_Element->{contact}) {
					$project_contact   = $project_Element->{contact} ;
				}
				if( ($project_name =~ /^\*(.+?)$/) || ($project_name =~ /^(.+?)\*$/) ) { # if project=*toto or toto*
					my $project_pattern = $1 ;
					my @projects = expand_this_directory("$drop_base_dir/.$volume_name",$project_pattern);
					if( scalar @projects > 0 ) {
						foreach my $this_project (@projects) {
							$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{nb_keep}             = $project_keep;
							$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{nb_keep_incremental} = $project_keep_inc;
							$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{skip_clean}          = $project_skip;
							$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{clean_on_next_cron}  = $project_next_cron;
							$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{mailFrom} = $project_mailFrom if(defined $project_mailFrom);
							$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{mailTo}   = $project_mailTo   if(defined $project_mailTo);
							$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{contact}  = $project_contact  if(defined $project_contact);
							if( $project_Element->{builds} ) {
								my $build_hRef = $project_Element->{builds};
								for my $build_Element (@$build_hRef) {
									my $build_name      = $build_Element->{build_name};
									next if($param_buildname && ($build_name =~ /\*/) );
									next if($param_buildname && ($param_buildname !~ /^$build_name$/));
									my $build_keep      = (defined $build_Element->{nb_keep})             ? $build_Element->{nb_keep}             : $project_keep;
									$build_keep         = (defined $param_keep)                           ? $param_keep                           : $build_keep;
									my $build_keep_inc  = (defined $build_Element->{nb_keep_incremental}) ? $build_Element->{nb_keep_incremental} : $project_keep_inc;
									$build_keep_inc     = (defined $param_inc_keep )                      ? $param_inc_keep                       : $build_keep_inc;
									my $build_skip      = ($build_Element->{skip_clean})                  ? $build_Element->{skip_clean}          : "false";
									my $build_next_cron = ($build_Element->{clean_on_next_cron})          ? $build_Element->{clean_on_next_cron}  : "false";
									my $build_mailFrom ;
									my $build_mailTo ;
									my $build_contact ;
									if(defined $build_Element->{mailFrom}) {
										$build_mailFrom  = $build_Element->{mailFrom} ;
									}
									if(defined $build_Element->{mailTo}) {
										$build_mailTo    = $build_Element->{mailTo} ;
									}
									if(defined $build_Element->{contact}) {
										$build_contact   = $build_Element->{contact} ;
									}
									if( ($build_name =~ /^\*(.+?)$/) || ($build_name =~ /^(.+?)\*$/) ) { # if build=*toto or toto*
										my $build_pattern = $1 ;
										my @builds = expand_this_directory("$drop_base_dir/.$volume_name/$this_project",$build_pattern);
										if( scalar @builds > 0 ) {
											foreach my $this_build (@builds) {
												$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{nb_keep}             = $build_keep;
												$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{nb_keep_incremental} = $build_keep_inc;
												$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{skip_clean}          = $build_skip;
												$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{clean_on_next_cron}  = $build_next_cron;
												$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{build_path}          = "$drop_base_dir/.$volume_name/$this_project/$this_build";
												$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{mailFrom} = $build_mailFrom if(defined $build_mailFrom);
												$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{mailTo}   = $build_mailTo   if(defined $build_mailTo);
												$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{contact}  = $build_contact  if(defined $build_contact);
											}
										}
									}  else  {
										$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$build_name}{nb_keep}             = $build_keep;
										$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$build_name}{nb_keep_incremental} = $build_keep_inc;
										$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$build_name}{skip_clean}          = $build_skip;
										$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$build_name}{clean_on_next_cron}  = $build_next_cron;
										$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$build_name}{build_path}          = "$drop_base_dir/.$volume_name/$this_project/$build_name";
										$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$build_name}{mailFrom} = $build_mailFrom if(defined $build_mailFrom);
										$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$build_name}{mailTo}   = $build_mailTo   if(defined $build_mailTo);
										$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$build_name}{contact}  = $build_contact  if(defined $build_contact);
									}
								}
							}  else  {
								foreach my $this_build ( keys %{$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}} ) {
									next if($param_buildname   && ($this_build =~ /\*/) );
									next if($param_buildname   && ($param_buildname !~ /^$this_build$/));
									next if($param_skip_builds && (grep /^$this_build$/ , @skip_builds));
									$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{nb_keep}             = $project_keep;
									$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{nb_keep_incremental} = $project_keep_inc;
									$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{skip_clean}          = "false";
									$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{clean_on_next_cron}  = $volume_next_cron;
									$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{build_path}          = "$drop_base_dir/.$volume_name/$this_project/$this_build";
									$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{mailFrom} = $project_mailFrom if(defined $project_mailFrom);
									$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{mailTo}   = $project_mailTo   if(defined $project_mailTo);
									$Delete_requirements{volumes}{$volume_name}{projects}{$this_project}{builds}{$this_build}{contact}  = $project_contact  if(defined $project_contact);
								}
							}
						}
					}
				}  else  {
					$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{nb_keep}             = $project_keep;
					$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{nb_keep_incremental} = $project_keep_inc;
					$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{skip_clean}          = $project_skip;
					$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{mailFrom} = $project_mailFrom if(defined $project_mailFrom);
					$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{mailTo}   = $project_mailTo   if(defined $project_mailTo);
					$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{contact}  = $project_contact  if(defined $project_contact);
					if( $project_Element->{builds} ) {
						my $build_hRef = $project_Element->{builds};
						for my $build_Element (@$build_hRef) {
							my $build_name     = $build_Element->{build_name};
							next if($param_buildname && ($build_name =~ /\*/) );
							next if($param_buildname && ($param_buildname !~ /^$build_name$/) );
							my $build_keep      = (defined $build_Element->{nb_keep})             ? $build_Element->{nb_keep}             : $project_keep;
							$build_keep         = (defined $param_keep)                           ? $param_keep : $build_keep;
							my $build_keep_inc  = (defined $build_Element->{nb_keep_incremental}) ? $build_Element->{nb_keep_incremental} : $project_keep_inc;
							$build_keep_inc     = (defined $param_inc_keep )                      ? $param_inc_keep : $build_keep_inc;
							my $build_skip      = ($build_Element->{skip_clean})                  ? $build_Element->{skip_clean}          : "false";
							my $build_next_cron = ($build_Element->{clean_on_next_cron})          ? $build_Element->{clean_on_next_cron}  : "false";
							my $build_mailFrom ;
							my $build_mailTo ;
							my $build_contact ;
							if(defined $build_Element->{mailFrom}) {
								$build_mailFrom  = $build_Element->{mailFrom} ;
							}
							if(defined $build_Element->{mailTo}) {
								$build_mailTo    = $build_Element->{mailTo} ;
							}
							if(defined $build_Element->{contact}) {
								$build_contact   = $build_Element->{contact} ;
							}
							if( ($build_name =~ /^\*(.+?)$/) || ($build_name =~ /^(.+?)\*$/) ) { # if *toto or toto*
								my $build_pattern = $1 ;
								my @builds = expand_this_directory("$drop_base_dir/.$volume_name/$project_name",$build_pattern);
								if( scalar @builds > 0) {
									foreach my $this_build (@builds) {
										$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{nb_keep}             = $build_keep;
										$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{nb_keep_incremental} = $build_keep_inc;
										$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{skip_clean}          = $build_skip;
										$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{clean_on_next_cron}  = $build_next_cron;
										$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{build_path}          = "$drop_base_dir/.$volume_name/$project_name/$this_build";
										$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{mailFrom} = $build_mailFrom if(defined $build_mailFrom);
										$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{mailTo}   = $build_mailTo   if(defined $build_mailTo);
										$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{contact}  = $build_contact  if(defined $build_contact);
									}
								}
							}  else  {
								$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$build_name}{nb_keep}             = $build_keep;
								$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$build_name}{nb_keep_incremental} = $build_keep_inc;
								$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$build_name}{skip_clean}          = $build_skip;
								$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$build_name}{clean_on_next_cron}  = $build_next_cron;
								$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$build_name}{build_path}          = "$drop_base_dir/.$volume_name/$project_name/$build_name";
								$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$build_name}{mailFrom} = $build_mailFrom if(defined $build_mailFrom);
								$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$build_name}{mailTo}   = $build_mailTo   if(defined $build_mailTo);
								$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$build_name}{contact}  = $build_contact  if(defined $build_contact);
							}
						}
					}  else  {
						foreach my $this_build ( keys %{$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}} ) {
							next if($param_buildname   && ($this_build =~ /\*/) );
							next if($param_buildname   && ($param_buildname !~ /^$this_build$/));
							next if($param_skip_builds && (grep /^$this_build$/ , @skip_builds));
							$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{nb_keep}             = $project_keep;
							$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{nb_keep_incremental} = $project_keep_inc;
							$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{skip_clean}          = "false";
							$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{clean_on_next_cron}  = $volume_next_cron;
							$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{build_path}          = "$drop_base_dir/.$volume_name/$project_name/$this_build";
							$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{mailFrom} = $project_mailFrom if(defined $project_mailFrom);
							$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{mailTo}   = $project_mailTo   if(defined $project_mailTo);
							$Delete_requirements{volumes}{$volume_name}{projects}{$project_name}{builds}{$this_build}{contact}  = $project_contact  if(defined $project_contact);
						}
					}
				}
			}
		}
	}
	# get and manage versions
	print "get and manage versions\n" if($opt_debug);
	foreach my $volume ( sort { versioncmp($a, $b) } keys %{$Delete_requirements{volumes}} ) {
		next if($param_volume && ($param_volume !~ /^$volume$/));
		print "$volume\n" if($opt_debug);
		foreach my $project ( sort { versioncmp($a, $b) } keys %{$Delete_requirements{volumes}{$volume}{projects}} ) {
			next if($param_project && ($param_project !~ /^$project$/));
			next if($Delete_requirements{volumes}{$volume}{projects}{$project}{skip_clean} eq "true" );
			print "\t$project\n" if($opt_debug);
			foreach my $build ( sort { versioncmp($a, $b) } keys %{$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}} ) {
				next if($Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{skip_clean} eq "true");
				next if($param_buildname && ($build =~ /\*/) );
				next if($param_buildname && ($param_buildname !~ /^$build$/));
				print "\t\t$build\n" if($opt_debug);
				my $nb_keep       = $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{nb_keep};
				my $nb_keep_inc   = $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{nb_keep_incremental};
				my @all_revisions = get_revisions_for_this_build_path("$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{build_path}"
																	 ,"$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{clean_on_next_cron}"
																	 );
				if( scalar @all_revisions > 0) {
					foreach my $revision ( sort { versioncmp($b, $a) } @all_revisions ) {
						next unless($revision);
						next if($param_revision && ($param_revision !~ /^$revision$/));
						print "\t\t\t$revision\n" if($opt_debug);
						if($revision =~ /\_will\_be\_deleted\_at\_/i) {
							$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{revisions}{$revision}{clean} = "true";
						}  else  {
							if($revision =~ /\.\d+$/) { # if incremental
								if($nb_keep_inc == 0) {
									$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{revisions}{$revision}{clean} = "true";
								}  else  {
									$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{revisions}{$revision}{clean} = "false";
									$nb_keep_inc--;
								}
							}  else  { # not incremental
								unless($opt_clean_incrementals_only) {
									if($nb_keep == 0) {
										$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{revisions}{$revision}{clean} = "true";
									}  else  {
										$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{revisions}{$revision}{clean} = "false";
										$nb_keep--;
									}
								}
							}
						}
					}
				}
			}
		}
	}
}

sub display_default_values() {
	print "\n\ndisplay default values tree\n";
	print "dropzone name                              = $alias_server_name\n"     if($alias_server_name);
	print "dropzone entry point                       = $drop_base_dir\n"         if($drop_base_dir);
	print "nb revisions to keep                       = $default_keep\n"          if($default_keep);
	print "nb incremental revisions to keep           = $default_inc_keep\n"      if($default_inc_keep);
	print "mailFrom                                   = $mailFrom\n"              if($mailFrom);
	print "mailTo                                     = $mailTo\n"                if($mailTo);
	print "contact                                    = $contact\n"               if($contact);
	print "nb clean in parallel allowed               = $nb_clean_process_ref\n"  if($nb_clean_process_ref);
	print "wait for between  slots of parallel cleans = $nb_waitfor_insec\n"      if($nb_clean_process_ref && $nb_waitfor_insec);
	print "\n\n";
}

sub display_infra_tree() {
	print "display infra tree\n" if($opt_debug);
	my $current_mailFrom = (defined $data_hRef->{mailFrom}) ? $data_hRef->{mailFrom} : "";
	my $current_mailTo   = (defined $data_hRef->{mailTo})   ? $data_hRef->{mailTo}   : "";
	my $current_contact  = (defined $data_hRef->{contact})  ? $data_hRef->{contact}  : "";

	foreach my $volume ( sort { versioncmp($a, $b) } keys %{$Delete_requirements{volumes}} ) {
		$current_mailFrom = (defined $Delete_requirements{volumes}{$volume}{mailFrom}) ? $Delete_requirements{volumes}{$volume}{mailFrom} : $current_mailFrom ;
		$current_mailTo   = (defined $Delete_requirements{volumes}{$volume}{mailTo})   ? $Delete_requirements{volumes}{$volume}{mailTo}   : $current_mailTo ;
		$current_contact  = (defined $Delete_requirements{volumes}{$volume}{contact})  ? $Delete_requirements{volumes}{$volume}{contact}  : $current_contact ;
		print "$volume\n";
		print "keep               = $Delete_requirements{volumes}{$volume}{nb_keep}\n";
		print "keep inc           = $Delete_requirements{volumes}{$volume}{nb_keep_incremental}\n";
		print "clean at next cron = $Delete_requirements{volumes}{$volume}{clean_on_next_cron}\n";
		if($Delete_requirements{volumes}{$volume}{mailFrom} || $Delete_requirements{volumes}{$volume}{mailTo} || $Delete_requirements{volumes}{$volume}{contact}) {
			print "mailFrom           = $current_mailFrom\n";
			print "mailTo             = $current_mailTo\n";
			print "contact            = $current_contact\n";
		}
		foreach my $project ( sort { versioncmp($a, $b) } keys %{$Delete_requirements{volumes}{$volume}{projects}} ) {
			if($Delete_requirements{volumes}{$volume}{projects}{$project}{skip_clean} eq "true" ) {
				print "\t$project will be skipped, no clean for that project\n";
				next;
			}
			$current_mailFrom = (defined $Delete_requirements{volumes}{$volume}{projects}{$project}{mailFrom}) ? $Delete_requirements{volumes}{$volume}{projects}{$project}{mailFrom} : $current_mailFrom ;
			$current_mailTo   = (defined $Delete_requirements{volumes}{$volume}{projects}{$project}{mailTo})   ? $Delete_requirements{volumes}{$volume}{projects}{$project}{mailTo}   : $current_mailTo ;
			$current_contact  = (defined $Delete_requirements{volumes}{$volume}{projects}{$project}{contact})  ? $Delete_requirements{volumes}{$volume}{projects}{$project}{contact}  : $current_contact ;			
			print "\t$project\n";
			print "\tkeep               = $Delete_requirements{volumes}{$volume}{projects}{$project}{nb_keep}\n";
			print "\tkeep inc           = $Delete_requirements{volumes}{$volume}{projects}{$project}{nb_keep_incremental}\n";
			print "\tclean at next cron = $Delete_requirements{volumes}{$volume}{projects}{$project}{clean_on_next_cron}\n";
			if($Delete_requirements{volumes}{$volume}{projects}{$project}{mailFrom} || $Delete_requirements{volumes}{$volume}{projects}{$project}{mailTo} || $Delete_requirements{volumes}{$volume}{projects}{$project}{contact}) {
				print "\tmailFrom           = $current_mailFrom\n";
				print "\tmailTo             = $current_mailTo\n";
				print "\tcontact            = $current_contact\n";
			}
			foreach my $build ( sort { versioncmp($a, $b) } keys %{$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}} ) {
				if($Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{skip_clean} eq "true") {
					print "\t\t$build will be skipped, no clean for that build\n";
					next;
				}
				$current_mailFrom = (defined $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{mailFrom}) ? $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{mailFrom} : $current_mailFrom ;
				$current_mailTo   = (defined $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{mailTo})   ? $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{mailTo}   : $current_mailTo ;
				$current_contact  = (defined $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{contact})  ? $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{contact}  : $current_contact ;
				my $nb_keep       = $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{nb_keep};
				my $nb_keep_inc   = $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{nb_keep_incremental};
				print "\t\t$build\n";
				print "\t\tkeep               = $nb_keep\n";
				print "\t\tkeep inc           = $nb_keep_inc\n";
				print "\t\tclean at next cron = $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{clean_on_next_cron}\n";
				print "\t\tpath       = $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{build_path}\n";
				if(defined $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{mailFrom} || $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{mailTo} || $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{contact}) {
					print "\t\tmailFrom           = $current_mailFrom\n";
					print "\t\tmailTo             = $current_mailTo\n";
					print "\t\tcontact            = $current_contact\n";
				}
				foreach my $revision ( sort { versioncmp($b, $a) } keys %{$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{revisions}} ) {
					next if($param_revision && ($param_revision !~ /^$revision$/));
					print "\t\t\t$revision -> clean = $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{revisions}{$revision}{clean}\n";
				}
				print "\n";
			}
		}
	}
}

sub expand_this_directory($$) {
	my ($this_path,$this_pattern) = @_ ;
	if(opendir FOLDER , "$this_path") {
		my @dirs;
		while(defined(my $element = readdir FOLDER)) {
			next if( $element =~ /^\./ );            # skip special folders '.' and '..' and '.something'
			next if( $element =~ /toClean$/i);       # skip 'toClean' folder
			# the 2 next are to ensure symlinks & simple files are not catched
			next if( -l "$this_path/$element" );     # skip symlinks
			next if( -f "$this_path/$element" );     # simple files
			if( -d "$this_path/$element" ) {
				if( $this_pattern ) {
					if( ($element =~ /^$this_pattern/) || ($element =~ /$this_pattern$/) ) {
						push @dirs , $element ;
					}
				}  else  {
					push @dirs , $element ;
				}
			}
		}
		closedir FOLDER;
		return @dirs if(scalar @dirs > 0);
	}  else  {
		warn "WARNING : cannot opendir '$this_path' : $!";
	}
}

sub get_crons() {
	if(open  CLEAN_CRON , "crontab -l | grep cron_clean_dropzone 2>&1 |") {
		while(<CLEAN_CRON>) {
			chomp;
			next if($_ =~ /^\#/i); # skip comments
			(my $hour) = $_ =~ /^\d+\s+(\d+)\s+/;
			push @crons_hours , $hour ;
		}
		close CLEAN_CRON;
	}
}

sub determine_next_cron() {
	get_crons();
	if( scalar @crons_hours > 0) {
		my $current_hour = `date '+%H'`;
		chomp $current_hour;
		foreach my $hour_cron (sort {$a <=> $b} @crons_hours) {
			next if($hour_cron < $current_hour);
			if( $hour_cron > $current_hour) {
				$next_clean = $hour_cron;
				$next_clean_delta = $hour_cron - $current_hour;
				last ;
			}
		}
		print "$next_clean - $next_clean_delta\n";
	}
}

sub get_revisions_for_this_build_path($$) {
	my ($this_path,$flag_next_cron) = @_ ;
	my @revisions;
	if(opendir FOLDER , "$this_path") {
		my $version_with_next_cron;
		while(defined(my $element = readdir FOLDER)) {
			next if( $element =~ /^\./ );        # skip special folders '.' and '..' and '.something'
			next if( -l "$this_path/$element" && $element !~ /\_will\_be\_deleted\_at\_/i ); # ensure skipping symlinks, except _will_be_deleted_at_
			next if( -f "$this_path/$element" ); # ensure skipping simple files
			if($element =~ /^(\d+(?:\.\d+)?)\_will\_be\_deleted\_at\_(.+?)$/i) { # whatever if incremental or not, get renamed build rev from previous run
				my ($this_revision,$expected_hour) = ($1,$2);
				$version_with_next_cron     = $this_revision ;
				my ($decimal_expected_hour) = $expected_hour =~ s-^0-- ;
				my ($decimal_local_hour)    = $LocalHour     =~ s-^0-- ;
				if($decimal_local_hour == $decimal_expected_hour) { # if currunt run is within the cron
					push @revisions , $element ;
				}
				if($decimal_local_hour > $decimal_expected_hour) { # if next cron outdated, eg if next cron expected at 17 and current hour is 18
					push @revisions , $element ;
				}
				if($decimal_local_hour < $decimal_expected_hour) { # check if yesterday
					my $mtime=(stat("$this_path/$element"))[9];
					my @this_folder_date =  localtime $mtime ;
					$this_folder_date[5] += 1900; # real year
					$this_folder_date[4] += 1;    # real month
					my ($decimal_local_month) = $LocalMonth =~ s-^0-- ;
					my ($decimal_local_day)   = $LocalDay   =~ s-^0-- ;
					if($decimal_local_day > $this_folder_date[3]) { # if yesterday within this month
						push @revisions , $element ;
					}  else  {
						if( $decimal_local_month > $this_folder_date[4] ) { # if last month
							push @revisions , $element ;
						}
					}
				}
			}
			if($element =~ /^(\d+(?:\.\d+)?)$/ ) { # with or without incremental ensure get no tagged builds
				if( -d "$this_path/$element" ) {
					if($flag_next_cron eq "true") {
						my $found_next_run = search_symlinks_for_revision($this_path,$element);
						if($found_next_run == 0) {
							push @revisions , $element ;
						}
					}  else  {
						push @revisions , $element ;
					}
				}
			}
		}
		closedir FOLDER;
	}  else  {
		warn "WARNING : cannot opendir '$this_path' : $!";
		@revisions = ();
	}
	return @revisions;
}

sub generate_base_csv_filename($) {
	my ($this_type) = @_ ;
	sleep 5 ;
	my $random_number = int(rand(10));
	sleep $random_number;
	my ( $this_Sec,
		  $this_Min,
		  $this_Hour,
		  $this_Day,
		  $this_Month,
		  $this_Year,
		  $this_wday,
		  $this_yday,
		  $this_isdst )
		  = localtime time ;
	# adapt to real current date,
	$this_Year   = $this_Year  + 1900;
	$this_Month  = $this_Month + 1;
	# with a good format (2 digits for each info, except for the year)
	$this_Day    = "0$this_Day"   if($this_Day   < 10);
	$this_Month  = "0$this_Month" if($this_Month < 10);
	$this_Hour   = "0$this_Hour"  if($this_Hour  < 10);
	$this_Min    = "0$this_Min"   if($this_Min   < 10);
	$this_Sec    = "0$this_Sec"   if($this_Sec   < 10);
	#put dat-time before for sorting when making a search
	my $this_csv_file_name  = "$this_Year"
							. "_$this_Month"
							. "_$this_Day"
							. "_$this_Hour"
							. "_$this_Min"
							. "_$this_Sec"
							. "____$this_type.csv"
							;
	return $this_csv_file_name;
}

sub prepare_cleans() {
	print "\nManage Revisions to keep/rename/delete\n";
	my @csv_keep_lines;
	my @csv_next_lines;
	foreach my $volume ( sort { versioncmp($a, $b) } keys %{$Delete_requirements{volumes}} ) {
		foreach my $project ( sort { versioncmp($a, $b) } keys %{$Delete_requirements{volumes}{$volume}{projects}} ) {
			if($Delete_requirements{volumes}{$volume}{projects}{$project}{skip_clean} eq "true" ) {
				print "\t$project will be skipped, no clean for that project\n";
				next;
			}
			print "\t$project\n";
			foreach my $build ( sort { versioncmp($a, $b) } keys %{$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}} ) {
				if($Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{skip_clean} eq "true") {
					print "\t\t$build will be skipped, no clean for that build\n";
					next;
				}
				print "\t\t$build\n";
				my @all_revisions = get_revisions_for_this_build_path("$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{build_path}"
																	 ,"$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{clean_on_next_cron}"
																	 );
				if( scalar @all_revisions > 0) {
					foreach my $revision ( sort { versioncmp($b, $a) } @all_revisions ) {
						if($revision =~ /^(.+?)\_will\_be\_deleted\_at\_/i) {
							my $orig_revision = $1 ;
							if(defined $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{revisions}{$revision}{clean} && $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{revisions}{$revision}{clean} eq "true") {
								print "\t\t\t$revision -> to clean\n";
								if( -l "$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{build_path}/$revision" ) {
									my $cmd = "cd $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{build_path} && rm -f $revision";
									system "$cmd 2>&1" and warn "WARNING : command '$cmd' failed : $!";
								}
								move_in_toClean_folder($volume,$project,$build,$orig_revision);
								$total_nb_move++;
							}
						}  else  {
							if( defined $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{revisions}{$revision}{clean} && $Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{revisions}{$revision}{clean} eq "true") {
								if($Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{clean_on_next_cron} eq "true") {
									print "\t\t\t$revision -> prepare for the next cron\n";
									prepare_revision_for_next_cron("$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{build_path}","$revision");
									push @csv_next_lines , "'$volume';'$project';'$build';'$revision';'$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{build_path}/$revision'" ;
								}  else  {
									print "\t\t\t$revision -> to clean\n";
									move_in_toClean_folder($volume,$project,$build,$revision);
									$total_nb_move++;
								}
							}  else  {
								print "\t\t\t$revision -> to keep\n";
								push @csv_keep_lines , "'$volume';'$project';'$build';'$revision';'$Delete_requirements{volumes}{$volume}{projects}{$project}{builds}{$build}{build_path}/$revision'" ;
							}
						}
					}
				}
				print "\n";
			}
		}
	}
	if( scalar @csv_keep_lines > 0) {
		my $csv_keep_file = generate_base_csv_filename("keep");
		print "Create $CSV_DIR/$csv_keep_file\n";
		if(open my $csv_handle , '>' , "$CSV_DIR/$csv_keep_file") {
			foreach my $line (@csv_keep_lines) {
				print $csv_handle $line , "\n";
			}
			close $csv_handle;
		}  else  {
			warn "WARNING : cannot create '$CSV_DIR/$csv_keep_file' : $!";
		}
	}
	if( scalar @csv_next_lines > 0) {
		my $csv_next_file = generate_base_csv_filename("next");
		print "Create $CSV_DIR/$csv_next_file\n";
		if(open my $csv_handle , '>' , "$CSV_DIR/$csv_next_file") {
			foreach my $line (@csv_next_lines) {
				print $csv_handle $line , "\n";
			}
			close $csv_handle;
		}  else  {
			warn "WARNING : cannot create '$CSV_DIR/$csv_next_file' : $!";
		}
	}
}

sub prepare_revision_for_next_cron($$) {
	my ($this_path,$this_revision) = @_ ;
	print "create symlink $this_revision -> ${this_revision}_will_be_deleted_at_$next_clean\n";
	my $cmd = "cd $this_path/ && ln -s $this_revision ${this_revision}_will_be_deleted_at_$next_clean && chown -h pblack:integrat ${this_revision}_will_be_deleted_at_$next_clean";
	system "$cmd 2>&1" and warn "WARNING : command '$cmd' failed : $!";
}

sub move_in_toClean_folder($$$$) {
	my ($this_volume,$this_project,$this_build,$this_revision) = @_ ;
	my $toClean_path = "$drop_base_dir/.$this_volume/toClean";
	my $target_dir   = "$toClean_path/$Full_Date/$this_project/$this_build/";
	unless ( -e "$target_dir") {
		mkpath "$target_dir" or warn "WARNING : cannot mkpath '$target_dir' : $!";
	}
	my $source_dir = "$drop_base_dir/.$this_volume/$this_project/$this_build/$this_revision";
	if( -e "$source_dir") {
		my $cmd = "mv $source_dir $target_dir";
		print  "$cmd\n";
		system "$cmd 2>&1" and warn "WARNING : command '$cmd' failed : $!";
	}
	my $real_revision = $this_revision;
	if($this_revision =~ /^(\d+(?:\.\d+)?)\_will\_be\_deleted\_at\_/i) {
		$real_revision = $1;
		if( -e "$target_dir/$this_revision") {
			my $cmd = "mv $target_dir/$this_revision $target_dir/$real_revision";
			print  "$cmd\n";
			system "$cmd 2>&1" and warn "WARNING : command '$cmd' failed : $!";
		}
	}
}

sub clean_in_toClean_folder() {
	my @csv_clean_lines;
	print "\nPerform Cleans\n";
	my $volume_hRef = $data_hRef->{volumes};
	my $current_mailFrom = (defined $data_hRef->{mailFrom}) ? $data_hRef->{mailFrom} : "";
	my $current_mailTo   = (defined $data_hRef->{mailTo})   ? $data_hRef->{mailTo}   : "";
	my $current_contact  = (defined $data_hRef->{contact})  ? $data_hRef->{contact}  : "";
	for my $volume_Element (@$volume_hRef) {
		next if($param_volume && ($param_volume !~ /^$volume_Element->{volume_name}$/));
		my $volume = $volume_Element->{volume_name};
		$current_mailFrom = (defined $Delete_requirements{volumes}{$volume}{mailFrom}) ? $Delete_requirements{volumes}{$volume}{mailFrom} : $current_mailFrom ;
		$current_mailTo   = (defined $Delete_requirements{volumes}{$volume}{mailFrom}) ? $Delete_requirements{volumes}{$volume}{mailTo}   : $current_mailTo ;
		$current_contact  = (defined $Delete_requirements{volumes}{$volume}{mailFrom}) ? $Delete_requirements{volumes}{$volume}{contact}  : $current_contact ;
		if(opendir VOLUMES , "$drop_base_dir/.$volume/toClean") {
			my $nb_dates = 0;
			while(defined(my $this_date = readdir VOLUMES)) {
				next if( $this_date =~ /^\./ ); # skip special folders '.' and '..' and '.something'
				if(opendir PROJECTS , "$drop_base_dir/.$volume/toClean/$this_date") {
					$nb_dates++;
					my $nb_projects = 0;
					while(defined(my $this_project = readdir PROJECTS)) {
						next if( $this_project =~ /^\./ ); # skip special folders '.' and '..' and '.something'
						if(opendir BUILDS , "$drop_base_dir/.$volume/toClean/$this_date/$this_project") {
							$nb_projects++;
							my $nb_builds = 0;
							$current_mailFrom = (defined $Delete_requirements{volumes}{$volume}{projects}{$this_project}{mailFrom}) ? $Delete_requirements{volumes}{$volume}{projects}{$this_project}{mailFrom} : $current_mailFrom ;
							$current_mailTo   = (defined $Delete_requirements{volumes}{$volume}{projects}{$this_project}{mailTo})   ? $Delete_requirements{volumes}{$volume}{projects}{$this_project}{mailTo}   : $current_mailTo ;
							$current_contact  = (defined $Delete_requirements{volumes}{$volume}{projects}{$this_project}{contact})  ? $Delete_requirements{volumes}{$volume}{projects}{$this_project}{contact}  : $current_contact ;
							while(defined(my $this_build = readdir BUILDS)) {
								next if( $this_build =~ /^\./ ); # skip special folders '.' and '..' and '.something'
								$current_mailFrom = (defined $Delete_requirements{volumes}{$volume}{projects}{$this_project}{builds}{$this_build}{mailFrom}) ? $Delete_requirements{volumes}{$volume}{projects}{$this_project}{builds}{$this_build}{mailFrom} : $current_mailFrom ;
								$current_mailTo   = (defined $Delete_requirements{volumes}{$volume}{projects}{$this_project}{builds}{$this_build}{mailTo})   ? $Delete_requirements{volumes}{$volume}{projects}{$this_project}{builds}{$this_build}{mailTo}   : $current_mailTo ;
								$current_contact  = (defined $Delete_requirements{volumes}{$volume}{projects}{$this_project}{builds}{$this_build}{contact})  ? $Delete_requirements{volumes}{$volume}{projects}{$this_project}{builds}{$this_build}{contact}  : $current_contact ;
								if(opendir REVISIONS , "$drop_base_dir/.$volume/toClean/$this_date/$this_project/$this_build") {
									$nb_builds++;
									my $nb_revisons = 0;
									while(defined(my $this_revision = readdir REVISIONS)) {
										next if( $this_revision =~ /^\./ ); # skip special folders '.' and '..' and '.something'
										if( -e "$drop_base_dir/.$volume/toClean/$this_date/$this_project/$this_build/$this_revision") {
											$nb_revisons++;
											if($opt_Prepare_ReClean_Step) {
												if($this_revision =~ /^(.+?)\_delete\_ongoing$/i) {
													my $rev = $1;
													my $cmd = "mv $drop_base_dir/.$volume/toClean/$this_date/$this_project/$this_build/$this_revision $drop_base_dir/.$volume/toClean/$this_date/$this_project/$this_build/$rev";
													system "$cmd 2>&1" and warn "WARNING : command '$cmd' failed : $!";
												}
											}  else  {
												unless ($this_revision =~ /\_delete\_ongoing$/i) {
													my $cmd = "mv $drop_base_dir/.$volume/toClean/$this_date/$this_project/$this_build/$this_revision $drop_base_dir/.$volume/toClean/$this_date/$this_project/$this_build/${this_revision}_delete_ongoing";
													system "$cmd 2>&1" and warn "WARNING : command '$cmd' failed : $!";
												}
												unless($opt_Refresh_Step) {
													unlink_revision($volume,$this_date,$this_project,$this_build,$this_revision,$current_mailFrom,$current_mailTo,$current_contact);
													(my $orig_revision = $this_revision) =~ s/\_delete\_ongoing$//i;
													my $this_path = "$drop_base_dir/.$volume/$this_project/$this_build/$orig_revision";
													push @csv_clean_lines , "'$volume';'$this_project';'$this_build';'$orig_revision';'$this_path'" ;
												}
											}
										}
									}
									closedir REVISIONS;
									if($nb_revisons == 0) {
										print "$drop_base_dir/.$volume/toClean/$this_date/$this_project/$this_build is empty, delete it.\n";
										my $cmd = "rm -rf $drop_base_dir/.$volume/toClean/$this_date/$this_project/$this_build";
										system "$cmd 2>&1" and warn "WARNING : command '$cmd' failed : $!";
									}
								}  else  {
									warn "WARNING : cannot opendir '$drop_base_dir/.$volume/toClean/$this_date/$this_project/$this_build' : $!";
								}
							}
							closedir BUILDS;
							if($nb_builds == 0) {
								print "$drop_base_dir/.$volume/toClean/$this_date/$this_project is empty, delete it.\n";
								my $cmd = "rm -rf $drop_base_dir/.$volume/toClean/$this_date/$this_project";
								system "$cmd 2>&1" and warn "WARNING : command '$cmd' failed : $!";
							}
						}  else  {
							warn "WARNING : cannot opendir '$drop_base_dir/.$volume/toClean/$this_date/$this_project' : $!";
						}
					}
					closedir PROJECTS;
					if($nb_projects == 0) {
						print "$drop_base_dir/.$volume/toClean/$this_date is empty, delete it.\n";
						my $cmd = "rm -rf $drop_base_dir/.$volume/toClean/$this_date";
						system "$cmd 2>&1" and warn "WARNING : command '$cmd' failed : $!";
					}
				}  else  {
					warn "WARNING : cannot opendir '$drop_base_dir/.$volume/toClean/$this_date' : $!";
				}
			}
			closedir VOLUMES;
		}  else  {
			die "ERROR : cannot opendir '$drop_base_dir/.$volume/toClean' : $!";
		}
	}
	unless($opt_Refresh_Step) {
		if( scalar @csv_clean_lines > 0) {
			my $csv_clean_file = generate_base_csv_filename("clean");
			print "Create $CSV_DIR/$csv_clean_file\n";
			if(open my $csv_handle , '>' , "$CSV_DIR/$csv_clean_file") {
				print "Create $CSV_DIR/$csv_clean_file\n";
				foreach my $line (@csv_clean_lines) {
					print $csv_handle $line , "\n";
				}
				close $csv_handle;
			}  else  {
				warn "WARNING : cannot create '$CSV_DIR/$csv_clean_file' : $!";
			}
		}
	}
	if(($total_nb_move > 0) && ($total_nb_clean_process_inpg > 0)) {
		print "\n";
		print "total nb move  : $total_nb_move\n";
		print "total nb clean : $total_nb_clean_process_inpg\n";
		if($total_nb_move > $total_nb_clean_process_inpg) {
			print "WARNING : nb move is greater than nb cleans, please checks in logs.\n";
		}
		print "\n";
	}
}

sub unlink_revision($$$$$$$$) {
	my ($this_volume,$this_date,$this_project,$this_build,$this_revision,$this_mailFrom,$this_mailTo,$this_contact) = @_ ;
	# build cmd line
	if( $this_revision !~ /\_delete\_ongoing$/i) {
		$this_revision .= "_delete_ongoing";
	}
	my $cmd = "nohup nice -n 19 $PERL_PATH/bin/perl -w $CURRENTDIR/multi_unlink.pl"
			. " -s=$drop_base_dir"
			. " -v=$this_volume"
			. " -d=$this_date"
			. " -p=$this_project"
			. " -b=$this_build"
			. " -r=$this_revision"
			;
	if($opt_scriptMail) {
		$cmd .= " -sm=$opt_scriptMail";
	}
	if($param_revision) {
		$cmd .= " -F";
	}
	if($this_mailFrom && $this_mailTo && $this_contact) {
		$cmd .= " -mf=\"$this_mailFrom\" -mt=\"$this_mailTo\" -c=\"$this_contact\"";
	}
	if( ! -e "$LOGS_DIR/$this_volume" ) {
		mkpath "$LOGS_DIR/$this_volume" or warn "WARNING : cannot mkpath '$LOGS_DIR/$this_volume' : $!";
	}
	my $log_file = "$LOGS_DIR/$this_volume/"
				 . "$this_date"
				 . "_$this_project"
				 . "_$this_build"
				 . "_$this_revision.log"
				 ;
	if ( -e "$LOGS_DIR/$this_volume") {
		if($nb_clean_process_ref && ($nb_clean_process_inpg > $nb_clean_process_ref)) {
			print "need to wait for $nb_waitfor_insec seconds . . .\n";
			sleep $nb_waitfor_insec;
			$nb_clean_process_inpg = 0;
		}
		$nb_clean_process_inpg++;
		$total_nb_clean_process_inpg++;
		print  "start $total_nb_clean_process_inpg $cmd >& $log_file &\n";
		system "$cmd >& $log_file &";
	}  else  {
		warn "WARNING : cannot run '$cmd >& $log_file', because '$LOGS_DIR/$this_volume' does not exists : $!";
	}
}

sub kill_unlinks_ongoing() {
	my $username = `nice -n 19 whoami`;
	chomp $username;
	my $ps = "ps -ef | grep unlink | grep -vw grep";
	for(my $iteration=0; $iteration<10 ; $iteration++) {
		if(open PS_UNLINK , "$ps 2>&1 |") {
			while(<PS_UNLINK>) {
				chomp;
				my $line = $_ ;
				next if($param_volume    && !($line =~ /\=$param_volume/));
				next if($param_project   && !($line =~ /\=$param_project/));
				next if($param_buildname && !($line =~ /\=$param_buildname/));
				my ($this_user,$PID) = $line =~ /^(.+?)\s+(\d+)\s+/;
				next unless($this_user eq $username);
				if($PID && ($PID =~ (/^\d+$/)) ) { # just to be sure $PID exists and is a number
					print  "kill -9 $PID ($line)\n";
					system "kill -9 $PID" and warn "WARNING : command 'kill -9 $PID' failed : $!";
				}
			}
			close PS_UNLINK;
		}
		sleep 1;
	}
}

sub display_info() {
	if(     ($param_just_info ne "nbc")
		and ($param_just_info ne "size")
		and ($param_just_info ne "content")
		and ($param_just_info ne "all")
		or  ($param_just_info eq "help")
	) {
		print "

available values for -ji parameter:
nbc     : display number of cleans on going
size    : to display size of volume(s)
content : to display content of toClean folder
all     : to display all info
help    : to display this mini help

";
	}  else  {
		my $volumes_Ref = $data_hRef->{volumes};
		for my $volume_Element(@$volumes_Ref) {
			# just to have shortname as variable
			my $volume_name = $volume_Element->{volume_name};
			next if($param_volume && ($param_volume ne $volume_name));
			print "\n\t\#\#\#\#\#\#\#\#\#\#\#" , "#" x length($volume_name) , "\#\#\#\#\#\#\#\#\#\#\#\n";
			print   "\t\#\#\#\#\#\#\#\#\#\# " , " " x length($volume_name) , " \#\#\#\#\#\#\#\#\#\#\n";
			print   "\t\#\#\#\#\#\#\#\#\#\# $volume_name \#\#\#\#\#\#\#\#\#\#\n";
			print   "\t\#\#\#\#\#\#\#\#\#\# " , " " x length($volume_name) , " \#\#\#\#\#\#\#\#\#\#\n";
			print   "\t\#\#\#\#\#\#\#\#\#\#\#" , "#" x length($volume_name) , "\#\#\#\#\#\#\#\#\#\#\#\n\n";
			list_unlink_running_on_this_volume($volume_name)              if($param_just_info eq "nbc"     or $param_just_info eq "all");
			display_size_of_this_volume($volume_name)                     if($param_just_info eq "size"    or $param_just_info eq "all");
			list_content_toClean_folder_for_this_volume($volume_name)     if($param_just_info eq "content" or $param_just_info eq "all");
		}
	}
}

sub list_unlink_running_on_this_volume($) {
	my ($my_volume) = @_ ;
	print "\n";
	my $pattern = "multi_unlink.pl";
	print "==== list of all '$pattern' running by root with $0 ====\n";
	my $total_nb_rm = 0 ;
	my $psCmd = "ps -ef | grep -wvi grep | grep -i \"$pattern\"  | grep -i $my_volume";
	print "$psCmd\n\n";
	if(open PS_UNLINK , "$psCmd 2>&1 |") {
		my %unlink_commands;
		while(<PS_UNLINK>) {
			chomp;
			# $s as source dropzone path
			# $v as volume
			# $d as date
			# $p as project
			# $b as build name
			# $r as revision
			my ($infos,$s,$v,$d,$p,$b,$r)
				= $_
				=~ /^(.+?)\s+\-s\=(.+?)\s+\-v\=(.+?)\s+\-d\=(.+?)\s+\-p\=(.+?)\s+\-b\=(.+?)\s+\-r\=(.+?)$/i; # -v=volume -d=date -p=project -b=build -r=revision
			my $v_dir = get_full_path_of_this_volume($v);
			my $dir = "$v_dir/toClean/$d/$p/$b/$r";
			$unlink_commands{$dir}{infos}  = $infos;
			$unlink_commands{$dir}{volume} = $v;
		}
		close PS_UNLINK;
		my $nb_rm_per_volume = 0 ;
		if((scalar keys %unlink_commands) > 0) {
			print "\t$my_volume\n";
			foreach my $dir (sort keys %unlink_commands) {
				next if($unlink_commands{$dir}{volume} ne $my_volume);
				my ($user,$pid,$ppid,$a,$start,$b,$c,$basic_cmd,$folder) = split '\s+' , $unlink_commands{$dir}{infos};
				my $real_start = get_start_time_of_this_pid($pid);
				print "$pid $real_start $basic_cmd $pattern $dir\n";
				print "\n";
				system("$PERL_PATH/bin/perl -w $CURRENTDIR/ptree.pl $pid");
				print "\n";
				$nb_rm_per_volume++;
			}
			print "nb multi_unlink.pl for $my_volume : $nb_rm_per_volume\n";
			print "\n";
		}
		$total_nb_rm = $total_nb_rm + $nb_rm_per_volume;
	}
	print "\ntotal $pattern : $total_nb_rm\n\n";
}

sub display_size_of_this_volume($) {
	my ($my_volume) = @_ ;
	print  "\n";
	print  "==== display size of $my_volume ====\n";
	my $v_dir = get_full_path_of_this_volume($my_volume);
	system "df -h $v_dir 2>&1" and warn "WARNING : command 'df -h $v_dir' failed : $!";
	print  "\n\n";
}

sub list_content_toClean_folder_for_this_volume($) {
	my ($my_volume) = @_ ;
	my $v_dir = get_full_path_of_this_volume($my_volume);
	my $common_dir  = "$v_dir/toClean";
	if( -e $common_dir) {
		print  "==== content of $v_dir/toClean ====\n";
		if(opendir TO_CLEAN_DIR , $common_dir) {
			while(defined (my $this_day = readdir TO_CLEAN_DIR)) {
				next if($this_day =~ /^\./); # skip special folders '.' and '..' and '.something'
				if(opendir DATE_DIR , "$common_dir/$this_day") {
					print "$this_day\n";
					while(defined (my $this_project = readdir DATE_DIR)) {
						next if($this_project =~ /^\./); # skip special folders '.' and '..' and '.something'
						if(opendir PROJECT_DIR , "$common_dir/$this_day/$this_project") {
							print "\t$this_project\n";
							while(defined (my $this_build = readdir PROJECT_DIR)) {
								next if($this_build =~ /^\./); # skip special folders '.' and '..' and '.something'
								if(opendir BUILD_DIR , "$common_dir/$this_day/$this_project/$this_build") {
									print "\t\t$this_build\n";
									while(defined (my $this_rev = readdir BUILD_DIR)) {
										next if($this_rev =~ /^\./); # skip special folders '.' and '..' and '.something'
										print "\t\t\t$this_rev\n";
									}
									closedir BUILD_DIR;
								}  else  {
									warn "WARNING : cannot opendir '$common_dir/$this_day/$this_project/$this_build' : $!";
								}
							}
							closedir PROJECT_DIR;
						}  else  {
							warn "WARNING : cannot opendir '$common_dir/$this_day/$this_project' : $!";
						}
					}
					closedir DATE_DIR
				}  else  {
					warn "WARNING : cannot opendir '$common_dir/$this_day' : $!";
				}
			}
			closedir TO_CLEAN_DIR;
		}  else  {
			warn "WARNING : cannot opendir '$common_dir' : $!";
		}
		print  "\n";
	}  else  {
		warn "WARNING : '$common_dir' does not exist : $!";
	}
	print "\n";
}

sub get_full_path_of_this_volume($) {
	my ($this_volume) = @_ ;
	my $tmp_v_dir = "$drop_base_dir/.$this_volume";
	if( ! -d $tmp_v_dir ) {
		$tmp_v_dir = "$drop_base_dir/$this_volume";
	}
	return $tmp_v_dir;
}

sub search_symlinks_for_revision($$) {
	my ($this_path,$this_revision) = @_ ;
	my $found_symlink = 0;
	if(open SEARCH_SYMLINK , "cd $this_path ; ls -l | grep -i $this_revision | grep -i _will_be_deleted_at_ | grep ' -> ' 2>&1 |") {
		while(<SEARCH_SYMLINK>) {
			chomp;
			if(/\_will\_be\_deleted\_at\_/i) {
				$found_symlink = 1 ;
				last;
			}
		}
		close SEARCH_SYMLINK;
	}
	return $found_symlink;
}


sub get_start_time_of_this_pid($) {
	my ($this_pid) = @_ ;
	my $start;
	$start = `nice -n 19 ps -p $this_pid -o start | grep -vi STARTED`;
	chomp $start;
	return $start;
}

sub sendMailOnCleanIssue($$$$) {
	my ($this_mailFrom,$this_mailTo,$this_subject,$this_htmlFile) = @_ ;
	my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>90, Debug=>1,);
	my $htmlFile;
	$smtp->hello($smtp->domain);
	$smtp->mail($this_mailFrom);
	$smtp->to(split  '\s*;\s*' , $this_mailTo);
	$smtp->data();
	$smtp->datasend("To: $this_mailTo\n");
	$smtp->datasend("Subject: $this_subject\n");
	$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.html\n");
	open HTML, "$this_htmlFile"  or die "ERROR: cannot read '$this_htmlFile' : $!";
		while(<HTML>) { $smtp->datasend($_) }
	close HTML;
	$smtp->dataend();
	$smtp->quit();
}

sub sendMailOnScriptIssue($@) {
	my ($issueType,@Messages) = @_;

	return if($NumberOfEmails);
	$NumberOfEmails++;

	open HTML, ">$TEMP_DIR/Mail$$.htm" or die "ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $!";
	print HTML "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n";
	print HTML "<html>\n";
	print HTML "\t<head>\n";
	print HTML "\t</head>\n";
	print HTML "\t<body>\n";
	print HTML "*****This email has been sent from an unmonitored automatic mailbox.*****<br/><br/>\n";
	print HTML "Hi everyone,<br/><br/>\n";
	print HTML "&nbsp;"x5, "We have the following error(s) while running '$CommandLine' on $hostName:<br/>\n";
	foreach (@Messages) {
		print HTML "&nbsp;"x5, "$_<br/>\n";
	}
	my $i = 1;
	print(HTML "<br/><br/>Stack Trace:<br/>\n");
	while((my ($FileName, $Line, $Subroutine) = (caller($i++))[1..3])) {
		print(HTML "File \"$FileName\", line $Line, in $Subroutine.<br/>\n");
	}
	
	print HTML "<br/><br/>Best regards<br/>\n";
	print HTML "\t</body>\n";
	print HTML "</html>\n";
	close HTML;

	my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>60) or warn"WARNING : SMTP connection impossible : $!";
	$smtp->mail($SCRIPT_SMTPFROM);
	$smtp->to(split('\s*;\s*', $SCRIPT_SMTPTO));
	$smtp->data();
	$smtp->datasend("To: $SCRIPT_SMTPTO\n");
	my($Script) = $0 =~ /([^\/\\]+)$/;
	$smtp->datasend("Subject: $issueType [$Script] Errors on $hostName\n");
	$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
	open HTML, "$TEMP_DIR/Mail$$.htm"  or warn "WARNING : cannot open '$TEMP_DIR/Mail$$.htm' : $!";
	while(<HTML>) { $smtp->datasend($_) } 
	close(HTML);
	$smtp->dataend();
	$smtp->quit();

	system "rm -f $TEMP_DIR/Mail$$.htm >& /dev/null || true";
}

sub end_script() {
	print "

end of $0

";
	exit 0;
}

sub display_usage() {
	print <<FIN_USAGE;

[synopsis]
$0 list, move, and remove some build revisions, without any tag, from
$drop_base_dir/.VOLUME_N/project/build_name/revision
to)
$drop_base_dir/.VOLUME_N/toClean/$Full_Date/project/build_name/...


[environment variables]
$0 can use environment variables,
$0 set default values if not set:
SITE=$SITE\t\t\t\t\t(used for default json filename: $SITE.json)
PERL_PATH=$PERL_PATH;\t\t(used to run multi_unlink.pl)
DROP_BASE_DIR=$drop_base_dir\t(directoy which should contains the volumes : .volumes)


[options]
	-help   argument displays helpful information about builtin commands.

	-j      choose a json file, by default -j=$SITE.json
	-s      choose a site, by default, -s=Walldorf
	-v      volume to manage
	-p      project to manage, '-v' is mandatory if you use '-p', only 1 project
	-b      build to manage, '-v' and '-p' are mandatory if you use '-b', only 1 build
	-k      number of builds to keep,
			WARNING : will override vkeep, pkeep and bkeep set in json file
	-ik     number of incremental builds to keep,
			WARNING : will override vki, pki and bki set in json file
	-jcj    just check json file (syntax,...) before push
	-jl     just list build revisions to keep/delete
	-ndl    no display list revisions to keep/delete (could be huge)
	-ndi    no display info (could be huge)
	-ji     just display info, available avalues:
			-ji=nbc     to display cleans on going
			-ji=size    to display size of volume(s)
			-ji=content to display content of toClean folder
			-ji=all     to display all info
			-ji=help    to display mini help
	-cio    Clean Incrementals Only
	-S      Stop cleans an going and execute step PRC (need to be run as root)
	-R      Refresh Step (cleanup toClean folder, need to be run as root) 
	-M      Move build revisions to delete into toClean/DATE/BUILDNAME (need to be run as root)
	-PRC    Prepare Re Clean Step (if machine rebooted, process killed), will remove suffix _delete_ongoing (need to be run as root)
	-C      Clean Step all build revisions in toClean/*/* (need to be run as root)
	-ni     to not display info

FIN_USAGE
	exit 0;
}
