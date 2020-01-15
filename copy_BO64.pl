use strict;

use Getopt::Long;
use Sys::Hostname;

use File::Find;
use File::Path;
use File::Copy;
use File::Basename;

use FindBin;
use lib $FindBin::Bin;

use Net::SMTP;
use SOAP::Lite;

sub Usage($);
sub NSDTransfert($$);
sub ExportBO64Pkg($$);
sub ASTECRegistration($$);
sub Export_BO_Client();
sub Export_Other_Packages($);
sub SendMail();

use vars qw (
	$CURRENTDIR
	$HOST
	$PLATFORM
	$OBJECT_MODEL
	$ASTEC
	$PROJECT
	$CONTEXT
	$INI_FILE
	$BUILD_NUMBER
	$BUILD_MODE
	$OUTPUT_DIR
	$DROP_DIR
	$DROP_DIR_B
	$DROP_NSD_DIR
	$Help
	%PLATFORMS64
	$DeleteCmd
	$MOVECmd
	$CopyCmd
	$DateCmd
	$NULLDEVICE
	$MAIL
	$DLMail
	$BOClient
	$PackagesToExport
	$Temp
	$IsRobocopy
);

$CURRENTDIR = $FindBin::Bin;
$HOST = hostname();
$Temp = $ENV{TEMP};

$Getopt::Long::ignorecase = 0;
GetOptions(
	"M"			=>\$MAIL,
	"Z"			=>\$ASTEC,
	"prj=s"		=>\$PROJECT,
	"c=s"		=>\$CONTEXT,
	"i=s"		=>\$INI_FILE,
	"v=s"		=>\$BUILD_NUMBER,
	"m=s"		=>\$BUILD_MODE,
	"o=s"		=>\$OUTPUT_DIR,
	"d=s"		=>\$DROP_DIR,
	"dl=s"		=>\$DLMail,
	"help|h|?"	=>\$Help,
	"BOC"		=>\$BOClient,
	"pkgs=s"	=>\$PackagesToExport,
);

Usage("") if($Help);

$PROJECT		||= $ENV{'PROJECT'};
$CONTEXT		||= $ENV{'CONTEXT'} || $ENV{'context'};
($INI_FILE)		||= "$CURRENTDIR/contexts/$CONTEXT.ini";
$BUILD_NUMBER	||= $ENV{'BUILD_NUMBER'} || $ENV{'build_number'};
$BUILD_MODE		||= $ENV{'BUILD_MODE'};
$OBJECT_MODEL	= $ENV{'OBJECT_MODEL'};
$OUTPUT_DIR		||= $ENV{'OUTPUT_DIR'};
$DROP_DIR		||= $ENV{'DROP_DIR'};
$DROP_DIR_B		= $ENV{'DROP_DIR_B'};
$DROP_NSD_DIR	||= $ENV{'DROP_NSD_DIR'};
$NULLDEVICE		  = $^O eq "MSWin32" ? "nul" : "/dev/null";
my $ASTECsuite ||=$PROJECT;
my $LoginName = getlogin() || getpwuid($<) || "builder";				  # default is builder
$LoginName = lc($LoginName);

$IsRobocopy = ($^O eq "MSWin32") ? (`which robocopy.exe 2>&1`=~/robocopy.exe$/i  ? 1 : 0) : 0;

