#!/usr/bin/perl

# uses
use HTML::TreeBuilder;
use HTML::Entities;
use LWP::UserAgent;
use Sys::Hostname;
use Getopt::Long;
use FindBin;
use lib ($FindBin::Bin);
use File::stat;
use Time::localtime;

# general vars
our $exitCode = 0;
use vars qw (
  $CURRENTDIR
  $TEMP_DIR
  $Help
  @optTestCaseNames
  $InstallDir
  $User
  $Password
  $TomcatPort
  $CMCPort
  $buildName
  $buildRev
  $Version
  $Model
  $HOST
  $localHOST;
  $TypeSetup
  $OBJECT_MODEL
  $PLATFORM
  $localUser
  $InstallDir2
  $ProductIdTtxtFile
  $flagServer_boe_cmsd
  $flag_SIA
  $flag_TOMCAT
  $SetupPath
  $PROJECT
  $responseIniFile
  $VERBOSE
);

# subs
sub testCases($$);
sub CheckPlatForm($);
sub testProductId($);
sub testCMC($);
sub testInfoView($);
sub determineProductId();
sub GetInstallDir();
sub checkSetupAvailable();

die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
$TEMP_DIR =~ s/[\\\/]\d+$//;
$CURRENTDIR = $FindBin::Bin;

##############
# Parameters #
##############
GetOptions(
  "help|?"    =>\$Help,
  "case=s@"   =>\@optTestCaseNames,
  "install=s"   =>\$InstallDir,
  "user=s"    =>\$User,
  "password=s"  =>\$Password,
  "port=i"    =>\$TomcatPort,
  "cmcport|cmsport=i"   =>\$CMCPort,
  "buildname=s" =>\$buildName,
  "revision=s"  =>\$buildRev,
  "version=s"   =>\$Version,
  "64!"     =>\$Model,
  "machine=s"   =>\$HOST,
  "typesetup=s" =>\$TypeSetup,
  "verbose" =>\$VERBOSE,
  );
Usage() if($Help);

$buildName ||=$ENV{'context'};

### define PLATFORM
$ENV{OBJECT_MODEL} = $OBJECT_MODEL = $Model ? "64" : ($ENV{OBJECT_MODEL} || "32"); 
$_ = $^O ;
SWITCH:
{
  /MSWin32/ and $PLATFORM = ($OBJECT_MODEL==64) ? "win64_x64"     : "win32_x86"   ;
  /linux/   and $PLATFORM = ($OBJECT_MODEL==64) ? "linux_x64"     : "linux_x86"   ;
  /solaris/ and $PLATFORM = ($OBJECT_MODEL==64) ? "solaris_sparcv9" : "solaris_sparc" ;
  /aix/   	and $PLATFORM = ($OBJECT_MODEL==64) ? "aix_rs6000_64"   : "aix_rs6000"    ;
  /hpux/    and $PLATFORM = ($OBJECT_MODEL==64) ? "hpux_ia64"     : "hpux_pa-risc"  ;
}

### init variables
$HOST ||= $ENV{SMT_MACHINE} || $ENV{SMTMACHINE} || hostname();
$HOST_IP ||= $ENV{SMTMACHINE_IP} || $HOST;
$localHOST = hostname();
$User ||= "administrator";
$SetupPath = GetSetupPath();
$PROJECT = $ENV{PROJECT} || "Aurora";

unless(defined($Password)) {
	if( $^O =~ /MSWin32/ ) {
		$responseIniFile = $ENV{RESPONSEINIFILE} || $ENV{RESPONSE_INI_FILE} || ( -e "c:/ASTEC/response.ini") ? "c:/ASTEC/response.ini" : GetResponseIni() ;
	} else {
		$responseIniFile = $ENV{RESPONSEINIFILE} || $ENV{RESPONSE_INI_FILE} || ( -e "$ENV{HOME}/ASTEC/$PROJECT/response.ini") ? "$ENV{HOME}/ASTEC/$PROJECT/response.ini" : GetResponseIni() ;	
	}
	if( -e $responseIniFile ) {
		if(open(INI,$responseIniFile)) {
			while(<INI>) {
				chomp;
				if(/^CMSPassword\=(.+?)$/) {
					$Password = $1;
				}
			}
			close(INI);
		} else {
			$Password = "Password1";
		}

	} else {
		$Password = "Password1";
	}
}

