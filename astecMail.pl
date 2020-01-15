#############################################################################
##### declare uses

use strict;
use diagnostics;

use Getopt::Long;
use Sys::Hostname;


use File::stat;

use File::Find;
use File::Path;
use File::Copy;
use File::Basename;
use File::Spec::Functions;

use FindBin;
use lib $FindBin::Bin;

use Net::SMTP;



#############################################################################
##### declare vars
# system
use vars qw (
    $CURRENTDIR
    $HOST
    $OBJECT_MODEL
    $Model
    $NULLDEVICE
    $Temp
    $PLATFORM
    $Site
);

#build info
use vars qw (
    $PROJECT
    $CONTEXT
    $BUILD_NUMBER
    $DROP_DIR
    $ASTEC_DIR
    $AstecTriggerFile
    $VersionFile
    %SetupPaths
    %TriggersPackages
    %PatchPaths
    %TriggersPatches
    $refRev
    $BOC
);

#parameter/options
use vars qw (
    $DLMail
    $Help
    $optPkgName
);

#for script it self



#############################################################################
##### declare functions
sub Usage($);
sub SendMail();
sub getBuildRev();



#############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "s=s"       =>\$Site,
    "p=s"       =>\$PROJECT,
    "c=s"       =>\$CONTEXT,
    "v=s"       =>\$BUILD_NUMBER,
    "64!"       =>\$Model,
    "dl=s"      =>\$DLMail,
    "tf=s"      =>\$AstecTriggerFile,
    "help|h|?"  =>\$Help,
    "pn=s"      =>\$optPkgName,
    "BOC"       =>\$BOC
);