if( ($OBJECT_MODEL eq "32") || (($^O eq "hpux") && (($OBJECT_MODEL eq "64"))) ) { #for 32 excepted hp itanium

	#0 display build infos
	print "

	START of $0

	Builds INFOS :
PROJECT			= $PROJECT
CONTEXT			= $CONTEXT
INI_FILE		= $INI_FILE
BUILD_NUMBER	= $BUILD_NUMBER
BUILD_MODE		= $BUILD_MODE
OBJECT_MODEL	= $OBJECT_MODEL
OUTPUT_DIR		= $OUTPUT_DIR
DROP_DIR		= $DROP_DIR

";

	#2 determine platforms source and platforms dest
	$_ = $^O ;
	SWITCH:
	{
	  /MSWin32/ and $PLATFORM = "win32_x86"		and $PLATFORMS64{$PLATFORM} = "win64_x64" ;
	  /linux/   and $PLATFORM = "linux_x86"		and $PLATFORMS64{$PLATFORM} = "linux_x64" ;
	  /solaris/ and $PLATFORM = "solaris_sparc"	and $PLATFORMS64{$PLATFORM}	= "solaris_sparcv9" ;
	  /aix/   	and $PLATFORM = "aix_rs6000"	and $PLATFORMS64{$PLATFORM}	= "aix_rs6000_64" ;
	  /hpux/   	and $PLATFORM = "hpux_ia64"		and $PLATFORMS64{$PLATFORM}	= "hpux_ia64" ;
	}

	#3 determine commands to launch
	if($^O =~ /MSWin32/) {
		$DeleteCmd	= "rmdir /S /Q";
		$MOVECmd	= "move /Y";
		if($IsRobocopy) {
			$CopyCmd = "robocopy /MIR /NP /NFL /NDL /R:3";
		} else {
			$CopyCmd	= "xcopy /ECIQHRYD";
		}
		$DateCmd	= "date \/t \& time \/t";
	} else {
		$DeleteCmd	= "rm -rf";
		$MOVECmd	= "mv";
		$CopyCmd	= "cp -dRuf --preserve=mode,timestamps";
		$DateCmd	= "date";
	}

	print "START\n";
	if($^O =~ /MSWin32/) {
		system("cmd /c \"$DateCmd\"");
	} else {
		system($DateCmd);
	}

	if($PackagesToExport) {
		my @OtherPackages = split(',',$PackagesToExport);
		if(($^O eq "hpux") && (($OBJECT_MODEL eq "64"))) {
			exit;
		}
		foreach my $pkg (@OtherPackages) {
			Export_Other_Packages($pkg);
		}
		NSDTransfert("packages",$PLATFORMS64{$PLATFORM});
		exit;
	}


	print "\n";
	#4 move BO64 pkg from packages folder to package64 folder
	my $srcDir64		= "$OUTPUT_DIR/packages/BusinessObjects64";
	my $tmpLocalDir64	= "$OUTPUT_DIR/packages64";

	if($^O =~ /MSWin32/) {
		#transfor to windows path
		($srcDir64) =~ s-\/-\\-g;
		($tmpLocalDir64) =~ s-\/-\\-g;
	}
	#delete if already existed
	if( -e $tmpLocalDir64 ) {
		if( -e $srcDir64 ) {
			system("chmod -R 777 \"$tmpLocalDir64\"");
			print ("$DeleteCmd $tmpLocalDir64\n");
			if($^O =~ /MSWin32/) {
				system("cmd /c \"$DeleteCmd \"$tmpLocalDir64\"\"");
			} else {
				system("$DeleteCmd \"$tmpLocalDir64\"");
			}
			print "\n";
		} else {
			print "'$srcDir64' not found or already exported\n";
			exit;
		}
	}
	if( -e $srcDir64 ) {
		#create intermediate folder
		print "mkdir -p \"$tmpLocalDir64\"\n";
		system("mkdir -p \"$tmpLocalDir64\"");
		print "\n";
		#move BO64 into intermediate folder
		print "$MOVECmd \"$srcDir64\" \"$tmpLocalDir64\"\n";
		system("$MOVECmd \"$srcDir64\" \"$tmpLocalDir64\"");
		print "\n";
		#rename BO64 to BusinessObjectsServer
		print "$MOVECmd \"$tmpLocalDir64/BusinessObjects64\" \"$tmpLocalDir64/BusinessObjectsServer\"\n";
		system("$MOVECmd \"$tmpLocalDir64/BusinessObjects64\" \"$tmpLocalDir64/BusinessObjectsServer\"");
		system("chmod -R 777 \"$tmpLocalDir64\"") if($^O =~ /MSWin32/);
		print "\n";
	} else {
		print "'$srcDir64' not found\n";
		exit;
	}

	#move BO32 into intermediate folder to not export it
	my $srcDir32		= "$OUTPUT_DIR/packages/BusinessObjectsTest";
	if( -e $srcDir32 ) {
		my $tmpLocalDir32	= "$OUTPUT_DIR/packages32";
		if($^O =~ /MSWin32/) {
			#transfor to windows path
			($srcDir32) =~ s-\/-\\-g;
			($tmpLocalDir32) =~ s-\/-\\-g;
		}
		if( -e "$tmpLocalDir32") {
			#delete if already existed
			print "$DeleteCmd \"$tmpLocalDir32\"\n";
			system("chmod -R 777 \"$tmpLocalDir32\"");
			system("$DeleteCmd \"$tmpLocalDir32\"");
			print "\n";
		}
		#create intermediate folder
		print "mkdir -p \"$tmpLocalDir32\"\n";
		system("mkdir -p \"$tmpLocalDir32\"");
		print "\n";
		print "$MOVECmd \"$srcDir32\" \"$tmpLocalDir32\"\n";
		system("$MOVECmd \"$srcDir32\" \"$tmpLocalDir32\"");
		system("chmod -R 777 \"$tmpLocalDir32\"") if($^O =~ /MSWin32/);
		print "\n";
	}
	print "\nINTERNAL move done\n";
	if($^O =~ /MSWin32/) {
		system("cmd /c \"$DateCmd\"");
	} else {
		system($DateCmd);
	}
	print "\n";

	#5 Export to official dropzone
	if($ENV{ASTEC_BUILD_MACHINE}) {
		my $BuildMachinePath;
		if($^O eq "MSWin32") {
			$BuildMachinePath = "//$HOST/$CONTEXT/$PLATFORM/release/packages64/BusinessObjectsServer";
		} else {
			$BuildMachinePath = "/net/$HOST/build/$LoginName/$CONTEXT/$PLATFORM/release/packages64/BusinessObjectsServer";
		}
		ASTECRegistration($BuildMachinePath,"$HOST.txt");
	}
	ExportBO64Pkg($tmpLocalDir64,$DROP_DIR);
	print "\nExport to dropzone done\n";

	my $PathList = "$DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/packages/BusinessObjectsServer";
	ASTECRegistration($PathList,"buildInfo.txt");

	NSDTransfert("packages",$PLATFORMS64{$PLATFORM});

	if($^O =~ /MSWin32/) {
		system("cmd /c \"$DateCmd\"");
	} else {
		system($DateCmd);
	}

	Export_BO_Client() if(($ENV{PLATFORM} eq "win32_x86") && ($BOClient));

	print "\n";
	SendMail() if(($MAIL) && ($DLMail));

	print "

END of $0

";

} else {
	print "\nnothing to be done on $ENV{'OBJECT_MODEL'} platforms\n";
};