# init ports
$flagServer_boe_cmsd = 0;
$flag_SIA = 0;
$flag_TOMCAT = 0;
$tomcatProcess = "tomcat6";
if($^O eq "MSWin32") {
    	$InstallDir ||= $ENV{INSTALLDIR} || $ENV{INSTALL_DIR} || GetInstallDir() || "C:\\Program Files (x86)\\SAP BusinessObjects";
        $TomcatPort	||= $ENV{TOMCATPORT} || $ENV{TOMCAT_PORT} || 8080;
        $CMCPort	||= $ENV{CMSPORT} || $ENV{CMS_PORT} || $ENV{CMCPORT} || $ENV{CMC_PORT} || 6400;
        $localUser    = $ENV{USERNAME};
        open(BOE_PROCESS,"tasklist |");
        while(<BOE_PROCESS>) {
          chomp;
          $flagServer_boe_cmsd = 1  if(/^CMS\.exe/);
          $flag_SIA = 1       if(/^sia\.exe/);
          if(/^tomcat(.+?).exe/) {
            $flag_TOMCAT = 1;
            ($tomcatProcess) = $_ =~ /^(.+?)\.exe\s+/i;
          }
        }
        close(BOE_PROCESS);
} else {
        $localUser = $ENV{INST_ACCNT};
        unless($localUser) { $localUser = getpwuid($<); } 
        unless($localUser) {
                my $tmp=`id`;
                chomp($tmp);
                ($localUser) = $tmp =~ /\((.+?)\)/ ;
        }
        my $InstallUser = $ENV{INSTALLUSER} || $ENV{INSTALL_USER} || $localUser;
        open(BOECMSD,"ps -edf | grep -w $InstallUser | grep -i boe_cmsd | awk \{\'print \$8\'\} | grep -wv grep |");
      while(<BOECMSD>) {
        chomp;
        if(/^(.+)\/+sap_bobj\/+enterprise_xi40\/+$PLATFORM\/+boe_cmsd/) {
          $InstallDir ||= $1;
          $flagServer_boe_cmsd = 1;
          last;
        }
      }
        close(BOECMSD);
        $InstallDir ||= $ENV{INSTALLDIR} || $ENV{INSTALL_DIR} || GetInstallDir() || "$ENV{'HOME'}/RM_Install_dir";
    unless($CMCPort) {
    	my $ccmConfigFile;
    	if( -e "$InstallDir/sap_bobj/ccm.config") {
    		$ccmConfigFile = "$InstallDir/sap_bobj/ccm.config";
    	}
    	 if( -e "$InstallDir/sap_bobj/ccm.config") {
    		$ccmConfigFile = "$InstallDir/sap_bobj/ccm.config";
    	}
    	if( ! -e $ccmConfigFile) {
    		print "WARNING : '$ccmConfigFile' not found!\n";
    	}
    	else {
			my $rep1=`grep -w CMSPORTNUMBER $ccmConfigFile`;
			chomp($rep1);
			($CMCPort) = $rep1 =~ /\=\"(.+?)\"$/;
			$CMCPort = $ENV{CMSPORT} || $CMCPort;
			$ENV{CMSPORT} = $CMCPort;
			unless($TomcatPort) {
				my $rep1=`grep -w CONNECTORPORT $ccmConfigFile`;
				chomp($rep1);
				($TomcatPort) = $rep1 =~ /\=\"(.+?)\"$/;
			}
		}
	}
	$CMCPort ||= $ENV{CMSPORT} || $ENV{CMS_PORT} || $ENV{CMCPORT} || $ENV{CMC_PORT};
    $TomcatPort ||= $ENV{TOMCATPORT} || $ENV{TOMCAT_PORT} || ($CMCPort + 2);
}

$ENV{'INSTALLDIR'} = $InstallDir;
$InstallDir2 = "";
$ProductIdTtxtFile    = determineProductId();
$TypeSetup      ||= CalculateTypeSetup();


########
# Main #
########

### display infos:
$buildRev ||=$ENV{'build_number'};
my $realBuildRev = $buildRev;
my $flagIncremental;
if($buildRev =~ /\.\d+$/) {
  ($buildRev) =~ s/\.\d+$//;
  $flagIncremental = 1;
}
print "
\tINFOS:
\t======
machine : $HOST
LOCAL User : $localUser
BUILD : $buildName
REVISION : $buildRev\n";
if($flagIncremental==1) {
  print "INCREMENTAL : YES : $realBuildRev\n";
}
print "INSTALLDIR : $InstallDir
CMSPORT : $CMCPort
TOMCATPORT : $TomcatPort
CMS User : $User\n";
if($Password) {
  print"CMS Password : $Password\n";
} else {
  print"CMS Password : no password\n";
}
if($^O ne "MSWin32") {
	my $ccmConfigFile;
	if( -e "$InstallDir/sap_bobj/ccm.config") {
		$ccmConfigFile = "$InstallDir/sap_bobj/ccm.config";
	}
	 if( -e "$InstallDir/sap_bobj/ccm.config") {
		$ccmConfigFile = "$InstallDir/sap_bobj/ccm.config";
	}
	if( ! -e $ccmConfigFile) {
		print "WARNING : $ccmConfigFile not found !!!\n";
	} else {
		print "ccm.config : $ccmConfigFile\n";
	}
}
if($localHOST eq $HOST) {
  print "\n";
  if($^O ne "MSWin32") {
    if( ! -e "$InstallDir/sap_bobj") {
      print "WARNING : $InstallDir/sap_bobj' does not exist, maybe the build is not well installed\n";
      $exitCode += 128;
    } else {
      print "$InstallDir exists ==> OK\n"
    }
    if($flagServer_boe_cmsd == 0) {
      print "WARNING : boe_cmsd not running\n";
      my $InstallUser = $ENV{INSTALLUSER} || $ENV{INSTALL_USER} || $localUser;
      print "try command : ps -edf | grep -w $InstallUser | grep -i boe_cmsd | awk \{\'print \$8\'\} | grep -wv grep\n";
      $exitCode += 64;
    } else {
      print "boe_cmsd running ==> OK\n";
    }
  } else {
    if( ! -e "$InstallDir") {
      print "WARNING : '$InstallDir' does not exist, maybe the build is not well installed\n";
      $exitCode += 128;
    } else {
      print "$InstallDir exists ==> OK\n"
    }
    if($flagServer_boe_cmsd == 0) {
      print "WARNING : CMS.exe not running\n";
      $exitCode += 64;
    } else {
      print "CMS.exe running ==> OK\n";
    }
    if($flag_SIA == 0) {
      print "WARNING : sia.exe not running\n";
      $exitCode += 32;
    } else {
      print "sia.exe running ==> OK\n";
    }
    if($flag_TOMCAT == 0) {
      print "WARNING : $tomcatProcess.exe not running\n";
      $exitCode += 16;
    } else {
      print "$tomcatProcess.exe running ==> OK\n";
    }
  }
}
print "\n\t======\n";


