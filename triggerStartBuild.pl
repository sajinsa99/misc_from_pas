##############################################################################
##### declare uses
use strict;
use warnings;
use diagnostics;

use Getopt::Long;
use Sys::Hostname;

use FindBin;
use lib ($FindBin::Bin, "$FindBin::Bin/site_perl");

use File::Basename;

use XML::Parser;
use XML::DOM;



##############################################################################
##### declare vars
use vars qw(
        $Model
        $OBJECT_MODEL
        $PLATFORM
        $BUILD_MODE
        $cbtPath
        $iniPath
        $CURRENTDIR
        $HOST
        $Context
        $P4CLIENT
        @P4PathsToScan
        $flag
        $Help
        $Project
        $CurrentVersion
        $NewVersion
        $p4
        $OUTLOG_DIR
        $DROP_DIR
        $IMPORT_DIR
        $HTTP_DIR
        %Greatests
        %newGreatests
        @Inis
        $startOnlyIfNewGreatestIni
        $paramIni
        $shortStatus
        @QSets
        $QsetLine
        $cmdRebuild
       );



##############################################################################
##### declare functions
sub Syntax($);
sub checkIfRecentFile($);
sub listAllInisIncluded($);
sub getBuildRev();



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "64!"    =>\$Model,
    "om=s"   =>\$OBJECT_MODEL,
    "m=s"    =>\$BUILD_MODE,
    "i=s"    =>\$paramIni , 
    "b=s"    =>\$Context , 
    "p=s"    =>\$Project ,
    "c=s"    =>\$P4CLIENT ,
    "help|?" =>\$Help,
    "ngio"   =>\$startOnlyIfNewGreatestIni,
    "s"      =>\$shortStatus,
);
            
&Syntax("") if($Help);
&Syntax("ERROR: no clientspec specified") if( (!($Context)) && (!($paramIni)) );

my (@P4PathsToScan) = @ARGV;



##############################################################################
##### init vars

# environment vars
if(scalar(@QSets>0)) {
    foreach (@QSets) {
        my($Variable, $String) = /^(.+?):(.*)$/;
        $ENV{$Variable} = $String;
        $QsetLine .= " -q=$Variable:$String";
    }
}


$OBJECT_MODEL ||= $Model ? "64" : "32" if(defined($Model));
$ENV{OBJECT_MODEL} = $OBJECT_MODEL ||= $ENV{OBJECT_MODEL} || "32";