exit;

########################################################################################################

sub ExportBO64Pkg($$) {
	my ($tmpLocalDir64,$destination) = @_ ;

	my $targetDir64	= "$destination/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/packages";
	if($^O =~ /MSWin32/) {
		$targetDir64 .= "/BusinessObjectsServer";
		#transform to windows path
		($targetDir64) =~ s-\/-\\-g;
	}

	if( -e "$tmpLocalDir64/BusinessObjectsServer") {
		if( ! -e $targetDir64 ) {
			print "mkdir -p \"$targetDir64\"\n";
			system("mkdir -p \"$targetDir64\" > $NULLDEVICE 2>&1");
			print "\n";
		}
		my $tmpDir64 = "$tmpLocalDir64/BusinessObjectsServer";
		($tmpDir64) =~ s-\/-\\-g if($^O =~ /MSWin32/);

		print "\n$CopyCmd \"$tmpDir64\" \"$targetDir64\"\n";
		if( -e "$destination/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/copy_BO64.inpg") {
			print "\nWARNING: a copy_BO64 is on going., stopping $0\n";
			print "see $destination/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/copy_BO64.inpg\n";
			exit;
		}
		system("touch $destination/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/copy_BO64.inpg");
		system("$CopyCmd \"$tmpDir64\" \"$targetDir64\"");
		if( -e "$destination/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/copy_BO64.inpg") {
			system("rm -f $destination/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/copy_BO64.inpg")
		}
		system("touch $destination/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/packages/packages_copy_done");
		print "\n";
	}
}

