#############################################################################
# unlink.pl

#############################################################################
##### declare uses

## ensure good code quality
use strict;
use warnings;
use diagnostics;

# requied for the script itself
use Date::Calc(qw(Today_and_Now Delta_DHMS Add_Delta_Days Add_Delta_DHMS));
use Time::HiRes qw ( sleep );
use POSIX qw(:sys_wait_h);
use Sys::Hostname;
use Getopt::Long;
use File::Find;
use File::Path;
use File::Copy;
use Net::SMTP;


# for calculatinbg current dir
use FindBin;
use lib $FindBin::Bin;



#############################################################################
##### declare vars
# for the script itself
use vars qw (
	@StartClean
	$full_path_to_clean
	$SMTP_SERVER
	$TEMP_DIR
	$hostName
	$NumberOfEmails
	$PERL_PATH
	$CLEAN_SCRIPT_DIR
	$SMTP_SERVER
	$SCRIPT_SMTPFROM
	$SCRIPT_SMTPTO
	$CommandLine
	$LOGS_DIR
);

# paths, dir, folder
use vars qw (
	$CURRENTDIR
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
	$param_mailFrom
	$param_mailTo
	$param_contact
);



#############################################################################
##### declare functions
sub sap_display_usage();
sub sap_get_full_path_of_this_volume($);
sub sap_create_fork($$);
sub sap_check_empty_folder($);
sub sap_start_script();
sub sap_end_script();
sub sendMailOnCleanIssue($$);
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
	"mf=s"      =>\$param_mailFrom,
	"mt=s"      =>\$param_mailTo,
	"c=s"       =>\$param_contact,
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
print "dropzone : $param_base_drz_dir\n";
print "volume : $param_volume\n";
print "date : $param_date\n";
print "project : $param_project\n";
print "buildname : $param_build_name\n";
print "revision : $param_build_rev\n";
print "PID: $$\n";
print "\n\nEnd Options\n\n\n";