#############################################################################
##### init vars
# system
$CURRENTDIR = $FindBin::Bin;
$HOST = hostname();
$OBJECT_MODEL = $Model ? "64" : "32" if(defined($Model));
$ENV{OBJECT_MODEL} = $OBJECT_MODEL ||= $ENV{OBJECT_MODEL} || "32";
unless($PLATFORM) {
       if($^O eq "MSWin32") { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64"       : "win32_x86"     }
    elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc" }
    elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64"   : "aix_rs6000"    }
    elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64"       : "hpux_pa-risc"  }
    elsif($^O eq "linux")   { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64"       : "linux_x86"     }
}
$NULLDEVICE = ($^O eq "MSWin32") ? "nul" : "/dev/null" ;
# Site
$Site ||= $ENV{'SITE'} || "Walldorf";
unless( $Site eq "Levallois"
     || $Site eq "Walldorf"
     || $Site eq "Vancouver"
     || $Site eq "Bangalore"
     || $Site eq "Paloalto"
     || $Site eq "Lacrosse" ) {
        my $msg  = "ERROR: SITE environment variable or 'perl $0 -s=my_site' must be set";
        $msg    .= "\navailable sites : ";
        $msg    .= "Levallois | Walldorf | Vancouver | Bangalore | Paloalto | Lacrosse\n";
        die("\n$msg");
}
$ENV{'SITE'} = $Site || "Walldorf";

#param
$PROJECT    ||="aurora_maint";
$CONTEXT    ||="aurora42_sp_cor";
$ENV{PROJECT} = $PROJECT || "aurora_maint";
require Site;

$DROP_DIR             = $ENV{DROP_DIR};
$ASTEC_DIR          ||= catdir($ENV{'ASTEC_DIR'},$PROJECT,$CONTEXT,$PLATFORM);
$AstecTriggerFile   ||= catdir($ASTEC_DIR,"buildInfo.txt");
($AstecTriggerFile)   =~ s-\\-\/-g;
die("ERROR : $AstecTriggerFile not found : $!") if ( ! -e "$AstecTriggerFile" );

$BUILD_NUMBER ||=`grep BUILD_VERSION \"$AstecTriggerFile\"`;
chomp($BUILD_NUMBER);
($BUILD_NUMBER) =~ s-^BUILD_VERSION\=--i;
$refRev = &getBuildRev();



#############################################################################
##### MAIN
&Usage("") if($Help);
&Usage("'-dl=distributionList' missed, use perl $0 -dl=distributionList") unless($DLMail);

print("\nStart at ", scalar(localtime()),"\n");

if(open(ASTEC,"$AstecTriggerFile")) {
    while(<ASTEC>) {
        chomp;
        next unless(/^SETUP_PATH/i);
        next if(/^SETUP_PATH\=/i);
        s-^SETUP\_PATH\_--i;
        my ($pkgName,$pkgPath) = $_ =~ /^(.+?)\=(.+?)$/;
        next if( ($optPkgName) && ($pkgName ne $optPkgName) );
        unless($pkgName =~ /\_patch$/i) {
            $SetupPaths{$pkgName}=$pkgPath  ;
            if( -e "$ASTEC_DIR/${pkgName}.buildInfo.txt" ) {
                my $tmp = "$ASTEC_DIR/${pkgName}.buildInfo.txt";
                if($^O eq "MSWin32") {
                    ($tmp) =~  s-\/-\\-g;
                }
                $TriggersPackages{$pkgName} = $tmp;
            }
        }
        if($pkgName =~ /\_patch$/i) {
            $PatchPaths{$pkgName}=$pkgPath;
            if( -e "$ASTEC_DIR/${pkgName}.buildInfo.txt" ) {
                my $tmp = "$ASTEC_DIR/${pkgName}.buildInfo.txt";
                if($^O eq "MSWin32") {
                    ($tmp) =~  s-\/-\\-g;
                }
            $TriggersPatches{$pkgName} = $tmp;
            }
        }
    }
    close(ASTEC);
}
    my $ShowAstecTriggerFile = $AstecTriggerFile;
    if($^O eq "MSWin32") {
        ($ShowAstecTriggerFile) =~ s-\/-\\-g
    }
print "

\tINFO :
\t======

PROJECT = $PROJECT
CONTEXT = $CONTEXT
BUILD_NUMBER = $BUILD_NUMBER
ASTEC TRIGGER FILE = $ShowAstecTriggerFile

";

if(scalar(keys(%SetupPaths)) > 0){
    foreach my $pkgName (sort(keys(%SetupPaths))) {
        my $pkgPath = $SetupPaths{$pkgName};
        print "$pkgName -> $pkgPath\n";
        if($TriggersPackages{$pkgName}) {
            print "trigger : $TriggersPackages{$pkgName}\n\n";
        }
    }
}
if(scalar(keys(%PatchPaths)) > 0){
    print "\n";
    foreach my $pkgName (sort(keys(%PatchPaths))) {
        my $pkgPath = $PatchPaths{$pkgName};
        print "$pkgName -> $pkgPath\n";
        if($TriggersPatches{$pkgName}) {
            print "trigger : $TriggersPatches{$pkgName}\n\n";
        }
    }
}

&SendMail();

print("\nStop at ", scalar(localtime()),"\n\n");
exit;



#############################################################################
### my functions

sub getBuildRev() {
    my $tmp = 0;
    if(open(VER, "$DROP_DIR/$CONTEXT/version.txt"))
    {
        chomp($tmp = <VER>);
        $tmp = int($tmp);
        close(VER);
    }
    else
    {
        # If version.txt does not exists or opening failed, instead of restarting from 1,
        #look for existing directory versions & generate the hightest version number
        #based on the hightest directory version
        # open current context dir to find the hightest directory version inside
        if(opendir(BUILDVERSIONSDIR, "$DROP_DIR/$CONTEXT"))
        {
            while(defined(my $next = readdir(BUILDVERSIONSDIR)))
            {
                # Only take a directory with a number as name,
                #which can be a number or a float number with a mandatory decimal value
                #& optional floating point
                $tmp = $1 if ($next =~ /^(\d+)(\.\d+)?$/ && $1 > $tmp && -d "$DROP_DIR/$CONTEXT/$next");
            }   
            closedir(BUILDVERSIONSDIR);
        }
    }
    return $tmp;
}

sub SendMail() {
    use Time::localtime;
    $Temp = $ENV{TEMP};
    $Temp = catdir($Temp,$CONTEXT,"64");
    if( ! -e $Temp ) {
        mkpath("$Temp") if( ! -e "$Temp");
    }

    my $htmlFile = catdir("$Temp","astec_mail_$CONTEXT");
    $htmlFile .= "_${BUILD_NUMBER}_release.htm";

    unlink("$htmlFile ") if( -e $htmlFile );
    open(HTML,">$htmlFile") || die("ERROR: cannot create '$htmlFile': $!");

    my %Mails;
    my $MailSite = $Site;
    $MailSite = "Levallois" if($Site eq "Walldorf");
    $_ = $MailSite ;
    SWITCH:
    {
        /Walldorf/  and %Mails = ( 'Walldorf'  ,
                                  ['DL PI HANA Plat Production Build Ops (FRANCE)'
                                  ,'DL_52ACCC73FD84A076E6000BF2@exchange.sap.corp']);
        /Levallois/ and %Mails = ( 'Levallois' ,
                                  ['DL PI HANA Plat Production Build Ops (FRANCE)'
                                  ,'DL_52ACCC73FD84A076E6000BF2@exchange.sap.corp']);
        /Vancouver/ and %Mails = ( 'Vancouver' ,
                                  ['DL PI HANA Platform Production Build Ops (CAN)'
                                  ,'DL_TIP_PROD_BOBJ_BUILD_OPS_(CAN)"@exchange.sap.corp']);
        /Bangalore/ and %Mails = ( 'Bangalore' ,
                                  ['DL PI HANA Plat Production Build Ops (India)'
                                  ,'DL_TIP_PROD_BOBJ_BUILD_OPS_(INDIA)"@exchange.sap.corp']);
    }
    my $Contact     = $Mails{$MailSite}[0];
    my $mailContact = $Mails{$MailSite}[1];

    print HTML '
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<html>
 <head>
  <meta http-equiv=Content-Type content="text/html; charset=iso-8859-1">
  <title>Mail ',"$CONTEXT $BUILD_NUMBER $PLATFORM release",'</title>

<!--[if !mso]>
<style>
st1\:*{behavior:url(#default#ieooui) }
</style>
<![endif]-->
<style>
table {
 border-collapse:collapse;
}
td { 
 padding-right: 10px;
 padding-left: 10px;
 padding-top: 5px;
 padding-bottom: 5px;
 }
</style>

 </head>
 <body>
<br/>
Hi Team,<br/><br/>
';
    if($optPkgName) {
        print HTML "
This email is just to inform you that <font color=\"blue\">$optPkgName</font> package is now available on <br/>
";
    } else {
        print HTML '
This email is just to inform you that <strong>all</strong> packages are now available, see below :<br/>
';
}
    print HTML '
';

    my $indice = 0;
    my $bgColor = "white";
    if(scalar(keys(%SetupPaths)) > 0) {
        print HTML "<br/>packages:<br/><table border=\"0\">\n";
        foreach my $pkgName (sort(keys(%SetupPaths))) {
            my $pkgPath = $SetupPaths{$pkgName};
            if($indice == 0) {
                $bgColor = "white";
            } else {
                $bgColor = "#A2CBF4";
            }
            if($TriggersPackages{$pkgName}) {
                my $datetime_string = ctime(stat($TriggersPackages{$pkgName})->mtime);
                my ($numDayFile,$hourFile,$minFile,$secFile) = $datetime_string =~ /\s+(\d+)\s+(\d+)\:(\d+)\:(\d+)\s+/;
                print HTML "\t<tr bgcolor=\"$bgColor\"><td rowspan=2>$pkgName</td><td>setup path</td><td>$pkgPath</td></tr><tr bgcolor=\"$bgColor\"><td>trigger file</td><td>$TriggersPackages{$pkgName}</td><td>$hourFile:$minFile:$secFile</td></tr>\n";
                
            } else {
                print HTML "\t<tr bgcolor=\"$bgColor\"><td>$pkgName</td><td>$pkgPath</td></tr>\n";
            }
            if($indice == 0) {
                $indice = 1;
            } else {
                $indice = 0;
            }
        }
        print HTML "</table><br/>\n";
    }
    if(scalar(keys(%PatchPaths)) > 0) {
        print HTML "<br/>patches:<br/><table border=\"0\">\n";
        foreach my $pkgName (sort(keys(%PatchPaths))) {
            my $pkgPath = $PatchPaths{$pkgName};
            if($indice == 0) {
                $bgColor = "white";
            } else {
                $bgColor = "#A2CBF4";
            }
            if($TriggersPatches{$pkgName}) {
                my $datetime_string = ctime(stat($TriggersPackages{$pkgName})->mtime);
                my ($numDayFile,$hourFile,$minFile,$secFile)
                  = $datetime_string
                  =~ /\s+(\d+)\s+(\d+)\:(\d+)\:(\d+)\s+/;
                print HTML "\t<tr bgcolor=\"$bgColor\"><td rowspan=2>$pkgName</td><td>setup path</td><td>$pkgPath</td></tr><tr bgcolor=\"$bgColor\"><td>trigger file</td><td>$TriggersPatches{$pkgName}</td><td>$hourFile:$minFile:$secFile</td></tr>\n";
                
            } else {
                print HTML "\t<tr bgcolor=\"$bgColor\"><td>$pkgName</td><td>$pkgPath</td></tr>\n";
            }
            if($indice == 0) {
                $indice = 1;
            } else {
                $indice = 0;
            }
        }
        print HTML "</table><br/>\n";
    }

    print HTML '
<br/>
';
    my $triggerFile1 = "$ASTEC_DIR/buildInfo.txt";
    my $triggerFile2 = "$ASTEC_DIR/nightly.txt";
    if($^O eq "MSWin32") {
        ($triggerFile1) =~ s-\/-\\-g;
        ($triggerFile2) =~ s-\/-\\-g;
    }
    print HTML "List of trigger files containing <strong>all</strong> packages and patches for $PROJECT/$CONTEXT/$PLATFORM:<br/>\n";
    print HTML "<table border=\"0\">\n";
    my $datetime_string = ctime(stat($triggerFile1)->mtime);
    my ($numDayFile,$hourFile,$minFile,$secFile)
      = $datetime_string
      =~ /\s+(\d+)\s+(\d+)\:(\d+)\:(\d+)\s+/;
    print HTML "<tr><td>trigger for nightly build and possible incremental build (.x version)</td><td>$triggerFile1</td><td>$hourFile:$minFile:$secFile</td></tr>\n";
    my $datetime_string2 = ctime(stat($triggerFile2)->mtime);
    my ($numDayFile2,$hourFile2,$minFile2,$secFile2)
      = $datetime_string2
      =~ /\s+(\d+)\s+(\d+)\:(\d+)\:(\d+)\s+/;
    print HTML "<tr><td>trigger for nightly build only (no incremental build)</td><td>$triggerFile2</td><td>$hourFile2:$minFile2:$secFile2</td></tr>\n";
    print HTML "</table><br/>\n";
    print HTML '
<br/>Contact <a href="mailto:',"$Contact",'">',"$Contact",'</a> for any further information.<br/>
<br/>
Thanks,<br/>
Build Ops ',"$MailSite",'.<br/>
<br/>
THIS EMAIL IS SEND AUTOMATICALLY, PLEASE DO NOT REPLY<br/>
<br/>
  </body>
</html>
';

    close(HTML);
    my $SMTP_SERVER = $ENV{SMTP_SERVER} || "mail.sap.corp";
    my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>90);
    $smtp->mail('remy.andre@sap.com');
    ($DLMail) =~ s-\,-\;-g;
    $smtp->to(split('\s*;\s*', $DLMail));
    $smtp->data();
    $smtp->datasend("To: $DLMail\n");
    $smtp->datasend("Subject: [$CONTEXT] build rev. $BUILD_NUMBER - $PLATFORM release: packages available\n");
    $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
    open(HTML, "$htmlFile") or die ("ERROR: cannot open '$htmlFile': $!");
    while(<HTML>) { $smtp->datasend($_) } 
    close(HTML);
    $smtp->dataend();
    $smtp->quit();
    print "\nSend ASTEC Mail done\n";
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
$0 send mail when ASTEC trigger file has been updated

    Usage   : perl $0 [options]
    Example : perl $0 -h

[options]
    -p      Choose a project
            by default, -p=$PROJECT

    -c      Choose a context name/build name
            by default, -c=$CONTEXT

    -v      Choose a version
            by default, -v=$BUILD_NUMBER ($0 scan $VersionFile)

    -dl     !!! it is mandatory !!!
            Choose a distribution list
            add ',' if you have more than one e-mail


    -tf     choose a trigger file
            by default, -tf=$AstecTriggerFile,

    -help|h|?   display this help

";
    exit;
}