sub ASTECRegistration($$) {
	my ($destination,$triggerFile) = @_ ;
	($^O eq "MSWin32") ? $destination =~ s/\//\\/g : $destination =~ s/\\/\//g;
	if($ASTEC) {
		my $ASTECPath;
		if(defined($ENV{ASTEC_DIR})) {
			$ASTECPath = $ENV{ASTEC_DIR};
		} else {
			$ASTECPath = "$DROP_DIR/../ASTEC";
		}
		$ASTECPath .="/$PROJECT/$CONTEXT/$PLATFORMS64{$PLATFORM}";
		mkpath($ASTECPath) or warn("WARNING: cannot mkpath '$ASTECPath': $!") unless(-e $ASTECPath);
		my $Setup = ($^O eq "MSWin32") ? "$destination\\setup.exe" : "$destination/setup.sh";
        if(-e $Setup) {
            if(open(ASTEC,">$ASTECPath/$triggerFile")) {
                print(ASTEC "ARCHITECTURE=64\n");
                print(ASTEC "BUILD_INI_FILE=", basename($INI_FILE), "\n");
                print(ASTEC "BUILD_VERSION=$BUILD_NUMBER\n");
                print(ASTEC "BUILD_MODE=$BUILD_MODE\n");
                print(ASTEC "suite=$ASTECsuite\n");
                print(ASTEC "SETUP_PATH=$destination\n");
                close(ASTEC);
                print "\nASTEC Registration of BusinessObjectsServer done in $triggerFile\n";

				#for BAT team who don't wan incremental build
                unless($BUILD_NUMBER =~ /\.\d+$/) { #not an incremental build
                	open(ASTEC2,">$ASTECPath/nightly.txt");
		                print(ASTEC2 "ARCHITECTURE=64\n");
		                print(ASTEC2 "BUILD_INI_FILE=", basename($INI_FILE), "\n");
		                print(ASTEC2 "BUILD_VERSION=$BUILD_NUMBER\n");
		                print(ASTEC2 "BUILD_MODE=$BUILD_MODE\n");
		                print(ASTEC2 "suite=$ASTECsuite\n");
		                print(ASTEC2 "SETUP_PATH=$destination\n");
                	close(ASTEC2);
                	print "\nASTEC Registration of BusinessObjectsServer done in '$ASTECPath/nightly.txt' (needed by BAT Team)\n";
                }
            } else {
            	warn("WARNING: cannot create '$ASTECPath/$triggerFile'");
            }
        } else {
        	print "ERROR: '$Setup' not found, please check the logs\n";
        }
	}
}