if(( -e $full_path_to_clean ) && ( -d $full_path_to_clean )) {
	sap_start_script();
	print "$0 $full_path_to_clean\n";

	my @StartClean1 = Today_and_Now();
	# determine number of process in parallel
	my $nb_process = 0;
	my %sub_folders;
	my $found_platform = 0;
	my @files_base;
	if(opendir BASE , "$full_path_to_clean") {
		 while(defined(my $this_platform = readdir(BASE))) {
			 next if ( ($this_platform =~ /^\.$/) || ($this_platform =~ /^\.\.$/) );
			 if( -d "$full_path_to_clean/$this_platform" ) {
				 if(opendir PLATFORM , "$full_path_to_clean/$this_platform") {
					 $found_platform = 1 ;
					 my $found_mode  = 0;
					 my @files_platform;
					while(defined(my $this_mode = readdir(PLATFORM))) {
						next if ( ($this_mode =~ /^\.$/) || ($this_mode =~ /^\.\.$/) );
						if( -d "$full_path_to_clean/$this_platform/$this_mode" ) {
							if(opendir MODE , "$full_path_to_clean/$this_platform/$this_mode") {
								$found_mode        = 1;
								my $found_artifact = 0;
								my @files_mode;
								while(defined(my $this_artifact = readdir(MODE))) {
									next if ( ($this_artifact =~ /^\.$/) || ($this_artifact =~ /^\.\.$/) );
									if( -d "$full_path_to_clean/$this_platform/$this_mode/$this_artifact" ) {
										$found_artifact       = 1;
										my $found_subArtifact = 0;
										my @files_subArtifact;
										if(opendir ARTIFACT , "$full_path_to_clean/$this_platform/$this_mode/$this_artifact") {
											my $sub_full_path = "$full_path_to_clean/$this_platform/$this_mode/$this_artifact";
											while(defined(my $this_subArtifact = readdir(ARTIFACT))) {
												next if ( ($this_subArtifact =~ /^\.$/) || ($this_subArtifact =~ /^\.\.$/) );
												if( -d "$full_path_to_clean/$this_platform/$this_mode/$this_artifact/$this_subArtifact" ) {
													$found_subArtifact = 1;
												}  else  {
													push @files_subArtifact , "$full_path_to_clean/$this_platform/$this_mode/$this_artifact/$this_subArtifact" ;
												}
											}
											closedir ARTIFACT;
											unlink @files_subArtifact if( scalar @files_subArtifact > 0);
											if($found_subArtifact == 1) {
												$nb_process++;
												$sub_folders{$sub_full_path} = 1;
											}  else  {
												if ( -e "$full_path_to_clean/$this_platform/$this_mode/$this_artifact") {
													system "rm -rf \"$full_path_to_clean/$this_platform/$this_mode/$this_artifact\" >& /dev/null || true";
												}
											}
										}  else  {
											warn "WARNING : cannot opendir '$full_path_to_clean/$this_platform/$this_mode/$this_artifact' : $!";
										}
									}  else  {
										push @files_mode , "$full_path_to_clean/$this_platform/$this_mode/$this_artifact";
									}
								}
								closedir MODE;
								unlink @files_mode if( scalar @files_mode > 0);
								if($found_artifact == 0) {
									system "rm -rf \"$full_path_to_clean/$this_platform/$this_mode\" >& /dev/null || true";
								}
							}  else  {
								warn "WARNING : cannot opendir '$full_path_to_clean/$this_platform/$this_mode' : $!";
							}
						}  else  {
							push @files_platform , "$full_path_to_clean/$this_platform/$this_mode" ;
						}
					}
					closedir PLATFORM;
					unlink @files_platform if( scalar @files_platform > 0);
					if( $found_mode == 0) {
						system "rm -rf \"$full_path_to_clean/$this_platform\" >& /dev/null || true";
					}
				 }  else  {
				 	warn "WARNING : cannot opendir '$full_path_to_clean/$this_platform' : $!";
				 }
			 }  else  {
				 push @files_base , "$full_path_to_clean/$this_platform" ;
			 }
		 }
		closedir BASE;
		unlink @files_base if( scalar @files_base > 0);
		if( $found_platform == 0 ) {
			system "rm -f \"full_path_to_clean\" >& /dev/null || true";
		}
	}  else  {
		die "ERROR : cannot opendir '$full_path_to_clean' : $!";
	}

	if($nb_process > 0) {
		my $numProc = 0;
		my %PIDS;

		# run parallel cleans
		foreach my $sub_folder (keys %sub_folders) {
			if($numProc >= $nb_process) {
				while( ! (my $pid = waitpid(-1, WNOHANG)) ) { sleep 1 }
				$numProc--;
			}
			my $command  = "nice -n 19 $PERL_PATH/bin/perl -w $CLEAN_SCRIPT_DIR/unlink.pl -f=\"$sub_folder\" -F";
			if($opt_scriptMail) {
				$command  .= " -sm=$opt_scriptMail";
			}
			#my $log_file =  $sub_folder;
			#($log_file)  =~ s/^//;
			#($log_file)  =~ s/^\///;
			#($log_file)  =~ s/\//\_/g;
			#$log_file    = "/logs/clean-dropzone/multi_cleans/$log_file";
			my $PID = sap_create_fork($command,"");
			$PIDS{$sub_folder}=$PID;
			$numProc++;
		}

		# check if done
		my $all_done = 0 ;
		foreach my $sub_folder (keys %sub_folders) {
			print "clean $sub_folder (PID: $PIDS{$sub_folder})";
			while( ! (my $pid = waitpid($PIDS{$sub_folder}, WNOHANG)) ) { sleep 1 }
			sleep 1;
			print " done\n";
			my $isCleaned = "false";
			if( -e "$sub_folder") {
				$isCleaned = sap_check_empty_folder($sub_folder);
				if( $isCleaned eq "true" ) {
					system "rm -rf \"$sub_folder\" >& /dev/null || true";
				}
			}
			$all_done++;
		}
		if($all_done == $nb_process) {
			if ( -e "$full_path_to_clean") {
				system "rm -rf \"$full_path_to_clean\" >& /dev/null || true";
			}
		}

		# send mail if any issue
		print "\n";
		print "mailFrom   : $param_mailFrom\n" if($param_mailFrom && defined $param_mailFrom);
		print "mailTo     : $param_mailTo\n"   if($param_mailTo   && defined $param_mailTo);
		print "contact    : $param_contact\n"  if($param_contact  && defined $param_contact);
		print "nb_process : $nb_process\n";
		print "all_done   : $all_done\n";
		print "full path  : $full_path_to_clean\n";
		print "\n";
		sleep 1;
		if( -e "$full_path_to_clean") {
			if( $param_mailFrom && $param_mailTo && $param_contact && defined $param_mailFrom && defined $param_mailTo && defined $param_contact && ($all_done < $nb_process) )  {
				my $subject   = "[dropzone clean issue] : fail to clean path : $full_path_to_clean";
				my $coreFile  = $param_volume . "_" . $param_project . "_" . $param_build_name . "_" . $param_build_rev ;
				my $htmlFile  = $coreFile . ".html" ;
				my $txtFile   = $coreFile . ".txt" ;
				if ( -e $htmlFile) {
					unlink $htmlFile or die "ERROR : cannot unlink '$htmlFile' : $!";
				}
				if ( -e $txtFile) {
					unlink $txtFile or die "ERROR : cannot unlink '$txtFile' : $!";
				}
				my $handleTxtFile;
				mkpath "$LOGS_DIR/mails" if( ! -e "$LOGS_DIR/mails");
				if(open $handleTxtFile , '>' , "$LOGS_DIR/mails/$txtFile") {
						print $handleTxtFile "volume=$param_volume\n";
						print $handleTxtFile "project=$param_project\n";
						print $handleTxtFile "build=$param_build_name\n";
						print $handleTxtFile "revision=$param_build_rev\n";
						print $handleTxtFile "path=$full_path_to_clean\n";
						print $handleTxtFile "from=$param_mailFrom\n";
						print $handleTxtFile "to=$param_mailTo\n";
						print $handleTxtFile "contact=$param_contact\n";
					close $handleTxtFile;
				}  else  {
					die "ERROR : cannot create '$LOGS_DIR/mails/$txtFile' : $!"
				}
				my $userName  = getpwuid($<);
				my $handleHtmlFile;
				(my $displayFrom = $param_mailFrom) =~ s-\@(.+?)$--i;
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
The clean mechanism might be encountered an issue during the clean of the path : $full_path_to_clean.<br/>
Please check on $hostName, as $userName, or please contact <a href=\"mailto:$param_contact\">$param_contact</a>.<br/>
If $full_path_to_clean is deleted, please ignore this email.

<br/><br/>
Regards,<br/>
$displayFrom

					";
					close $handleHtmlFile ;
					sendMailOnCleanIssue($subject,$htmlFile);
				}  else  {
					die "ERROR : cannot create '$handleHtmlFile' : $!"
				}
			}
		}
	}

	printf "\nFiles cleans took %u h %02u mn %02u s at %s\n",
			(Delta_DHMS(@StartClean1, Today_and_Now()))[1..3]
			, scalar localtime
			;

	sleep 5;
	my @StartClean2 = Today_and_Now();
	if( -e "$full_path_to_clean") {
		system "rm -f \"full_path_to_clean\" >& /dev/null || true";
	}
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
	print "MESSAGE : $full_path_to_clean not found or not a directory\n";
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