if   ($^O eq "MSWin32") { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64"       : "win32_x86"       }
elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc"   }
elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64"   : "aix_rs6000"      }
elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64"       : "hpux_pa-risc"    }
elsif($^O eq "linux")   { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64"       : "linux_x86"       }
elsif($^O eq "darwin")  { $PLATFORM = $OBJECT_MODEL==64 ? "mac_x64"         : "mac_x86"         }


$BUILD_MODE ||= $ENV{BUILD_MODE} || "release";
if($ENV{BUILD_MODE}) {
    if(($BUILD_MODE) && ($BUILD_MODE ne $ENV{BUILD_MODE})) {
        print "\n-m=$BUILD_MODE is different than the environment variable BUILD_MODE=$ENV{BUILD_MODE}, to not mix, $0 exit now\n";
        exit;
    }
}
if("debug"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="debug"
} elsif("release"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="release"
} elsif("releasedebug"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="releasedebug"
} else {
    &Usage("compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease|releasedebug]");
}

$cbtPath = $ENV{CBTPATH} if($ENV{CBTPATH});
$cbtPath ||= ($^O eq "MSWin32")
             ? "c:/core.build.tools/export/shared"
             : "$ENV{HOME}/core.build.tools/export/shared";
die("ERROR : $cbtPath not found\n") if( ! -e $cbtPath );
chdir($cbtPath) or die("ERROR : cannot chdir into $cbtPath : $!\n");
$iniPath = $ENV{INIPATH} || "$cbtPath/contexts"; #new (git) system or p4 system

$HOST = hostname();
$CURRENTDIR = $FindBin::Bin;

if($paramIni) {
    ($paramIni) =~ s-\\-\/-g;
} else {
    unless($Context) {
        &Syntax("ERROR : -i=ini_file or -b=build_name missed");
    } else {
        $paramIni ||="$iniPath/$Context.ini";
    }
}

chdir($cbtPath) or die("ERROR : cannot chdir into $cbtPath : $!\n");
$cmdRebuild = "perl $cbtPath/rebuild.pl -i=$paramIni";
$cmdRebuild .= $QsetLine if($QsetLine);

unless($Context) {
    $Context = `$cmdRebuild -si=context`;
}

if( -e "$paramIni") {
    $P4CLIENT = `$cmdRebuild -si=clientspec`;
    chomp($P4CLIENT);
} else {
    if( ($Context) && !($P4CLIENT) ) {
        $P4CLIENT ||= "${Context}_$HOST"
    }
}

unless($Project) {
    $Project = `$cmdRebuild -si=project`;
    chomp($Project);
}

if(defined($Project)) {
    $ENV{PROJECT}=$Project;
    delete $ENV{DROP_DIR};
    delete $ENV{DROP_NSD_DIR};
    delete $ENV{IMPORT_DIR}
}
require Site;

$HTTP_DIR = $ENV{HTTP_DIR} ;

#get current version
if(open(VER, "$ENV{'DROP_DIR'}/$Context/version.txt")) {
    chomp($CurrentVersion = <VER>);
    $CurrentVersion = int($CurrentVersion);
    close(VER);
    $NewVersion = $CurrentVersion + 1;
}

#list all greatests used by $Context
$DROP_DIR   = `$cmdRebuild -si=dropdir`;
chomp($DROP_DIR);
($DROP_DIR) =~ s-\\-\/-g;
$IMPORT_DIR = `$cmdRebuild -si=importdir`;
chomp($IMPORT_DIR);
($IMPORT_DIR) =~ s-\\-\/-g;
$OUTLOG_DIR = `$cmdRebuild -si=logdir`;
chomp($OUTLOG_DIR);
($OUTLOG_DIR) =~ s-\\-\/-g;
my $contextFromDropZone;
if($CurrentVersion) {
    $contextFromDropZone  = "$DROP_DIR/$Context/$CurrentVersion";
    $contextFromDropZone .= "/contexts/allmodes/files/$Context.context.xml";
    if( ! -e "$contextFromDropZone" ) {
        my $previousVersion = $CurrentVersion - 1;
        $previousVersion = 1 if($CurrentVersion == 1);
        if($previousVersion > 1) {
            for ( my $count = 1; $count <= 100; $count++) { # search in last 100 builds
                $contextFromDropZone  = "$DROP_DIR/$Context/$previousVersion";
                $contextFromDropZone  .= "/contexts/allmodes/files/$Context.context.xml";
                last if( -e "$contextFromDropZone" );
                last if($previousVersion == 1);
                $previousVersion--;
            }
        } else {
            if( -e "$DROP_DIR/$Context/$previousVersion/contexts/allmodes/files/$Context.context.xml" ) {
                $contextFromDropZone  = "$DROP_DIR/$Context/$previousVersion";
                $contextFromDropZone  .= "/contexts/allmodes/files/$Context.context.xml";
            }
        }
    }
}

$flag=0;

my $thisContext = ( -e "$OUTLOG_DIR/Build/$Context.context.xml" )
                  ? "$OUTLOG_DIR/Build/$Context.context.xml"
                  : "$contextFromDropZone";

if( -e $thisContext) {
    &listCurrentGreatests("$thisContext");
} else {
    $flag=1;
}

#list ini files
push(@Inis,"$paramIni");
&listAllInisIncluded("$paramIni");




##############################################################################
##### MAIN

#display infos
unless($shortStatus) {
    print "\n";
    print "\nstart  at ",scalar(localtime),"\n\n";
    print "hostname : $HOST\n";
    print "platform : $PLATFORM\n";
    print "context: $Context\n";
    print "based on context file : $thisContext\n";
    print "last version with context.xml found: $CurrentVersion\n" if($CurrentVersion);
    print "clientspec: $P4CLIENT\n";
    print "PROJECT: $Project\n";
    print "scan: @P4PathsToScan\n" if(@P4PathsToScan);
}

#2 p4 sync -n
unless($startOnlyIfNewGreatestIni) {
    system("rm -f \"$cbtPath/$P4CLIENT.log\"");
    if ( ! -e "$cbtPath/$P4CLIENT.log" ) {
        require Perforce;
        $p4 = new Perforce;
        eval { $p4->Login("-s") };
        $p4->SetOptions("-c \"$P4CLIENT\"") if($p4);
        if(@P4PathsToScan) {
            $p4->sync("-n", " @P4PathsToScan > $cbtPath/$P4CLIENT.log 2>&1");
        } else {
            $p4->sync("-n", " > $cbtPath/$P4CLIENT.log 2>&1");
        }
        $p4->Final() if($p4);
    } else {
        die("ERROR : $cbtPath/$P4CLIENT.log still exist, please delete it before running $0\n");
    }
    #3 parse result
    open(P4TRIG,"$cbtPath/$P4CLIENT.log") or die("ERROR: cannot open '$cbtPath/$P4CLIENT.log' : $!\n");
        print "\n";
        while(<P4TRIG>) {
            chomp;
            s/^\s+$//;
            ### skip unwanted pattern
            next if(/\s+\-\s+file\(s\)\s+up\-to\-date\.$/);
            next if(/\.dep$/);
            next if(/\.dep\.new$/);
            next if(/\.dep\.new\.64$/);
            next if(/\.context\.xml$/);
            next unless($_);
            if($_) {
                if(/\s+\-\s+file\(s\)\s+not\s+in\s+client\s+view\.$/) {
                    ### if p4 path not in clientspec
                    print "\nWARNING : $_\n\n";
                } else {
                    print "$_\n";
                    $flag = 1;
                }
            }
        }
    close(P4TRIG);
}

#check if new greatest
$flag ||= &searchNewGreatests();

#check if ini updated, including ini included
if(@Inis) {
    print "ini(s):\n" unless($shortStatus);
    foreach my $ini (@Inis) {
        print "$ini"  unless($shortStatus);
        $flag ||= &checkIfRecentFile("$ini");
        print "\n"  unless($shortStatus);
    }
}


if(%newGreatests) {
    print "greatest(s) updated:\n" unless($shortStatus);
    foreach my $greatest (sort(keys(%newGreatests))) {
        print "$greatest : $Greatests{$greatest} -> $newGreatests{$greatest}\n" unless($shortStatus);
    }
}
print "\ngreatest(s) not changed:\n" unless($shortStatus);
foreach my $greatest (sort(keys(%Greatests))) {
    next unless($newGreatests{$greatest});
    print "$greatest : $Greatests{$greatest}\n" unless($shortStatus);
}

my $SRC_DIR = `$cmdRebuild -si=src_dir`;
if( ! -e "$SRC_DIR" ) { # never fetched on local build machine
    print "\nstart=yes\n" unless($shortStatus);
    print "yes" if($shortStatus);
    exit;
}

my $DATFileInfra;
my $DATFileHost;

if( -e "$DROP_DIR/$Context/version.txt" ) {
    if( -e "$HTTP_DIR/$Context/Build_$Context.dat") {
        my $versionFound = &getBuildRev();
        my $thisFullBuildNumber = sprintf("%05d", $versionFound);
        my $datFile  = "$HTTP_DIR/$Context/${Context}_$thisFullBuildNumber";
        $datFile    .= "/${Context}_${thisFullBuildNumber}=${PLATFORM}_${BUILD_MODE}_host_1.dat";
        if( -e "$datFile" ) {
            if(open(DAT,"$datFile")) {
                my($Hst, $Src, $Out) = split(/\s*\|\s*/, <DAT>);
                close(DAT);
                $flag = 1 if (!($HOST =~ /^$Hst$/i));
            } else {
                $flag = 1;
            }
        } else {
            $flag = 1;
        }
    } else {
        $flag = 1;
    }
} else {
    $flag = 1;
}

#4 provide info to start a build or not
if($flag==1) {
    unless($shortStatus) {
        if($NewVersion) {
            print "\nnew version: $NewVersion\n"
        }
    }
    if ( -e "$DROP_DIR/$Context/forcebuild.txt" ) {
        system("rm -f \"$DROP_DIR/$Context/forcebuild.txt\"")
    }
    print "\nstart=yes\n" unless($shortStatus);
    print "yes" if($shortStatus);
} else {
    if ( -e "$DROP_DIR/$Context/forcebuild.txt" ) {
        system("rm -f \"$DROP_DIR/$Context/forcebuild.txt\"");
        print "Build launch forced\n" unless($shortStatus);
        print "\n\nstart=yes\n"       unless($shortStatus);
        print "yes" if($shortStatus);
        print "\n"  unless($shortStatus);
        exit;
    }
    print "\nstart=no\n" unless($shortStatus);
    print "no" if($shortStatus);
}

print "\n" unless($shortStatus);
exit;



##############################################################################
### my functions
sub Syntax($) {
    my ($msg) = @_ ;
    if($msg)
    {
        print "\n";
        print "\tERROR:\n";
        print "\t======\n";
        print "$msg\n";
    }
    print "
    Usage   : perl $0 [options] p4paths

[options]
    -h|?        argument displays helpful information about $0.
    -b      context (buildname)
    -c      clienspec, mandatory if -b not specified
    -p      project, with this option, $0 can display last and new revision build
    -om     choose a boject model (-om=32 or -om=64)
    -64     force the 64 bits compilation (-64) or not (-no64), default is -no64 i.e 32 bits,
            same usage than Build.pl
    -m      choose a compile mode,
            same usage than Build.pl -m=

[examples]
perl $0 -c=Aurora_cons_$HOST
perl $0 -c=Aurora_cons_$HOST //product/aurora/4.0/REL/export/...
perl $0 -b=Aurora_cons -p=Aurora //product/aurora/4.0/REL/export/...
perl $0 -c=Aurora_cons_$HOST //depot3/crystalreports.*/... //depot3/platform.client.cpp.*/4.0/REL/...
perl $0 -c=Aurora_PI_tp_$HOST //tp/*/... //internal/tp.*/... //internal/compilation.framework/trunk/PI/... //product/aurora/trunk/PI/...
perl $0 -b=Aurora_PI_tp -p=Aurora //tp/*/... //internal/tp.*/... //internal/compilation.framework/trunk/PI/... //product/aurora/trunk/PI/...

";
    exit 0 unless($msg);
    exit 1 if    ($msg);
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
            #my $buildDir = dirname( $greatest );
            if($^O ne "MSWin32") { #if unix and windows path in context
                $greatest =~ s-^\/\/-\/net\/- if($greatest =~ /^\/\//);
            }
            if($^O eq "MSWin32") { #if windows and unix path
                $greatest =~ s-^\/net-\/- if($greatest =~ /^\/net/);
            }
            if(!($greatest =~ /^$IMPORT_DIR/)) {
                $greatest = "$IMPORT_DIR/$greatest";
            }
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

sub checkIfRecentFile($) {
    my ($file) = @_ ;
    if ( -e $file ) {
        my $mtime = (lstat $file)[9];
        my $now = time ;
        if ( ($now -  $mtime) < (24 * 60 * 60) ) {  # ignore the file if it was created more than 24 heures
            my $last_modif =  int (($now -  $mtime)/ (60 * 60 )) ;
            print " Last modification : $last_modif hours ago"  unless($shortStatus);
            return 1;
        }
    }
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

sub getBuildRev() {
    my $tmp = 0;
    if(open(VER, "$DROP_DIR/$Context/version.txt"))
    {
        chomp($tmp = <VER>);
        $tmp = int($tmp);
        close(VER);
    } else {
        # If version.txt does not exists or opening failed, instead of restarting from 1,
        #look for existing directory versions & generate the hightest version number
        #based on the hightest directory version
        # open current context dir to find the hightest directory version inside
        if(opendir(BUILDVERSIONSDIR, "$DROP_DIR/$Context"))
        {
            while(defined(my $next = readdir(BUILDVERSIONSDIR)))
            {
                # Only take a directory with a number as name,
                # which can be a number or a float number with a mandatory decimal value
                # & optional floating point
                $tmp = $1 if ($next =~ /^(\d+)(\.\d+)?$/ && $1 > $tmp && -d "$DROP_DIR/$Context/$next");
            }   
            closedir(BUILDVERSIONSDIR);
        }
    }
    return $tmp;
}