sub NSDTransfert($$)  {
	my ($Folder,$NSDPlatform) = @_;
	return unless(-e "$DROP_DIR/$CONTEXT/$BUILD_NUMBER/$NSDPlatform/$BUILD_MODE/$Folder");
	(my $FolderPath = "$CONTEXT/$BUILD_NUMBER/$NSDPlatform/$BUILD_MODE/$Folder") =~ s/\\/\//g;
	while($FolderPath =~ s/[^\/.]+[\/]\.\.[\/]//g) { }
	(my $FolderName = $FolderPath) =~ s/[\\\/]/-/g;    
	my $NSD_DIR = $ENV{NSD_DIR};
	(my $drop_dir = $DROP_NSD_DIR) =~ s/\\/\//g;
	$ENV{GLOBAL_REPLICATION_SERVER} ||= "http://dewdfgrsig01.wdf.sap.corp";
	print SOAP::Lite->uri("$ENV{GLOBAL_REPLICATION_SERVER}/gr_trig")->proxy("$ENV{GLOBAL_REPLICATION_SERVER}:1080/cgi-bin/trigger-gr")->dailyBuild('john,doe', "$drop_dir/$FolderPath,$PROJECT/$FolderPath,")->result();
}

sub Export_BO_Client() {
	print "\nExport BO Client\n";
	my $srcDir = "$OUTPUT_DIR/packages/BusinessObjectsClient";
	if( ! -e $srcDir ) {
		print "'$srcDir' does not exist\n";
	} else {
		my $tmpLocalDir	= "$OUTPUT_DIR/packages_bo_client";
		if( -e "$tmpLocalDir" ) {
			system("chmod -R 777 \"$tmpLocalDir\"");
			system("$DeleteCmd \"$tmpLocalDir\"");
		}
		system("mkdir -p \"$tmpLocalDir\"");
		system("$MOVECmd \"$srcDir\" \"$tmpLocalDir\"");
		my $targetDir	= "$DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORM/$BUILD_MODE/packages/BusinessObjectsClient";
		($targetDir) =~ s-\/-\\-g;
		if( ! -e $targetDir ) {
			system("mkdir -p \"$targetDir\" > $NULLDEVICE 2>&1");
		}
		$tmpLocalDir .= "/BusinessObjectsClient";
		($tmpLocalDir) =~ s-\/-\\-g;
	
		print "\n$CopyCmd \"$tmpLocalDir\" \"$targetDir\"\n";
		if( -e "$DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORM/$BUILD_MODE/copy_BO_Client.inpg") {
			print "\nWARNING: a copy_BO_Client is on going., stopping $0\n";
			print "see $DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORM/$BUILD_MODE/copy_BO_Client.inpg\n";
			exit;
		}
		system("touch $DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORM/$BUILD_MODE/copy_BO_Client.inpg");
		system("$CopyCmd \"$tmpLocalDir\" \"$targetDir\"");
		if( -e "$DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORM/$BUILD_MODE/copy_BO_Client.inpg") {
			system("rm -f $DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORM/$BUILD_MODE/copy_BO_Client.inpg")
		}
		print "\n";
	
		if($ASTEC) {
			my $PathList = "$DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORM/$BUILD_MODE/packages/BusinessObjectsClient";
			($^O eq "MSWin32") ? $PathList =~ s/\//\\/g : $PathList =~ s/\\/\//g;
			my $Setup = ($^O eq "MSWin32") ? "$PathList\\setup.exe" : "$PathList/setup.sh";
			my $ASTECPath;
			if(defined($ENV{ASTEC_DIR})) {
				$ASTECPath = $ENV{ASTEC_DIR};
			} else {
				$ASTECPath = "$DROP_DIR/../ASTEC";
			}
			$ASTECPath .="/$PROJECT/$CONTEXT/$PLATFORM";
	        if(-e $Setup) {
	            mkpath($ASTECPath) or warn("WARNING: cannot mkpath '$ASTECPath': $!") unless(-e $ASTECPath);
	            if(open(ASTEC,">$ASTECPath/buildInfo.txt")) {
	                print(ASTEC "ARCHITECTURE=32\n");
	                print(ASTEC "BUILD_INI_FILE=", basename($INI_FILE), "\n");
	                print(ASTEC "BUILD_VERSION=$BUILD_NUMBER\n");
	                print(ASTEC "BUILD_MODE=$BUILD_MODE\n");
	                print(ASTEC "suite=$ASTECsuite\n");
	                print(ASTEC "SETUP_PATH=$PathList\n");
	                close(ASTEC);
	                print "\nASTEC Registration of BusinessObjectsClient done\n";
	            } else {
	            	warn("WARNING: cannot create '$ASTECPath/buildInfo.txt'");
	            }

				#for BAT team who don't wan incremental build
                unless($BUILD_NUMBER =~ /\.\d+$/) { #not an incremental build
                	open(ASTEC2,">$ASTECPath/nightly.txt");
		                print(ASTEC2 "ARCHITECTURE=32\n");
		                print(ASTEC2 "BUILD_INI_FILE=", basename($INI_FILE), "\n");
		                print(ASTEC2 "BUILD_VERSION=$BUILD_NUMBER\n");
		                print(ASTEC2 "BUILD_MODE=$BUILD_MODE\n");
		                print(ASTEC2 "suite=$ASTECsuite\n");
		                print(ASTEC2 "SETUP_PATH=$PathList\n");
                	close(ASTEC2);
                	print "\nASTEC Registration of BusinessObjectsClient done in '$ASTECPath/nightly.txt' (needed by BAT Team)\n";
                }

	        } else {
	        	print("setup: '$Setup' does not exist\n");
	        }
		} #end astec registration
		NSDTransfert("packages",$PLATFORM);
	}
}

sub Export_Other_Packages($) {
	my ($Package) = @_;

use File::Spec::Functions;

	print "\nExport '$Package'\n";
	my $srcDir = "$OUTPUT_DIR/packages/$Package";
	if( ! -e $srcDir ) {
		print "'$srcDir' does not exist\n";
	} else {
		my $tmpLocalDir = catdir($OUTPUT_DIR,"packages_$Package");

		if( -e "$tmpLocalDir" ) {
			system("chmod -R 777 \"$tmpLocalDir\"");
			system("$DeleteCmd \"$tmpLocalDir\"");
		}
		system("mkdir -p \"$tmpLocalDir\"");
		system("$MOVECmd \"$srcDir\" \"$tmpLocalDir\"");
		$tmpLocalDir .="/$Package";
		my $targetDir = catdir($DROP_DIR,$CONTEXT,$BUILD_NUMBER,$PLATFORMS64{$PLATFORM},$BUILD_MODE,"packages");
		if($^O =~ /MSWin32/) {
			$targetDir .= "/$Package";
			($targetDir) =~ s-\/-\\-g ;
		}
		if( ! -e $targetDir ) {
			system("mkdir -p \"$targetDir\" > $NULLDEVICE 2>&1");
		}
		($tmpLocalDir) =~ s-\/-\\-g if($^O =~ /MSWin32/);

		print "\n$CopyCmd \"$tmpLocalDir\" \"$targetDir\"\n";
		if( -e "$DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/copy_$Package.inpg") {
			print "\nWARNING: a copy_$Package is on going., stopping $0\n";
			print "see $DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORM/$BUILD_MODE/copy_$Package.inpg\n";
			exit;
		}
		system("touch $DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/copy_$Package.inpg");
		system("$CopyCmd \"$tmpLocalDir\" \"$targetDir\"");
		if( -e "$DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/copy_$Package.inpg") {
			system("rm -f $DROP_DIR/$CONTEXT/$BUILD_NUMBER/$PLATFORMS64{$PLATFORM}/$BUILD_MODE/copy_$Package.inpg")
		}
		print "\n";
	}

}

sub SendMail() {
	my $mailPlatform = $PLATFORMS64{$PLATFORM};
	my $PathList = "$DROP_DIR/$CONTEXT/$BUILD_NUMBER/$mailPlatform/$BUILD_MODE/packages/BusinessObjectsServer";
	($^O eq "MSWin32") ? $PathList =~ s/\//\\/g : $PathList =~ s/\\/\//g;
	my $Setup = ($^O eq "MSWin32") ? "$PathList\\setup.exe" : "$PathList/setup.sh";
	if( -e $Setup ) {

		my $linkMail = "";
		if( $^O eq "MSWin32" ) {
			$linkMail = "<a href=\"$PathList\">$PathList</a>";
		} else {
			$linkMail = $PathList;
		}
		if( ! -e $Temp ) {
			system("mkdir -p $Temp");
		}
		my $htmlFile = "$Temp/mail_copy_BO64";
		$htmlFile .= "_${BUILD_NUMBER}_$BUILD_MODE.htm";
		my %Mails;
		my $Site = $ENV{SITE};
		$_ = $Site;
		SWITCH:
		{
			/Levallois/		and %Mails = ( 'Levallois' , ['DL TG_TD Prod BOBJ Build Ops (FR)','DL_011000358700001506162009E@exchange.sap.corp']);
			/Vancouver/		and %Mails = ( 'Vancouver' , ['DL TG_TD Prod BOBJ Build Ops (CAN)','DL_011000358700001507052009E@exchange.sap.corp']);
			/Bangalore/		and %Mails = ( 'Bangalore' , ['DL TG_TD Prod BOBJ Build Ops (India)',' DL_011000358700001507042009E@exchange.sap.corp']);
		}
		my $Contact		= $Mails{$Site}[0];
		my $mailContact	= $Mails{$Site}[1];
		if(open(HTML,">$htmlFile")) {
		print HTML '
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<html>
 <head>
  <meta http-equiv=Content-Type content="text/html; charset=iso-8859-1">
  <title>Mail ',"$CONTEXT $BUILD_NUMBER $mailPlatform $BUILD_MODE",'</title>
 </head>
 <body>
<br/>
Hi Team,<br/>
This email is just to inform you that BusinessObjectsServer is now available on ',"$linkMail",'<br/>
Contact <a href="mailto:',"$Contact",'">',"$Contact",'</a> for any further information.<br/>
<br/>
Thanks,<br/>
Build OPS LVL.<br/>
<br/>
THIS EMAIL IS SEND AUTOMATICALLY, PLEASE DO NOT REPLY<br/>
<br/>
  </body>
</html>
';

			close(HTML);
			my $SMTP_SERVER = $ENV{SMTP_SERVER} || "mail.sap.corp";
			my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>90);
			#$DLMail ||='DL_3587000015093708E@exchange.sap.corp;DL_011000358700001506162009E@exchange.sap.corp;jean-gerard.boidot@sap.com;dominique.avril@sap.com'	;
			#$DLMail ||='julian.oprea@sap.com;xiaohong.ding@sap.com;jean-gerard.boidot@sap.com;dominique.avril@sap.com'	;
			$smtp->mail('PGEDCReleaseManagementTools@businessobjects.com');
			$smtp->to(split('\s*;\s*', $DLMail));
			$smtp->data();
			$smtp->datasend("To: $DLMail\n");
			$smtp->datasend("Subject: [$CONTEXT] build rev. $BUILD_NUMBER - $mailPlatform $BUILD_MODE: package available\n");
			$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
			open(HTML, "$htmlFile") or die ("ERROR: cannot open '$htmlFile': $!");
			while(<HTML>) { $smtp->datasend($_) } 
			close(HTML);
			$smtp->dataend();
			$smtp->quit();
			print "\nSend Mail done\n";
		}
	} else {
		print "\n'$Setup' not found\n";
	}
}

