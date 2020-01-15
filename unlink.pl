#############################################################################
# unlink.pl

#############################################################################
##### declare uses

## ensure good code quality
use strict;
use warnings;
use diagnostics;

# requied for the script itself
use Sys::Hostname;
use Getopt::Long;
use File::Find;
use File::Path;
use File::Copy;
use Date::Calc(qw(Today_and_Now Delta_DHMS Add_Delta_Days Add_Delta_DHMS));
# for calculatinbg current dir
use FindBin;
use lib $FindBin::Bin;



#############################################################################
##### declare vars
# for the script itself
use vars qw (
	@StartClean
	$full_path_to_clean
	$CURRENTDIR
	$PERL_PATH
	$CLEAN_SCRIPT_DIR
	$TEMP_DIR
	$LOGS_DIR
	$hostName
	$NumberOfEmails
	$SMTP_SERVER
	$SCRIPT_SMTPFROM
	$SCRIPT_SMTPTO
	$CommandLine
);

# paths, dir, folder
use vars qw (
	$toClean_folder
	$v_dir
);

# parameters / options for variables not listed above
use vars qw (
	$opt_help
	$opt_force
	$opt_scriptMail
	$param_base_drz_dir
	$param_volume
	$param_date
	$param_project
	$param_build_name
	$param_build_rev
	$param_filetree
);



#############################################################################
##### declare functions
sub sap_display_usage();
sub sap_get_full_path_of_this_volume($);
sub sap_clean_this_directory($);
sub sap_start_script();
sub sap_end_script();
sub sendMailOnScriptIssue($@);



#############################################################################
##### get & manage options/parameters
$CommandLine = "$0 @ARGV";
$Getopt::Long::ignorecase = 0;
GetOptions(
	"help|?"    =>\$opt_help,
	"s=s"       =>\$param_base_drz_dir,
	"v=s"       =>\$param_volume,
	"d=s"       =>\$param_date,
	"p=s"       =>\$param_project,
	"b=s"       =>\$param_build_name,
	"r=s"       =>\$param_build_rev,
	"f=s"       =>\$param_filetree,
	"F"         =>\$opt_force,
	"sm=s"      =>\$opt_scriptMail,
);

sap_display_usage() if($opt_help);

$hostName   = hostname;
$CURRENTDIR = $FindBin::Bin;
$CLEAN_SCRIPT_DIR = $ENV{CLEAN_SCRIPT_DIR}  || $CURRENTDIR;
$PERL_PATH        = $ENV{CLEAN_PERL_PATH}   || "/softs/perl/latest";
$TEMP_DIR         = $ENV{TEMP} || $ENV{TMP} || "$ENV{HOME}/tmp";
$LOGS_DIR         = $ENV{CLEAN_LOGS_DIR}    || "/logs/clean-dropzone" ;
if( ! -e $TEMP_DIR ) {
	mkpath "$TEMP_DIR" or die "ERROR : cannot mkpath '$TEMP_DIR' : $!";
}
if( ! -e "$LOGS_DIR") {
	mkpath "$LOGS_DIR" or die "ERROR : cannot mkpath '$LOGS_DIR' : $!";
}

$SMTP_SERVER = $ENV{CLEAN_SMTP_SERVER} || "mail.sap.corp";
if($opt_scriptMail) {
	$SCRIPT_SMTPFROM    = $ENV{CLEAN_SCRIPT_SMTPFROM} || 'bruno.fablet@sap.com' ;
	$SCRIPT_SMTPTO      = $ENV{CLEAN_SCRIPT_SMTPTO}   || 'bruno.fablet@sap.com' ;
	$NumberOfEmails     = 0;
	if( ($opt_scriptMail =~ /^die$/)  || ($opt_scriptMail =~ /^all$/) ){
		$SIG{__DIE__}       = sub { eval { sendMailOnScriptIssue("die"  , @_) } ; die(@_)  };
	}
	if( ($opt_scriptMail =~ /^warn$/) || ($opt_scriptMail =~ /^all$/) ){
		$SIG{__WARN__}      = sub { eval { sendMailOnScriptIssue("warn" , @_) } ; warn(@_) };
	}
}

unless($param_filetree) {
	unless($param_volume) {
		die "ERROR : param -v missing, eg : use perl $0 -v=volume1 : $!";
	}
	unless($param_date) {
		die "ERROR : param -d missing, eg : use perl $0 -d=2015_09_10 : $!";
	}
	unless($param_project) {
		die "ERROR : param -p missing, eg : use perl $0 -p=aurora_maint : $!";
	}
	unless($param_build_name) {
		die "ERROR : param -b missing, eg : use perl $0 -b=aurora41_sp06_patch_cor : $!";
	}
	unless($param_build_rev) {
		die "ERROR : param -r missing, eg : use perl $0 -r=1794_delete_ongoing : $!";
	}
	if( ! $opt_force) {
		if($param_build_rev && ($param_build_rev !~ /\d+\_delete\_ongoing$/)) {
			die "ERROR : revision should have this format : [number_delete_ongoing] in lower case, eg : -r=1794_delete_ongoing : $!";
		}
	}
}



#############################################################################
##### init vars
$param_base_drz_dir ||= "/net/build-drops-wdf/dropzone";
$v_dir                = sap_get_full_path_of_this_volume($param_volume);
$toClean_folder     ||= "$v_dir/toClean" unless($param_filetree);
$full_path_to_clean   = ($param_filetree) ? $param_filetree
					  : "$toClean_folder"
					  . "/$param_date"
					  . "/$param_project"
					  . "/$param_build_name"
					  . "/$param_build_rev"
					  ;