if(@optTestCaseNames) {
  foreach my $testCaseName (@optTestCaseNames) {
    my $realTestCaseName;
    #transform option to a short name and launch only the test case
    $_ = $testCaseName;
    SWITCH:
    {
      /^ProductId$/i    and $realTestCaseName = "ProdId"  and $TypeSetup="legacy";
      /^CMC$/i      and $realTestCaseName = "CMC"   and $TypeSetup="legacy";
      /^newCMC$/i     and $realTestCaseName = "CMC"   and $TypeSetup="new";
      /^Infoview$/i   and $realTestCaseName = "IV"    and $TypeSetup="legacy";
      /^newInfoview$/i  and $realTestCaseName = "IV"    and $TypeSetup="new";
    }
    testCases($realTestCaseName,$TypeSetup);
  }
} else { # if no -c, execute all test cases
  testCases("CMC",$TypeSetup);
  testCases("IV",$TypeSetup);
}

exit $exitCode;

#############
# Functions #
#############

### prepare test cases
sub CheckPlatForm($) {
  my ($testCaseName) = @_ ;
  $_ = $PLATFORM;
  SWITCH:
  {
    #MSWin32
    /win32_x86/     and $TypeSetup ||= "new";
    /win64_x64/     and $TypeSetup ||= "new";
    #linux
    /linux_x86/     and $TypeSetup ||= "new";
    /linux_x64/     and $TypeSetup ||= "new";
    #solaris
    /solaris_sparc/   and $TypeSetup ||= "new";
    /solaris_sparcv9/ and $TypeSetup ||= "new";
    #aix
    /aix_rs6000/    and $TypeSetup = "legacy";
    /aix_rs6000_64/   and $TypeSetup = "legacy";
    #hpux
    /hpux_pa-risc/    and $TypeSetup = "legacy";
    /hpux_ia64/     and $TypeSetup = "legacy";
  }
  testCases($testCaseName,$TypeSetup);
}


sub testCases($$) {
  my ($testCase,$mode) = @_ ;
  $_ = $testCase;
  SWITCH:
  {
    /^ProdId$/    and testProductId($mode);
    /^CMC$/     and testCMC($mode);
    /^IV$/      and testInfoView($mode);
  }
}


### test cases
sub testProductId($) {
  my ($typePkg) = @_ ;
  print "\n";
  if($typePkg eq "legacy") {
    print("\tStarting $TypeSetup ProductId.txt test case...\n");    
    checkSetupAvailable();
    eval
    {
      my $productVersion = "";
      # 2 read txt $ProductIdTtxtFile
      if( -e $ProductIdTtxtFile) {
        open(PRODUCTID,$ProductIdTtxtFile) or die("ERROR: cannot open '$ProductIdTtxtFile': $!");
          chomp($productVersion = <PRODUCTID>);
        close(PRODUCTID);
        print "$ProductIdTtxtFile : $productVersion\n";
        ($productVersion) =~ s/^BuildVersion\=//;
        # check
        my $typePkg ;
        ($typePkg) = $productVersion =~ /\d+\.(\w+)_$buildName$/;
        my $versionToCheck = "${Version}.${buildRev}.${typePkg}_$buildName";
        if ($versionToCheck eq $productVersion) {
          print "INFO: ProductId.txt ($TypeSetup package) checked Successfully-\n\n";
        } else {
          print "version of ProductId.txt ($TypeSetup package) is '$productVersion' instead of '$versionToCheck'\n";
          print "ERROR: bad version\n\n";
        }
      } else { die("ERROR: '$ProductIdTtxtFile' does not exist\n\n") }
    };
    if($@) { print "$@\n" }
  } else {
    print "no ProductId file '$ProductIdTtxtFile' for new package\n\n";
  }
}