sub Usage($) {
	my ($msg) = @_ ;
	if($msg)
	{
		print "\n";
		print "\tERROR:\n";
		print "\t======\n";
		print "$msg\n";
		print "\n";
	}
	print "

	Description :
$0 move on local 32 build machine
	from
\$OUTPUT_DIR/packages/BusinessObjects64
	to
\$OUTPUT_DIR/packages64/BusinessObjectsTest
	and export it in
\$DROP_DIR/\$CONTEXT/\$BUILD_NUMBER/\$PLATFORM64/\$BUILD_MODE/packages/BusinessObjectsTest

	Usage	: perl $0 [options]
	Example	: perl $0 -h

[options]
	-Z		ASTEC registration
	-p		choose PROJECT,		by default, use environment variable PROJECT setted by Build.pl
	-c		choose CONTEXT,		by default, use environment variable CONTEXT setted by Build.pl
	-i		choose INI_FILE,	by default, use ini file of the context selected by -c
	-v		choose BUILD_NUMBER,	by default, use environment variable BUILD_NUMBER setted by Build.pl
	-m		choose BUILD_MODE,	by default, use environment variable BUILD_MODE setted by Build.pl
	-o		choose OUTPUT_DIR,	by default, use environment variable OUTPUT_DIR setted by Build.pl
	-d		choose DROP_DIR,	by default, use environment variable DROP_DIR setted by Build.pl
	-help|h|?	display this help

";
	exit;
}