#############################################################################
##### MAIN

print "\n\n\nOptions used:\n";
unless($param_filetree) {
	print "dropzone  : $param_base_drz_dir\n";
	print "volume    : $param_volume\n";
	print "date      : $param_date\n";
	print "project   : $param_project\n";
	print "buildname : $param_build_name\n";
	print "revision  : $param_build_rev\n";
}
print "PID: $$\n";
print "\n\nEnd Options\n\n\n";

if(( -e $full_path_to_clean ) && ( -d $full_path_to_clean )) {
	sap_start_script();
	print "$0 $full_path_to_clean\n";

	my @StartClean1 = Today_and_Now();
	sap_clean_this_directory($full_path_to_clean);
	printf "\nFiles cleans took %u h %02u mn %02u s at %s\n",
			(Delta_DHMS(@StartClean1, Today_and_Now()))[1..3]
			, scalar localtime
			;

	my @StartClean2 = Today_and_Now();
	system "rm -f \"full_path_to_clean\" >& /dev/null || true";
	printf "\nFolders cleans took %u h %02u mn %02u s at %s\n",
			(Delta_DHMS(@StartClean2, Today_and_Now()))[1..3]
			, scalar localtime
			;

	printf "\nAll cleans took %u h %02u mn %02u s at %s\n",
			(Delta_DHMS(@StartClean1, Today_and_Now()))[1..3]
			, scalar localtime
			;
	print "\n";

	sap_end_script();
}  else  {
	die "ERROR : $full_path_to_clean not found or not a directory : $!";
}



#############################################################################
### internal functions
sub sap_get_full_path_of_this_volume($) {
	my ($this_volume) = @_ ;
	my $tmp_v_dir = "$param_base_drz_dir/.$this_volume";
	if( ! -d $tmp_v_dir ) {
		$tmp_v_dir = "$param_base_drz_dir/$this_volume";
	}
	return $tmp_v_dir;
}

sub sap_clean_this_directory($) { # optim, get from internet by CVIGNON
	my ($dir) = @_;
	if (opendir (my $dh, $dir)) {
		my @folders;
		my @files;
		# get content of a folder
		while(defined (my $elem = readdir $dh)) {
			next if ( ($elem =~ /^\.$/) || ($elem =~ /^\.\.$/) );
			if ( -d "$dir/$elem" ) {
				push @folders, "$dir/$elem" ;
			}  else  {
				push @files , "$dir/$elem" ;
			}
		}
		closedir $dh;
		# cleans
		if( (scalar @files == 0) && (scalar @folders == 0) ) {
			rmdir $dir or warn "WARNING : cannot rmdir '$dir' : $!";
			return;
		}
		if(scalar @files > 0) {
			unlink @files;
			if(scalar @folders == 0) {
				rmdir $dir or warn "WARNING : cannot rmdir '$dir' : $!";
				return;
			}
		}
		if(scalar @folders > 0) {
			foreach my $folder (@folders) {
				sap_clean_this_directory("$folder");
			}
		}
	}
	return;
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

	my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>60) or warn "WARNING: SMTP connection impossible: $!";
	$smtp->mail($SCRIPT_SMTPFROM);
	$smtp->to(split('\s*;\s*', $SCRIPT_SMTPTO));
	$smtp->data();
	$smtp->datasend("To: $SCRIPT_SMTPTO\n");
	my($Script) = $0 =~ /([^\/\\]+)$/;
	$smtp->datasend("Subject: $issueType [$Script] Errors on $hostName\n");
	$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
	open HTML, "$TEMP_DIR/Mail$$.htm"  or warn "WARNING : cannot open '$TEMP_DIR/Mail$$.htm': $!";
	while(<HTML>) { $smtp->datasend($_) } 
	close(HTML);
	$smtp->dataend();
	$smtp->quit();

	system "rm -f $TEMP_DIR/Mail$$.htm >& /dev/null || true";
}

sub sap_start_script() {
	my $dateStart = scalar localtime;
	print "\nSTART of '$0' at $dateStart\n";
	print "#" x length "START of '$0' at $dateStart" , "\n";
	print "\n";
}

sub sap_end_script() {
	print "\n\n";
	my $dateEnd = scalar localtime;
	print "#" x  length "END of '$0' at $dateEnd" , "\n";
	print "END of '$0' at $dateEnd\n";
	exit 0;
}

sub sap_display_usage() {
	print <<FIN_USAGE;

[synopsis]
$0 search all files from a location, recursively, and delete them, faster than "rm -rf"

[options]
    -help   argument displays helpful information about builtin commands.
    -s      source dropzone path, eg: -s=/net/build-drops-wdf/dropzone
    -v      volume to clean,      eg: -v=volume1
    -d      date to clean,        eg: -d=2015_09_29
    -p      project to clean,     eg: -p:kxen_dev
    -b      build to clean,       eg: -b:ii_cons_master
    -r      revision to clean,    eg: -r=15_delete_ongoing
    -f      filetree to clean    (if -f, other options are ignored)
            eg: -f=/net/build-drops-wdf/dropzone/.volume2/toClean/2015_09_29/kxen_dev/ii_cons_master/398_delete_ongoing

FIN_USAGE
	exit 0;
}