sub testCMC($) {
  my ($typePkg) = @_ ;
  my $httpRoot = "http://$HOST_IP:$TomcatPort";
  $httpRoot .= "/BOE" if($typePkg eq "new");

  sleep(5);
  print "\n";
  print("\tStarting $typePkg CMC test case...\n");
  checkSetupAvailable();
  eval
  {
    $exitCode += 8;
    my $HTMLTree = HTML::TreeBuilder->new();
    my $ua = LWP::UserAgent->new();
    $ua->timeout(1800);
	
    # retrieve the OSGI build number - this changes in every release, so we need to extract here dynamically #
    my $OSGI;
    my $URL0 = "$httpRoot/CMC";
	debugEcho($URL0);
    my $Request = HTTP::Request->new(GET => $URL0);
    $Request->header(Content_Type=>"application/x-www-form-urlencoded");
    my $Response = $ua->request($Request);
    my $result = $Response->content();
    die("ERROR: $result\n") unless($Response->is_success());
    if($result =~ m/"CMC\/(\d+)\/admin\/logon.faces"/) { $OSGI = $1;};
	if ( $OSGI ) {
		print "The OSGI Build Number is $OSGI\n";
	}
	else {
		warn("WARN: Unable to determine OSGI Build Number!");
	}
    # grab the JSESSIONID cookie
    my $jsessionCookie = $Response->header('Set-Cookie');
    ($jsessionCookie) = $jsessionCookie =~ /(.+);/;	
	
    # retrieve form and parse its contents for field names and hidden values #
    my $Cookies1 = "CMCPLATFORMSVC_COOKIE_USR=$User; CMCPLATFORMSVC_COOKIE_CMS=$HOST:$CMCPort; CMCPLATFORMSVC_COOKIE_AUTH=secEnterprise";
    my $URL1 = "$httpRoot/CMC/$OSGI/admin/logon.faces";
	debugEcho($URL1);
	
    print "root http address : $HOST_IP:$TomcatPort\n";
    print "$typePkg CMC logon to : $httpRoot/CMC\n\n";
    $Request = "";
    $Request = HTTP::Request->new(GET => $URL1);
    $Request->header(Cookie=>"$jsessionCookie;$Cookies1");
    $Response = $ua->request($Request);
    sleep(3);
    open (CMC, ">${typePkg}_CMC_logon_init.htm");
      print CMC $Response->content();
    close(CMC);
    my $Status = $Response->status_line(); 
    chomp($Status);
    warn("WARN: '$Status', see ${typePkg}_CMC_logon_init.htm") unless($Response->is_success());
    # parse form for field names and hidden field values
    my $logonFormContent = $Response->content();
    my ($FIELD_CMS) = $logonFormContent =~ /\<input[^>]*name=\"(\_id\d+\:logon\:CMS)\"[^>]*>/;
    my ($FIELD_USERNAME) = $logonFormContent =~ /\<input[^>]*name=\"(_id\d+:logon:USERNAME)\"[^>]*>/;
    my ($FIELD_PASSWORD) = $logonFormContent =~ /\<input[^>]*name=\"(_id\d+:logon:PASSWORD)\"[^>]*>/;
    my ($FIELD_AUTHTYPE) = $logonFormContent  =~ /\<select[^>]*name=\"(_id\d+:logon:AUTH_TYPE)\"[^>]*>/;
    my ($VALUE_FACES_VIEW) = $logonFormContent =~ /\<input[^>]*name=\"com.sun.faces.VIEW\"[^>]*value=\"([^\"]+)\"[^>]*>/;
    my ($FIELD_ID, $VALUE_ID) = $logonFormContent =~ /\<input[^>]*type=\"hidden\"[^>]name=\"(_id\d+)\"[^>]*value=\"(_id\d+)\"[^>]*>/;
    
    # logon #
    # POST
    $URL2 = "$httpRoot/CMC/$OSGI/admin/logon.faces";
	debugEcho($URL2);
    $Request = HTTP::Request->new(POST => $URL2);
    $Request->header(referer=>"$httpRoot/CMC/$OSGI/admin/logon.faces");	
    $Request->header(Content_Type=>"application/x-www-form-urlencoded");
    $Request->header(Cookie=>"$jsessionCookie; CMCPLATFORMSVC_COOKIE_TOKEN=");
    my $formContent = "$FIELD_CMS=$HOST:$CMCPort&$FIELD_USERNAME=$User&$FIELD_PASSWORD=$Password&$FIELD_AUTHTYPE=secEnterprise&com.sun.faces.VIEW=$VALUE_FACES_VIEW&$FIELD_ID=$VALUE_ID&";
    $formContent =~ s/:/\%3A/g;
	debugEcho($formContent);
    $Request->content($formContent);
    $Response = $ua->request($Request);
    open (CMC, ">${typePkg}_CMC_logon.htm");
      print CMC $Response->content();
    close(CMC);
    $Status = $Response->status_line();
    chomp($Status);
    die("ERROR: '$Status', see ${typePkg}_CMC_logon.htm") unless ($Response->is_success() || $Response->is_redirect());
	if ($Response->is_success()) {
		my $responseContent = $Response->content();
		if ( $responseContent =~ /<div\s+class\s*\=\s*"logonError"/ ) {
			# logon error encountered
			$responseContent =~ m/<div\s+class\s*\=\s*"logonError">\n*(.+)<\/div>/;
			die("ERROR: ", decode_entities($1));
		}
	}
    my $Cookies2 = $Response->header('Set-Cookie');
    my ($bttoken) = $Response->header('Location') =~ /bttoken=(.+)[^\&]?/;
	unless ($bttoken) {
		# redirect moved to the body in recent versions (we'll handle both)
		($bttoken) = $Response->content() =~ /window\.location.*bttoken=(\w+)/;
	}
	unless ( $bttoken ) {
		my $logonFormContent = $Response->content();
		($bttoken) = $logonFormContent =~ /\<input[^>]*name=\"bttoken\"[^>]*value=\"([^\"]+)\"[^>]*>/;
	}
	unless ( $bttoken ) {
		warn("ERROR: Unable to retrieve bttoken!");
	}
    
    # visit home redirect page
    if ($Response->is_redirect()) {
	    $URL3 = "$httpRoot/CMC/$OSGI/admin/App/homeRedirect.jsp?bttoken=$bttoken";
		debugEcho($URL3);
	    $Request = HTTP::Request->new(GET => $URL3);
	    $Request->header(referer=>$URL2);
	    $Request->header(Cookie=>"$jsessionCookie; CMCPLATFORMSVC_COOKIE_TOKEN=; CMCPLATFORMSVC_COOKIE_CMS=$HOST%3A$CMCPort; CMCCE_SAPSys=; CMCCE_SAPCnt=; CMCPLATFORMSVC_COOKIE_USR=$User; CMCPLATFORMSVC_COOKIE_AUTH=secEnterprise");
	    $Response = $ua->request($Request);
	    open (CMC, ">${typePkg}_CMC_ON_pre.htm");
	    	print CMC $Response->content();
	    close(CMC);
	    $Status = $Response->status_line();
	    chomp($Status);
	    die("ERROR: '$Status', see ${typePkg}_CMC_ON_pre.htm") unless ($Response->is_success() || $Response->is_redirect());
    }

	die("INFO: Stopping CMC smoke test here as following steps need to be reworked...");
	
	
    # Verify that logon is successful #
    $URL4 = "$httpRoot/CMC/$OSGI/admin/App/home.faces?bttoken=$bttoken&appKind=CMC&service=%2Fadmin%2FApp%2FappService.jsp&loc=";
	debugEcho($URL4);
    $Request = HTTP::Request->new(GET => $URL4);
    $Request->header(Cookie=>$jsessionCookie);
    $Response = $ua->request($Request);
    open (CMC, ">${typePkg}_CMC_ON.htm");
      print CMC $Response->content();
    close(CMC);
    my $ContentHTML = $Response->content();
    die("ERROR: '$User' not logged on $typePkg CMC") unless($ContentHTML =~ /\<title\>.*?Central\s+Management\s+Console.*?\<\/title\>/);    
    
    $Status = $Response->status_line();
    chomp($Status);
    die("ERROR: '$Status', see ${typePkg}_CMC_ON.htm") unless($Response->is_success());    
    print "INFO: Successfully logged on $typePkg CMC\n";

    #Logoff#    
    $URL5 = "$httpRoot/CMC/$OSGI/admin/App/logoff.jsp?cleanedUp=true&appKind=CMC&bttoken=$bttoken";
	debugEcho($URL5);
    $Request = HTTP::Request->new(GET => $URL5);
    $Request->header(Cookie=>"$jsessionCookie;$Cookies1");
    $Response = $ua->request($Request);
    open (CMC, ">${typePkg}_CMC_logoff.htm");
      print CMC $Response->content();
    close(CMC);
    $Status = $Response->status_line();
    chomp($Status);
    die("ERROR: '$Status', see ${typePkg}_CMC_logoff.htm") unless($Response->is_success()); 

    #Verify that logoff is successful#
    $URL6 = "$httpRoot/CMC/$OSGI/admin/logon.faces";
	debugEcho($URL6);
    $Request = HTTP::Request->new(GET => $URL6);
    $Request->header(Cookie=>"$jsessionCookie;$Cookies1");
    $Response = $ua->request($Request);
    open (CMC, ">${typePkg}_CMC_OFF.htm");
      print CMC $Response->content();
    close(CMC);
    $ContentHTML = $Response->content();
    die("ERROR: '$User' not logged off $typePkg CMC\n") unless($ContentHTML =~ /\<div.*\>\s+Log\s+On\s+to\s+the\s+Central\s+Management\s+Console\s+\<\/div\>/ || $ContentHTML =~ /Enter\syour\suser\sinformation/ );
    $Status = $Response->status_line();
    chomp($Status);
    die("ERROR: '$Status', see ${typePkg}_CMC_OFF.htm") unless($Response->is_success());
    print "INFO: Successfully logged off from $typePkg CMC\n\n";
    $HTMLTree->delete();
    $exitCode = $exitCode - 8;
  };
  if($@) { print "$@\n"; }
}

