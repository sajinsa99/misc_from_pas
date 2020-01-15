##############################################################################
##### declare uses

use strict;
use warnings;
use diagnostics;

use Time::Local;

use Getopt::Long;
use Sys::Hostname;

use FindBin;
use lib $FindBin::Bin;

use File::Copy;
use File::Path;
use File::Basename;

use XML::Parser;
use XML::DOM;

use Net::SMTP;



##############################################################################
##### declare vars
#SYSTEM
use vars qw (
    $CURRENTDIR
    $HOST
    $FULLNAME_HOST
    $TEMPDIR
    $OBJECT_MODEL
    $PLATFORM
    $NULLDEVICE
);

#OPTIONS/PARAMETERS
use vars qw (
    $cbtPath
    $Help
    $Config
    $Model
    $BUILD_MODE
    $BuildNumber
    $noSync
    $checkGreatest
    $checkIni
    $MAIL
    $MAIL_UPDATE
    $jenkins
    $elements
    $paramChangelist
    @Changelists
    $justSyncBootstrap
    $NoBuildSync
    $ForceBuildPL
    $txtFile
    $fetchTime
    $optCheckDep
    @statuscheckDep
    $ctime
    $Import
    $optCheckInit
);

#P4
use vars qw (
    $p4
    $bootStrapClientSpec
    $P4USER
    $P4PORT
);

#date/time
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
);

#divers
use vars qw (
    %POMS
    $PomFetch
    $OUTLOG_DIR
    $DROP_DIR
    $Context
    $refBuildNumber
    $PROJECT
    $newGreatestFound
    %Greatests
    %newGreatests
    $testIni
    @Inis
    %InisToTest
    $LocaRep
    $FetchCommand
    @News
    $FetchDone
    $Status
    @QSets
    $QsetLine
    $cmdRebuild
);

#jenkins
use vars qw (
    $JENKINS_DIR
    $JENKINS_JOB
    $JENKINS_BUILD_VERSION
    $JENKINS_EXECUTION
);

#mail
use vars qw (
    $SMTP_SERVER
    $SMTPFROM
    $SMTPTO
);



##############################################################################
##### declare functions
#p4
sub getP4User();
sub getSubmitter($);
sub getCL($);

#versioning
sub getBuildRev();
sub getLastIncremental($$);
sub setBuildRef();
sub Versioning();

#divers
sub checkPom($$$);
sub listCurrentGreatests($);
sub searchNewGreatests();
sub listAllInisIncluded($);
sub getFullNameMachine();
sub sendMailOnError($$);
sub sendMailUpdates($);
sub checkDeps();
sub checkInit();

sub TransformDateTimeToSeconds($$);


#my generic functions
sub Usage($);
sub startScript();
sub endScript();



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions("help|?" =>\$Help,
    "ini=s"         =>\$Config,
    "64!"           =>\$Model,
    "m=s"           =>\$BUILD_MODE,
    "v=s"           =>\$BuildNumber,
    "n"             =>\$noSync,
    "cg"            =>\$checkGreatest,
    "ci"            =>\$checkIni,
    "M"             =>\$MAIL,
    "UM"            =>\$MAIL_UPDATE,
    "smtp=s"        =>\$SMTP_SERVER,
    "from=s"        =>\$SMTPFROM,
    "to=s"          =>\$SMTPTO,
    "elem=s"        =>\$elements,
    "cl=s"          =>\$paramChangelist,
    "jsb"           =>\$justSyncBootstrap,
    "ns"            =>\$NoBuildSync,
    "fb"            =>\$ForceBuildPL,
    "jenkins"       =>\$jenkins, # to use ONLY if you execute this script through jenkins job
    "txt"           =>\$txtFile,
    "ft=s"          =>\$fetchTime,
    "cd"            =>\$optCheckDep,
    "ct=s"          =>\$ctime,
    "qset=s@"       =>\@QSets,
    "Import"        =>\$Import,
    "ic"            =>\$optCheckInit,
);
&Usage("") if($Help);
&Usage("-i=ini missed, please use $0 -i=ini_file") unless($Config);
if( ($txtFile) && (!($fetchTime)) ) { #if -txt but not -ft=... -txt has to be use with -ft
    &Usage("-ft option missed, -txt option has to be used with -ft option")
}



##############################################################################
##### init vars

# environment vars
if(scalar(@QSets)>0) {
    foreach (@QSets) {
        my($Variable, $String) = /^(.+?):(.*)$/;
        $ENV{$Variable} = $String;
        $QsetLine .= " -q=$Variable:$String";
    }
}

$cbtPath = $ENV{CBTPATH} if($ENV{CBTPATH});
$cbtPath ||= ($^O eq "MSWin32") ? "c:/core.build.tools/export/shared" : "$ENV{HOME}/core.build.tools/export/shared";
die("ERROR : $cbtPath not found\n") if( ! -e $cbtPath );
chdir($cbtPath) or die("ERROR : cannot chdir into $cbtPath : $!\n");

# system
$CURRENTDIR = $FindBin::Bin;
$HOST = hostname();
&getFullNameMachine();
$TEMPDIR=$ENV{TEMP};
$TEMPDIR =~ s/[\\\/]\d+$//;
$NULLDEVICE = ($^O eq "MSWin32") ? "nul" : "/dev/null" ;

#date/time, need for set of incremental version
($LocalSec,$LocalMin,$LocalHour,$LocalDay,$LocalMonth,$LocalYear,$wday,$yday,$isdst) = localtime(time);
$LocalYear  = $LocalYear + 1900;
$LocalMonth = $LocalMonth + 1;
if($LocalHour < 10) { $LocalHour = "0$LocalHour" }
if($LocalMin  < 10) { $LocalMin  = "0$LocalMin"  }
if($LocalSec  < 10) { $LocalSec  = "0$LocalSec"  }

# -64 or not
$OBJECT_MODEL = $Model ? "64" : "32" if(defined($Model));
$ENV{OBJECT_MODEL} = $OBJECT_MODEL ||= $ENV{OBJECT_MODEL} || "32";

