##############################################################################
##### declare uses

#use strict;
#use diagnostics;

use Getopt::Long;
use Sys::Hostname;

use File::Find;
use File::Path;
use File::Copy;
use File::Basename;
use File::Spec::Functions;

use FindBin;
use lib $FindBin::Bin;
use IO::File;

use XML::DOM;

use Config;



##############################################################################
##### declare vars
#SYSTEM
use vars qw (
    $CURRENTDIR
    $HOST
    $OBJECT_MODEL
    $PLATFORM
    $NULLDEVICE
);
#BUILD infos
use vars qw (
    $BUILD_MODE
    $BuildNumber
    $buildName
    $Config
    $Context
    $Model
    $Project
    $refBuildNumber
    $Site
    $Version
);
#BUILD DIRS
use vars qw (
    $DROP_DIR
    $IMPORT_DIR
    $OUTLOG_DIR
    $OUTPUT_DIR
    $SRC_DIR
);
#PARAMETERS
use vars qw (
    $paramAreasToRebuild
    $paramChangeLists
    $paramFullAreasToRebuild
    $paramLocalLogsDir
    $paramP4Dirs
    $paramSkipAreasToRebuild
);
#OPTS
use vars qw (
    $DisplayTimesOnly
    $FetchCmd
    $Help
    $ImportCmd
    $JustMissingCompile
    $KeepRefLogs
    $nbFirstErrors
    $NoDisplayTimes
    $noExec
    $offLineMode
    $optExport
    $optRetouchDatForIncTarget
    $QuietMode
    @QSets
    $theseBUs
    $WithCleanAreas
    $withDUs
    $withDUsOnly
    @iniTargets
    $tinyStatus
    $showInfo
    $jenkins
    $paramFetchAreas
    @AreasToFetch
    $opt_pas
    $Display_CIS_link
);
#P4
use vars qw (
    @ChangeLists
    $Client
    @P4Dirs
);
#for script itself
use vars qw (
    %AREAS
    @AreasToRebuild
    @AreasToSkip
    $BuildPlCommand
    @Errors
    %ErrorsSortedByStart
    @FullAreasToReBuild
    $flagMergedDUs
    @ENVVARS
    @ENVLOCALVARS
    @Inis
    %ErrorsPerPlatform
);
#for ReadIni
use vars qw (
    @Adapts
    @BMonitors
    @BuildCmds
    $BuildOptions
    $CACHEREPORT_ENABLE
    @CleanCmds
    @DependenciesCmds
    @Exports
    @ExportCmds
    @GTxPackages
    @Imports
    $IncrementalCmd
    @IncrementalCmds
    $IsVariableExpandable
    @ReportCmds
    @MailCmds
    @MonitoredVariables
    $NoCheckIni
    $Options
    @PackageCmds
    @PrefetchCmds
    @QACPackages
    @ReportCmds
    $Root
    @SmokeCmds
    @TestCmds
    @ValidationCmds
    @Views
    @GITViews
    $ConfigFile
);



##############################################################################
##### declare functions
sub setBuildRef();
sub getBuildRev();
sub parseDatFile($$$$$);
sub buildDatFile();
sub getLastIncremental($$);
sub reBuildAreas(@);
sub retouch_dat_for_inc_target();
sub listCurrentGreatests($);

sub execBuildPL($);
sub listAllInisIncluded($);

sub Usage($);
sub startScript();
sub endScript();



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "64!"           =>\$Model,
    "A=s"           =>\$paramFullAreasToRebuild,
    "CA"            =>\$WithCleanAreas,
    "E"             =>\$optExport,
    "F"             =>\$FetchCmd,
    "I"             =>\$ImportCmd,
    "Noexec!"       =>\$noExec,
    "Quiet!"        =>\$QuietMode,
    "a=s"           =>\$paramAreasToRebuild,
    "buildname=s"   =>\$Context,
    "bus=s"         =>\$theseBUs,
    "cl=s"          =>\$paramChangeLists,
    "dto"           =>\$DisplayTimesOnly,
    "help|?"        =>\$Help,
    "ini=s"         =>\$Config,
    "jenkins"       =>\$jenkins,
    "jm"            =>\$JustMissingCompile,
    "kl"            =>\$KeepRefLogs,
    "l=s"           =>\$paramLocalLogsDir,
    "m=s"           =>\$BUILD_MODE,
    "na=s"          =>\$paramSkipAreasToRebuild,
    "nci"           =>\$NoCheckIni,
    "ndt"           =>\$NoDisplayTimes,
    "nfe=s"         =>\$nbFirstErrors,
    "oas=s"         =>\$OverAllStatus,
    "ofl"           =>\$offLineMode,
    "om=s"          =>\$OBJECT_MODEL,
    "p"             =>\$withDUs,
    "p4dirs=s"      =>\$paramP4Dirs,
    "pas"           =>\$opt_pas,
    "pf=s"          =>\$PLATFORM,
    "pfa=s"         =>\$paramFetchAreas,
    "po"            =>\$withDUsOnly,
    "qset=s@"       =>\@QSets,
    "r=s"           =>\$refBuildNumber,
    "rtinc"         =>\$optRetouchDatForIncTarget,
    "si=s"          =>\$showInfo,
    "site=s"        =>\$Site,
    "ti=s@"         =>\@iniTargets,
    "ts"            =>\$tinyStatus,
    "v=s"           =>\$BuildNumber,
    "CIS"           =>\$Display_CIS_link,
);

### set options
$NoDisplayTimes ||=0;
$NoDisplayTimes = 1 if($OverAllStatus);
if($QuietMode && $noExec) {
    Usage("-Q and -N are incompatible, choose -Q or -N but not the both");
}

if($paramAreasToRebuild) {
    @AreasToRebuild = split ',',$paramAreasToRebuild;
}

if($paramSkipAreasToRebuild) {
    @AreasToSkip    = split ',',$paramSkipAreasToRebuild;
}

if($JustMissingCompile) {
    $NoDisplayTimes = 1;
}

if($paramFullAreasToRebuild) {
    $NoDisplayTimes = 1;
    @FullAreasToReBuild = split ',',$paramFullAreasToRebuild;
}



##############################################################################
##### init vars
# system
$CURRENTDIR = $FindBin::Bin;
$HOST = hostname();
$OBJECT_MODEL ||= $Model ? "64" : "32" if(defined $Model);
$ENV{OBJECT_MODEL} = $OBJECT_MODEL ||= $ENV{OBJECT_MODEL} || "32";
unless($PLATFORM) {
       if($^O eq "MSWin32") { $PLATFORM = ($OBJECT_MODEL==64) ? "win64_x64"       : "win32_x86"       }
    elsif($^O eq "solaris") { $PLATFORM = ($OBJECT_MODEL==64) ? "solaris_sparcv9" : "solaris_sparc"   }
    elsif($^O eq "aix")     { $PLATFORM = ($OBJECT_MODEL==64) ? "aix_rs6000_64"   : "aix_rs6000"      }
    elsif($^O eq "hpux")    { $PLATFORM = ($OBJECT_MODEL==64) ? "hpux_ia64"       : "hpux_pa-risc"    }
    elsif($^O eq "darwin")  { $PLATFORM = ($OBJECT_MODEL==64) ? "mac_x64"         : "mac_x86"         }
    elsif($^O eq 'linux')   {
        if($Config{'archname'}=~/ppc64/) {
                $PLATFORM='linux_ppc64'
        } else {
                              $PLATFORM = ($OBJECT_MODEL==64) ? 'linux_x64'       :'linux_x86'        }
    }
}
$NULLDEVICE = ($^O eq "MSWin32") ? "nul" : "/dev/null" ;
# Site
$Site ||= $ENV{'SITE'} || "Walldorf";
unless(    $Site eq "Levallois"
        || $Site eq "Walldorf"
        || $Site eq "Vancouver"
        || $Site eq "Bangalore" 
        || $Site eq "Paloalto"
        || $Site eq "Lacrosse" ) {
                my $msgErr  = "ERROR: SITE environment variable or";
                $msgErr    .= "'perl $0 -s=my_site' must be set\navailable sites : ";
                $msgErr    .= "Levallois | Walldorf | Vancouver | Bangalore | Paloalto | Lacrosse";
                die "\n$msgErr\n";
}
$ENV{'SITE'} = $Site;
# build
$BUILD_MODE ||= $ENV{BUILD_MODE} || "release";
if($ENV{BUILD_MODE}) {
    if($BUILD_MODE && ($BUILD_MODE ne $ENV{BUILD_MODE}) ) {
        my $msg  = "-m=$BUILD_MODE is different than the environment variable";
        $msg    .= "BUILD_MODE=$ENV{BUILD_MODE}";
        $msg    .= ", to not mix, $0 exit now";
        print "\n$msg\n";
        exit;
    }
}
if("debug"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="debug";
} elsif("release"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="release";
} elsif("releasedebug"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="releasedebug";
} else {
    Usage("compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease|releasedebug]");
}
$Context    ||= "aurora41_cons";
$Config     ||= "contexts/$Context.ini";
($Config)     =~ s-\\-\/-g;

# environment vars
foreach (@QSets) {
    my($Variable, $String) = /^(.+?):(.*)$/;
    Monitor(\${$Variable});
    ${$Variable} = $ENV{$Variable} = $String;
}

#parse ini
if( -e "$Config") {
    ReadIni();
} else {
    unless($showInfo && ($showInfo eq "help")) {
        Usage("ini : '$Config' not found")
    }
}

# set project for Site.pm
$ENV{PROJECT}   = $Project || "aurora_dev";
require Site;

$DROP_DIR       = $ENV{DROP_DIR};
$IMPORT_DIR     = $ENV{IMPORT_DIR};

#manage version
setBuildRef();

# if already an incremental build (rebuild.pl started from ini file and not from terminal command), no touch 2nd chance : .01
if($ENV{BUILD_NUMBER} && $ENV{BUILD_NUMBER} =~ /\.(\d+)$/) {
    my $already_inc = $1;
    if($BuildNumber) {
        #if -v=.x or -v=.xx
        if($BuildNumber =~ /^\.(\d+)$/) {
            my $inc = $1;
            ($inc) =~ s-^0--;
            if($refBuildNumber =~ /\.\d+$/) {
                my $tmp = $refBuildNumber;
                $tmp =~ s-\.\d+$--;
                $BuildNumber = "${tmp}.${already_inc}$inc";
            } else {
                $BuildNumber = "${refBuildNumber}.${already_inc}$inc";
            }
        }
        # full version with 000, needed for the full path of dat file
        my $fullBuildNumber = sprintf "%05d",$refBuildNumber;
        my $fullBuildNameVersion = "${Context}_$fullBuildNumber";

        #if -v=+ or -v=++
        if($BuildNumber =~ /^\++$/) {
            my $indice = getLastIncremental($fullBuildNameVersion,$refBuildNumber);
            my $incremental = $indice + 1;
            my $tmp = $refBuildNumber;
            ($tmp) =~ s-\.\d+$--;
            $BuildNumber = "${tmp}.$incremental";
        }
    }
}
else {
    if($BuildNumber) {
        #if -v=.x or -v=.xx
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
        my $fullBuildNumber = sprintf "%05d", $refBuildNumber;
        my $fullBuildNameVersion = "${Context}_$fullBuildNumber";

        #if -v=+
        if($BuildNumber =~ /^\+$/) {
            my $indice = getLastIncremental($fullBuildNameVersion,$refBuildNumber);
            my $incremental = $indice + 1;
            my $tmp = $refBuildNumber;
            ($tmp) =~ s-\.\d+$--;
            my $tmp2;
            if($indice>0) {
                $tmp2 = "${Context}_${fullBuildNumber}.$indice";
            } else {
                $tmp2 = "${Context}_${fullBuildNumber}";
            }
            my $currentDatFile  = "$ENV{HTTP_DIR}/$Context/$tmp2";
            $currentDatFile    .= "/${tmp2}=${PLATFORM}_${BUILD_MODE}_build_1.dat";
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
            my $indice = getLastIncremental($fullBuildNameVersion,$refBuildNumber);
            my $incremental = $indice + 1;
            my $tmp = $refBuildNumber;
            ($tmp) =~ s-\.\d+$--;
            $BuildNumber = "${tmp}.$incremental";
        }
    }
}