sub sap_create_fork($$) {
	my ($this_cmd,$this_log) = @_;
	my $pid;
	unless ($this_log) {
		$this_log = "/dev/null"
	}
	if( ! defined($pid=fork()) ) {
		die "ERROR: cannot fork '$this_cmd' : $!";
	}  elsif($pid)  {
		return $pid;
	}  else  {
		exec "$this_cmd > $this_log 2>&1";
		exit 0;
	}
}

sub sap_check_empty_folder($) {
	my ($this_folder) = @_ ;
	my $cleaned = "true";
	if(opendir BASE , "$this_folder") {
		while(defined(my $this_elem = readdir(BASE))) {
			next if ( ($this_elem =~ /^\.$/) || ($this_elem =~ /^\.\.$/) );
			if( -e "$this_folder/$this_elem") {
				$cleaned = "false";
				last;
			}
		}
		closedir BASE;
	}  else  {
		warn "WARNINg : cannot opendir '$this_folder' : $!";
	}
	return $cleaned;
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
	print "END of '$0' at $dateEnd\n\n\n";
	exit 0;
}

sub sendMailOnCleanIssue($$) {
	my ($this_subject,$this_htmlFile) = @_ ;
	my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>90, Debug=>1,);
	my $htmlFile;
	$smtp->hello($smtp->domain);
	$smtp->mail($param_mailFrom);
	$smtp->to(split  '\s*;\s*' , $param_mailTo);
	$smtp->data();
	$smtp->datasend("To: $param_mailTo\n");
	$smtp->datasend("Subject: $this_subject\n");
	$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.html\n");
	open HTML, "$this_htmlFile"  or die "ERROR: cannot read '$this_htmlFile' : $!";
		while(<HTML>) { $smtp->datasend($_) }
	close HTML;
	$smtp->dataend();
	$smtp->quit();
	unlink $this_htmlFile;
}

sub sendMailOnScriptIssue($@) {
	my ($issueType,@Messages) = @_;

	return if($NumberOfEmails);
	$NumberOfEmails++;

	open HTML, ">$TEMP_DIR/Mail$$.htm" or die "ERROR: cannot open '$TEMP_DIR/Mail$$.htm' : $!";
	print HTML "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n";
	print HTML "<html>\n";
	print HTML "\t<head>\n";
	print HTML "\t</head>\n";
	print HTML "\t<body>\n";
	print HTML "*****This email has been sent from an unmonitored automatic mailbox.*****<br/><br/>\n";
	print HTML "Hi everyone,<br/><br/>\n";
	print HTML "&nbsp;"x5, "We have the following error(s) while running '$CommandLine' on $hostName :<br/>\n";
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

	my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>60) or warn "WARNING: SMTP connection impossible : $!";
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