# platform
if($^O eq "MSWin32")    { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64"       : "win32_x86"       }
elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc"   }
elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64"   : "aix_rs6000"      }
elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64"       : "hpux_pa-risc"    }
elsif($^O eq "linux")   { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64"       : "linux_x86"       }

# -m=r or ...
$BUILD_MODE = $ENV{BUILD_MODE} || "release" unless($BUILD_MODE);
if($ENV{BUILD_MODE}) {
        if( ($BUILD_MODE) && ($BUILD_MODE ne $ENV{BUILD_MODE}) ) {
            &Usage("\n-m=$BUILD_MODE is different than the environment variable BUILD_MODE=$ENV{BUILD_MODE}, to not mix, $0 exit now")
        }
}
if("debug"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="debug";
} elsif("release"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="release";
} elsif("releasedebug"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="releasedebug";
} else {
    &Usage("compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease|releasedebug]");
}

#prepare status if fetch
$LocaRep = ($^O eq "MSWin32") ? "C:/core.build.tools" : "$ENV{HOME}";
$PomFetch = 0;
$newGreatestFound = 0;
$testIni = 0;
($Config) =~ s-\\-\/-g;
my $iniBase = basename($Config);
push(@Inis,$iniBase);
&listAllInisIncluded($Config);
$FetchDone = 0;

#MAIL
$SMTP_SERVER    ||= "mail.sap.corp";
$SMTPFROM       ||= "bruno.fablet\@sap.com";
$SMTPTO         ||= "bruno.fablet\@sap.com";

$cmdRebuild = "perl $cbtPath/rebuild.pl -i=$Config";
$cmdRebuild .= $QsetLine if($QsetLine);



##############################################################################
##### MAIN

&startScript();

chdir($cbtPath) or die("ERROR : cannot chdir into $cbtPath : $!\n");
############
### 0 get some info
    # 0.1 get some build info
$DROP_DIR   = `$cmdRebuild -si=dropdir`;
chomp($DROP_DIR);
$OUTLOG_DIR = `$cmdRebuild -si=logdir`;
chomp($OUTLOG_DIR);
$Context    = `$cmdRebuild -si=context`;
chomp($Context);
$PROJECT    = `$cmdRebuild -si=project`;
chomp($PROJECT);
$ENV{PROJECT} = $PROJECT;

require Site;
    # 0.2 set jenkins infos
#jenkins
if($jenkins) {
    $JENKINS_DIR        = $ENV{JENKINS_DIR}     || "c:/jenkins" ;
    $JENKINS_JOB        = $ENV{JENKINS_JOBS}    || "$Context" ;
    if(open(VERSION,"$JENKINS_DIR/jobs/$JENKINS_JOB/nextBuildNumber")) {
        while(<VERSION>) {
            chomp;
            $JENKINS_BUILD_VERSION = int($_);
            last;
        }
        close(VERSION);
    }
    $JENKINS_BUILD_VERSION ||=2;
    $JENKINS_BUILD_VERSION = $JENKINS_BUILD_VERSION - 1;
}
    #0.3 versioning
&Versioning();

############
### 1 bootstrap
if($ENV{P4PORT}) {
    $P4PORT = $ENV{P4PORT};
} else {
    $P4PORT = ($^O eq "MSWin32") ? "perforceproxy0.wdf.sap.corp:21971" : "ldm078.wdf.sap.corp:21971";
} 
$ENV{P4PORT} = $P4PORT;
    # 1.1 get user
&getP4User();
    # 1.2 login p4
require Perforce;
$p4 = new Perforce;
eval { $p4->Login("-s") };
    # 1.3 get boot strap clientspec
$bootStrapClientSpec = "${P4USER}_$HOST";
$p4->SetClient($bootStrapClientSpec);

if(($fetchTime) && ($txtFile)) { # restore bootstrap to the previous update to ensure all bootstrap are aligned
    #1.3.1 determine previous day to fetch
    my $numericDate = &TransformDateTimeToSeconds("$LocalYear/$LocalMonth/$LocalDay","$fetchTime");
    my $minusOneday = 24 * 3600 ; # 1 day in seconds
    my $dayBeforeInSec = $numericDate - $minusOneday;
    my $fetchDateTime = &FormatDate($dayBeforeInSec);
    #1.3.2 due to p4 limit, need to fetch one by one
    $p4->client("-o"," > $cbtPath/bootstrapClientSpec.log 2>&1");
    my @P4SCMS;
    if(open(BOOTSTRAP,"$cbtPath/bootstrapClientSpec.log")) {
        my $startView = 0;
        while(<BOOTSTRAP>) {
            chomp;
            s-^\s+$--g;
            next unless($_);
            next if(/^\#/); #skip comments
            if(/^View\:/i) {
                $startView = 1;
                next;
            }
            if($startView == 1) {
                (my $p4path) = $_ =~ /^\s+(.+?)\s+/;
                ($p4path) =~ s/^\+// if($p4path =~ /^\+/);
                next unless( ($p4path =~ /\.ini$/i) || ($p4path =~ /\/pom\.xml$/i) );
                push(@P4SCMS,$p4path);
            }
        }
        close(BOOTSTRAP);
    }
    if(scalar(@P4SCMS)>0) {
        print "\nsync $bootStrapClientSpec at $fetchDateTime\n";
        #(my $fetchDateTime2 = $fetchDateTime) =~ s-\/|\:-_-g;
        #print "$fetchDateTime -> $fetchDateTime2\n";
        system("rm -f $cbtPath/fetch_back_bootstrap.log") if( -e "$cbtPath/fetch_back_bootstrap.log");
        foreach my $p4scm (sort(@P4SCMS)) {
            print "${p4scm}\@$fetchDateTime,$fetchDateTime\n";
            $p4->sync("", " ${p4scm}\@$fetchDateTime,$fetchDateTime >> $cbtPath/fetch_back_bootstrap.log 2>&1");
        }
        print "\n";
    }
}

print "bootstrap : $bootStrapClientSpec\n";
    # 1.4 perform a simple sync of bootstrap
system("rm -f $cbtPath/bootstrap.log") if( -e "$cbtPath/bootstrap.log");
if($noSync) {
    $p4->sync("-n", " >$cbtPath/bootstrap.log 2>&1");
} else {
    if($elements) {
        ($elements) =~ s-,- -g;
        print "sync $elements\n";
        $checkIni = 1 if($elements =~ /\.ini/i); # set -ci if ini file detected in $elements and user forgot to set -ci
        $p4->sync("-f", " $elements >$cbtPath/bootstrap.log 2>&1"); # force sync to ensure to test $elements
    }
    if($paramChangelist) {
        @Changelists = split(',',$paramChangelist);
        foreach my $cl (sort{$a <=> $b}(@Changelists)) {
            print "sync $cl\n";
            $p4->sync("-f", " //...\@$cl,$cl >>$cbtPath/bootstrap.log 2>&1"); # force sync to ensure to test the changelist
        }
    }
    unless(($elements) && ($paramChangelist)) {
        $p4->sync("", " >$cbtPath/bootstrap.log 2>&1");
        if($justSyncBootstrap) {
            print "\n";
            print "-jsb detected, no fetch test to do\n";
            system("cat $cbtPath/bootstrap.log");
            $Status = "no" ;
            unless($ForceBuildPL) {
                goto CHKDEPS if($optCheckDep);
                &endScript();
            }
        }
    }
}
    # 1.5 scan log
if(open(SYNCLOG,"$cbtPath/bootstrap.log")) {
    while(<SYNCLOG>) {
        chomp;
        my $line = $_ ;
        ($line) =~ s-\s+as\s+- - if($line =~ /\s+as\s+/i);
        if($line =~ /\/pom.xml\#/i) {
            my ($pomSync,$fileVersion,$action,$fileInDisk) = $line =~ /^(.+?)\#(.+?)\s+\-\s+(.+?)\s+(.+?)$/i;
            $POMS{$pomSync}{version}    = $fileVersion;
            $POMS{$pomSync}{action}     = $action;
            $POMS{$pomSync}{submitter}  = &getSubmitter($pomSync);
            $POMS{$pomSync}{changelist} = &getCL($pomSync);
            $POMS{$pomSync}{file}       = $fileInDisk;
        }
        if($checkIni) {
            if($line =~ /\.ini\#/i) {
                my ($iniSync,$iniVersion,$iniAction,$iniFileInDisk) = $line =~ /^(.+?)\#(.+?)\s+\-\s+(.+?)\s+(.+?)$/i;
                my $fileName = basename($iniFileInDisk);
                if(grep(/^$fileName$/, @Inis)) {
                    $InisToTest{$iniSync}{version}      = $iniVersion;
                    $InisToTest{$iniSync}{action}       = $iniAction;
                    $InisToTest{$iniSync}{submitter}    = &getSubmitter($iniSync);
                    $InisToTest{$iniSync}{changelist}   = &getCL($iniSync);
                    $InisToTest{$iniSync}{file}         = $iniFileInDisk;
                    $testIni = 1;
                    $Status = "yes";
                }
            }
        }
    }
    close(SYNCLOG);
}
    #1.6 display & check pom(s) added/updated/deleted
if(%POMS) {
    $PomFetch = 1;
    $Status = "yes";
    print "\n";
    print "List of pom file(s) + check pom file(s):\n";
    print ("-" x (length("List of pom file(s) + check pom file(s):")),"\n");
    print "scm - version - action - submitter - changelist - file on HDD\n";
    push(@News,"<li><h3>poms added/updated/deleted:</h3></li>");
    foreach my $pom (sort(keys(%POMS))) {
        my $statusPom;
        unless($POMS{$pom}{action} eq "deleted") {
            $statusPom = &checkPom("$pom","$POMS{$pom}{version}","$POMS{$pom}{file}") if( -e "$POMS{$pom}{file}");
        }
        print "$pom - $POMS{$pom}{version} - $POMS{$pom}{action} - $POMS{$pom}{submitter} - $POMS{$pom}{changelist} - $POMS{$pom}{file}\n";
        my $line = "$pom - $POMS{$pom}{version} - $POMS{$pom}{action} - $POMS{$pom}{submitter} - $POMS{$pom}{changelist} - $POMS{$pom}{file}";
        if($statusPom) {
            print "staus validation : $statusPom\n\n";
            $line .= " - staus validation : $statusPom";
        }
        push(@News,$line);
    }
    print "\n";
} else {
    $PomFetch = 0;
    $Status ||="no";
    unless($ForceBuildPL) {
        if( (!($checkGreatest)) && (!($checkIni)) ) {
            goto CHKDEPS if($optCheckDep);
            &endScript()
        }
    }
}


############
### test fetch if needed
    # 2.1 check if test also greatest
if($checkGreatest) {
    my $thisContext = ( -e "$OUTLOG_DIR/Build/$Context.context.xml" )
                      ? "$OUTLOG_DIR/Build/$Context.context.xml"
                      : "$DROP_DIR/$Context/$refBuildNumber/contexts/allmodes/files/$Context.context.xml";
    &listCurrentGreatests("$thisContext");
    $newGreatestFound = &searchNewGreatests();
}
    # 2.2 display infos
print "\n";
if($jenkins) {
    print "jenkins dir  : $JENKINS_DIR\n";
    print "jenkins jobs : $JENKINS_JOB\n";
    print "jenkins build version : $JENKINS_BUILD_VERSION\n";
}
print "projet   : $PROJECT\n";
print "build    : $Context\n";
print "ini(s)   : @Inis\n";
print "version  : $BuildNumber\n";
print "platform : $PLATFORM\n";
print "mode     : $BUILD_MODE\n";
print "tmpdir   : $TEMPDIR\n";
if(%Greatests) {
    $Status = "yes";
    print "all greatest(s):\n";
    if(%newGreatests) {
        print "greatest(s) updated:\n";
        push(@News,"<li><h3>greatest(s) updated:</h3></li>");
        foreach my $greatest (sort(keys(%newGreatests))) {
            print "$greatest : $Greatests{$greatest} -> $newGreatests{$greatest}\n";
            push(@News,"$greatest : $Greatests{$greatest} -> $newGreatests{$greatest}");
        }
    }
    print "\ngreatest(s) not changed:\n";
    foreach my $greatest (sort(keys(%Greatests))) {
        print "$greatest : $Greatests{$greatest}\n";
    }
}
if(($checkGreatest) && ($newGreatestFound == 0)) {
    $Status ||= "no";
    print "no new greatest.\n\n";
    unless($ForceBuildPL) {
        if(($PomFetch==0) && ($testIni==0)) {
            goto CHKDEPS if($optCheckDep);
            &endScript()
        }
    }
}
if($checkIni) {
    if( ($testIni==1) && (scalar(keys(%InisToTest))>0) ) {
        $Status = "yes";
        print "ini(s) updated:\n";
        push(@News,"<li><h3>ini(s) updated:</h3></li>");
        foreach my $ini (keys(%InisToTest)) {
            print "$ini - $InisToTest{$ini}{version} - $InisToTest{$ini}{action} - $InisToTest{$ini}{submitter} - $InisToTest{$ini}{changelist} - $InisToTest{$ini}{file}\n";
            push(@News,"$ini - $InisToTest{$ini}{version} - $InisToTest{$ini}{action} - $InisToTest{$ini}{submitter} - $InisToTest{$ini}{changelist} - $InisToTest{$ini}{file}");
        }
    } else {
        if( ($PomFetch==0) && (($checkGreatest) && ($newGreatestFound == 0)) ) {
            print "no ini files, no included ini files updated.\n\n";
            $Status ||= "no";
            unless($ForceBuildPL) {
                goto CHKDEPS if($optCheckDep);
                &endScript()
            }
        }
    }
}

if($noSync) { #put this 'if' after display info, then can displays info even if nothing to do
    print "\nno test to perform, it was just a 'p4 -c $bootStrapClientSpec sync -n'.\n";
    $Status = "no";
    unless($ForceBuildPL) {
        goto CHKDEPS if($optCheckDep);
        &endScript()
    }
}

if($txtFile) {
    goto CHKDEPS if($optCheckDep);
    &endScript()
}

    # 2.3 delete previous logs generated by Build.pl
$LocaRep .= "/LocalRepos/$Context/$PLATFORM/$BUILD_MODE/repository";
unlink("$LocaRep/fill_repository.log")              if( -e "$LocaRep/fill_repository.log" );
unlink("$OUTLOG_DIR/Build/fetch_step.log")          if( -e "$OUTLOG_DIR/Build/fetch_step.log" );
unlink("$OUTLOG_DIR/Build/fetch_step.summary.txt")  if( -e "$OUTLOG_DIR/Build/fetch_step.summary.txt" );
    # 2.4 Fetch
$FetchCommand = "perl Build.pl -nonsd -nolego -d -lo=yes  -i=$Config -m=$BUILD_MODE -v=$BuildNumber";
$FetchCommand .= ($OBJECT_MODEL==64) ? " -64" : "";
$FetchCommand .= " -F" unless($NoBuildSync);
$FetchCommand .= " -I" if($Import);
$FetchCommand .= " -c=$ctime" if($ctime);
print "\nStart fetch test:\n";
print ("-" x (length("Start fetch test:")),"\n");
print "command  : $FetchCommand\n";
print "\n";
if((!($noSync)) && (!($NoBuildSync))){
    system("$FetchCommand > $OUTLOG_DIR/${BuildNumber}_Build.pl.log 2>&1");
    sleep(3);
    print "\n";
    if( -e "$OUTLOG_DIR/${BuildNumber}_Build.pl.log") {
        print "execution done, see content in $OUTLOG_DIR/${BuildNumber}_Build.pl.log\n";
    } else {
        print "execution NOT done.\n";
        my $titleMail = "[ROLLING FETCH][$PROJECT][$Context][$BuildNumber][$PLATFORM][$BUILD_MODE]";
        $titleMail   .= " : issue, Build.pl seems not executed";
        my $msgMail   = "<font color=\"red\"><strong>ERROR</strong></font>";
        $msgMail     .= " : $OUTLOG_DIR/${BuildNumber}_Build.pl.log does not exist.\n";
        &sendMailOnError($titleMail,$msgMail) if($MAIL);
    }
}
    # 2.5 save new log files generated by Build.pl
copy("$cbtPath/bootstrap.log","$OUTLOG_DIR/${BuildNumber}_bootstrap.log")                             if( -e "$cbtPath/bootstrap.log" );
copy("$LocaRep/fill_repository.log","$OUTLOG_DIR/${BuildNumber}_fill_repository.log")                 if( -e "$LocaRep/fill_repository.log" );
copy("$OUTLOG_DIR/Build/fetch_step.log","$OUTLOG_DIR/${BuildNumber}_fetch_step.log")                  if( -e "$OUTLOG_DIR/Build/fetch_step.log" );
copy("$OUTLOG_DIR/Build/fetch_step.summary.txt","$OUTLOG_DIR/${BuildNumber}_fetch_step.summary.txt")  if( -e "$OUTLOG_DIR/Build/fetch_step.summary.txt" );
    #2.6 check logs
unless($NoBuildSync) {
    if( -e "$OUTLOG_DIR/Build/fetch_step.summary.txt" ) {
        my $nbError = 0;
        if(open(SUMMARY,"$OUTLOG_DIR/Build/fetch_step.summary.txt")) {
            while(<SUMMARY>) {
                chomp;
                if(/\=\=\s+Sections\s+with\s+errors\:\s+(.+?)$/i) {
                    $nbError = $1;
                    next;
                }
                if(/Connection\s+timed\s+out/i) { #if connection timed out, skip it !
                    $nbError-- if($nbError >0);
                    next;
                }
            }
            close(SUMMARY);
            if($nbError > 0) {
                print "\n=> ERROR : Fetch with issue : see $OUTLOG_DIR/Build/fetch_step.summary.txt or $OUTLOG_DIR/Build/fetch_step.log.\n\n";
                system("cat \"$OUTLOG_DIR/Build/fetch_step.summary.txt\"");
                print "\n";
                my $content =`cat \"$OUTLOG_DIR/Build/fetch_step.summary.txt\"`;
                chomp($content);
                my $msg = "<br/><fieldset style=\"border-style:solid;border-color:black;border-size:1px\"><legend>Error(s) - fetch_step.summary.txt</legend><pre>\n";
                $msg .="$content\n";
                $msg .="</pre></fieldset>";
                my $titleMail  = "[ROLLING FETCH][$PROJECT][$Context][$BuildNumber][$PLATFORM][$BUILD_MODE]";
                $titleMail    .= " : issue detected during fetch";
                my $part2      = "<font color=\"red\"><strong>ERROR</strong></font>";
                $part2        .= " : Fetch with issue : see $OUTLOG_DIR/Build/fetch_step.summary.txt";
                $part2        .= " or $OUTLOG_DIR/Build/fetch_step.log.\n<br/>$msg";
                &sendMailOnError($titleMail,$part2) if($MAIL);
                exit 1;
            } else {
                print "\n=> PASSED : Fetch without any issue\n";
                $FetchDone = 1;
            }
        }
    } else {
        if( -e "$LocaRep/fill_repository.log" ) {
            print "\n=> ERROR : pom issue : no fetch, pom issue, see in $LocaRep/fill_repository.log.\n\n";
            system("cat \"$LocaRep/fill_repository.log\"");
            print "\n";
            my $content =`cat \"$LocaRep/fill_repository.log\"`;
            chomp($content);
            my $msg = "<br/><fieldset style=\"border-style:solid;border-color:black;border-size:1px\"><legend>Error(s) - fill_repository.log</legend><pre>\n";
            $msg .="$content\n";
            $msg .="</pre></fieldset>";
            my $titleMail  = "[ROLLING FETCH][$PROJECT][$Context][$BuildNumber][$PLATFORM][$BUILD_MODE]";
            $titleMail    .= " : issue detected during pom tree calculation";
            my $part2      = "<font color=\"red\"><strong>ERROR</strong></font>";
            $part2        .= " : pom issue : no fetch, pom issue, see in $LocaRep/fill_repository.log.\n<br/>$msg";
            &sendMailOnError($titleMail,$part2) if($MAIL);
        } else {
            if( -e "$OUTLOG_DIR/${BuildNumber}_Build.pl.log" ) {
                my $content =`cat \"$OUTLOG_DIR/${BuildNumber}_Build.pl.log\"`;
                chomp($content);
                my $msg = "<br/><fieldset style=\"border-style:solid;border-color:black;border-size:1px\"><legend>Error(s) - ${BuildNumber}_Build.pl.log</legend><pre>\n";
                $msg .="$content\n";
                $msg .="</pre></fieldset>";
                print "\n=> ERROR : $LocaRep/fill_repository.log does not exist, see in $OUTLOG_DIR/${BuildNumber}_Build.pl.log.\n\n";
                my $titleMail  = "[ROLLING FETCH][$PROJECT][$Context][$BuildNumber][$PLATFORM][$BUILD_MODE]";
                $titleMail    .= " : issue detected during Build.pl";
                my $part2      = "<font color=\"red\"><strong>ERROR</strong></font>";
                $part2        .= " : $LocaRep/fill_repository.log does not exist, see in $OUTLOG_DIR/${BuildNumber}_Build.pl.log.\n<br/>$msg";
                &sendMailOnError($titleMail,$part2) if($MAIL);
            } else {
                my $titleMail  = "[ROLLING FETCH][$PROJECT][$Context][$BuildNumber][$PLATFORM][$BUILD_MODE]";
                $titleMail    .= " : issue, Build.pl seems not executed";
                my $part2      = "<font color=\"red\"><strong>ERROR</strong></font>";
                $part2        .= " : $OUTLOG_DIR/${BuildNumber}_Build.pl.log does not exist.\n";
                &sendMailOnError($titleMail,$part2) if($MAIL);
            }
        }
        exit 1;
    }
} else {
    if( -e "$LocaRep/fill_repository.log" ) {
        print "\n=> Build.pl without '-F'.\n\n";
        system("cat \"$LocaRep/fill_repository.log\"");
        print "\n";
        my $content =`cat \"$LocaRep/fill_repository.log\"`;
        chomp($content);
    }
}

CHKDEPS:
if($optCheckDep) {
    unless($FetchCommand) {
        $FetchCommand = "perl Build.pl -nonsd -nolego -d -lo=yes  -i=$Config -m=$BUILD_MODE -v=$BuildNumber";
        $FetchCommand .= ($OBJECT_MODEL==64) ? " -64" : "";
        $FetchCommand .= " -F" unless($NoBuildSync);
        $FetchCommand .= " -I" if($Import);
        $FetchCommand .= " -c=$ctime" if($ctime);
    }
    print "\n check if circular dependency exist\n";
    &checkDeps();
    if(scalar(@statuscheckDep) > 0) {
        my $line;
        foreach my $error (@statuscheckDep) {
            $line .= "<strong><font color=\"red\">ERROR</font></strong></font> : $error<br/>"
        }
        my $titleMail  = "[ROLLING FETCH][$PROJECT][$Context][$BuildNumber][$PLATFORM][$BUILD_MODE]";
        $titleMail    .= " : check dep FAILED";
        &sendMailOnError($titleMail,"$line\n") if($MAIL);
        exit 1;
    }
}
&checkInit() if($optCheckInit);

if(($MAIL_UPDATE) && (scalar(@News)>0)) {
    my $titleMail  = "[ROLLING FETCH][$PROJECT][$Context][$BuildNumber][$PLATFORM][$BUILD_MODE]";
    if($FetchDone == 1) {
        $titleMail .= " : list of Updates, Fetch PASSED";
    } else {
        $titleMail .= " : list of Updates";
    }
    &sendMailUpdates($titleMail);
} else {
    print "\nnothing to send\n";
}
&endScript();



##############################################################################
### my functions
#p4
sub getP4User() {
    $P4USER = $ENV{P4USER} || (`p4 set P4USER`=~/^P4USER=(\w+)/,$1);
    $P4USER ||= ($^O eq "MSWin32") ? $ENV{USERNAME} : $ENV{USER};
    $P4USER ||= (`id` =~ /^\s*uid\=\d+\((.+?)\).*?/,$1);
    ($P4USER) = $P4USER =~ /^\s*(.+)\s*$/;
    $ENV{P4USER} ||= $P4USER;
}

sub getSubmitter($) {
    my ($p4File) = @_ ;
    my $res = $p4->filelog("-m 1 -t -L","$p4File | grep -w By");
    my $thisSubmitter;
    foreach (@{$res}) {
        if(/by\:\s+(.+?)$/i) {
            $thisSubmitter = $1;
            last;
        }
    }
    return $thisSubmitter if($thisSubmitter);
}

sub getCL($) {
    my ($p4File) = @_ ;
    my $res = $p4->filelog("-m 1 -t -s","$p4File | grep -w change");
    my $thisCL;
    foreach (@{$res}) {
        if(/\s+change\s+(\d+)\s+/i) {
            $thisCL = $1;
            last;
        }
    }
    return $thisCL if($thisCL);
}

#versioning
sub getBuildRev() {
    my $tmp = 0;
    if(open(VER, "$DROP_DIR/$Context/version.txt"))
    {
        chomp($tmp = <VER>);
        $tmp = int($tmp);
        close(VER);
    } else {# If version.txt does not exists or opening failed, instead of restarting from 1,
    #look for existing directory versions & generate the hightest version number
    #based on the hightest directory version
        # open current context dir to find the hightest directory version inside
        if(opendir(BUILDVERSIONSDIR, "$DROP_DIR/$Context")) {
            while(defined(my $next = readdir(BUILDVERSIONSDIR))) {
                $tmp = $1 if ($next =~ /^(\d+)(\.\d+)?$/ && $1 > $tmp && -d "$DROP_DIR/$Context/$next"); # Only take a directory with a number as name, which can be a number or a float number with a mandatory decimal value & optional floating point
            }   
            closedir(BUILDVERSIONSDIR);
        }
    }
    return $tmp;
}

sub setBuildRef() {
    my $versionFound = &getBuildRev();
    #if -r=. just '.' without number, get last incremental build and set it as reference
    if($refBuildNumber) {
        if($refBuildNumber =~ /^\.$/) {
            my $thisFullBuildNumber = sprintf("%05d", $versionFound);
            my $thisFullBuildNameVersion = "${Context}_$thisFullBuildNumber";       
            my $indice = &getLastIncremental($thisFullBuildNameVersion,$versionFound);
            if($indice>0) {
                $refBuildNumber = ".$indice"
            } else {
                $refBuildNumber = $versionFound;
            }
        }
        #if -r=.x if you want a specific incremntal version as reference
        if($refBuildNumber =~ /^\.\d+$/) {
            $refBuildNumber = "${versionFound}$refBuildNumber";
        }
    } else { #if not -r=xxx
        $refBuildNumber = $versionFound;
    }
}

sub getLastIncremental($$) {
    # if -v=+ or -v=++, need to know the last incremental build before increment it
    my ($fullBuildNameVersion,$refVersion) = @_;
    my $localIndice=0;
    if(opendir(BUILDVERSIONSDIR, "$ENV{HTTP_DIR}/$Context")) {
        my $fullBuildNumber = sprintf("%05d", $refVersion);
        my $fullBuildNameVersion = "${Context}_$fullBuildNumber";
        while(defined(my $buildNameVersion = readdir(BUILDVERSIONSDIR))) {
            next if( $buildNameVersion =~ /^\./ );
            next if( -f "$ENV{HTTP_DIR}/$Context/$buildNameVersion" );
            if($buildNameVersion =~ /$fullBuildNameVersion/) {
                if($buildNameVersion =~ /\.(\d+)$/) {
                    $localIndice = $1 if($1 > $localIndice);
                }
            }
        }
        closedir(BUILDVERSIONSDIR);
    }
    return  $localIndice;   
}

sub Versioning() {
    &setBuildRef();
    if(($jenkins) && ($JENKINS_BUILD_VERSION)) {
        $BuildNumber ||= "${refBuildNumber}.$JENKINS_BUILD_VERSION";
    } else {
        if($BuildNumber) {
            #if -v=.x
            if($BuildNumber =~ /^\.(\d+)$/) {
                my $inc = $1;
                if($refBuildNumber =~ /\.\d+$/) {
                    my $tmp = $refBuildNumber;
                    $tmp =~ s-\.\d+$--;
                    $BuildNumber = "${tmp}.$inc";
                } else {
                    $BuildNumber = "${refBuildNumber}.$inc";
                }
            }
        
            # full version with 000, needed for the full path of dat file
            my $fullBuildNumber = sprintf("%05d", $refBuildNumber);
            my $fullBuildNameVersion = "${Context}_$fullBuildNumber";
            #if -v=+
            if($BuildNumber =~ /^\+$/) {
                my $indice = &getLastIncremental($fullBuildNameVersion,$refBuildNumber);
                my $incremental = $indice + 1;
                my $tmp = $refBuildNumber;
                ($tmp) =~ s-\.\d+$--;
                my $tmp2;
                if($indice>0) {
                    $tmp2 = "${Context}_${fullBuildNumber}.$indice";
                } else {
                    $tmp2 = "${Context}_${fullBuildNumber}";
                }
                my $currentDatFile = "$ENV{HTTP_DIR}/$Context/$tmp2/${tmp2}=${PLATFORM}_${BUILD_MODE}_build_1.dat";
                ($currentDatFile) =~ s-\\-\/-g ;
                # check if previous build/incremental build was done, if yes, then increment
                if( -e $currentDatFile ) {
                    $BuildNumber = "${tmp}.$incremental";
                } else {
                    $BuildNumber = "${tmp}.$indice";
                }
            }
        
            #if -v=++
            if($BuildNumber =~ /^\+\+$/) {
                my $indice = &getLastIncremental($fullBuildNameVersion,$refBuildNumber);
                my $incremental = $indice + 1;
                my $tmp = $refBuildNumber;
                ($tmp) =~ s-\.\d+$--;
                $BuildNumber = "${tmp}.$incremental";
            }
        } else {
            $BuildNumber ||= "$refBuildNumber.${LocalHour}${LocalMin}${LocalSec}";
        }
    }
}

#divers
sub checkPom($$$) {
    my ($p4PomFile,$version,$hddPomFile) = @_;
    # 1 check if valid xml 
    my $xmlValidStatus = 0;
    my $parser= new XML::Parser();
    my $resume;
    eval {$parser->parsefile( $hddPomFile )};
    if ($@) { $resume = $@ }
    else    { $resume = "xml syntax valid PASSED"; $xmlValidStatus = 1  }
    if($xmlValidStatus == 1) {
        my ($depot,$p4area,$p4version,$p4branch) = $p4PomFile =~ /^\/\/(.+?)\/(.+?)\/(.+?)\/(.+?)\//;
        my $group = "com.sap";
        $group .=".tp" if($p4area =~ /^tp\./);
        my $POM = XML::DOM::Parser->new()->parsefile("$hddPomFile");
        my $pomGroup    = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("groupId", 0)->item(0)->getFirstChild()->getData();
        my $artifactId  = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("artifactId", 0)->item(0)->getFirstChild()->getData();
        my $name        = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("name", 0)->item(0)->getFirstChild()->getData();
        my $scm         = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("scm")->item(0)->getElementsByTagName("connection", 0)->item(0)->getFirstChild()->getData();
        $POM->dispose();
        ($scm) =~ s-^scm\:perforce\:\$Id\:\s+--;
        my ($scmVersion) = $scm =~ /\#(.+?)\s+\$$/;
        ($scm) =~ s-\#.+?$--;
        my ($scmDepot,$scmP4area,$scmP4version,$scmB4branch) = $scm =~ /^\/\/(.+?)\/(.+?)\/(.+?)\/(.+?)\//;
        #checks
        if($group ne $pomGroup) {
            $resume .= " - WARNING group : $pomGroup not ok, should be $group";
        }
        if($p4area ne $artifactId) {
            $resume .= " - WARNING artifactId '$artifactId' not ok, should be $p4area";
        }
        if($artifactId ne $name) {
            #$resume .= " - WARNING name '$name' not ok, should be $p4area";
        }
        if($p4area ne $scmP4area) {
            $resume .= " - WARNING area '$scm' not ok, should be $p4area";
        }
        if($p4version ne $scmP4version) {
            $resume .= " - WARNING version '$scmP4version' not ok, should be $p4version";
        }
        if($p4branch ne $scmB4branch) {
            $resume .= " - WARNING branch '$scmB4branch' not ok, should be $p4branch";
        }
        if(($version ne $scmVersion) && (!($noSync)) ) {
            $resume .= " - WARNING file version '$scmVersion' not ok, should be $version";
        }
    }
    return $resume;
}

sub listCurrentGreatests($) {
    my ($XMLContext) = @_;
    my $CONTEXT = XML::DOM::Parser->new()->parsefile($XMLContext);
    for my $SYNC (@{$CONTEXT->getElementsByTagName("fetch")})
    {
        my($thisGreatest, $thisVersion) = ($SYNC->getAttribute("logicalrev"), $SYNC->getAttribute("buildrev"));
        next unless($thisGreatest =~ /greatest.xml$/);
        ($thisGreatest) =~ s-^\=--;
        ($thisGreatest) =~ s-\\-\/-g;
        my ($buildRev) = $thisVersion =~ /\.(\d+)$/;
        $Greatests{$thisGreatest} = $buildRev;
    }
    $CONTEXT->dispose();
}

sub searchNewGreatests() {
    if(%Greatests) {
        foreach my $greatest (sort(keys(%Greatests))) {
            my ($buildRev) = $Greatests{$greatest};
            my $buildDir = dirname( $greatest );
            my $CONTEXT = XML::DOM::Parser->new()->parsefile($greatest);
            my ($versionInContext) = $CONTEXT->getElementsByTagName("version")->item(0)->getFirstChild()->getData() =~ /\.(\d+)$/;
            $CONTEXT->dispose();
            if($buildRev ne $versionInContext) {
                $newGreatests{$greatest} = $versionInContext;
            }
        }
    }
    return 1 if(%newGreatests);
}

sub listAllInisIncluded($) {
    my ($iniFile) = @_ ;
    my $iniName = basename($iniFile);
    my @initsFound;
    if(open(INI,$iniFile)) {
        while(<INI>) {
            chomp;
            s-\${CURRENTDIR\}-$CURRENTDIR- if(/CURRENTDIR/);
            if(/^\#include\s+(.+?)$/) {
                my $iniFileFound = $1;
                my $initFound = basename($iniFileFound);
                push(@Inis,$initFound);
                push(@initsFound,$iniFileFound);
            }
        }
        close(INI);
        foreach my $ini (@initsFound) {
            &listAllInisIncluded($ini);
        }
    }
}

sub getFullNameMachine() {
    open(NSLOOKUP,"nslookup DEWDFTH0425GM 2>&1 | grep Name |");
    while(<NSLOOKUP>) {
        chomp;
        ($FULLNAME_HOST) = $_ =~ /^Name\:\s+(.+?)$/;
    }
    close(NSLOOKUP);
}

sub sendMailOnError($$) {
    my ($title,$msg) = @_ ;
    if(open(HTML, ">${BuildNumber}_Mail_RollingFetch.html")) {
        print HTML '
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <title>',$title,'</title>
    <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
    <meta http-equiv="content-language" content="fr" />
</head>
<body>
<br/><br/>
';
        if(scalar(@News)>0) {
            print HTML "<h1>What's new :</h1><br/>\n";
            print HTML "<ul>\n";
            foreach my $new (@News) {
                if($new =~  /\<li\>/) {
                    print HTML "$new\n";
                } else {
                    print HTML "$new<br/>\n";
                }
            }
            print HTML "</ul>\n";
            print HTML "<br/><br/>\n";
        }       
        print HTML '
command executed : ',$FetchCommand,'<br/><br/>
',$msg,'<br/><br/>
Link(s):<br/>
<table border="0">
<tr><td>CIS Dashboard</td><td><a href="http://cis_wdf.pgdev.sap.corp:1080/cgi-bin/CIS.pl?streams=',$Context,'&projects=',$PROJECT,'">',$Context,'</a></td><td>',$BuildNumber,'</td></tr>';
    if($jenkins) {
        print HTML '
<tr><td>Jenkins</td><td><a href="http://',$FULLNAME_HOST,':8080/job/',$Context,'/',$JENKINS_BUILD_VERSION,'">',$HOST,'</a></td><td>',$JENKINS_BUILD_VERSION,'</td></tr>
</table>
<br/><br/>
</body>
</html>
';
        }
        close(HTML);
        if(open(HTML, "${BuildNumber}_Mail_RollingFetch.html")) {
            my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>120) or die("ERROR: SMTP connection impossible: $!");
            $smtp->mail($SMTPFROM);
            $smtp->to(split('\s*;\s*', $SMTPTO));
            $smtp->data();
            map({$smtp->datasend("To: $_\n")} split('\s*;\s*', $SMTPTO));
            $smtp->datasend("Subject: $title\n");
            $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=${BuildNumber}_Mail_RollingFetch.html\n");
            while(<HTML>) { $smtp->datasend($_) } 
            close(HTML);
            $smtp->dataend();
            $smtp->quit();
            print "mail (on error) sent to $SMTPTO\n";
        }
    }
}

sub sendMailUpdates($) {
    my ($title) = @_;
    if(open(HTML, ">${BuildNumber}_MailUpdate_RollingFetch.html")) {
        print HTML '
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <title>',$title,'</title>
    <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
    <meta http-equiv="content-language" content="fr" />
</head>
<body>
<br/><br/>
';
        if(scalar(@News)>0) {
            print HTML "<u>What's new :</u><br/>\n";
            foreach my $new (@News) {
                print HTML "$new<br/>\n";
            }
            print HTML "<br/><br/>\n";
        }       
        if($FetchDone == 1) {
        print HTML '
command executed : ',$FetchCommand,' => <strong><font color="green">PASSED</font></strong><br/>
<br/><br/>';
        }
        print HTML '
Link(s):<br/>
<table border="0">
<tr><td>CIS Dashboard</td><td><a href="http://cis_wdf.pgdev.sap.corp:1080/cgi-bin/CIS.pl?streams=',$Context,'&projects=',$PROJECT,'">',$Context,'</a></td><td>',$BuildNumber,'</td></tr>';
    if($jenkins) {
        print HTML '
<tr><td>Jenkins</td><td><a href="http://',$FULLNAME_HOST,':8080/job/',$Context,'/',$JENKINS_BUILD_VERSION,'">',$HOST,'</a></td><td>',$JENKINS_BUILD_VERSION,'</td></tr>
</table>
<br/><br/>
</body>
</html>
';
        }
        close(HTML);
        if(open(HTML, "${BuildNumber}_MailUpdate_RollingFetch.html")) {
            my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>120) or die("ERROR: SMTP connection impossible: $!");
            $smtp->mail($SMTPFROM);
            $smtp->to(split('\s*;\s*', $SMTPTO));
            $smtp->data();
            map({$smtp->datasend("To: $_\n")} split('\s*;\s*', $SMTPTO));
            $smtp->datasend("Subject: $title\n");
            $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=${BuildNumber}_MailUpdate_RollingFetch.html\n");
            while(<HTML>) { $smtp->datasend($_) } 
            close(HTML);
            $smtp->dataend();
            $smtp->quit();
            print "mail (on update) sent to $SMTPTO\n";
        }
    }
}

sub checkDeps(){
    my $SRC_DIR = `$cmdRebuild -si=src_dir`;
    chomp($SRC_DIR);
    my $gmk= `$cmdRebuild -si=makefile`;
    chomp($gmk);
    if( -e "$gmk" ) {
        if ( -e "$cbtPath/checkDeps_${Context}_$OBJECT_MODEL.log" ) {
            system("rm -f \"$cbtPath/checkDeps_${Context}_$OBJECT_MODEL.log\" > $NULLDEVICE 2>&1"); 
        }
        system("perl $cbtPath/MultiProc.pl -noi -noe -g=\"$gmk\" -s=\"$SRC_DIR\" > $cbtPath/checkDeps_${Context}_$OBJECT_MODEL.log 2>&1");
        if ( -e "$cbtPath/checkDeps_${Context}_$OBJECT_MODEL.log" ) {
            if(open(CHKDEP,"$cbtPath/checkDeps_${Context}_$OBJECT_MODEL.log")) {
                while(<CHKDEP>) {
                    chomp;
                    if(/^ERROR\:/i) {
                        print "$_\n";
                        my $line = $_;
                        ($line) =~ s-^ERROR\:\s+--;
                        push(@statuscheckDep,$line);
                    }
                }
                close(CHKDEP);
            }
        }

    } else {
        print "WARNING : $gmk not found\n";
    }
}

sub checkInit() {
    my $initTarget= `$cmdRebuild -si=build| grep -w init`;
    chomp($initTarget);
    if($initTarget) {
        chdir($cbtPath) or die("ERROR : cannot chdir into $cbtPath : $!\n");
        my $buildCmd = "perl Build.pl -nonsd -nolego -d -lo=yes  -i=$Config -m=$BUILD_MODE -v=$BuildNumber";
        $buildCmd .= ($OBJECT_MODEL==64) ? " -64" : "";
        $buildCmd .= " -t=init -B";
        print "\n";
        system("$buildCmd");
        print "\n";
        my $nbError = 0;
        if(open(INIT_SUMMARY,"$OUTLOG_DIR/Build/init.summary.txt")) {
            while(<INIT_SUMMARY>) {
                chomp;
                if(/\=\= Sections\s+with\s+errors\:\s+(\d+)/i) {
                    $nbError = $1;
                    last;
                }
            }
            close(INIT_SUMMARY);
            if($nbError > 0) {
                print "\n";
                system("cat $OUTLOG_DIR/Build/init.summary.txt");
                print "\n";
            } else {
                print "\n";
                print "no error found\n";
                print "\n";
            }
        } else {
            print "\nERROR : cannot open $OUTLOG_DIR/Build/init.summary.txt\n";
        }
    } else {
        print"\nMessage : no init target found in $Config\n";
    }
}

sub TransformDateTimeToSeconds($$) {
    my ($Date2,$Time2) = @_;
    my ($hour,$min,$sec) = $Time2 =~ /^(\d+)\:(\d+)\:(\d+)$/;
    my ($Year,$Month,$Day) = $Date2 =~ /^(\d+)\/(\d+)\/(\d+)$/;
    $Month = $Month - 1;
    #print "$Date,$Time => $sec,$min,$hour,$Day,$Month,$Year\n";
    my @temps = ($sec,$min,$hour,$Day,$Month,$Year);
    # 051104 6:30:12)
    return timelocal(@temps);
}

sub FormatDate
{
    my ($Time) = @_;
    my($ss, $mn, $hh, $dd, $mm, $yy, $wd, $yd, $isdst) = localtime($Time);
    return sprintf("%04u/%02u/%02u:%02u:%02u:%02u", $yy+1900, $mm+1, $dd, $hh, $mn, $ss);
}

#my generic functions
sub startScript() {
    my $dateStart = scalar(localtime);
    print "\nSTART of '$0' at $dateStart\n";
    print ("#" x (length("START of '$0' at $dateStart")),"\n");
    print "\n";
}

sub endScript() {
    $p4->Final() if($p4);
    if($txtFile) {
        my $HOST2 = lc($HOST);
        $txtFile = "$cbtPath/${HOST2}_${Context}_$OBJECT_MODEL.txt";
        if( -e "$txtFile" ) {
            unlink("$txtFile") or die("ERROR :  cannot delete $txtFile : $!");
        }
        open(TXT,">$txtFile") or die("ERROR : cannot create $txtFile : $!");
            $Status ||= "no";
            print TXT "$Status";
        close(TXT);
        eval { mkpath("$DROP_DIR/$Context/$refBuildNumber") or warn("WARNING : cannot mkpath '$DROP_DIR/$Context/$refBuildNumber': $!") } unless(-e "$DROP_DIR/$Context/$refBuildNumber");
        if( -e "$DROP_DIR/$Context/$refBuildNumber" ) {
            copy("$txtFile","$DROP_DIR/$Context/$refBuildNumber/${HOST2}_${Context}_$OBJECT_MODEL.txt") or warn("WARNING : cannot copy $txtFile to $DROP_DIR/$Context/$refBuildNumber/${HOST2}_${Context}_$OBJECT_MODEL.txt : $!\n");
            print "\nsee $DROP_DIR/$Context/$refBuildNumber/${HOST2}_${Context}_$OBJECT_MODEL.txt\n" if ( -e "$DROP_DIR/$Context/$refBuildNumber/${HOST2}_${Context}_$OBJECT_MODEL.txt" );
        } else {
            print "\nsee $txtFile\n";
        }
    }
    print "\n\n";
    my $dateEnd = scalar(localtime);
    print ("#" x (length("END of '$0' at $dateEnd")),"\n");
    print "END of '$0' at $dateEnd\n";
    exit 0;
}

sub Usage($) {
    my ($msg) = @_ ;
    if($msg)
    {
        print STDERR "
\tERROR:
\t======
$msg

";
    }
    print "
    Description : $0 can test a fetch when a pom file or ini file is updated in the bootstrap clientspec.
It can also test a fetch when a new greatest is detected (accordling with the ini file).
This tools was done to try to catch potential issues and fix/avoid them before the start of the nightly build.
    Usage   : perl $0 [options]
    Example : perl $0 -h

 [options]
    -h|?    argument displays helpful information about builtin commands.
    -i  choose an ini file, syntax: -i=contexts/buildname.ini.
    -64 force the 64 bits fetch (-64) or not (-no64), default is -no64 i.e 32 bits,
        same usage than Build.pl.
    -m  choose a compile mode.
        same usage than Build.pl -m=.
    -v  choose a version, usages:
        -v=xxx
        -v=xxx.y
        -v=.y
        -v=+ (auto increment the minor version, .y only if the .'y-1' incremental build was done)
        -v=++ (FORCE auto increment the minor version, .y)
        by default -v=xxx.hhmmss,
        executed through jenkins, the default is : -v=xxx.jenins_build_version.
    -n  no sync of bootstrap (no fetch also).
    -cg check if new greatest.
    -ci check if ini and included ini files updated.
    -M  send mail only on error.
    -UM send mail even if the fetch test is passed.
    -smtp   smtp server, by default -smtp=mail.sap.com.
    -from   mail sent from, by default -from=bruno.fablet\@sap.com.
    -to mail sent to, list seperated by ';', by default -to=bruno.fablet\@sap.com.
    -elem   specific element(s) to test (ini files, pom files), separate by a comma (,),
        a force sync will be done on these specific element(s),
        e.g.: -elem=//product/aurora/4.1/REL/export/shared/contexts/aurora41_sp_cor.ini,//product/aurora/4.1/SP_COR/pom.xml
    -cl specific changelist(s) to test (ini, pom files), separate by a comma (,),
        a force sync will be done on these specific changelist(s),
        sync order: from the oldest to the latest changelist,
        e.g.: -cl=5,4,6,2 , sync order : 2,4,5,6
    -jsb    just sync the bootstrap without any fetch test, no mail sent.
    -ns Build.pl just calculates the clientspec, no '-F'.
    -fb even if no change/update, execute Build.pl

";
    exit 0;
}