$flagMergedDUs = 0;

$BuildNumber ||=$refBuildNumber;

# var for build
($SRC_DIR = ExpandVariable(\$SRC_DIR)) =~ s/\\/\//g;
$SRC_DIR ||= $ENV{SRC_DIR};
$ENV{OUTPUT_DIR} = $OUTPUT_DIR
                 = $ENV{OUTPUT_DIR} || (($ENV{OUT_DIR}
                 || ($SRC_DIR=~/^(.*)[\\\/]/, "$1/$PLATFORM"))."/$BUILD_MODE");
$ENV{OUTLOG_DIR} = $OUTLOG_DIR  = $ENV{OUTLOG_DIR} || "$OUTPUT_DIR/logs";

if($OverAllStatus) {
    if($OverAllStatus =~ /^all$/i ) {
        $OverAllStatus = "infra,build,setup,test,smoke,bat";
    }
    if($OverAllStatus =~ /^help$/i ) {
        print "\navailable values of -oas :
    CIS column :
all    (=infra,build,setup,test,smoke,bat)
infra
build
setup
test
smoke
bat
    MODE:
release
debug
releasedebug
    PLATFORM
win32_x86 win64_x64 solaris_sparc solaris_sparcv9 linux_x86 linux_x64 aix_rs6000 aix_rs6000_64 hpux_ia64 mac_x86 mac_x64 linux_ppc64

e.g.:
-oas=build,setup:release,debug:win32_x86,win64_x64
or
-oas=build,setup:release
or
-oas=build,setup:win32_x86,win64_x64
or
-oas=infra[clean-import],build:win32_x86,win64_x64
or
-oas=infra[clean-import],build:release:win32_x86,win64_x64


order:
CIS column(s):mode(s):platform(s)
or
CIS column(s):mode(s)
or
CIS column(s):platform(s)
";
        exit;
    }
    my ($realElems,$realModes,$realPlatforms) = split ':',$OverAllStatus;
    my @elemsToCheck = split ',',$realElems;
    my @modesToCheck;
    my @platformsToCheck;
    if($realModes) { #if 2 arguments
        if($realPlatforms) { #if 3 arguments
            @modesToCheck = split ',',$realModes;
            @platformsToCheck = split ',',$realPlatforms;
        } else {
            my $modes = qr/release|debug|releasedebug/;
            if($realModes =~ /^$modes$/i) {
                @modesToCheck = split ',',$realModes;
                @platformsToCheck  = qw(win32_x86
                                       win64_x64
                                       solaris_sparc 
                                       solaris_sparcv9
                                       linux_x86
                                       linux_x64
                                       aix_rs6000
                                       aix_rs6000_64
                                       hpux_ia64
                                       mac_x86
                                       mac_x64
                                       linux_ppc64);
            } else {
                @modesToCheck     = qw(release debug releasedebug);
                @platformsToCheck = split ',',$realModes;
            }
        }
    } else {
        @modesToCheck       = qw(release debug releasedebug);
        @platformsToCheck   = qw(win32_x86
                                 win64_x64
                                 solaris_sparc
                                 solaris_sparcv9 
                                 linux_x86
                                 linux_x64
                                 aix_rs6000
                                 aix_rs6000_64
                                 hpux_ia64
                                 mac_x86
                                 mac_x64
                                 linux_ppc64);
    }
    my $baseOn = sprintf "%05d",$refBuildNumber;
    $baseOn   .= ".$1" if ($refBuildNumber =~ /\.(\d+)$/ ); #if ref build is incremental version
    my $buildName  = "${Context}_$baseOn";
    my $totalError = 0;
    print "
project  : $Project
buidname : $Context
revision : $refBuildNumber
";
    foreach my $elem (sort @elemsToCheck) {
        my $elem2;
        my @patterns;
        if( $elem =~ /\[/) {
            my $tmp;
            ($elem2,$tmp) = $elem =~ /^(.+?)\[(.+?)\]$/i;
            @patterns = split '-',$tmp;
        } else {
            $elem2 = $elem ;
        }
        print "\n\t$elem2";
        if((scalar @patterns) > 0) {
            print " [@patterns]";
        }
        print "\n";
        foreach my $thisBuildMode (sort @modesToCheck) {
            print "\t\t$thisBuildMode\n";
            foreach my $thisPlatform (sort @platformsToCheck) {
                my $datFile  = "$ENV{HTTP_DIR}/$Context/$buildName";
                $datFile    .= "/$buildName=${thisPlatform}_${thisBuildMode}_${elem2}_1.dat";
                ($datFile) =~ s-\\-\/-g;
                if( -e "$datFile") {
                    if((scalar @patterns) > 0) {
                        parseDatFile($thisPlatform,$thisBuildMode,$elem2,"$datFile",\@patterns);
                    } else {
                        parseDatFile($thisPlatform,$thisBuildMode,$elem2,"$datFile","");
                    }
                    print "$thisPlatform : ";
                    if($ErrorsPerPlatform{$thisPlatform}{$thisBuildMode}{$elem2}) {
                        if( $ErrorsPerPlatform{$thisPlatform}{$thisBuildMode}{$elem2} > 0 ) {
                            print "$ErrorsPerPlatform{$thisPlatform}{$thisBuildMode}{$elem2} error(s)\n";
                            $totalError = $totalError
                                + $ErrorsPerPlatform{$thisPlatform}{$thisBuildMode}{$elem2};
                        } else {
                            print "passed\n";
                        }
                    } else {
                        print "passed\n";
                    }
                } else {
                    print("\nERROR : $thisPlatform not found in CIS\n");
                    $totalError++;
                }
            }
        }
    }
    print "\n";
    if($totalError > 0) {
        print "general status : failed with $totalError error(s)\n";
        exit 1;
    } else {
        print "general status : passed\n";
        exit 0;
    }
    exit;
}

if($showInfo) {
    print "\n" if($jenkins);
    if($showInfo eq "help") {
        print "

help of '-si' option

\tDescription :
\t-------------
$0 can display specific information and exit.
It can be helpful for automation of other scripts which they required specific information.
(e.g.: RollingFetch.pl)
if nothing returned, then $0 found no value.

\tUsage:
\t------
perl $0 -i=your_context -si=info_to_display

\te.g.:
\t-----
perl $0 -i=$Config -si=context

\tlist of info available:
\t-----------------------

project
context
version
revision
nextrevision
revinc
nextrevinc
inc
nextinc
greatest
areas
branch
src_dir
view
gitview
clean
import
build
packages
export
exportcmd
var:variable_to_search, eg: var:MY_AREAS
envvars
localvars
buildoptions
options
prefetch
mail
test
smoke
valid
report
adapt
astec
qac
gtx
outputdir
logdir
dropdir
importdir
cis
clientspec
makefile (used by Multiproc.pl & extention = .gmk
inis
platform
config
";
    } elsif($showInfo eq "project") {
        print "$Project" if($Project);
    } elsif($showInfo eq "context") {
        print "$Context" if($Context);
    } elsif($showInfo eq "version") {
        print "$Version" if($Version);
    } elsif($showInfo eq "revision") {
        print "$BuildNumber" if($BuildNumber);
    } elsif($showInfo eq "nextrevision") {
        if($BuildNumber) {
            my $nextBuildRev = $BuildNumber + 1;
            print "$nextBuildRev";
        }
    } elsif($showInfo eq "revinc") {
        my $fullBuildNumber = sprintf "%05d",$refBuildNumber;
        my $fullBuildNameVersion = "${Context}_$fullBuildNumber";
        my $incremental = getLastIncremental($fullBuildNameVersion,$refBuildNumber);
        print "$BuildNumber.$incremental";
    } elsif($showInfo eq "nextrevinc") {
        my $fullBuildNumber = sprintf "%05d",$refBuildNumber;
        my $fullBuildNameVersion = "${Context}_$fullBuildNumber";
        my $indice = getLastIncremental($fullBuildNameVersion,$refBuildNumber);
        my $incremental = $indice + 1;
        print "$BuildNumber.$incremental";
    } elsif($showInfo eq "inc") {
        my $fullBuildNumber = sprintf "%05d",$refBuildNumber;
        my $fullBuildNameVersion = "${Context}_$fullBuildNumber";
        my $incremental = getLastIncremental($fullBuildNameVersion,$refBuildNumber);
        print "$incremental";
    } elsif($showInfo eq "nextinc") {
        my $fullBuildNumber = sprintf "%05d", $refBuildNumber;
        my $fullBuildNameVersion = "${Context}_$fullBuildNumber";
        my $indice = getLastIncremental($fullBuildNameVersion,$refBuildNumber);
        my $incremental = $indice + 1;
        print "$incremental";
    } elsif($showInfo eq "greatest") {
        my $greatestVersion;
        if($ENV{REF_REVISION}) {
            if($ENV{REF_REVISION} =~ /\.xml$/i) {
                my $thisContext = "$DROP_DIR/$ENV{REF_REVISION}";
                ($thisContext) =~ s-\=--g;
                $greatestVersion = listCurrentGreatests("$thisContext") if( -e "$thisContext");
            }
            print "$ENV{REF_REVISION}";
            print " : $greatestVersion" if($greatestVersion);
        }
    } elsif($showInfo eq "areas") {
        if($ENV{MY_AREAS}) {
            my @AllAreas = split ',',$ENV{MY_AREAS};
            my @realAreas;
            foreach my $gav (@AllAreas) {
                my ($branch,$group,$artifact,$verion)
                   = $gav =~ /^(.+?)\:(.+?)\:(.+?)\:(.+?)$/i;
                push @realAreas,$artifact;
            }
            @realAreas = sort @realAreas;
            print "@realAreas";
        }
    } elsif($showInfo eq "branch") {
        if($ENV{MY_AREAS}) {
            my @AllAreas = split ',',$ENV{MY_AREAS};
            my @realBranches;
            foreach my $gav (@AllAreas) {
                my ($branch,$group,$artifact,$verion)
                    = $gav =~ /^(.+?)\:(.+?)\:(.+?)\:(.+?)$/i;
                push @realBranches,$branch unless(grep /^$branch$/ , @realBranches);
            }
            @realBranches = sort @realBranches;
            print "@realBranches";
        }
    } elsif($showInfo eq "src_dir") {
        print "$SRC_DIR" if($SRC_DIR);
    } elsif($showInfo eq "view") {
        if(@Views) {
            foreach my $elem (@Views) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "gitview") {
        if(@GITViews) {
            foreach my $elem (@GITViews) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "clean") {
        if(@CleanCmds) {
            foreach my $elem (@CleanCmds) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "prefetch") {
        if(@PrefetchCmds) {
            foreach my $elem (@PrefetchCmds) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "import") {
        if(@Imports) {
            foreach my $elem (@Imports) {
                print "@$elem\n";
            }
        }
        if(@NexusImports) {
            foreach my $elem (@NexusImports) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "build") {
        if(@BuildCmds) {
            foreach my $elem (@BuildCmds) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "packages") {
        if(@PackageCmds) {
            foreach my $elem (@PackageCmds) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "export") {
        if(@Exports) {
            foreach my $elem (@Exports) {
                print "$elem\n";
            }
        }
    } elsif($showInfo eq "exportcmd") {
        if(@Exports) {
            foreach my $elem (@ExportCmds) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo =~ /var\:(.+?)$/) {
        my $Name = $1;
        if(${$Name}) {
            print "${$Name}";
        } elsif($ENV{$Name}) {
            print "$ENV{$Name}";
        }
    } elsif($showInfo eq "envvars") {
        if(@ENVVARS) {
            foreach my $elem (@ENVVARS) {
                print "$elem=$ENV{$elem}\n";
            }
        }
    } elsif($showInfo eq "localvars") {
        if(@ENVLOCALVARS) {
            foreach my $elem (@ENVLOCALVARS) {
                my ($Key,$Value) = $elem =~ /^(.+?)\=(.+?)$/; # search all ${my_variable_name}
                while($Value =~ /\${(.*?)}/g) {
                    my $Name = $1;
                    $Value =~ s/\${$Name}/${$Name}/    if(    defined ${$Name});
                    $Value =~ s/\${$Name}/$ENV{$Name}/ if( (! defined ${$Name}) && (defined $ENV{$Name}) );
                }
                print "$Key=$Value\n";
            }
        }
    } elsif($showInfo eq "buildoptions") {
        print "$BuildOptions" if($BuildOptions);
    } elsif($showInfo eq "options") {
        print "$Options" if($Options);
    } elsif($showInfo eq "mail") {
        if(@MailCmds) {
            foreach my $elem (@MailCmds) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "test") {
        if(@TestCmds) {
            foreach my $elem (@TestCmds) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "smoke") {
        if(@SmokeCmds) {
            foreach my $elem (@SmokeCmds) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "valid") {
        if(@ValidationCmds) {
            foreach my $elem (@ValidationCmds) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "report") {
        if(@ReportCmds) {
            foreach my $elem (@ReportCmds) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "adapt") {
        if(@Adapts) {
            foreach my $elem (@Adapts) {
                print "$elem\n";
            }
        }
    } elsif($showInfo eq "astec") {
        foreach my $pkg (qw(packages patches)) {
            next unless(${"ASTEC$pkg"});
            foreach my $PackageName (split /\s*,\s*/,${"ASTEC$pkg"}) {
                print "$PackageName\n";
            }
        }
    } elsif($showInfo eq "qac") {
        if(@QACPackages) {
            foreach my $elem (@QACPackages) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "gtx") {
        if(@GTxPackages) {
            foreach my $elem (@GTxPackages) {
                print "@$elem\n";
            }
        }
    } elsif($showInfo eq "outputdir") {
        print "$ENV{OUTPUT_DIR}" if($ENV{OUTPUT_DIR});
    } elsif($showInfo eq "logdir") {
        print "$ENV{OUTLOG_DIR}" if($ENV{OUTLOG_DIR});
    } elsif($showInfo eq "dropdir") {
            print "$DROP_DIR";
    } elsif($showInfo eq "importdir") {
            print "$IMPORT_DIR";
    } elsif($showInfo eq "cis") {
            print "$ENV{HTTP_DIR}" if($ENV{HTTP_DIR});
    } elsif($showInfo eq "clientspec") {
            print "$Client" if($Client);
    } elsif($showInfo eq "makefile") {
            if(@IncrementalCmds) {
                if($IncrementalCmds[1] =~ /MultiProc\.pl/i) {
                    my $nbElem = (scalar @IncrementalCmds) - 1;
                    my $makefile = $IncrementalCmds[$nbElem];
                    chomp $makefile;
                    print "$makefile" if($makefile =~ /\.gmk$/i);
                }
            }
    } elsif($showInfo eq "inis") {
            my $iniBase = basename($Config);
            push @Inis,$iniBase;
            listAllInisIncluded($Config);
            print "@Inis";
    } elsif($showInfo eq "platform") {
            print "$PLATFORM" if($PLATFORM);
    } elsif($showInfo eq "config") {
        print "$ConfigFile" if($ConfigFile);
    }else {
        print "ERROR : -si=$showInfo unkown.";
    }
    if($jenkins) {
        print "\n\n";
        sleep(10); # add a sleep, otherwise, to fast for jenkins !!!
    }
    exit;
}

#if jlin or 40fy
unless($NoCheckIni) { #
    if($Config =~ /jlin|40fy/i) {
        print "\nno rebuild for $Context ($Config)\n\n";
        exit;
    }
}

#if test dep
if($ENV{TEST_DEP_FILES}) {
    print "\n current build is for testing dep files before submit, $0 exit now\n";
    exit;
}

#if CIS down
if($offLineMode) {
    $OUTLOG_DIR = $paramLocalLogsDir if($paramLocalLogsDir);
    unless( -e "$OUTLOG_DIR") {
        print "$OUTLOG_DIR not found, what is the log paths ?:\n";
        $OUTLOG_DIR = <STDIN> ;
        chomp $OUTLOG_DIR;
    }
    if( -e "$OUTLOG_DIR" ) {
        $ENV{OUTLOG_DIR} = $OUTLOG_DIR;
        buildDatFile();
    } else {
        Usage("ERROR : '$OUTLOG_DIR' not found");
        exit;
    }
}



##############################################################################
##### MAIN
Usage("") if($Help);
unless($tinyStatus) {
    startScript();

    ##display
    print "\n ","#" x length "OUTLOG_DIR   = $OUTLOG_DIR","\n";
    print "     PROJECT      = $Project
     Context      = $Context
     Ini          = $Config
     Ref Version  = $refBuildNumber
     Version      = $BuildNumber
     PLATFORM     = $PLATFORM
     OBJECT_MODEL = $OBJECT_MODEL
     MODE         = $BUILD_MODE
     SRC_DIR      = $SRC_DIR
     OUTLOG_DIR   = $OUTLOG_DIR\n";
    print " ", "#" x length"OUTLOG_DIR   = $OUTLOG_DIR","\n\n";
}

if($Display_CIS_link) {
    my ($buildnumber, $precision) = $refBuildNumber =~ /^(\d+)(\.?\d*)/; 
    my $fullBuildNumber = sprintf("%05d", $refBuildNumber).$precision;
    my $CIS_URL;
    if($Site eq "Walldorf") {
        $CIS_URL = "http://cis-wdf.pgdev.sap.corp:1080/cgi-bin/CIS.pl";
    }
    elsif ($Site eq "Vancouver") {
        $CIS_URL = "http://cis-van.pgdev.sap.corp:1080/cis/cgi-bin/CIS.pl";
    }
    else {
        $CIS_URL = "http://cis-wdf.pgdev.sap.corp:1080/cgi-bin/CIS.pl";
    }
    if($jenkins) {
        print "CIS : <a href=\"$CIS_URL?streams=$Context&tag=${Context}_$fullBuildNumber\">$CIS_URL?streams=$Context&tag=${Context}_$fullBuildNumber</a><br><br>\n\n";
    }
    else {
        print "CIS : $CIS_URL?streams=$Context&tag=${Context}_$fullBuildNumber\n\n";
    }
    exit;
}

if($paramFetchAreas) {
    #create an array
    @AreasToFetch = split ',',$paramFetchAreas;
    #get clientspec and p4 login
    my $clientSpec = `perl rebuild.pl -i=$Config -om=$OBJECT_MODEL -si=clientspec`;
    chomp $clientSpec;
    require Perforce;
    $p4 = new Perforce;
    eval { $p4->Login("-s") };
    if($@)
    {
        if($WarningLevel<2) { warn "$WarningMessage: User not logged : $@" } 
        else { die "ERROR: User not logged : $@" }
        $p4 = undef;    
    } 
    elsif($p4->ErrorCount())
    {
        if($WarningLevel<2) {
            warn "$WarningMessage: User not logged : ", @{$p4->Errors()}
        } else {
            die "ERROR: User not logged : ", @{$p4->Errors()}
        }
        $p4 = undef;
    }
    $p4->SetOptions("-c \"$clientSpec\"") if($p4);
    # search area in clientspec, strict search (case-sensitive and between 2 slashes)
    $p4->client("-o"," > $CURRENTDIR/$clientSpec.log 2>&1");
    my %P4SCMS;
    my $found = 0;
    if(open CLIENTSPEC,"$CURRENTDIR/$clientSpec.log") {
        while(<CLIENTSPEC>) {
            chomp;
            my $line = $_ ;
            foreach my $area (sort @AreasToFetch) {
                if($line =~ /\/$area\//) {
                    my ($scm) = $line =~ /^\s+(.+?)\s+/;
                    ($scm) =~ s-^\+--;
                    $P4SCMS{$area} = $scm;
                    $found = 1;
                }
            }
        }
        close CLIENTSPEC;
    }
    #sync if area found in clientspec
    if($found == 1) {
        print "\nclientspec : $clientSpec\n";
        print "\tfetch area(s): ",sort keys %P4SCMS,"\n";
        foreach my $area (sort keys %P4SCMS) {
            print "p4 -c $clientSpec sync $P4SCMS{$area}\#head\n";
            my $fetchLogArea = "$OUTLOG_DIR/fetch_$area.log";
            $p4->sync("", " $P4SCMS{$area}\#head > $fetchLogArea 2>&1");
            if( -e "$fetchLogArea") {
                system "cat $fetchLogArea"
            }
            print "\n";
        }
    } else {
        print "\nany area in '$paramFetchAreas' are found in $clientSpec\n\n";
    }
}

if($optRetouchDatForIncTarget) {
    retouch_dat_for_inc_target();
    print "\nThe build dat file in CIS is updated\n";
    # end script
    print "\nEND of '$0', at ",scalar localtime,"\n\n";
    exit;
}

if($offLineMode) {
    my $datOffLine = "$OUTLOG_DIR/$Context.dat";
    if( -e "$datOffLine") {
        parseDatFile($PLATFORM,$BUILD_MODE,"build","$datOffLine","");
    } else {
        Usage("ERROR : '$datOffLine' not found");
        exit;
    }
} else {
    parseDatFile($PLATFORM,$BUILD_MODE,"build","","");
}

my $nbAreas = (keys %AREAS);
if($tinyStatus) {
    if( $nbAreas > 0) {
        die "\ntiny status:  failed\n";
        exit 1;
    } else {
        print "\ntiny status:  passed\n";
        exit 0;
    }
    exit 0;
}

#sync if -cl=... , only if not a full area rebuild,
#if yes, the fetch is done inside the reBuildAreas function,
#and then to not multiply the same fetchs.
if($paramChangeLists && (!(@FullAreasToReBuild > 0)) ) {
    @ChangeLists = split ',',$paramChangeLists;
    foreach my $cl (sort @ChangeLists) {
        print "\nsync $cl :\n";
        my $logSyncCl = "$OUTPUT_DIR/logs/Build/rb_sync_$cl.log";
        system "p4 -c $Client sync -f //...\@$cl,$cl > $logSyncCl 2>&1";
    }
}

#sync list of p4 dirs , only if not a full area rebuild, 
#if yes, the fetch is done inside the reBuildAreas function,
#and then to not multiply the same fetchs.
if($paramP4Dirs && !(@FullAreasToReBuild > 0) ) {
    @P4Dirs = split ',',$paramP4Dirs;
    foreach my $p4dir (sort @P4Dirs) {
        print "\nsync $p4dir :\n";
        my $logSync = "$OUTPUT_DIR/logs/Build/rb_sync_p4dir.log";
        if($p4dir =~ /\/\.\.\.$/) { # simple sync if p4 dir finish by /...
            system "p4 -c $Client sync $p4dir >> $logSync 2>&1";
        } else { # force sync if p4 dir is a file
            system "p4 -c $Client sync -f $p4dir >> $logSync 2>&1";
        }
        if( -e "$logSync") {
            system "cat $logSync";
        }
    }
}

#build command line
$BuildPlCommand  = "perl Build.pl -m=$BUILD_MODE -lo=no -nolego -d";
$BuildPlCommand .= ($OBJECT_MODEL==64) ? " -64" : "";
if(@QSets>0) {
    my $qsetOPtion;
    foreach my $varValue (@QSets) {
        $qsetOPtion .= " -qset=$varValue";
    }
    $BuildPlCommand .= $qsetOPtion;
}
$BuildPlCommand .= " -qset=BUILD_DASHBOARD_ENABLE:0";
$BuildPlCommand .= " -i=$Config -v=$BuildNumber";

if(@iniTargets) {
    foreach my $iniTarget (@iniTargets) {
        $BuildPlCommand .= " -t=$iniTarget";
    }
}

#check if mergedDUs needs to be rebuild
#if($flagMergedDUs == 1) {
#   $BuildPlCommand .= " -t=merged_DUs";
#}

$BuildPlCommand .= " -F" if($FetchCmd);
$BuildPlCommand .= " -I" if($ImportCmd);

#if with full clean of areas with compile issues
if($WithCleanAreas) {
    foreach my $area (sort keys %AREAS) {
        unless(grep /^$area$/ , @FullAreasToReBuild) {
            if($paramSkipAreasToRebuild) {
                unless(grep /^$area$/ , @AreasToSkip) {
                    push @FullAreasToReBuild,$area;
                }
            } else {
                push @FullAreasToReBuild,$area;
            }
        }
    }
}
#if full recompilation of area
if(@FullAreasToReBuild > 0) {
    if($QuietMode) {
        reBuildAreas(@FullAreasToReBuild);
    } else {
        if($noExec) {
            print "\n no execution\n\n";
        } else {
            my $displayListAreas = join ',',@FullAreasToReBuild;
            print "would you like to rebuild '$displayListAreas' with clean of them before ? (y/n)\n";
            my $readRep = <STDIN> ;
            chomp $readRep;
            if($readRep =~ /^y/i) { #'Y' or 'y' answerd only available to follow
                reBuildAreas(@FullAreasToReBuild);
            } else {
                print "\n no execution\n\n";
            }
        }
    }
    exit;
}

my $OptionsBuildPl;

#if force compile selected build units in -bu=....
if($theseBUs) {
    ($OptionsBuildPl = $theseBUs) =~ s-\;- \-a\=-g;
    print "$BuildPlCommand -a=$OptionsBuildPl -B\n";
    print  "\n\n","#" x  length "command line :","\n";
    print "command line :\n\n";
    print "\n$BuildPlCommand -a=$OptionsBuildPl -B\n";
    if($QuietMode) {
        if( -e "$SRC_DIR") {
            execBuildPL("$BuildPlCommand -a=$OptionsBuildPl -B");
            retouch_dat_for_inc_target();
        } else {
            print "\nERROR '$Context' is not on this build machine '$HOST', no execution\n";
        }
    }
    if($noExec) {
        print "\n no execution\n\n";
    }
    if( !$QuietMode && !$noExec ) {
        print "would you like to execute this command ? (y/n)\n";
        my $readRep = <STDIN> ;
        chomp $readRep;
        if($readRep =~ /^y/i) { #'Y' or 'y' answerd only available to follow
            if ( -e "$SRC_DIR") {
                execBuildPL("$BuildPlCommand -a=$OptionsBuildPl -B");
                retouch_dat_for_inc_target();
            } else {
                print "\nERROR '$Context' is not on this build machine '$HOST', no execution\n";
            }
        } else {
            print "\n no execution\n\n";
        }
    }
    exit;
}

#build list of -a=... for Build.pl
if( ( $nbAreas > 0 ) && !$paramFullAreasToRebuild ) {
    print ("\n\n","#" x (length("area/build units to rebuild :")),"\n");
    print "area/build units to rebuild :\n\n";

    ### build list of area:build_unit to rebuild
    my %displayAreas;
    my %areasFoundInList;
    my %areasToSkip;
    foreach my $area (sort keys %AREAS) {
        if($paramAreasToRebuild) {
            foreach my $areaSelected (@AreasToRebuild) {
                if( $area =~ /^$areaSelected/i) {
                    $areasFoundInList{$area} = 1;
                    last;
                }
            }
        }
        if($paramSkipAreasToRebuild) {
            foreach my $areaSelected (@AreasToSkip) {
                if( $area =~ /^$areaSelected/i) {
                    $areasToSkip{$area} = 1;
                    last;
                }
            }
        }
        next if($paramAreasToRebuild     && ($areasFoundInList{$area}==0) ); #if -a=xxx but not found
        next if($paramSkipAreasToRebuild && ($areasToSkip{$area}==1) );      #if -na=xxx but found in the list
        $OptionsBuildPl .= " -a=\"$area:";
        foreach my $bu_errors (sort @{$AREAS{$area}} ) {
            my ($bu,$nbErrors) = $bu_errors =~ /^(.+?)\s+(.+?)$/;
            if ($bu =~ /^package\./) {
                if( $withDUs || $withDUsOnly ) {
                    $displayAreas{$area}=1;
                    $OptionsBuildPl .= "$bu,";
                }
            } else {
                next if($withDUsOnly);
                $displayAreas{$area}=1;
                $OptionsBuildPl .= "$bu,";
            }
        }
        ($OptionsBuildPl) =~ s-\,$-\"-; #remove last ','
    }
    if($OptionsBuildPl) {
        my @areasFoundToRebuild = split ' ',$OptionsBuildPl;
        undef $OptionsBuildPl;
        foreach my $opt (@areasFoundToRebuild) {
            next if($opt =~ /\:$/);
            $OptionsBuildPl .= " $opt";
        }
        undef @areasFoundToRebuild;
    }
    
    ### display list of area:build_unit to rebuild
    my $nbTotalErrrorsInThisBuild = 0;
    foreach my $area (sort keys %AREAS) {
        next if($paramAreasToRebuild     && ($areasFoundInList{$area}==0) ); #if -a=xxx but not found
        next if($paramSkipAreasToRebuild && ($areasToSkip{$area}==1) );      #if -na=xxx but found in the list
        #calcul nb errors, for the display
        my $nErrorsPerArea = 0;
        foreach my $bu (sort @{$AREAS{$area}} ) {
            my $nbErrors = 0;
            if ($bu =~ /^package\./) {
                if( $withDUs || $withDUsOnly ) {
                    ($nbErrors) = $bu =~ /\s+(\d+)$/;
                    $nErrorsPerArea = $nErrorsPerArea + $nbErrors;
                }
            } else {
                next if($withDUsOnly);
                ($nbErrors) = $bu =~ /\s+(\d+)$/;
                $nErrorsPerArea = $nErrorsPerArea + $nbErrors;
            }
        }
        $nbTotalErrrorsInThisBuild = $nbTotalErrrorsInThisBuild + $nErrorsPerArea ;
        #display
        print "\n$area - $nErrorsPerArea\n" if($displayAreas{$area}==1);
        foreach my $bu (sort @{$AREAS{$area}} ) {
            if ($bu =~ /^package\./) {
                if( $withDUs || $withDUsOnly ) {
                    ($bu) =~ s-\s+- \- -;
                    print "\t$bu\n";
                }
            } else {
                next if($withDUsOnly);
                ($bu) =~ s-\s+- \- -;
                print "\t$bu\n";
            }
        }
    }
    print "\n\nnb total error(s): $nbTotalErrrorsInThisBuild\n" if($nbTotalErrrorsInThisBuild>0);
    #back orig logs
    if($KeepRefLogs) {
        foreach my $area (sort keys %AREAS) {
            next if($paramAreasToRebuild     && ($areasFoundInList{$area}==0) ); #if -a=xxx but not found
            next if($paramSkipAreasToRebuild && ($areasToSkip{$area}==1) );      #if -na=xxx but found in the list
            foreach my $bu (sort @{$AREAS{$area}} ) {
                ($bu) =~ s-\s+.+?$--;
                my $buLog = "$OUTLOG_DIR/$area/$bu.log";
                if( -e "$buLog" ) {
                    if( ! -e "$OUTLOG_DIR/$area/_orig_$bu.log" ) {
                        system "cp -f $buLog $OUTLOG_DIR/$area/_orig_$bu.log";
                    }
                }
                my $buSummary = "$OUTLOG_DIR/$area/$bu.summary.txt";
                if( -e "$buSummary" ) {
                    if( ! -e "$OUTLOG_DIR/$area/_orig_$bu.summary.txt" ) {
                        system "cp -f $buSummary $OUTLOG_DIR/$area/_orig_$bu.summary.txt";
                    }
                }
            }
        }
    }
    my $flagExec = 0;
    # execution (or not)
    if($OptionsBuildPl) {
        print "\n\n","#" x  length "command line :","\n";
        print "command line :\n\n";
        print "\n$BuildPlCommand $OptionsBuildPl -B\n";
        if($QuietMode) {
            if ( -e "$SRC_DIR") {
                execBuildPL("$BuildPlCommand $OptionsBuildPl -B");
                retouch_dat_for_inc_target();
                $flagExec = 1;
            } else {
                print "\nERROR '$Context' is not on this build machine '$HOST', no execution\n";
            }
        }
        if($noExec) {
            print "\n no execution\n\n";
        }
        if( !$QuietMode && !$noExec ) {
            print "would you like to execute this command ? (y/n)\n";
            my $readRep = <STDIN> ;
            chomp $readRep;
            if($readRep =~ /^y/i) { #'Y' or 'y' answerd only available to follow
                if ( -e "$SRC_DIR") {
                    execBuildPL("$BuildPlCommand $OptionsBuildPl -B");
                    retouch_dat_for_inc_target();
                    $flagExec = 1;
                } else {
                    print "\nERROR '$Context' is not on this build machine '$HOST', no execution\n";
                }
            } else {
                print "\n no execution\n\n";
            }
        }
        ## save logs
        if($KeepRefLogs) {
            if($flagExec == 1 ) {
                my $inc=0;
                if($BuildNumber =~ /\.(\d+)$/) {
                $inc = $1;
                }
                foreach my $area (sort keys %AREAS) {
                    next if($paramAreasToRebuild     && ($areasFoundInList{$area}==0) ); #if -a=xxx but not found
                    next if($paramSkipAreasToRebuild && ($areasToSkip{$area}==1) );      #if -na=xxx but found in the list
                    foreach my $bu (sort @{$AREAS{$area}} ) {
                        ($bu) =~ s-\s+.+?$--;
                        my $buLog = "$OUTLOG_DIR/$area/$bu.log";
                        if( -e "$buLog" ) {
                            system "mv -f $buLog $OUTLOG_DIR/$area/_${inc}_$bu.log";
                        }
                        my $buSum = "$OUTLOG_DIR/$area/$bu.summary.txt";
                        if( -e "$buSum" ) {
                            system "mv -f $buSum $OUTLOG_DIR/$area/_${inc}_$bu.summary.txt";
                        }
                        #restore original logs
                        if( -e "$OUTLOG_DIR/$area/_orig_$bu.log" ) {
                            system "cp -f $OUTLOG_DIR/$area/_orig_$bu.log $buLog";
                        }
                        if( -e "$OUTLOG_DIR/$area/_orig_$bu.summary.txt" ) {
                            system "cp -f $OUTLOG_DIR/$area/_orig_$bu.summary.txt $buSum";
                        }
                    }
                }
            }
        }
    } else {
        print "nothing to compile, check your option(s)/parameter(s)\n";
    }
} else {
    if($flagMergedDUs == 1) { # only merged_DUS to redo
        print "$BuildPlCommand -B\n";
        print "\n\n","#" x length "command line :","\n";
        print "command line :\n\n";
        print "\n$BuildPlCommand -B\n";
        if($QuietMode) {
            if ( -e "$SRC_DIR") {
                execBuildPL("$BuildPlCommand -B");
                retouch_dat_for_inc_target();
            } else {
                print "\nERROR '$Context' is not on this build machine '$HOST', no execution\n";
            }
        }
        if($noExec) {
            print "\n no execution\n\n";
        }
        if( !$QuietMode && !$noExec ) {
            print "would you like to execute this command ? (y/n)\n";
            my $readRep = <STDIN> ;
            chomp $readRep;
            if($readRep =~ /^y/i) { #'Y' or 'y' answerd only available to follow
                if ( -e "$SRC_DIR") {
                    execBuildPL("$BuildPlCommand -B");
                    retouch_dat_for_inc_target();
                } else {
                    print "\nERROR '$Context' is not on this build machine '$HOST', no execution\n";
                }
            } else {
                print "\n no execution\n\n";
            }
        }
    } else {
        print "\nnothing to rebuild\n";
    }
}

endScript();



##############################################################################
### my functions

sub setBuildRef() {
    my $versionFound = getBuildRev();
    #if -r=. just '.' without number, get last incremental build and set it as reference
    if($refBuildNumber) {
        if($refBuildNumber =~ /^\.$/) {
            my $thisFullBuildNumber = sprintf "%05d",$versionFound;
            my $thisFullBuildNameVersion = "${Context}_$thisFullBuildNumber";
            my $indice = getLastIncremental($thisFullBuildNameVersion,$versionFound);
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

sub getBuildRev() {
    my $tmp = 0;
    if(open VER,"$DROP_DIR/$Context/version.txt") {
        chomp($tmp = <VER>);
        $tmp = int $tmp;
        close VER;
    }
    else
    {
        # open current context dir to find the hightest directory version inside
        if(opendir BUILDVERSIONSDIR, "$DROP_DIR/$Context") {
            while(defined(my $next = readdir BUILDVERSIONSDIR))
            {
                $tmp = $1 if ($next =~ /^(\d+)(\.\d+)?$/ && $1 > $tmp && -d "$DROP_DIR/$Context/$next");
            }   
            closedir BUILDVERSIONSDIR;
        }
    }
    return $tmp;
}


sub buildDatFile() { #for offline mode
    my $outPutDatfile = "$OUTLOG_DIR/$Context.dat";
    my $logPath = $OUTLOG_DIR;
    ($logPath) =~ s-\\-\/-g;
    print "\nOffline mode, parsing $logPath, please wait  . . .\n";
    my $findCmd = ($^O eq "MSWin32") ? "C:/cygwin/bin/find.exe" : "/usr/bin/find";
    my @tmpSummaries = `$findCmd $logPath -name \"*.summary.txt\" 2>&1`;
    my %Summaries;
    #search all summaries files with error
    foreach my $summary (@tmpSummaries) {
        chomp $summary;
        ($summary) =~ s-\\-\/-g;
        next if($summary =~ /\/Build\//);    #skip Build folder
        next if($summary =~ /\/assemble\-/); #skip assemble-*
        next if($summary =~ /\/\_orig\_/);   #skip logs beginning with _orig_
        my $foundErrors = `grep \"Sections with errors:\" $summary | grep -v 0`;
        chomp $foundErrors;
        if($foundErrors) {
            $Summaries{$summary}=1;
        }
    }

    #determine nb errors
    my $nbTotalErrors = 0;
    my $lineForDat;
    foreach my $summary (keys %Summaries) {
        my $unit = basename($summary);
        ($unit) =~ s-\.summary\.txt$--;
        if(open SUMMARY,"$summary") {
            my $area;
            my $startBU;
            my $endBU;
            my $nbErrorsBU = 0;
            while(<SUMMARY>) {
                chomp;
                if(/\s+area\=(.+?)\,\s+/)               { $area         = $1 ; next; }
                if( (/Build start/) && (/\((\d+)\)$/) ) { $startBU      = $1 ; next; }
                if( (/Build end/) && (/\((\d+)\)$/) )   { $endBU        = $1 ; next; }
                if(/\[ERROR\s+\@/)                      { $nbErrorsBU++      ; next; }
            }
            close SUMMARY;
            $lineForDat   .= "[$nbErrorsBU,'Host_1/$unit=${PLATFORM}_${BUILD_MODE}_build.log'";
            $lineForDat   .= ",'Host_1/$unit=${PLATFORM}_${BUILD_MODE}_summary_build.txt'";
            $lineForDat   .= ",'$area','$startBU','$endBU'],";
            $nbTotalErrors = $nbTotalErrors + $nbErrorsBU;
        }
    }
    #write dat file
    if(defined $lineForDat) {
        ($lineForDat) =~ s-\,$--;
        $lineForDat = "($nbTotalErrors,$lineForDat);";
    }
    open DAT,">$outPutDatfile" or die "ERROR: cannot create '$outPutDatfile': $!";
        print DAT "\@Errors = $lineForDat";
    close DAT;
}

#
sub getLastIncremental($$) {
    # if -v=+ or -v=++, need to know the last incremental build before increment it
    my ($fullBuildNameVersion,$refVersion) = @_;
    my $localIndice=0;
    if(opendir BUILDVERSIONSDIR,"$ENV{HTTP_DIR}/$Context") {
        my $fullBuildNumber = sprintf "%05d",$refVersion;
        my $fullBuildNameVersion = "${Context}_$fullBuildNumber";
        while(defined(my $buildNameVersion = readdir BUILDVERSIONSDIR)) {
            next if( $buildNameVersion =~ /^\./ );
            next if( -f "$ENV{HTTP_DIR}/$Context/$buildNameVersion" );
            if( ($buildNameVersion =~ /^$fullBuildNameVersion/i) && ($buildNameVersion =~ /\.(\d+)$/) ) {
                $localIndice = $1 if($1 > $localIndice);
            }
        }
        closedir BUILDVERSIONSDIR;
    }
    return  $localIndice;   
}

sub parseDatFile($$$$$) { #need to list which build units have to be rebuilt
    my ($thisPlatform,$thisBuildMode,$step,$datFile,$these_patterns) = @_;
    my $baseOn = sprintf "%05d",$refBuildNumber;
    if ($refBuildNumber =~ /\.(\d+)$/ ) { #if ref build is incremental version
        $baseOn .=".$1";
    }
    my $buildName  = "${Context}_$baseOn";
    my $HTTPDIR    = "$ENV{HTTP_DIR}/$Context";
    $datFile    ||= "$HTTPDIR/$buildName/$buildName=${thisPlatform}_${thisBuildMode}_${step}_1.dat";
    ($datFile) =~ s-\\-\/-g ;
    die "ERROR: '$datFile' does not exist" if ( ! -e "$datFile" );
    #check if file is well complete
    my $delayStart = 1;
    sleep 1;
    if(open DAT, $datFile) {
        while(<DAT>) {
            chomp;
            if( /\]\)\;$/ ) { # if finish well
                $delayStart = 0;
                last;
            }
        }
        close DAT;
    }
    sleep 10 if($delayStart == 1);
    sleep 1;

    if(open DAT,$datFile) {
        eval <DAT>;
        close DAT;
    }
    if(@Errors) {
        foreach my $error (@Errors) {
            next unless(@{$error}[1]);
            next unless(@{$error}[3]);
            (my $buildUnit) = @{$error}[1] =~ /Host_1\/(.+?)\=/ ;
            #if($buildUnit =~ /merged_DUs/i) {
            #   $flagMergedDUs = 1 if( @{$error}[0] > 0 );
            #   next;
            #}
            if( -e $SRC_DIR && !($buildUnit =~ /\_step$/i) && ! $opt_pas ) { #not a bpl step
                # remove multi version name in area name (tp case) to determine real gmk name
                my $gmkName = @{$error}[3];
                ($gmkName) =~ s-\/.+?$--; 
                next if( ! -e "$SRC_DIR/@{$error}[3]/$gmkName.gmk");
            }
            if( @{$error}[0] eq "" ) {
                if($JustMissingCompile) {
                    my $refTimeStart =  @{$error}[4] || "na";
                    my $refTimeEnd   =  @{$error}[5] || "na";
                    push @{$ErrorsSortedByStart{$refTimeStart}},"@{$error}[3],$buildUnit,na,$refTimeEnd";
                }
            } else {
                next if( @{$error}[0] == 0 );
                next if($JustMissingCompile);
                next if( ($buildUnit eq "inc") && (@{$error}[3] eq "inc") );
                ($buildUnit) =~ s-\_step$--i;
               	next if( $these_patterns && !(grep /^$buildUnit$/i , @$these_patterns) );
                push @{$ErrorsSortedByStart{@{$error}[4]}},"@{$error}[3],$buildUnit,@{$error}[0],@{$error}[5]";
                my $nberror = @{$error}[0];
                chomp $nberror;
                $ErrorsPerPlatform{$thisPlatform}{$thisBuildMode}{$step} =
                    $ErrorsPerPlatform{$thisPlatform}{$thisBuildMode}{$step}
                    + $nberror ;
            }
        }
    }
    if( (keys %ErrorsSortedByStart) >0 ) {
        if($NoDisplayTimes==0) {
            unless($tinyStatus) {
                print "\nbuild unit(s)/deployment unit(s) in error(s), sort by time of build unit :\n";
                print "output format :\n";
                print "===================================================\n";
                print "start time\n";
                print "\tarea\n";
                print "\t\tbuild unit | nb error(s) | duration\n";
                print "===================================================\n\n";
            }
        }
        my $numError = 0;
        foreach my $start (sort keys %ErrorsSortedByStart) {
            last if($nbFirstErrors && ($numError == $nbFirstErrors) );
            my $displayTime = ($start eq "na") ? "na" : FormatDate($start);
            if($paramAreasToRebuild) {
                my $found = 0;
                foreach my $startbu (sort @{$ErrorsSortedByStart{$start}} ) {
                    my ($area,$bu,$nberror,$endCompile) = split ',',$startbu;
                    foreach my $areaSelected (@AreasToRebuild) {
                        if( $area =~ /^$areaSelected/i) {
                            $found++;
                            last;
                        }
                    }
                }
                if($found>0) {
                    unless($tinyStatus) {
                        print "\n$displayTime\n" if($NoDisplayTimes==0);
                    }
                }
            } else {
                unless($tinyStatus) {
                    print "\n$displayTime\n"   if($NoDisplayTimes==0);
                }
            }
            my $previousArea = "No_Area_Just_Init_For_Script";
            foreach my $startbu (sort @{$ErrorsSortedByStart{$start}} ) {
                my ($area,$bu,$nberror,$endCompile) = split ',',$startbu;
                my $skipNotArea = 0;
                foreach my $cmd (@BuildCmds) {
                    if ( ($area eq ${$cmd}[1]) && ($bu eq ${$cmd}[1]) && !$opt_pas ) {
                    # the area and the build unit have the same name than a target
                    # in section buildcmd, it is not a real area, skip
                        $skipNotArea = 1;
                        last;
                    }
                }
                next if($skipNotArea == 1);
                my $found = 0;
                if($paramAreasToRebuild) {
                    foreach my $startbu (sort @{$ErrorsSortedByStart{$start}} ) {
                        my ($area,$bu,$nberror) = split ',',$startbu;
                        foreach my $areaSelected (@AreasToRebuild) {
                            if( $area =~ /^$areaSelected/i) {
                                $found++;
                                last;
                            }
                        }
                    }
                }
                next if($paramAreasToRebuild && ($found==0) );
                push @{$AREAS{$area}},"$bu $nberror";
                unless($tinyStatus) {
                    print "\t$area\n" if( ($previousArea ne $area) && ($NoDisplayTimes==0) );
                }
                my $totalTimeDisplay;
                unless(($start eq "na") || ($endCompile eq "na")) {
                    $totalTimeDisplay = HHMMSS($endCompile - $start);
                }
                $totalTimeDisplay = "| $totalTimeDisplay" if($totalTimeDisplay);
                my $displayErrors;
                $displayErrors = "| $nberror error(s)"  unless($nberror eq "na");
                unless($tinyStatus) {
                    if($NoDisplayTimes==0) {
                        print "\t\t$bu $displayErrors $totalTimeDisplay\n";
                    }
                }
                $previousArea = $area;
            }
            $numError++;
        }
        #print "\n";
    }
    exit if($DisplayTimesOnly);
}

sub reBuildAreas(@) {
    my (@areas) = @_;
    my $displayListAreas = join ',',@areas;
    print "\n\n rebuild all Areas '$displayListAreas'\n\n";

    print " 1 - Cleans\n\n";
    my @dirs = qw(bin obj deploymentunits logs lib tlb pdb);
    foreach my $area (@areas) {
        print "$area\n";
        (my $areaGMK = $area ) =~ s/\/.+?$//;
        (my $areaLog = $area ) =~ s/\//\_/;
        if( -e "$SRC_DIR/$area/$areaGMK.gmk") {
            # 1 make -f $areaGMK.gmk clean
            print "\tmake -f $areaGMK.gmk clean\n";
            chdir "$SRC_DIR/$area";
            my $cleanAreaLog = "$OUTPUT_DIR/logs/Build/rb_clean_$areaLog.log";
            system "make -f $areaGMK.gmk clean > $cleanAreaLog 2>&1";
            # 2 clean folders $OUT_*/*/area
            foreach my $dir (@dirs) {
                if(-e "$OUTPUT_DIR/$dir/$area") {
                    print "\t$OUTPUT_DIR/$dir/$area\n";
                    rmtree("$OUTPUT_DIR/$dir/$area");
                }
            }
            # 3 p4clean $area to ensure there is no hijacks
            # and remove intermediate files in $SRC_DIR/area
            print "\tperl $CURRENTDIR/P4Clean.pl -c=$Client -a=\"$area\"\n";
            chdir "$CURRENTDIR";
            my $p4CleanLog = "$OUTPUT_DIR/logs/Build/rb_p4clean_$areaLog.log";
            system "$CURRENTDIR/P4Clean.pl -c=$Client -a=\"$area\" > $p4CleanLog 2>&1";
            # 4 recreate folders with init target and ensure all paths are created
            my $initAreaLog = "$OUTPUT_DIR/logs/Build/rb_init_$areaLog.log";
            system "make -f $area.gmk init > $initAreaLog 2>&1";
            foreach my $dir (@dirs) {
                unless( -e "$OUTPUT_DIR/$dir/$area") {
                    mkpath("$OUTPUT_DIR/$dir/$area");
                }
            }
        }
        print "\n";
    }
    # resyncs after a p4clean
    # resync if -cl=...
    if($paramChangeLists) {
        @ChangeLists = split ',',$paramChangeLists;
        foreach my $cl (sort @ChangeLists) {
            print "\nsync $cl :\n";
            my $syncLog = "$OUTPUT_DIR/logs/Build/rb_sync_$cl.log";
            system "p4 -c $Client sync -f //...\@$cl,$cl > $syncLog 2>&1";
        }
    }
    # resync list of p4dir
    if($paramP4Dirs) {
        @P4Dirs = split ',',$paramP4Dirs;
        foreach my $p4dir (sort @P4Dirs) {
            print "\nsync $p4dir :\n";
            my $syncLog = "$OUTPUT_DIR/logs/Build/rb_sync_p4dir.log";
            if($p4dir =~ /\/\.\.\.$/) { # simple sync if p4 dir finish by /...
                system "p4 -c $Client sync $p4dir >>  $syncLog 2>&1";
            } else { # force sync if p4 dir is a file
                system "p4 -c $Client sync -f $p4dir >> $syncLog 2>&1";
            }
            system "cat $syncLog" if( -e "$syncLog");
        }
    }
    #build -a option and create folders: $OUT_*/*/area
    my $optAreas;
    foreach my $area (@areas) {
        (my $areaGMK = $area ) =~ s/\/.+?$//;
        if( -e "$SRC_DIR/$area/$areaGMK.gmk") {
            foreach my $dir (@dirs) {
                mkpath("$OUTPUT_DIR/$dir/$area");
            }
            $optAreas .= " -a=\"$area\"";
        }
    }
    $optAreas .= " -B";
    print "\n 2 - Rebuild\n";
    print "$BuildPlCommand $optAreas\n";
    chdir "$CURRENTDIR";
    execBuildPL("$BuildPlCommand $optAreas");
    if($optExport) {
        my $exportOption = " -e=";
        foreach my $area (@areas) {
            $exportOption .= "bin/$area,";
        }
        ($exportOption) =~ s-\,$-- if($exportOption =~ /\,$/);
        print "\n 3 - Rebuild\n";
        print "$BuildPlCommand -E $exportOption\n";
        system "$BuildPlCommand -E $exportOption 2>$NULLDEVICE";
        retouch_dat_for_inc_target();
    }
    print "\n\n";
    print "\nEND of '$0', at ",scalar localtime,"\n\n";
    exit;
}

sub retouch_dat_for_inc_target() {
    # some init vars
    my $baseOn = sprintf "%05d",$BuildNumber;
    $baseOn .=".$1" if($BuildNumber =~ /\.(\d+)$/ ); #if ref build is incremental version
    my $buildName   = "${Context}_$baseOn";
    my $HTTPDIR     = "$ENV{HTTP_DIR}/$Context";
    my $CISdatFile  = "$HTTPDIR/$buildName/";
    $CISdatFile    .= "$buildName=${PLATFORM}_${BUILD_MODE}_build_1.dat";
    ($CISdatFile) =~ s-\\-\/-g;
    #parse dat file
    if(open DAT,$CISdatFile) {
        eval <DAT>;
        close DAT;
    }
    if(@Errors) {
        my $lineDat;
        my $nbTotalError = 0;
        foreach my $error (@Errors) {
            my $nbError = @{$error}[0];
            next unless(defined $nbError);
            $nbError = 0 if(@{$error}[3] =~ /^inc$/); # set nb error to 0 if inc target
            $nbTotalError = $nbTotalError + $nbError;
            $lineDat .= ",[$nbError";
            for my $number (1..5) {
                $lineDat .= ",'@{$error}[$number]'";
                $lineDat .= "]" if($number == 5);
            }
        }
        $lineDat = "\@Errors = ($nbTotalError $lineDat);";
        if(open NEW_DAT,">$CISdatFile") {
            print NEW_DAT $lineDat;
            close NEW_DAT;
        }
    }
}

sub listCurrentGreatests($) {
    my ($XMLContext) = @_;
    my $CONTEXT = XML::DOM::Parser->new()->parsefile($XMLContext);
    my ($versionInContext) = $CONTEXT->getElementsByTagName("version")
                             ->item(0)->getFirstChild()->getData()
                             =~ /\.(\d+)$/;
    $CONTEXT->dispose();
    return  $versionInContext;
}

sub execBuildPL($) {
    my ($command) = @_;
    if(open BUILD_PL,"$command 2>&1 |") {
        while(<BUILD_PL>) {
            next if(/error\:\s+unable\s+to\s+empty\s+file/i);
            next if(/error\:\s+called\s+by\:\s+XLogging\:\:xLogOpen/i);
            print $_;
        }
        close BUILD_PL;
    }   
}

sub listAllInisIncluded($) {
    my ($iniFile) = @_ ;
    my $iniName = basename($iniFile);
    my @initsFound;
    if(open INI,$iniFile) {
        while(<INI>) {
            chomp;
            s-\${CURRENTDIR\}-$CURRENTDIR- if(/CURRENTDIR/);
            if(/^\#include\s+(.+?)$/) {
                my $iniFileFound = $1;
                my $initFound = basename($iniFileFound);
                push @Inis,$initFound;
                push @initsFound,$iniFileFound;
            }
        }
        close INI;
        foreach my $ini (@initsFound) {
            listAllInisIncluded($ini);
        }
    }
}


##############
sub Usage($) {
    my ($msg) = @_ ;
    if($msg) {
        print STDERR "

\tERROR:
\t======
$msg
";
    }
    print <<FIN_USAGE;

    Description : $0 can detect which area(s), which build unit(s) to rebuild.
No need to open web browser, search build unit(s) in error, copy-paste them to the command line ...
It can also display the time order of build unit(s) in error.
It can save a build failed only due to dependency issues, with the '2ndChance' target in the ini file. The incremental version should be -v=xxx.01
    Usage   : perl $0 [options]
    Example : perl $0 -h

 [options]
    -64      Force the 64 bits compilation (-64) or not (-no64), default is -no64 i.e 32 bits,
    -A       Choose a list of areas to rebuild, with a clean only on these selected areas, separated with ','
                eg.: -A=areaA,areaB,areaC
    -CA      Clean only area(s) containing compile issue(s) and rebuild fully this/these area(s)
    -E       Export bin/area(s) built by -A=areaA,areaB,areaC
    -F       Execute 'perl Build.pl ... -F'
    -I       Execute 'perl Build.pl ... -I'
    -N       No execution of Build.pl called in $0
                cannot use -N with -Q
    -Q       Quiet mode, Suppresses prompting to confirm you want to execute Build.pl called in $0
                cannot use -Q with -N
    -a       Choose a list of failed areas, separated with ','
                eg.: -a=areaA,areaB,areaC
    -b       Choose a buildname, by default: -b=$Context
    -bus     Force recompilation specific build unit(s)
                eg.: -bus=areaA:buA1,buA2;areaB:buB1,buB2
    -cl      List of changelit(s) to sync to not use Build.pl -F (to skip to refetch all), separated with ','
                e.g.: -cl=cl1,cl2
    -dto     Display Times Only, display only times
    -h|?     Argument displays helpful information about builtin commands.
    -i       Choose an ini file, by default: -i=contexts/buildname.ini,
                without -b option, -i=contexts/$Context.ini,
    -jenkins If rebuild.pl is executed through jenkins, make a sleep 10
    -jm      Build only missed build units which they are not compiled yet
    -kl      Keep logs of reference version (-E -e=logs, in $OUTLOG_DIR,
                logs of BUs rebuilt are saved as _orig_\$buName.log, _orig_\$buName.summary.txt
                and new logs are renamed as _\$incremental_\$buName.log, _\$incremental_\$buName.summary.txt
                if [version = xxx.y] then \$incremental = y
    -l       If -ofl, you can also choose a specific $OUTLOG_DIR to scan,
                by default -l=\$OUTLOG_DIR
    -m       Choose a compile mode,
                same usage than Build.pl -m=
    -na      Choose to skip a list of failed areas, separated with ','
                eg.: -na=areaA,areaB,areaC
    -nci     rebuild.pl, by default, does not recompile anything for jlin and/or 40fy builds,
                but if it is really requested, use -nci
    -ndt     Not Display Times, to skip display times
    -nfe     Display the N First Error(s)
    -oas     Over All Status for all platforms done, each column of CIS dashboard done
                make -oas=help to list available values
    -ofl     Scan summaries in $OUTLOG_DIR (except for 'Build' folder)
                create $OUTLOG_DIR/$Context.dat if not found
    -om      Choose an object model (-om=32 or -om=64)
                used for automatization through jenkins (ujg)
    -p       With deploymentunits (build units started by 'package.')
    -p4dirs  Fetch p4dirs
                if p4dirs finished by '/...', a simple 'p4 sync' is executed
                if p4dirs finished by a file (e.g.:'/toto.java') , 'p4 sync -f' is executed
                p4dirs should be in clientspec otherwise, p4 will raise up an error 
    -pas     Fix parse issue when not aurora projects (now check target compile in ini file)
    -pf      Choose a specific platform, permit to have a quick status without connecting on build machine, or on a dashboard
    -pfa     List of area(s) to fetch, should be in the clientspec
    -po      With ONLY deploymentunits (build units started by 'package.')
    -q.set   Sets environment variables. Syntax is -q=variable:string,
                same usage than Build.pl
    -r       Choose a reference version
                -r=xxx
                -r=xxx.y
                -r=.y (use 'y' as reference, xxx is automaticaly calculated by the script)
                -r=. (find last incremental version and use it as reference)
    -rtinc   $0 just retouch the build dat file in CIS, to set nb error=0 for inc target only, and exit
    -si      Just diplays some specific information and exit.
                make perl $0 -si=help to have more details.
    -s       Choose a site, by default: -s=$Site
    -ti      Execute targets in ini file
    -ts      Tiny status, $0 returns ONLY (without any other information):
                tiny status:  failed and $0 exit with returning error code (exit 1)
                or
                tiny status:  passed and $0 exit with returning error code (exit 0)
                and exit (used for voting builds).
    -v       Choose a version, usages:
                -v=xxx
                -v=xxx.y
                -v=.y
                -v=+ (auto increment the minor version, .y only if the .'y-1' incremental build was done)
                -v=++ (FORCE auto increment the minor version, .y)

for more details see:
https://wiki.wdf.sap.corp/wiki/display/MultiPlatformBuild/rebuild.pl+user+guide


FIN_USAGE
    exit;
}

sub startScript() {
    my $dateStart = scalar localtime;
    print "\nSTART of '$0' at $dateStart\n";
    print "#" x length "START of '$0' at $dateStart","\n";
    print "\n";
}

sub endScript() {
    print "\n\n";
    my $dateEnd = scalar localtime;
    print "#" x length "END of '$0' at $dateEnd","\n";
    print "END of '$0' at $dateEnd\n";
    exit;
}



##############################################################################
### functions from Build.pl, requested to parse the ini file
sub ReadIni
{
    my @Lines = PreprocessIni($Config);
    my $i = -1;
    SECTION: for($_=$Lines[++$i]; $i<@Lines; $_=$Lines[++$i])
    {
        next unless(my($Section) = /^\[(.+)\]/);
        for($_=$Lines[++$i]; $i<@Lines; $_=$Lines[++$i])
        {
            redo SECTION if(/^\[(.+)\]/);
            next if(/^\s*$/ || /^\s*#/);
            s/^\s*//;
            s/\s*$//;
            chomp;
            if($Section eq "version")            { $Version = $_; Monitor(\$Version) } 
            elsif($Section eq "buildoptions")    { $BuildOptions = $_; Monitor(\$BuildOptions) } 
            elsif($Section eq "options")         { $Options = $_; Monitor(\$Options) } 
            elsif($Section eq "context")         { $Context = $_; Monitor(\$Context) } 
            elsif($Section eq "project")         { $Project = $_; Monitor(\$Project) } 
            elsif($Section eq "client")          { $Client = $_; Monitor(\$Client) } 
            elsif($Section eq "config")          { $ConfigFile = $_; Monitor(\$ConfigFile) } 
            elsif($Section eq "prefetchcmd")     { push(@PrefetchCmds, [split('\s*\|\s*', $_)]); Monitor(\${$PrefetchCmds[-1]}[2]) } 
            elsif($Section eq "dependenciescmd") { push(@DependenciesCmds, [split('\s*\|\s*', $_)]); Monitor(\${$DependenciesCmds[-1]}[2]) } 
            elsif($Section eq "packagecmd")      { push(@PackageCmds, [split('\s*\|\s*', $_)]); Monitor(\${$PackageCmds[-1]}[2]) } 
            elsif($Section eq "cleancmd")        { push(@CleanCmds, [split('\s*\|\s*', $_)]); Monitor(\${$CleanCmds[-1]}[2]) } 
            elsif($Section eq "buildcmd")        { push(@BuildCmds, [split('\s*\|\s*', $_)]); Monitor(\${$BuildCmds[-1]}[2]) } 
            elsif($Section eq "mailcmd")         { push(@MailCmds, [split('\s*\|\s*', $_)]); Monitor(\${$MailCmds[-1]}[2]) } 
            elsif($Section eq "testcmd")         { push(@TestCmds, [split('\s*\|\s*', $_)]); Monitor(\${$TestCmds[-1]}[2]) } 
            elsif($Section eq "smokecmd")        { push(@SmokeCmds, [split('\s*\|\s*', $_)]); Monitor(\${$SmokeCmds[-1]}[2]) }  
            elsif($Section eq "validationcmd")   { push(@ValidationCmds, [split('\s*\|\s*', $_)]); Monitor(\${$ValidationCmds[-1]}[2]) }  
            elsif($Section eq "reportcmd")       { push(@ReportCmds, [split('\s*\|\s*', $_)]); Monitor(\${$ReportCmds[-1]}[2]) }  
            elsif($Section eq "exportcmd")       { push(@ExportCmds, [split('\s*\|\s*', $_)]); Monitor(\${$ExportCmds[-1]}[2]) }  
            elsif($Section eq "export")          { push(@Exports, $_); Monitor(\$Exports[-1]) } 
            elsif($Section eq "adapt")           { push(@Adapts, $_); Monitor(\$Adapts[-1]) } 
            elsif($Section eq "cachereport")     { $CACHEREPORT_ENABLE = "yes"=~/^$_/i ? 1 : 0 } 
            elsif($Section eq "monitoring")      { push(@BMonitors, [split('\s*\|\s*', $_)]); Monitor(\${$BMonitors[-1]}[0]); Monitor(\${$BMonitors[-1]}[1]);}
            elsif($Section eq "gitview")         { push(@GITViews, [split('\s*\|\s*', $_)]); map({Monitor(\$_)} @{$GITViews[-1]}) }
            elsif($Section eq "nexusimport")     { push(@NexusImports, [split('\s*\|\s*', $_)]); map({Monitor(\$_)} @{$NexusImports[-1]}) }
            elsif($Section eq "view")
            { 
                my $Line = $_;
                if($Line =~ s/\\$//)
                { 
                    for($_=$Lines[++$i]; $i<@Lines; $_=$Lines[++$i])
                    {
                        redo SECTION if(/^\[(.+)\]/);
                        s/^\s*//;
                        s/\s*$//;
                        chomp;
                        $Line .= $_;
                        $Line =~ s/\s*\\$//;
                        last unless(/\\$/);
                    }
                    $Line = join(",", split(/\s*,\s*\\\s*/, $Line));
                }
                push(@Views, [split('\s*\|\s*', $Line)]);
                if($Views[-1][0] =~ /^get/i) { ${$Views[-1]}[1] ||= '${REF_WORKSPACE}' }
                else { ${$Views[-1]}[1] ||= (${$Views[-1]}[0]=~/^[-+]?\/{2}(?:[^\/]*[\/]){3}(.+)$/, "//\${Client}/$1") }
                ${$Views[-1]}[2] ||= '@now';
                for my $n (0..2) { Monitor(\${$Views[-1]}[$n]) }
            } 
            elsif($Section eq "import")
            { 
                my $Line = $_;
                if($Line =~ s/\\$//)
                { 
                    for($_=$Lines[++$i]; $i<@Lines; $_=$Lines[++$i])
                    {
                        redo SECTION if(/^\[(.+)\]/);
                        s/^\s*//;
                        s/\s*$//;
                        chomp;
                        $Line .= $_;
                        $Line =~ s/\s*\\$//;
                        last unless(/\\$/);
                    }
                    $Line = join(",", split(/\s*,\s*\\\s*/, $Line));
                }
                push(@Imports, [split('\s*\|\s*', $Line)]);
                for my $n (0..3) { Monitor(\${$Imports[-1]}[$n]) }
            } 
            elsif($Section eq "root")
            { 
                my $Platform;
                ($Platform, $Root) = split('\s*\|\s*', $_);
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL);
                ($SRC_DIR = $Root) =~ s/\\/\//g;
            } 
            elsif($Section eq "environment") 
            { 
                my($Platform, $Env) = split('\s*\|\s*', $_);
                unless($Env) { $Platform="all"; $Env=$_ }
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL); 
                my($Key, $Value) = $Env =~ /^(.*?)=(.*)$/;
                next if(grep(/^$Key:/, @QSets));
                $Value = ExpandVariable(\$Value) if($Key=~/^PATH/);
                $Value = ExpandVariable(\$Value) if($Value =~ /\${$Key}/);                
                ${$Key} = $Value;
                $ENV{$Key} = $Value;
                Monitor(\${$Key}); Monitor(\$ENV{$Key});
                push(@ENVVARS,$Key) unless(grep /^$Key$/,@ENVVARS);
            }
            elsif($Section eq "localvar") 
            { 
                my($Platform, $Var) = split('\s*\|\s*', $_);
                unless($Var) { $Platform="all"; $Var=$_ }
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL); 
                my($Key, $Value) = $Var =~ /^(.*?)=(.*)$/;
                next if(grep(/^$Key:/, @QSets));
                $Value = ExpandVariable(\$Value) if($Value =~ /\${$Key}/);
                ${$Key} = $Value;
                Monitor(\${$Key});
                push(@ENVLOCALVARS,"$Key=$Value") unless(grep /^$Key\=/,@ENVLOCALVARS);
            } 
            elsif($Section eq "astec")
            {
                my($Platform, $KeyValue) = /\|/ ? split('\s*\|\s*', $_) : ("all", $_);
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL);
                my($Key, $Value) = split('\s*=\s*', $KeyValue); ${"ASTEC$Key"} = $Value;
                Monitor(\${"ASTEC$Key"});
            }
            elsif($Section eq "qac")
            {
                my($Platform, $KeyValue) = /\|/ ? split('\s*\|\s*', $_) : ("all", $_);
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL);
                my($Key, $Value) = split('\s*=\s*', $KeyValue);
                if($Key eq "package")
                {
                    my($Name, $BuildType, $Extent, $Suite, $Phase, $Reference) = split('\s*,\s*', $Value);
                    $ENV{"BUILDTYPE_\U$Name"} = $BuildType;
                    push(@QACPackages, [$Name, $BuildType, $Extent, $Suite, $Phase, $Reference]);
                    Monitor(\${$QACPackages[-1]}[0]); Monitor(\${$QACPackages[-1]}[1]); Monitor(\${$QACPackages[-1]}[2]); Monitor(\${$QACPackages[-1]}[3]); Monitor(\${$QACPackages[-1]}[4]);Monitor(\${$QACPackages[-1]}[5]);Monitor(\$ENV{"BUILDTYPE_\U$Name"});
                }
                else { ${"QAC$Key"} = $Value; Monitor(\${"QAC$Key"}) }
            }
            elsif($Section eq "gtx")
            {
                my($Platform, $KeyValue) = /\|/ ? split('\s*\|\s*', $_) : ("all", $_);
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL);
                my($Key, $Value) = split('\s*=\s*', $KeyValue);
                if($Key eq "package")
                {
                    my($GTxPackage, $GTxExtend, $GTxLanguage, $GTxPatch, $GTxReplicationSites) = split('\s*,\s*', $Value);
                    push(@GTxPackages, [$GTxPackage, $GTxExtend, $GTxLanguage, $GTxPatch, $GTxReplicationSites]);
                    Monitor(\${$GTxPackages[-1]}[0]); Monitor(\${$GTxPackages[-1]}[1]); Monitor(\${$GTxPackages[-1]}[2]);
                }
                else { ${"GTx$Key"} = $Value; Monitor(\${"GTx$Key"}) }                
            }
            elsif($Section eq "cwb")
            {
                my($Platform, $KeyValue) = /\|/ ? split('\s*\|\s*', $_) : ("all", $_);
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL);
                my($Key, $Value) = split('\s*=\s*', $KeyValue);
                ${"CWB$Key"} = $Value; Monitor(\${"CWB$Key"});                
            }
            elsif($Section eq "incrementalcmd")
            { 
                my($Platform, $Name, $Command, $Makefile) = split('\s*\|\s*', $_);
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL); 
                @IncrementalCmds = ($Name, $Command, $Makefile);
                $IncrementalCmd = $Command;
                Monitor(\$IncrementalCmds[1]); Monitor(\$IncrementalCmds[2]); Monitor(\$IncrementalCmd);
            } 
        }
    }
}

sub PreprocessIni 
{
    my($File, $rhDefines) = @_; $File=ExpandVariable(\$File); $File =~ s/[\r\n]//g;
    my(@Lines, $Define);
   
    my $fh = new IO::File($File, "r") or die("ERROR: cannot open '$File': $!");
    while(my $Line = $fh->getline())
    {
        $Line =~ s/^[ \t]+//; $Line =~ s/[ \t]+$//;
        if(my($Defines) = $Line =~ /^\s*\#define\s+(.+)$/) { @{$rhDefines}{split('\s*,\s*', $Defines)} = (undef) }
        elsif(($Define) = $Line =~ /^\s*\#ifdef\s+(.+)$/)
        {
            next if(exists(${$rhDefines}{$Define}));
            while(my $Line = $fh->getline()) { last if($Line =~ /^\s*\#endif\s+$Define$/) }
        }
        elsif(($Define) = $Line =~ /^\s*\#ifndef\s+(.+)$/)
        { 
            next unless(exists(${$rhDefines}{$Define}));
            while(my $Line = $fh->getline()) { last if($Line =~ /^\s*\#endif\s+$Define$/) }
        }
        elsif($Line =~ /^\s*\#endif\s+/) { }
        elsif(my($IncludeFile) = $Line =~ /^\s*\#include\s+(.+)$/)
        {
            Monitor(\$IncludeFile); $IncludeFile =~ s/[\r\n]//g;
            unless(-f $IncludeFile)
            {
                my $Candidate = catfile(dirname($File), $IncludeFile);
                $IncludeFile = $Candidate if(-f $Candidate);
            }
            push(@Lines, PreprocessIni($IncludeFile, $rhDefines))
        }
        else { push(@Lines, $Line) }
    }
    $fh->close();
    return @Lines;
}

sub Bm
{
    my($BuildSystem, $UpLoad);
    foreach(@BMonitors)
    {
        my($Field1, $Field2) = @{$_};
        if($Field1 =~ /^buildSystem$/i) { $BuildSystem = $Field2 }
        elsif($Field1=~/^all$/i || $Field1 eq $PLATFORM || ($^O eq "MSWin32" && $Field1=~/^windows$/i) || ($^O ne "MSWin32" && $Field1=~/^unix$/i)) {
             $UpLoad = "yes"=~/^$Field2/i;
        } 
    }

    eval
    {   return unless($UpLoad);
        die("ERROR:Bm: missing buildSystem in [monitoring] section in $Config.") unless($BuildSystem); 
        (my $build_date = $ENV{BUILD_DATE}) =~ s/:/ /;     	
        my $xbm = new XBM($ENV{OBJECT_MODEL}, $ENV{SITE}, 0, $ENV{TEMP});   
        unless(defined($xbm))
        {    XBM::objGenErrBuild($BuildSystem, $ENV{context}, $ENV{PLATFORM}, $ENV{BUILDREV}, $build_date, $ENV{TEMP});
             die("ERROR:Bm: Failed to gen object.");
        }  
        die("ERROR:Bm: BM data injection is turned off.") if($xbm == 0);     
        $xbm->uploadBuild($BuildSystem, $ENV{context}, $ENV{PLATFORM}, $ENV{BUILDREV}, $build_date);
    };
    warn("ERROR:Bm: Failed in uploading build info. with ERR: $@; $!") if($@);
}

sub Monitor
{
    my($rsVariable) = @_;
    return undef unless(tied(${$rsVariable}) || (${$rsVariable} && ${$rsVariable}=~/\${.*?}/));
    push(@MonitoredVariables, [$rsVariable, ${$rsVariable}]);
    return tie ${$rsVariable}, 'main', $rsVariable;
}

sub TIESCALAR
{ 
    my($Pkg, $rsVariable) = @_;
    return bless($rsVariable);
}

sub FETCH
{
    my($rsVariable) = @_;

    my $Variable = ExpandVariable($rsVariable);
    return $Variable unless($IsVariableExpandable);
    for(my $i=0; $i<@MonitoredVariables; $i++)
    { 
        next unless($MonitoredVariables[$i]);
        unless(ExpandVariable(\${$MonitoredVariables[$i]}[1]) =~ /\${.*?}/)
        {
            ${${$MonitoredVariables[$i]}[0]} = ${$MonitoredVariables[$i]}[1];
            untie ${$MonitoredVariables[$i]}[0];
            $MonitoredVariables[$i] = undef;
        }
    }
    @MonitoredVariables = grep({$_} @MonitoredVariables);
    return ${$rsVariable};
}

sub STORE
{
    my($rsVariable, $Value) = @_;
    ${$rsVariable} = $Value;
}

sub ExpandVariable
{
    my($rsVariable) = @_;
    my $Variable = ${$rsVariable};
        
    return "" unless(defined($Variable));
    while($Variable =~ /\${(.*?)}/g)
    {
        my $Name = $1;
        $Variable =~ s/\${$Name}/${$Name}/ if(defined(${$Name}));
        $Variable =~ s/\${$Name}/$ENV{$Name}/ if(!defined(${$Name}) && defined($ENV{$Name}));
    }
    ${$rsVariable} = $Variable if($IsVariableExpandable);
    return $Variable;
}

sub FormatDate
{
    (my $Time) = @_;
    my($ss, $mn, $hh, $dd, $mm, $yy, $wd, $yd, $isdst) = localtime $Time;
    #return sprintf("%04u/%02u/%02u %02u:%02u:%02u", $yy+1900, $mm+1, $dd, $hh, $mn, $ss);
    return sprintf "%02u:%02u:%02u", $hh, $mn, $ss;
}

sub HHMMSS
{
    my($Difference) = @_;
    my $s = $Difference % 60;
    $Difference = ($Difference - $s)/60;
    my $m = $Difference % 60;
    my $h = ($Difference - $m)/60;
    return sprintf "%02u:%02u:%02u", $h, $m, $s;
}