sub testInfoView($) {
  my ($typePkg) = @_ ;
  my $httpRoot = "http://$HOST_IP:$TomcatPort";
  my $IV_Page = "";
    $httpRoot .= "/BOE";
  $IV_Page = "BI";

  sleep(5);
  print "\n";
  print "\tStarting $typePkg InfoView test case ...\n";
  checkSetupAvailable();
  eval
  {
    $exitCode += 4;
    my $HTMLTree = HTML::TreeBuilder->new();
    my $ua = LWP::UserAgent->new();
    $ua->timeout(900);
	
    # retrieve the OSGI build number - this changes in every release #
    my $OSGI;
    my $URL0 = "$httpRoot/$IV_Page";
	debugEcho($URL0);
    my $Request = HTTP::Request->new(GET => $URL0);
    $Request->header(Content_Type=>"application/x-www-form-urlencoded");
    $Response = $ua->request($Request);
    my $result = $Response->content();	
    die("ERROR: $result\n") unless($Response->is_success());		
    if ($result =~ m/"portal\/(\d+)\/InfoView\/logon.faces/) { $OSGI = $1;};
	if ( $OSGI ) {
		print "The OSGI Build Number is $OSGI\n";
	}
	else {
		warn("WARN: Unable to determine OSGI Build Number!");
	}
    # grab the JSESSIONID cookie
    my $jsessionCookie = $Response->header('Set-Cookie');
    ($jsessionCookie) = $jsessionCookie =~ /(.+);/;	
	
    # retrieve form and parse its contents for field names and hidden values #
    my $URL1 = "$httpRoot/portal/$OSGI/InfoView/logon.faces";
	debugEcho($URL1);
    my $Cookies1 = "InfoViewPLATFORMSVC_COOKIE_TOKEN=; ivsExitPage=; ivsEntSessionVar=; InfoViewPLATFORMSVC_COOKIE_USR=$User; InfoViewPLATFORMSVC_COOKIE_CMS=$HOST:$CMCPort; InfoViewPLATFORMSVC_COOKIE_AUTH=secEnterprise";
    print "root http address : $HOST_IP:$TomcatPort\n";
    print "IV logon to : $httpRoot/BI\n\n";
    $Request = "";
    $Request = HTTP::Request->new(POST => $URL1);
    $Request->header(Cookie=>"$jsessionCookie;$Cookies1");
    my $Response = $ua->request($Request);
    open (IV, ">${typePkg}_IV_init.htm");
      print IV $Response->content();
    close(IV);
    my $Status = $Response->status_line();
    chomp($Status);
    die("ERROR: '$Status', see ${typePkg}_IV_init.htm") unless($Response->is_success());
    # parse form for field names and hidden field values
    my $logonFormContent = $Response->content();
    my ($FIELD_CMS) = $logonFormContent =~ /\<input[^>]*name=\"(\_id\d+\:logon\:CMS)\"[^>]*>/;
    my ($FIELD_USERNAME) = $logonFormContent =~ /\<input[^>]*name=\"(_id\d+:logon:USERNAME)\"[^>]*>/;
    my ($FIELD_PASSWORD) = $logonFormContent =~ /\<input[^>]*name=\"(_id\d+:logon:PASSWORD)\"[^>]*>/;
    my ($FIELD_AUTHTYPE) = $logonFormContent  =~ /\<select[^>]*name=\"(_id\d+:logon:AUTH_TYPE)\"[^>]*>/;
    my ($VALUE_FACES_VIEW) = $logonFormContent =~ /\<input[^>]*name=\"com.sun.faces.VIEW\"[^>]*value=\"([^\"]+)\"[^>]*>/;
    my ($FIELD_ID, $VALUE_ID) = $logonFormContent =~ /\<input[^>]*type=\"hidden\"[^>]name=\"(_id\d+)\"[^>]*value=\"(_id\d+)\"[^>]*>/;
	
    # logon #
    $URL2 = "$httpRoot/portal/$OSGI/InfoView/logon.faces";
	debugEcho($URL2);
    $Request = HTTP::Request->new(POST => $URL2);
    $Request->header(referer=>"$httpRoot/portal/$OSGI/InfoView/logon.faces");
    $Request->header(Content_Type=>"application/x-www-form-urlencoded");
    $Request->header(Cookie=>"$Cookies1; $jsessionCookie");
    my $formContent = "$FIELD_CMS=$HOST:$CMCPort&$FIELD_USERNAME=$User&$FIELD_PASSWORD=$Password&$FIELD_AUTHTYPE=secEnterprise&com.sun.faces.VIEW=$VALUE_FACES_VIEW&$FIELD_ID=$VALUE_ID&";
    $formContent =~ s/:/\%3A/g;
	debugEcho($formContent);
    $Request->content($formContent);
    $Response = $ua->request($Request);
    open (IV, ">${typePkg}_IV_logon.htm");
      print IV $Response->content();
    close(IV);
    $Status = $Response->status_line();
    chomp($Status);
    die("ERROR: '$Status', see ${typePkg}_IV_logon.htm") unless($Response->is_success() || $Response->is_redirect());
	if ($Response->is_success()) {
		my $responseContent = $Response->content();
		if ( $responseContent =~ /<div\s+class\s*\=\s*"logonError"/ ) {
			# logon error encountered
			$responseContent =~ m/<div\s+class\s*\=\s*"logonError">\n*(.+)<\/div>/;
			die("ERROR: ", decode_entities($1));
		}
	}
    my ($bttoken) = $Response->header('Location') =~ /bttoken=(.+)[^\&]?/;
	unless ($bttoken) {
		# redirect moved to the body in recent versions (we'll handle both)
		($bttoken) = $Response->content() =~ /window\.location.*bttoken=(\w+)/;
	}
	unless ( $bttoken ) {
		my $logonFormContent = $Response->content();
		($bttoken) = $logonFormContent =~ /\<input[^>]*name=\"bttoken\"[^>]*value=\"([^\"]+)\"[^>]*>/;
	}
	unless ( $bttoken ) {
		warn("ERROR: Unable to retrieve bttoken!");
	}

	die("INFO: Stopping InfoView smoke test here as following steps need to be reworked...");

    # do main
    $URL3 = "$httpRoot/portal/$OSGI/InfoView/listing/main.do?service=%2Fcommon%2FappService.do&appKind=InfoView&bttoken=$bttoken";
	debugEcho($URL3);
    $Request = HTTP::Request->new(GET => $URL3);
    $Request->header(referer=>$URL2);
    $Request->header(Cookie=>$jsessionCookie);
    $Response = $ua->request($Request);
    open (IV, ">${typePkg}_IV_Main_Do.htm");
      print IV $Response->content();
    close(IV);
    $Status = $Response->status_line();
    chomp($Status);
    die("ERROR: '$Status', see ${typePkg}_IV_Main_Do.htm") unless($Response->is_success() || $Response->is_redirect());
    my $Cookies2 = $Response->header('Set-Cookie');
	
	
    # Verify the Infoview Home page as logged on    
    $URL4 = "$httpRoot/portal/$OSGI/InfoView/listing/home.do?appKind=InfoView&service=%2Fcommon%2FappService.do&bttoken=$bttoken";
	debugEcho($URL4);
    $Request = HTTP::Request->new(GET => $URL4);
    $Request->header(referer=>$URL3);
    $Request->header(Cookie=>$jsessionCookie);
    $Response = $ua->request($Request);
    open (IV, ">${typePkg}_IV_ON.htm");
      print IV $Response->content();
    close(IV);
    my $ContentHTML = $Response->content();
    unless( ($ContentHTML =~ /\<title\>Home&#x20;Page&#x20;of&#x20;BI&#x20;launch&#x20;pad\<\/title\>/) || ($ContentHTML =~ /\<title\>Home\s+Page\s+of\s+BI\s+launch\s+pad\<\/title\>/) || ($ContentHTML =~ /\<title\>Home\s+Page\s+of\s+BusinessObjects\s+InfoView\<\/title\>/) ) {
    	die("ERROR: '$User' not logged on $typePkg Infoview");
    }
    $Status = $Response->status_line();
    chomp($Status);
    die("ERROR: '$Status', see ${typePkg}_IV_ON.htm") unless($Response->is_success());
    print "INFO: Successfully logged on $typePkg Infoview\n";


    #Logoff#
    $URL5 = "$httpRoot/portal/$OSGI/InfoView/logon/logoff.do";
	debugEcho($URL5);
    $Request = HTTP::Request->new(POST => $URL5);  
    $Request->header(Content_Type=>"application/x-www-form-urlencoded");
    $Request->header(Cookie=>$jsessionCookie);
    $Request->content("cleanedUp=true&bttoken=$bttoken");
    $Request->header(referer=>"$httpRoot/portal/$OSGI/InfoView/logon/logoff.do?bttoken=$bttoken");
    $Response = $ua->request($Request);
    open (IV, ">${typePkg}_IV_logoff_do.htm");
      print IV $Response->content();
    close(IV);
    $ContentHTML = $Response->content();


    # Verify logoff is successful
    $URL6 = "$httpRoot/portal/$OSGI/InfoView/logon.faces";
	debugEcho($URL6);
    $Request = HTTP::Request->new(POST => $URL6);
    $Request->header(Content_Type=>"application/x-www-form-urlencoded");
    $Request->header(Cookie=>$jsessionCookie);
    $Request->header(referer=>"$httpRoot/portal/$OSGI/InfoView/logon/logoff.do");
    $Response = $ua->request($Request);
    open (IV, ">${typePkg}_IV_OFF.htm");
      print IV $Response->content();
    close(IV);
    $ContentHTML = $Response->content();	
    die("ERROR: '$User' not logged on $typePkg Infoview") unless($ContentHTML =~ /\<div.*\>\s+Log\s+On\s+to\s+BI\s+launch\s+pad\s+\<\/div\>/ || $ContentHTML =~ /Enter\syour\suser\sinformation/);
    $Status = $Response->status_line();
    chomp($Status);
    die("ERROR: '$Status', see ${typePkg}_IV_OFF.htm") unless($Response->is_success());
    print "INFO: Successfully logged off from $typePkg Infoview\n\n";
    $HTMLTree->delete();
    $exitCode = $exitCode - 4;
  };
  if($@) { print "$@\n"; }
}



sub Usage
{
  print <<USAGE;
  Usage   : SmokeTests.pl [-ca] [-i] [-u] [-pa] [-po] [-cm] 
  SmokeTests.pl -h.elp|?
  Example : SmokeTests.pl -c=Infoview -c=CMS

  [options]
  -help|?     argument displays helpful information about builtin commands.
  -ca.se      specifies one or more test cases, by default all (values: Infoview, CMC) 
  -cm.cport   specifies the CMC port number, default is 6400
  -i.nstall   specifies the installation directory, default is C:\\Program Files (x86)\\SAP BusinessObjects.
  -u.ser      specifies the user, default is 'Administrator'
  -pa.ssword  specifies the password, default is no password
  -po.rt      specifies the tomcat port number, default is 8080
  -ma.chine specifies a server, by default, current machine
USAGE
    exit;
}

sub determineProductId() {
  my $ProductIdTtxtFile = "";
  # 1 determine $ProductIdTtxtFile
  if($^O eq "MSWin32") {
    $InstallDir2 = "C:\\Program Files (x86)\\SAP BusinessObjects\\SAP BusinessObjects Enterprise XI 4.0";
    $ProductIdTtxtFile = "$InstallDir2\\ProductId.txt";
  } else { # unix
    if($ENV{'INSTALLDIR'}) {
      $InstallDir2 = "$ENV{'INSTALLDIR'}/sap_bobj/enterprise_xi40";
      $ProductIdTtxtFile = "$InstallDir2/ProductId.txt";
    } else {
      my $AutoChainProductIdtxtFile = "$ENV{HOME}/ValidationChain/buildToTest/sap_bobj/enterprise_xi40/ProductId.txt";
      my $ASTECProductIdtxtFile = "$ENV{HOME}/ASTEC/buildToTest/sap_bobj/enterprise_xi40/ProductId.txt";
      if ( -e "$AutoChainProductIdtxtFile" ) {
        if ( -e "$ASTECProductIdtxtFile" ) {

          my $AutoChain_datetime  = stat($AutoChainProductIdtxtFile)->mtime;
          my $ASTEC_datetime    = stat($ASTECProductIdtxtFile)->mtime;
          if($ASTEC_datetime > $AutoChain_datetime ) { # ASTEC + récent
            $ProductIdTtxtFile = $ASTECProductIdtxtFile;
            $InstallDir2 = "$ENV{HOME}/ASTEC/buildToTest/sap_bobj/enterprise_xi40";
          } else {
            $InstallDir2 = "$ENV{HOME}/ValidationChain/buildToTest/sap_bobj/enterprise_xi40";
            $ProductIdTtxtFile = $AutoChainProductIdtxtFile;
          }
        } else { # pas ASTEC
          $InstallDir2 = "$ENV{HOME}/ValidationChain/buildToTest/sap_bobj/enterprise_xi40";
          $ProductIdTtxtFile = $AutoChainProductIdtxtFile;
        }
      } elsif ( -e "$ASTECProductIdtxtFile" ) {
        $InstallDir2 = "$ENV{HOME}/ASTEC/buildToTest/sap_bobj/enterprise_xi40";
        $ProductIdTtxtFile = $ASTECProductIdtxtFile;
      }
    } # -i not setted
  } #endif unix
  return $ProductIdTtxtFile;
}

sub CalculateTypeSetup {
  # 2 read txt $ProductIdTtxtFile
  my $tmpTypeSetup;
  if( -e $ProductIdTtxtFile) {
    open(PRODUCTID,$ProductIdTtxtFile) or die("ERROR: cannot open ProductID file '$ProductIdTtxtFile': $!");
      my $productVersion;
      chomp($productVersion = <PRODUCTID>);
    close(PRODUCTID);
    ($productVersion) =~ s/^BuildVersion\=//;
    # check
    my $typePkg;
    ($typePkg) = $productVersion =~ /\d+\.(\w+)_$buildName$/;
    my $versionToCheck = "${Version}.${buildRev}.${typePkg}_$buildName";
    $tmpTypeSetup = ($typePkg eq "New") ? "new" : "legacy";
  } else {
    #new pkg have no ProductId.txt in $InstallDir2
    $tmpTypeSetup = "new";
  }
  return $tmpTypeSetup;
}

sub checkSetupAvailable() {
	if($SetupPath) {
	    my $Setup;
	    if($^O eq "MSWin32") {
			$Setup = "$SetupPath\\setup.exe";
		} else {
			$Setup = "$SetupPath/setup.sh";
		}
		if( ! -e $Setup ) {
			print "\n\tWARNING : '$Setup' not found\n\n";
		}
	}
}

sub GetInstallDir () {
	my $installdir;
	if(open(INI,$responseIniFile)) {
		while(<INI>) {
			chomp;
			if(/^InstallDir\=(.+?)$/) {
				$installdir = $1;
				last;
			}
		}
		close(INI);
	}
	return $installdir if( -e $installdir );
}

sub GetResponseIni {
	if ($SetupPath) {
		my $responseIniFile = "$SetupPath\\response.ini";
		($^O eq "MSWin32") ? $responseIniFile =~ s/\//\\/g : $responseIniFile =~ s/\\/\//g;
		return $responseIniFile;
	}
}
sub GetSetupPath {
	if( ($ENV{'DROP_DIR'}) && ($ENV{'CONTEXT'}) && ($ENV{'BUILD_NUMBER'}) && ($ENV{'PLATFORM'}) && ($ENV{'BUILD_MODE'}) ) {
		my $DROP_DIR	= $ENV{'DROP_DIR'};
		my $Context		= $ENV{'CONTEXT'};
		my $BuildNumber	= $ENV{'BUILD_NUMBER'};
		my $PLATFORM	= $ENV{'PLATFORM'};
		my $BUILD_MODE	= $ENV{'BUILD_MODE'};
		my $Name		= "BusinessObjectsServer";
		my $PathList	= "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/packages/$Name";
		($^O eq "MSWin32") ? $PathList =~ s/\//\\/g : $PathList =~ s/\\/\//g;
		return $PathList;
	}
}

sub debugEcho () {
	my ($line, $alwaysPrint) = @_;
	chomp $line;
	if ($VERBOSE || $alwaysPrint) {
		print $line, "\n";
	}
}
