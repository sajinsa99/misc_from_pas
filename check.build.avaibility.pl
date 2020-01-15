##############################################################################
##### declare uses
#use strict;
use warnings;
use diagnostics;

# required for the script
use Getopt::Long;
use File::stat;
use Net::SMTP;

use SOAP::Lite;

use DBI;
use DBD::mysql;

use FindBin;
use lib $FindBin::Bin;

use File::Basename;



##############################################################################
##### declare vars

#for the script itself
use vars qw (
    %forDB
    %BUILDS
    %localChecks
    %grChecks
    %Checks
    %Issues
    %PLATFORMS
    $RegExp
    $SMTP_SERVER
    $currentTime
    $CURRENTDIR
    $CHECK_BUILD_AVAIBILITY_DIR
    %HTTP_CIS
    %NSD_SERVERS_TARGET
    $exit_status
);

# options/parameters
use vars qw (
    $Help
    $iniFile
    $Site
    $param_Build
    $Mail
    $overrideTrace
    $noTrace
    $updateDB
    $Verbose
    $HTML
    $grCheck
    $localCheck
    $opt_exit_status
    $param_build_rev
    $param_project
);

#for parsing ini
use vars qw (
    $DROP_DIR
    $DROP_DIR_WINDOWS
    $DROP_DIR_LINUX
    $DEFAULT_SMTP_FROM
    $DEFAULT_SMTP_TO
    $DEFAULT_AVAILABLE
    $DEFAULT_TOLERANCE
);



##############################################################################
##### declare functions
sub Usage();
sub parseIniFile($);
sub getVersion($);
sub checkDoneFile($$$$$$$$);
sub checkGR();
sub sendMail($$$$$$$$@);
sub genereHMTL();
sub insertDB();



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "help|?"    =>\$Help,
    "ini=s"     =>\$iniFile,
    "site=s"    =>\$Site,
    "build=s"   =>\$param_Build,
    "mail"      =>\$Mail,
    "ot"        =>\$overrideTrace,
    "nt"        =>\$noTrace,
    "db"        =>\$updateDB,
    "verbose"   =>\$Verbose,
    "html"      =>\$HTML,
    "gr"        =>\$grCheck,
    "local"     =>\$localCheck,
    "es"        =>\$opt_exit_status,
    "br=s"      =>\$param_build_rev,
    "prj=s"     =>\$param_project,
);
Usage() if($Help);



##############################################################################
##### init vars

$Site ||= $ENV{'SITE'} || "Walldorf";
unless($Site eq "Levallois" || $Site eq "Walldorf"
    || $Site eq "Vancouver" || $Site eq "Bangalore"
    || $Site eq "Paloalto"  || $Site eq "Lacrosse") {
    die "\nERROR: SITE environment variable or 'perl $0 -s=my_site' must be set\navailable sites : Levallois | Walldorf | Vancouver | Bangalore | Paloalto | Lacrosse\n";
}
$ENV{'SITE'} = $Site;

# set different possible configurations
$PLATFORMS{windows} = [qw(win32_x86 win64_x64)];
$PLATFORMS{unix}    = [qw(solaris_sparc linux_x86 aix_rs6000 hpux_pa-risc mac_x86 solaris_sparcv9 linux_x64 aix_rs6000_64 hpux_ia64 mac_x64)];
$PLATFORMS{linux}   = [qw(linux_x86 linux_x64)];
$PLATFORMS{solaris} = [qw(solaris_sparc solaris_sparcv9)];
$PLATFORMS{aix}     = [qw(aix_rs6000 aix_rs6000_64)];
$PLATFORMS{hp}      = [qw(hpux_pa-risc hpux_ia64)];
$PLATFORMS{mac}     = [qw(mac_x86 mac_x64)];
$PLATFORMS{32}      = [qw(win32_x86 solaris_sparc linux_x86 aix_rs6000 hpux_pa-risc mac_x86)];
$PLATFORMS{64}      = [qw(win64_x64 solaris_sparcv9 linux_x64 aix_rs6000_64 hpux_ia64 mac_x64)];
$PLATFORMS{all}     = [qw(win32_x86 solaris_sparc linux_x86 aix_rs6000 hpux_pa-risc mac_x86 win64_x64 solaris_sparcv9 linux_x64 aix_rs6000_64 hpux_ia64 mac_x64)];

$NSD_SERVERS_TARGET{Walldorf}   = $ENV{NSD_SERVERS_TARGET} || "dewdfgr02";
$NSD_SERVERS_TARGET{Vancouver}  = $ENV{NSD_SERVERS_TARGET} || "cavangr02";
$NSD_SERVERS_TARGET{Levallois}  = $ENV{NSD_SERVERS_TARGET} || "frpargr01";
$NSD_SERVERS_TARGET{Bangalore}  = $ENV{NSD_SERVERS_TARGET} || "inblrgr01";
$NSD_SERVERS_TARGET{Lacrosse}   = $ENV{NSD_SERVERS_TARGET} || "uslsegr01";
$NSD_SERVERS_TARGET{Paloalto}   = $ENV{NSD_SERVERS_TARGET} || "uspalgr01";


$CURRENTDIR = $FindBin::Bin;
$CHECK_BUILD_AVAIBILITY_DIR = $ENV{CHECK_BUILD_AVAIBILITY_DIR} || $CURRENTDIR;

$iniFile   ||= "$CHECK_BUILD_AVAIBILITY_DIR/$Site.ini";
$SMTP_SERVER = $ENV{SMTP_SERVER} || "mail.sap.corp";
$RegExp = qr/smtp_from|smtp_to|drop_dir|available|tolerance|version|typecheck|host/;

## CIS Walldorf dashboard
#with Site env
$HTTP_CIS{Walldorf}     = "http://cis_wdf.pgdev.sap.corp:1080/cgi-bin/CIS.pl" ;
#with NSD host (src)
$HTTP_CIS{dewdfgr02}    = "http://cis_wdf.pgdev.sap.corp:1080/cgi-bin/CIS.pl" ;
## CIS Vancouver dashboard
#with Site env
$HTTP_CIS{Vancouver}    = "http://cis_van.pgdev.sap.corp:1080/cis/cgi-bin/CIS.pl" ;
#with NSD host (src)
$HTTP_CIS{cavangr02}    = "http://cis_van.pgdev.sap.corp:1080/cis/cgi-bin/CIS.pl" ;

# create structure
parseIniFile($iniFile) if ( -e $iniFile );

# for jenkins
$exit_status = 0;



##############################################################################
##### MAIN

#for our futur dahsboard and keep a trace
my ($LocalSec,$LocalMin,$LocalHour,$LocalDay,$LocalMonth,$LocalYear,$wday,$yday,$isdst) = localtime(time);
$LocalYear      = $LocalYear  + 1900;
$LocalMonth     = $LocalMonth + 1;
$LocalMonth     = "0$LocalMonth"    if ($LocalMonth < 10);
$LocalDay       = "0$LocalDay"      if ($LocalDay   < 10);
$LocalHour      = "0$LocalHour"     if ($LocalHour  < 10);
$LocalMin       = "0$LocalMin"      if ($LocalMin   < 10);
$LocalSec       = "0$LocalSec"      if ($LocalSec   < 10);
$currentTime    = "$LocalYear-$LocalMonth-$LocalDay  $LocalHour:$LocalMin:$LocalSec";

print "\n$0 started at $LocalHour:$LocalMin:$LocalSec, on $LocalYear/$LocalMonth/$LocalDay\n\n";

### checks
if(%localChecks) {
    foreach my $project(keys %localChecks) {
        foreach my $Build (keys %{$localChecks{$project}} ) {
            next if($param_Build && ($Build ne $param_Build));
            foreach my $platform (keys %{$localChecks{$project}{$Build}}) {
                next if($platform =~ /$RegExp/);
                foreach my $folder (@{$localChecks{$project}{$Build}{$platform}{folders}} ) {
                    my $buildDir =  $localChecks{$project}{$Build}{drop_dir} || $DROP_DIR;
                    my $version  =  $localChecks{$project}{$Build}{version};
                    $buildDir   .=  "/$project/$Build/$version/$platform/release/$folder";
                    ($buildDir)  =~ s-\\-\/-g;
                    my $thisAvailable = $localChecks{$project}{$Build}{$platform}{available}{$folder} || $localChecks{$project}{$Build}{available} || $DEFAULT_AVAILABLE;
                    my $thisTolerance = $localChecks{$project}{$Build}{$platform}{tolerance}{$folder} || $localChecks{$project}{$Build}{tolerance} || $DEFAULT_TOLERANCE || 0;
                    unless($grCheck)    { checkDoneFile($project,$Build,$version,$platform,$buildDir,$folder,$thisAvailable,$thisTolerance) }
                    if(defined $localChecks{$project}{$Build}{$platform}{msgs}{$folder}) { #if any issue found, store it in %Issues
                        $Issues{$project}{$Build}{version}                          = $localChecks{$project}{$Build}{version};
                        $Issues{$project}{$Build}{smtp_from}                        = $localChecks{$project}{$Build}{smtp_from}                     if(defined $localChecks{$project}{$Build}{smtp_from});
                        $Issues{$project}{$Build}{smtp_to}                          = $localChecks{$project}{$Build}{smtp_to}                       if(defined $localChecks{$project}{$Build}{smtp_to});
                        $Issues{$project}{$Build}{drop_dir}                         = $localChecks{$project}{$Build}{drop_dir}                      if(defined $localChecks{$project}{$Build}{drop_dir});
                        $Issues{$project}{$Build}{available}                        = $localChecks{$project}{$Build}{available}                     if(defined $localChecks{$project}{$Build}{available});
                        $Issues{$project}{$Build}{tolerance}                        = $localChecks{$project}{$Build}{tolerance}                     if(defined $localChecks{$project}{$Build}{tolerance});
                        $Issues{$project}{$Build}{$platform}{available}{$folder}    = $localChecks{$project}{$Build}{$platform}{available}{$folder} if(defined $localChecks{$project}{$Build}{$platform}{available}{$folder});
                        $Issues{$project}{$Build}{$platform}{tolerance}{$folder}    = $localChecks{$project}{$Build}{$platform}{tolerance}{$folder} if(defined $localChecks{$project}{$Build}{$platform}{tolerance}{$folder});
                        $Issues{$project}{$Build}{$platform}{msgs}{$folder}         = $localChecks{$project}{$Build}{$platform}{msgs}{$folder};
                        push @{$Issues{$project}{$Build}{$platform}{folders}},$folder;
                        #my $msg = ($localChecks{$project}{$Build}{$platform}{msgs}{$folder} =~ /ERROR/) ? "ERROR" : "WARNING" ;
                    }
                }
            }
        }
    }
}

unless($localCheck) { checkGR() if(%grChecks); }


### reports
# display
print "
    Default variables :

INI = $iniFile
SITE = $Site
DROP_DIR = $DROP_DIR
DEFAULT_SMTP_FROM = $DEFAULT_SMTP_FROM
DEFAULT_SMTP_TO = $DEFAULT_SMTP_TO
DEFAULT_AVAILABLE = $DEFAULT_AVAILABLE
DEFAULT_TOLERANCE = $DEFAULT_TOLERANCE

    STATUS:
";

if(%localChecks && %grChecks) {
    %Checks = (%localChecks,%grChecks);
}
elsif(%localChecks && !(%grChecks)) {
    %Checks = %localChecks;
}
elsif( !(%localChecks) && %grChecks) {
    %Checks = %grChecks;
}

if (scalar keys %Issues > 0) {
    print "\nBuilds with issues:";
    for my $project (keys %Issues) {
        print "\n\n[$project]\n";
        foreach my $Build (keys %{$Issues{$project}}) {
            next unless($Issues{$project}{$Build}{version});
            my @linesToMail;
            print "\t==== $Build - $Issues{$project}{$Build}{version}";
            print " - $Issues{$project}{$Build}{available}" if(defined $Issues{$project}{$Build}{available});
            print " - tolerance: +$Checks{$project}{$Build}{tolerance} min" if(defined $Checks{$project}{$Build}{tolerance});
            print " ====\n";
            foreach my $platform (keys %{$Issues{$project}{$Build}}) {
                next if($platform =~ /$RegExp/);
                my $linePlatform = "platform:$platform",
                print "\t\t$platform";
                print "\n";
                foreach my $folder ( @{$Issues{$project}{$Build}{$platform}{folders}} ) {
                    if(defined $Issues{$project}{$Build}{$platform}{available}{$folder}) {
                        print " - $Issues{$project}{$Build}{$platform}{available}{$folder}";
                        print " - tolerance: +$Checks{$project}{$Build}{$platform}{tolerance}{$folder} min - "  if(defined $Checks{$project}{$Build}{$platform}{tolerance}{$folder});
                        $linePlatform .=" - specific check for this platform : $Issues{$project}{$Build}{$platform}{available}{$folder}";
                    }
                    push @linesToMail,$linePlatform;

                    if($^O eq "MSWin32") {
                        ($Issues{$project}{$Build}{$platform}{msgs}{$folder}) =~ s-\/-\\-g; #display in windows format
                    }
                    print "$folder  :  $Issues{$project}{$Build}{$platform}{msgs}{$folder}\n";
                    my $lineFolder  = "folder:$folder:$Issues{$project}{$Build}{$platform}{msgs}{$folder}";
                    push @linesToMail,$lineFolder;
                }
            }
            my $smtp_from           = $Issues{$project}{$Build}{smtp_from}  || $DEFAULT_SMTP_FROM;
            my $smtp_to             = $Issues{$project}{$Build}{smtp_to}    || $DEFAULT_SMTP_TO;
            my $titleMail           = "[BUILD check avaibility] - $Build - $Issues{$project}{$Build}{version} - not (yet) available in $Site dropzone";
            my $generalAvailable    = $Issues{$project}{$Build}{available}  || $DEFAULT_AVAILABLE;
            my $generalTolerance    = $Issues{$project}{$Build}{tolerance}  || $DEFAULT_TOLERANCE;
            #my $dropDir             = $Issues{$project}{$Build}{drop_dir}   || $DROP_DIR;
            my $dropDir             = $DROP_DIR_WINDOWS;
            sendMail($Build,$project,$Issues{$project}{$Build}{version},$dropDir,$generalAvailable,$smtp_from,$smtp_to,$titleMail,@linesToMail) if($Mail);
            print "\n";
        }
    }
}
else {
    if (scalar keys %Checks < 1) {
        print "nothing to check\n";
        exit;
    }
    else {
        for my $project (keys %Checks) {
            print "$project\n";
            foreach my $Build (keys %{$Checks{$project}}) {
                next if($param_Build && ($Build ne $param_Build) );
                print "  $Build\n";
                print "    $Checks{$project}{$Build}{version}\n";
                foreach my $platform (keys %{$Checks{$project}{$Build}}) {
                    next if($platform =~ /$RegExp/);
                    print "      $platform\n";
                    foreach my $folder (@{$Checks{$project}{$Build}{$platform}{folders}}) {
                        print "        $folder";
                        print " ok: $Checks{$project}{$Build}{$platform}{passed}{$folder}"  if($Checks{$project}{$Build}{$platform}{passed}{$folder});
                        print " warn: $Checks{$project}{$Build}{$platform}{msgs}{$folder}"  if($Checks{$project}{$Build}{$platform}{msgs}{$folder});
                        print " error: $Issues{$project}{$Build}{$platform}{msgs}{$folder}" if($Issues{$project}{$Build}{$platform}{msgs}{$folder});
                        print "\n";
                        
                    }
                }
                print "\n";
            }
            print "\n";
        }
    }
}

genereHMTL() if($HTML);
insertDB()   if($updateDB);

# for jenkins
if($opt_exit_status) {
    if($exit_status == 1) {
        print "\nsome folders missing, exit $exit_status\n\n";
    }
    if($exit_status == 0) {
        print "\nno folder missing, exit $exit_status\n\n";
    }
    exit $exit_status;
}
else {
    exit 0;
}



##############################################################################
### my functions
sub parseIniFile($) {
    my ($configFile) = @_;
        if(open INI,"$configFile") {
        SECTION: while(<INI>) {
            chomp;
            s-^\s+$--;
            next unless($_);
            next if(/^\#/); #skip comments
            s-\#(.+?)$--; # remove comments in end of line
            $DROP_DIR           = $1 if(/DROP_DIR\=(.+?)$/);
            $DROP_DIR_WINDOWS   = $1 if(/DROP_DIR_WINDOWS\=(.+?)$/);
            $DROP_DIR_LINUX     = $1 if(/DROP_DIR_LINUX\=(.+?)$/);
            $DEFAULT_SMTP_FROM  = $1 if(/DEFAULT_SMTP_FROM\=(.+?)$/);
            $DEFAULT_SMTP_TO    = $1 if(/DEFAULT_SMTP_TO\=(.+?)$/);
            $DEFAULT_AVAILABLE  = $1 if(/DEFAULT_AVAILABLE\=(.+?)$/);
            $DEFAULT_TOLERANCE  = $1 if(/DEFAULT_TOLERANCE\=(.+?)$/);
            next unless(my ($Build) = /^\[(.+?)\]/);
            my $typeCheck;
            if($Build =~ /^(.+?)\:(.+?)$/) {
                $typeCheck  = $1 ;
                $Build      = $2;
            }
            else {
                $typeCheck  = "local" ;
            }
            next if($grCheck    && ($typeCheck ne "gr"));
            next if($localCheck && ($typeCheck ne "local"));
            if($^O ne "MSWin32") {
                $DROP_DIR = ($DROP_DIR_LINUX) ? $DROP_DIR_LINUX : $DROP_DIR;
            }
            else {
                $DROP_DIR = ($DROP_DIR_WINDOWS) ? $DROP_DIR_LINUX : $DROP_DIR;
            }
            my ($project,$smtp_from,$smtp_to,$drop_dir,$available,$tolerance);
            while(<INI>) {
                chomp;
                s-^\s+$--;
                next unless($_);
                s-\#(.+?)$--; # remove comments in end of line
                redo SECTION if(/^\[(.+)\]/);
                my $this_drop_dir = "";
                if(/^(.+?)\=(.+?)$/) {
                    my $var     = $1;
                    my $value   = $2;
                    $project    = $value if($var =~ /^project/);
                    $smtp_from  = $value if($var =~ /^smtp_from/);
                    $smtp_to    = $value if($var =~ /^smtp_to/);
                    $drop_dir   = $value if($var =~ /^drop_dir/);
                    $available  = $value if($var =~ /^available/);
                    $tolerance  = $value if($var =~ /^tolerance/);
                    my $this_drop_dir;
                    next if($param_project && ($param_project ne "$project"));
                    if($typeCheck eq "local") {
                        $this_drop_dir = $localChecks{$project}{$Build}{drop_dir}   || $DROP_DIR; # if specifc drop_dir
                        $localChecks{$project}{$Build}{typecheck}   = $typeCheck;
                        $localChecks{$project}{$Build}{smtp_from}   = $smtp_from    if(defined $smtp_from);
                        $localChecks{$project}{$Build}{smtp_to}     = $smtp_to      if(defined $smtp_to);
                        $localChecks{$project}{$Build}{drop_dir}    = $drop_dir     if(defined $drop_dir);
                        $localChecks{$project}{$Build}{available}   = $available    if(defined $available);
                        $localChecks{$project}{$Build}{tolerance}   = $tolerance    if(defined $tolerance);
                    }
                    if($typeCheck eq "gr") {
                        $this_drop_dir = $grChecks{$project}{$Build}{drop_dir}  || $DROP_DIR; # if specifc drop_dir
                        $grChecks{$project}{$Build}{typecheck}      = $typeCheck;
                        $grChecks{$project}{$Build}{smtp_from}      = $smtp_from    if(defined $smtp_from);
                        $grChecks{$project}{$Build}{smtp_to}        = $smtp_to      if(defined $smtp_to);
                        $grChecks{$project}{$Build}{drop_dir}       = $drop_dir     if(defined $drop_dir);
                        $grChecks{$project}{$Build}{available}      = $available    if(defined $available);
                        $grChecks{$project}{$Build}{tolerance}      = $tolerance    if(defined $tolerance);
                    }
                    ($this_drop_dir) =~ s-\\-\/-g if(defined $this_drop_dir); #unix style
                    my $version = getVersion("$this_drop_dir/$project/$Build")      if(defined $project);
                    if($param_build_rev && (defined $project)) {
                        $version = $param_build_rev;
                    }
                    if($typeCheck eq "local") {
                        $localChecks{$project}{$Build}{version}     = $version      if(defined $version);
                    }
                    if($typeCheck eq "gr") {
                        $grChecks{$project}{$Build}{version}        = $version      if(defined $version);
                    }
                }
                if(/\s+\|\s+/) { #if platform(s) | folder(s) | available(?)
                    s-\s+--g;
                    # structure:
                    # platform | folder1,folder2
                    # or
                    # platform | folder1,folder2 | available
                    my @elems   = split '\|',$_; # seperate elements
                    my @folders = split ',',$elems[1]; # $elem[1] = list of folders
                    my $specificAvailable = $elems[2] if($elems[2]); # if $elem[2], override vailable value for this build but for specific platform
                    ($specificAvailable)  =~ s-^available\=--i if(defined $specificAvailable);
                    my $specificTolerance = $elems[3] if($elems[3]); # if $elem[3], override vailable value for this build but for specific platform
                    ($specificTolerance)  =~ s-^tolerance\=--i if(defined $specificTolerance);
                    #provide real platforms;
                    my @PlatformsToCheck  = split ',',$elems[0];
                    #get skip platforms
                    my @skipPlatforms;
                    foreach my $platformToCheck (@PlatformsToCheck) {
                    	push @{$PLATFORMS{$platformToCheck}} , $platformToCheck ;
                        if($platformToCheck =~ /^\-(.+?)$/) {
                            push(@skipPlatforms,$1) unless(grep /^$1$/,@skipPlatforms);
                        }
                    }
                    #ass folders for each platforms
                    foreach my $platformToCheck (@PlatformsToCheck) {
                        next if($platformToCheck =~ /^\-/);
                        if( @{$PLATFORMS{$platformToCheck}} ) {
                            foreach my $thisPlatform ( @{$PLATFORMS{$platformToCheck}} ) {
                                my $skip = 0;
                                foreach my $skipPlatform (@skipPlatforms) {
                                    if($thisPlatform =~ /^$skipPlatform/) {
                                        $skip = 1;
                                        last;
                                    }
                                }
                                if($skip == 0) {
                                    foreach my $folder (@folders) {
                                        if($typeCheck eq "local") {
                                            push(@{$localChecks{$project}{$Build}{$thisPlatform}{folders}},$folder) unless(grep /^$folder$/,@{$localChecks{$project}{$Build}{$thisPlatform}{folders}});
                                            $localChecks{$project}{$Build}{$thisPlatform}{folder}{$folder}     = 1;
                                            $localChecks{$project}{$Build}{$thisPlatform}{available}{$folder}  = $specificAvailable if(defined $specificAvailable);
                                            $localChecks{$project}{$Build}{$thisPlatform}{tolerance}{$folder}  = $specificTolerance if(defined $specificTolerance);
                                        }
                                        if($typeCheck eq "gr") {
                                            push(@{$grChecks{$project}{$Build}{$thisPlatform}{folders}},$folder) unless(grep /^$folder$/,@{$grChecks{$project}{$Build}{$thisPlatform}{folders}});
                                            $grChecks{$project}{$Build}{$thisPlatform}{folder}{$folder}        = 1;
                                            $grChecks{$project}{$Build}{$thisPlatform}{available}{$folder}     = $specificAvailable if(defined $specificAvailable);
                                            $grChecks{$project}{$Build}{$thisPlatform}{tolerance}{$folder}     = $specificTolerance if(defined $specificTolerance);
                                        }
                                    }
                                }
                            }
                        }
                        else {
                            foreach my $folder (@folders) {
                                if($typeCheck eq "local") {
                                    push(@{$localChecks{$project}{$Build}{$platformToCheck}{folders}},$folder) unless(grep /^$folder$/,@{$localChecks{$project}{$Build}{$platformToCheck}{folders}});
                                    $localChecks{$project}{$Build}{$platformToCheck}{folder}{$folder}          = 1;
                                    $localChecks{$project}{$Build}{$platformToCheck}{available}{$folder}       = $specificAvailable if(defined $specificAvailable);
                                    $localChecks{$project}{$Build}{$platformToCheck}{tolerance}{$folder}       = $specificTolerance if(defined $specificTolerance);
                                }
                                if($typeCheck eq "gr") {
                                    push(@{$grChecks{$project}{$Build}{$platformToCheck}{folders}},$folder) unless(grep /^$folder$/,@{$grChecks{$project}{$Build}{$platformToCheck}{folders}});
                                    $grChecks{$project}{$Build}{$platformToCheck}{folder}{$folder}             = 1;
                                    $grChecks{$project}{$Build}{$platformToCheck}{available}{$folder}          = $specificAvailable if(defined $specificAvailable);
                                    $grChecks{$project}{$Build}{$platformToCheck}{tolerance}{$folder}          = $specificTolerance if(defined $specificTolerance);
                                }
                            }
                        }
                    }
                }
            }
        }
        close INI;
    }
}

sub getVersion($) {
    my ($versionDir) = @_;
    my $tmp = 0;
    if(open VER, "$versionDir/version.txt")
    {
        chomp($tmp = <VER>);
        $tmp = int $tmp;
        close VER;
    }
    else { # If version.txt does not exists or opening failed or due to gr transvers, instead of restarting from 1, look for existing directory versions & generate the hightest version number based on the hightest directory version
        # open current context dir to find the hightest directory version inside
        if(opendir BUILDVERSIONSDIR,"$versionDir") {
            while(defined(my $next = readdir BUILDVERSIONSDIR)) {
                # Only take a directory with a number as name, which can be a number or a float number with a mandatory decimal value & optional floating point
                $tmp = $1 if ($next =~ /^(\d+)(\.\d+)?$/ && $1 > $tmp && -d "$versionDir/$next");
            }   
            closedir BUILDVERSIONSDIR;
        }
    }
    return $tmp;
}

# checks
sub checkDoneFile($$$$$$$$) {
    my ($thisProject,$thisBuild,$thisVersion,$thisPlatform,$buildDir,$folder,$thisTime,$thisTolerance) = @_;
    my ($hourRef,$minRef) = $thisTime =~ /^(\d+)\:(\d+)$/;
    my $fileDone = "$buildDir/${folder}_copy_done";
    use Time::localtime;

    ($minRef) =~ s-^0--;
    $minRef   = $minRef + $thisTolerance;
    #set to numeric for calculs;
    ($hourRef)  =~ s-^0-- if($hourRef   =~ /^0/);
    ($LocalDay) =~ s-^0-- if($LocalDay  =~ /^0/);
    ($LocalHour)=~ s-^0-- if($LocalHour =~ /^0/);
    ($LocalMin) =~ s-^0-- if($LocalMin  =~ /^0/);
    #check minRef > 60 (1h) to transform in hours
    my $nbHour = int($minRef/60);
    if($nbHour > 0) {
        $hourRef     = $hourRef + $nbHour;
        my $tmpNbMin = $nbHour  * 60;
        my $diff     = $minRef  - $tmpNbMin;
        $minRef      = $diff;
    }
    # check if time running script and time ref
    my $LocalTotal = ($LocalHour*60) + $LocalMin;
    my $LocalRef   = ($hourRef*60)   + $minRef;
    $localChecks{$thisProject}{$thisBuild}{host} = $Site;
    if( ! -e $fileDone ) { # file copy_done not exist
        if($LocalTotal >= $LocalRef) { # check during the ref time
            $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
            = "[ERROR] : file $buildDir/${folder}_copy_done not found";
            if($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{available}) {
                $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                .=" expected at $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{available}{$folder}";
            }
            else {
                $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                .=" expected at $localChecks{$thisProject}{$thisBuild}{available}{$folder}";
            }
            if($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} && ($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder}>0)) {
                $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{passed}{$folder}
                .= ", with a tolerance of $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} minute(s)";
            }
            else {
                if($localChecks{$thisProject}{$thisBuild}{tolerance}{$folder} && ($localChecks{$thisProject}{$thisBuild}{tolerance}{$folder}>0)) {
                    $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{passed}{$folder}
                    .= ", with a tolerance of $localChecks{$thisProject}{$thisBuild}{tolerance}{$folder} minute(s)";
                }
            }
            $exit_status = 1;
            $forDB{$thisProject}{$thisBuild}{$thisVersion}{$thisPlatform}{$buildDir}{$thisTime}{0} = 1;
        }
        else { # check done too earlier
                if($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{available}) {
                    $Issues{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                    = "expected at $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{available}{$folder}";
                }
                else {
                    $Issues{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                    = "expected at $localChecks{$thisProject}{$thisBuild}{available}{$folder}";
                }
                if($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} && ($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder}>0)) {
                    $Issues{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                    .= " with a tolerance of $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} minute(s)";
                }
                else {
                    if($localChecks{$thisProject}{$thisBuild}{tolerance} && ($localChecks{$thisProject}{$thisBuild}{tolerance}>0)) {
                        $Issues{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                        .= ", with a tolerance of $localChecks{$thisProject}{$thisBuild}{tolerance} minute(s)";
                    }
                }
                $Issues{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                .= ", check done too earlier, please restart at $hourRef:$minRef";
        }
    }
    else { # file copy_done exist
        # search latest folder modified
        # no use copy_done due to the fact under 64,
        # there is a difference betwenn the latest copy under 32 and the creation of this file under 64
        # some steps could be done before the end of export and creation of copy�done file
        my $last_folder;
        if(($folder =~ /^packages$/i) || ($folder =~ /^patches$/i)) {
            my %sub_folders;
            if(opendir DIR,$buildDir) {
                while(defined(my $sub_folder = readdir DIR)) {
                    next if($sub_folder =~ /^\./);
                    if( -d "$buildDir/$sub_folder") {
                        my $ts_folder = stat("$buildDir/$sub_folder")->mtime;
                        $sub_folders{$ts_folder} = $sub_folder
                    }
                }
                closedir DIR;
            }
            foreach my $ts (sort {$b <=> $a} keys %sub_folders) {
                $last_folder = "$buildDir/$sub_folders{$ts}";
                last;
            }
            $last_folder ||= $buildDir;
        }
        else {
            $last_folder = $fileDone;
        }
        my $datetime_string = ctime(stat($last_folder)->mtime);
        my ($numDayFile,$hourFile,$minFile,$secFile) = $datetime_string =~ /\s+(\d+)\s+(\d+)\:(\d+)\:(\d+)\s+/;
        my $diffDay  = 0;
        if($LocalDay > $numDayFile) {
            $diffDay = $LocalDay - $numDayFile;
        }
        elsif ($LocalDay < $numDayFile) {
            $diffDay = $numDayFile - ($numDayFile - $LocalDay);
        }
        else {
            $diffDay = 0
        }
        if( ($numDayFile eq $LocalDay) || ($diffDay == 1) ) { # check if export was done the day before or the same day of the check, only 1 day in difference is acceptable
            my $timeForDB = "$hourFile:$minFile:$secFile";
            $forDB{$thisProject}{$thisBuild}{$thisVersion}{$thisPlatform}{$buildDir}{$thisTime}{$timeForDB} = 1;
            ($hourFile) =~ s-^0-- if($hourFile =~ /^0/);
            ($minFile)  =~ s-^0-- if($minFile  =~ /^0/);
            $hourRef = $hourRef + 24 if($diffDay == 1); # if 1 day difference
            if($hourFile > $hourRef) { #if after hour ref
                my $deltaMinRef = 60 - $minRef ;
                my $deltaMin = $deltaMinRef + $minFile;
                if($deltaMin > $thisTolerance) { #if "� cheval entre 2 heures"
                    $hourRef  = "0$hourRef"  if ($hourRef  < 10);
                    $minRef   = "0$minRef"   if ($minRef   < 10);
                    $hourFile = "0$hourFile" if ($hourFile < 10);
                    $minFile  = "0$minFile"  if ($minFile  < 10);
                    $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                    = "[WARNING] : file $buildDir/${folder}_copy_done arrived too late at '$hourFile:$minFile' instead of ";
                    if($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{available}{$folder}) {
                        $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                        .= "$localChecks{$thisProject}{$thisBuild}{$thisPlatform}{available}{$folder}";
                    }
                    else {
                        $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                        .= "$localChecks{$thisProject}{$thisBuild}{available}";
                    }
                    if($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} && ($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} > 0)) {
                        $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                        .= ", with a tolerance of $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} minute(s)";
                    }
                    else {
                        if($localChecks{$thisProject}{$thisBuild}{tolerance} && ($localChecks{$thisProject}{$thisBuild}{tolerance} > 0)) {
                            $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                            .= ", with a tolerance of $localChecks{$thisProject}{$thisBuild}{tolerance} minute(s)";
                        }
                    }
                }
            }
            else {
                if( ($hourFile == $hourRef) && ($minFile > $minRef) ) { #if hour is equal hour ref but min after min ref, so, it is also too late, e.g.: ref=10:00, file_time=10:33, it is also too late
                    $hourRef  = "0$hourRef"  if ($hourRef  < 10);
                    $minRef   = "0$minRef"   if ($minRef   < 10);
                    $hourFile = "0$hourFile" if ($hourFile < 10);
                    $minFile  = "0$minFile"  if ($minFile  < 10);
                    $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                        = "[WARNING] : file $buildDir/${folder}_copy_done arrived too late at '$hourFile:$minFile' instead of ";
                    if($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{available}) {
                        $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                            .= "$localChecks{$thisProject}{$thisBuild}{$thisPlatform}{available}{$folder}";
                    }
                    else {
                        $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                            .="$localChecks{$thisProject}{$thisBuild}{available}{$folder}";
                    }
                    if($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} && ($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} > 0)) {
                        $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                            .= ", with a tolerance of $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} minute(s)";
                    }
                    else {
                        if($localChecks{$thisProject}{$thisBuild}{tolerance} && ($localChecks{$thisProject}{$thisBuild}{tolerance} > 0)) {
                            $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{msgs}{$folder}
                                .= ", with a tolerance of $localChecks{$thisProject}{$thisBuild}{tolerance} minute(s)";
                        }
                    }
                }
                else {
                    my $displayHour    = $hourFile;
                    $displayHour       = "0$displayHour" if ($displayHour < 10);
                    my $displayMinutes = $minFile;
                    $displayMinutes    = "0$minFile"     if ($minFile     < 10);
                    if($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{available}{$folder}) {
                        $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{passed}{$folder}
                            = "expected at $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{available}{$folder}";
                    }
                    else {
                        $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{passed}{$folder}
                            = "expected at $localChecks{$thisProject}{$thisBuild}{available}";
                    }
                    if($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} && ($localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder}>0)) {
                        $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{passed}{$folder}
                            .= " with a tolerance of $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{tolerance}{$folder} minute(s)";
                    }
                    else {
                        if($localChecks{$thisProject}{$thisBuild}{tolerance} && ($localChecks{$thisProject}{$thisBuild}{tolerance}>0)) {
                            $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{passed}{$folder}
                                .= ", with a tolerance of $localChecks{$thisProject}{$thisBuild}{tolerance} minute(s)";
                        }
                    }
                    $localChecks{$thisProject}{$thisBuild}{$thisPlatform}{passed}{$folder}
                        .= ", arrived at $displayHour:$displayMinutes, the $numDayFile/$LocalMonth/$LocalYear";
                }
            }
        }
    }
}

sub checkGR() {
    my $sinceThisDateTime = "$LocalYear-$LocalMonth-$LocalDay 00:00:01";
    my $tmp = SOAP::Lite
        -> uri('http://dewdfgrdb01.wdf.sap.corp/gr_ext')
        -> proxy('http://dewdfgrdb01.wdf.sap.corp:1080/cgi-bin/gr-ext')
        -> lastsinceByTarget("$sinceThisDateTime|$NSD_SERVERS_TARGET{$Site}")
        -> result;
    my @Results = split('\n',$tmp);
    foreach my $result (@Results) {
        my ($grSrc,$grTarget,$syncDir,$versionTransferred,$statusTransfer,$dateTime)    = split ',',$result;
        my ($grProject,$grBuild,$grVersion,$grPlatform,$grMode,$grFolder)               = split '/',$syncDir;
        my ($grDate,$thisNsdTime)     = split ' ',$dateTime;
        my ($grYear,$grMonth,$grDay)  = split '-',$grDate;
        my ($hourNSD,$minNSD,$secNSD) = split ':',$thisNsdTime;
        foreach my $project(sort keys %grChecks) {
            next if($grProject ne $project);
            foreach my $Build (sort keys %{$grChecks{$project}}) {
                next if($param_Build && ($Build ne $param_Build) );
                next if($grBuild ne $Build);
                foreach my $platform (sort keys %{$grChecks{$project}{$Build}}) {
                    next if($platform =~ /$RegExp/);
                    next if($grPlatform ne $platform);
                    foreach my $folder (sort @{$grChecks{$project}{$Build}{$platform}{folders}}) {
                        next if($grFolder ne $folder);
                        my $buildDir     = $grChecks{$project}{$Build}{drop_dir} || $DROP_DIR;
                        my $thisVersion  = $grChecks{$project}{$Build}{version};
                        next if($grVersion ne $thisVersion);
                        $buildDir  .= "/$project/$Build/$thisVersion/$platform/release/$folder";
                        ($buildDir) =~ s-\\-\/-g;
                        my $thisTime        = $grChecks{$project}{$Build}{$platform}{available}{$folder}
                                           || $grChecks{$project}{$Build}{available} || $DEFAULT_AVAILABLE;
                        my $thisTolerance   = $grChecks{$project}{$Build}{$platform}{tolerance}{$folder}
                                           || $grChecks{$project}{$Build}{tolerance} || $DEFAULT_TOLERANCE || 0;
                        if( ($grProject eq $project) && ($grBuild eq $Build) && ($grVersion eq $thisVersion) && ($grPlatform eq $platform) && ($grFolder eq $folder) ) {
                            $grChecks{$project}{$Build}{host} = $grSrc;
                            my ($hourRef,$minRef) = $thisTime =~ /^(\d+)\:(\d+)$/;
                            ($minRef)   =~ s-^0--;
                            $minRef     = $minRef + $thisTolerance;
                            # set to numeric for calculs;
                            ($hourRef)  =~ s-^0-- if($hourRef   =~ /^0/);
                            # ($LocalDay)=~ s-^0--  if($LocalDay =~ /^0/);
                            ($LocalHour)=~ s-^0-- if($LocalHour =~ /^0/);
                            ($LocalMin) =~ s-^0-- if($LocalMin  =~ /^0/);
                            # check minRef > 60 (1h) to transform in hours
                            my $nbHour = int($minRef/60);
                            if($nbHour > 0) {
                                $hourRef     = $hourRef + $nbHour;
                                my $tmpNbMin = $nbHour  * 60;
                                my $diff     = $minRef  - $tmpNbMin;
                                $minRef      = $diff;
                            }
                            # check if time running script and time ref
                            my $LocalTotal = ($LocalHour*60) + $LocalMin;
                            my $LocalRef   = ($hourRef*60)   + $minRef;
                            ($grSrc) =~ s-\..+?$--; # remove domain name
                            if(($statusTransfer =~ /^complete$/i) && ( -d $buildDir)) {
                                    my $diffDay = 0;
                                    if($LocalDay > $grDay) {
                                        $diffDay = $LocalDay - $grDay;
                                    }
                                    elsif ($LocalDay < $grDay) {
                                        $diffDay = $grDay - ($grDay - $LocalDay);
                                    }
                                    else {
                                        $diffDay = 0
                                    }
                                    if( ($grDay eq $LocalDay) || ($diffDay == 1) ) { # check if export was done the day before or the same day of the check, only 1 day in difference is acceptable else
                                        my $timeForDB = "$hourNSD:$minNSD:$secNSD";
                                        $forDB{$project}{$Build}{$thisVersion}{$platform}{$buildDir}{$thisTime}{$timeForDB}=1;
                                        ($hourNSD) =~ s-^0-- if($hourNSD =~ /^0/);
                                        ($minNSD)  =~ s-^0-- if($minNSD  =~ /^0/);
                                        $hourRef = $hourRef + 24 if($diffDay == 1); # if 1 day difference
                                        if($hourNSD > $hourRef) { # if after hour ref
                                            my $deltaMinRef = 60 - $minRef ;
                                            my $deltaMin = $deltaMinRef + $minNSD;
                                            if($deltaMin > $thisTolerance) { # if "� cheval entre 2 heures"
                                                $hourRef  = "0$hourRef"  if ($hourRef  < 10);
                                                $minRef   = "0$minRef"   if ($minRef   < 10);
                                                $hourNSD  = "0$hourNSD"  if ($hourNSD  < 10);
                                                $minNSD   = "0$minNSD"   if ($minNSD   < 10);
                                                $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                                = "[WARNING] : $buildDir arrived too late at '$hourNSD:$minNSD' instead of ";
                                                if($grChecks{$project}{$Build}{$platform}{available}{$folder}) {
                                                    $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                                    .="$grChecks{$project}{$Build}{$platform}{available}{$folder}";
                                                }
                                                else {
                                                    $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                                    .="$grChecks{$project}{$Build}{available}";
                                                }
                                                if($grChecks{$project}{$Build}{$platform}{tolerance}{$folder} && ($grChecks{$project}{$Build}{$platform}{tolerance}{$folder}>0)) {
                                                    $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                                    .= ", with a tolerance of $grChecks{$project}{$Build}{$platform}{tolerance}{$folder} minute(s)";
                                                }
                                                else {
                                                    if($grChecks{$project}{$Build}{tolerance} && ($grChecks{$project}{$Build}{tolerance}>0)) {
                                                        $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                                        .= ", with a tolerance of $grChecks{$project}{$Build}{tolerance} minute(s)";
                                                    }
                                                }
                                            }
                                        }
                                        else {
                                            if( ($hourNSD == $hourRef) && ($minNSD > $minRef) ) { # if hour is equal hour ref but min after min ref, so, it is also too late, e.g.: ref=10:00, file_time=10:33, it is also too late
                                                $hourRef  = "0$hourRef"  if ($hourRef  < 10);
                                                $minRef   = "0$minRef"   if ($minRef   < 10);
                                                $hourNSD  = "0$hourNSD"  if ($hourNSD  < 10);
                                                $minNSD   = "0$minNSD"   if ($minNSD   < 10);
                                                $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                                = "[WARNING] : $buildDir arrived too late at '$hourNSD:$minNSD' instead of ";
                                                if($grChecks{$project}{$Build}{$platform}{available}) {
                                                    $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                                        .= "$grChecks{$project}{$Build}{$platform}{available}{$folder}";
                                                }
                                                else {
                                                    $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                                        .= "$grChecks{$project}{$Build}{available}{$folder}";
                                                }
                                                if($grChecks{$project}{$Build}{$platform}{tolerance}{$folder} && ($grChecks{$project}{$Build}{$platform}{tolerance}{$folder}>0)) {
                                                    $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                                        .= ", with a tolerance of $grChecks{$project}{$Build}{$platform}{tolerance}{$folder} minute(s)";
                                                }
                                                else {
                                                    if($grChecks{$project}{$Build}{tolerance} && ($grChecks{$project}{$Build}{tolerance}>0)) {
                                                        $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                                            .= ", with a tolerance of $grChecks{$project}{$Build}{tolerance} minute(s)";
                                                    }
                                                }
                                            }
                                            else {
                                                my $displayHour    = $hourNSD;
                                                $displayHour       = "0$displayHour" if ($displayHour < 10);
                                                my $displayMinutes = $minNSD;
                                                $displayMinutes    = "0$minNSD"      if ($minNSD      < 10);
                                                if($grChecks{$project}{$Build}{$platform}{available}{$folder}) {
                                                    $grChecks{$project}{$Build}{$platform}{passed}{$folder}
                                                        = "expected at $grChecks{$project}{$Build}{$platform}{available}{$folder}";
                                                }
                                                else {
                                                    $grChecks{$project}{$Build}{$platform}{passed}{$folder}
                                                        = "expected at $grChecks{$project}{$Build}{available}";
                                                }
                                                if($grChecks{$project}{$Build}{$platform}{tolerance}{$folder} && ($grChecks{$project}{$Build}{$platform}{tolerance}{$folder} > 0)) {
                                                    $grChecks{$project}{$Build}{$platform}{passed}{$folder}
                                                        .= " with a tolerance of $grChecks{$project}{$Build}{$platform}{tolerance}{$folder} minute(s)";
                                                }
                                                else {
                                                    if($grChecks{$project}{$Build}{tolerance} && ($grChecks{$project}{$Build}{tolerance} > 0)) {
                                                        $grChecks{$project}{$Build}{$platform}{passed}{$folder}
                                                            .= ", with a tolerance of $grChecks{$project}{$Build}{tolerance} minute(s)";
                                                    }
                                                }
                                                $grChecks{$project}{$Build}{$platform}{passed}{$folder}
                                                    .= ", arrived at $displayHour:$displayMinutes, the $grDay/$LocalMonth/$LocalYear";
                                            }
                                        }
                                    }
                            }
                            elsif($statusTransfer =~ /^active$/i) {
                                $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                = "[WARNING] : transfer of $project/$Build/$platform/$grMode/$folder still on going";
                                if($grChecks{$project}{$Build}{$platform}{available}) {
                                    $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                        .= "$grChecks{$project}{$Build}{$platform}{available}{$folder}";
                                }
                                else {
                                    $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                    .= "$grChecks{$project}{$Build}{available}{$folder}";
                                }
                                if($grChecks{$project}{$Build}{$platform}{tolerance}{$folder} && ($grChecks{$project}{$Build}{$platform}{tolerance}{$folder} > 0)) {
                                    $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                        .= ", with a tolerance of $grChecks{$project}{$Build}{$platform}{tolerance}{$folder} minute(s)";
                                }
                                else {
                                    if($grChecks{$project}{$Build}{tolerance} && ($grChecks{$project}{$Build}{tolerance} > 0)) {
                                        $grChecks{$project}{$Build}{$platform}{msgs}{$folder}
                                            .= ", with a tolerance of $grChecks{$project}{$Build}{tolerance} minute(s)";
                                    }
                                }
                                $forDB{$project}{$Build}{$thisVersion}{$platform}{$buildDir}{$thisTime}{0} = 1;
                            }
                            else {
                                $Issues{$project}{$Build}{$platform}{msgs}{$folder}
                                     = "[WARNING] : $statusTransfer transfer for $project/$Build/$platform/$folder";
                                $forDB{$project}{$Build}{$thisVersion}{$platform}{$buildDir}{$thisTime}{0} = 1;
                            }
                        }
                    }
                }
            }
        }
    }
    foreach my $project(keys %grChecks) {
        foreach my $Build (keys %{$grChecks{$project}}) {
            next if($param_Build && ($Build ne $param_Build) );
            foreach my $platform (keys %{$grChecks{$project}{$Build}}) {
                next if($platform =~ /$RegExp/);
                foreach my $folder (@{$grChecks{$project}{$Build}{$platform}{folders}}) {
                    if(defined $grChecks{$project}{$Build}{$platform}{msgs}{$folder}) { #if any issue found, store it in %Issues
                        $Issues{$project}{$Build}{version}                          = $grChecks{$project}{$Build}{version};
                        $Issues{$project}{$Build}{smtp_from}                        = $grChecks{$project}{$Build}{smtp_from}                        if(defined $grChecks{$project}{$Build}{smtp_from});
                        $Issues{$project}{$Build}{smtp_to}                          = $grChecks{$project}{$Build}{smtp_to}                          if(defined $grChecks{$project}{$Build}{smtp_to});
                        $Issues{$project}{$Build}{drop_dir}                         = $grChecks{$project}{$Build}{drop_dir}                         if(defined $grChecks{$project}{$Build}{drop_dir});
                        $Issues{$project}{$Build}{available}                        = $grChecks{$project}{$Build}{available}                        if(defined $grChecks{$project}{$Build}{available});
                        $Issues{$project}{$Build}{tolerance}                        = $grChecks{$project}{$Build}{tolerance}                        if(defined $grChecks{$project}{$Build}{tolerance});
                        $Issues{$project}{$Build}{$platform}{available}{$folder}    = $grChecks{$project}{$Build}{$platform}{available}{$folder}    if(defined $grChecks{$project}{$Build}{$platform}{available}{$folder});
                        $Issues{$project}{$Build}{$platform}{tolerance}{$folder}    = $grChecks{$project}{$Build}{$platform}{tolerance}{$folder}    if(defined $grChecks{$project}{$Build}{$platform}{tolerance}{$folder});
                        $Issues{$project}{$Build}{$platform}{msgs}{$folder}         = $grChecks{$project}{$Build}{$platform}{msgs}{$folder};
                        push(@{$Issues{$project}{$Build}{$platform}{folders}},$folder);
                        # my $msg = ($grChecks{$project}{$Build}{$platform}{msgs}{$folder} =~ /ERROR/) ? "ERROR" : "WARNING" ;
                    }
                }
            }
        }
    }
}

sub genereHMTL() {
    $ENV{HTML_DIR}        ||= "D:/Dashboard_EDC/internal/build.ops.quality/trunk/PI/export/sbop_dashboard/HTML/EDC";
    $ENV{HTML_IMAGES_DIR} ||= "../images";
    my $phpScript       = "check.build.avaibility_current_status.php";
    my $htmlOutPutFile  = "check.build";
    if($param_project) {
        $htmlOutPutFile .= ".$param_project";
    }
    if($param_Build) {
        $htmlOutPutFile .= ".$param_Build";
    }
    $htmlOutPutFile    .= ".avaibility_current_status.html";
    if($grCheck) {
        $phpScript      = "check.grBuild.avaibility_current_status.php";
        $htmlOutPutFile = "gr.$htmlOutPutFile";
    }
    if($localCheck) {
        $htmlOutPutFile = "local.$htmlOutPutFile";
    }
    if(open HTML,">$ENV{HTML_DIR}/$htmlOutPutFile") {
        my $displayMonth    = $LocalMonth;
        my $displayDay      = $LocalDay;
        my $displayHour     = $LocalHour;
        my $displayMin      = $LocalMin;
        # $displayMonth      = "0$displayMonth"  if($LocalMonth  < 10);
        # $displayDay        = "0$displayDay"    if($LocalDay    < 10);
        # $displayHour       = "0$displayHour"   if($LocalHour   < 10);
        # $displayMin        = "0$displayMin"    if($LocalMin    < 10);
        print HTML "<br/><center><h1>Daily Quick Status<br/>$LocalYear/$displayMonth/$displayDay - $displayHour:$displayMin:$LocalSec</h1>\n";
        print HTML '
<form action="./'.$phpScript.'"> 
<input border=0 src="'.$ENV{HTML_IMAGES_DIR}.'/refresh.gif" type="image" Value="submit" align="middle" >';
        if($param_project) {
            print HTML '<span style="display:none"><input type="text" name="prj" value="'.$param_project.'"/></span><br/>';
        }
        if($param_Build) {
            print HTML '<span style="display:none"><input type="text" name="build" value="'.$param_Build.'"/></span><br/>';
        }
        print HTML '
</form> 
<br/>
<p style="font-size:10px">
based on //internal/build.ops.quality/trunk/PI/export/check.build.avaibility/'.$Site.'.ini,<br/><br/>
syntax in the ini file to differentiate the source of the builds:<br/>
[local|grs:my_build] by default the check is done on local build(s).<br/>
for local builds : [local:my_build] or [my_build] are equivalent<br/>
for gr builds  : [gr:my_build]<br/>
"gr" means <strong>g</strong>lobal <strong>r</strong>eplication (nsd)<br/>
</p>
<br/>
';
        print HTML "<table border=\"0\" cellspacing=\"10\">\n";
        for my $project (sort keys %Checks) {
            next if($param_project && ($param_project ne $project));
            foreach my $Build (sort keys %{$Checks{$project}}) {
                next if($param_Build && ($param_Build ne $Build));
                my $nbPlatform = 0;
                my %folders;
                foreach my $platform (sort keys %{$Checks{$project}{$Build}}) {
                    next if($platform =~ /$RegExp/);
                    $nbPlatform++;
                    next if(scalar(@{$Checks{$project}{$Build}{$platform}{folders}}) < 1);
                    foreach my $folder (sort @{$Checks{$project}{$Build}{$platform}{folders}}) {
                        $folders{$folder} = 1;
                    }
                }
                $nbPlatform++;
                $nbPlatform = $nbPlatform * 2;
                my $hostGR  = $Checks{$project}{$Build}{host} if($Checks{$project}{$Build}{host});
                if($hostGR) {
                    if($HTTP_CIS{$hostGR}) {
                        my $CIS = $HTTP_CIS{$hostGR};
                        print HTML "\t<tr><td colspan=\"$nbPlatform\" align=\"left\"><strong><font color=\"#0000FF\"><a href=\"$CIS\?streams=$Build\&projects=$project\">$project/$Build/$Checks{$project}{$Build}{version}</a></font></strong></td></tr>\n";
                    }
                    else {
                        print HTML "\t<tr><td colspan=\"$nbPlatform\" align=\"left\"><strong><font color=\"#0000FF\">$project/$Build/$Checks{$project}{$Build}{version}</font></strong></td></tr>\n";
                    }
                }
                else {
                    print HTML "\t<tr><td colspan=\"$nbPlatform\" align=\"left\"><strong><font color=\"#0000FF\">$project/$Build/$Checks{$project}{$Build}{version}</font></strong></td></tr>\n";
                }
                print HTML "\t\t<tr><td></td>";
                foreach my $platform (sort keys %{$Checks{$project}{$Build}}) {
                    next if($platform =~ /$RegExp/);
                     print HTML "<td>$platform</td><td>&nbsp;&nbsp;&nbsp;</td>";
                }
                print HTML "</tr>\n";
                foreach my $folder (sort keys %folders) {
                    print HTML "\t\t<tr><td>$folder</td>";
                    my $line = "";
                    foreach my $platform (sort keys %{$Checks{$project}{$Build}}) {
                        next if($platform =~ /$RegExp/);
                        if($Checks{$project}{$Build}{$platform}{folder}{$folder}) {
                            if(defined $Issues{$project}{$Build}{$platform}{msgs}{$folder}) {
                                if($Issues{$project}{$Build}{$platform}{msgs}{$folder} =~ /ERROR/) { # if error => no copy_done
                                    if( ! -e "$DROP_DIR/$project/$Build/$Checks{$project}{$Build}{version}/$platform/release/$folder" ) {
                                        $line .= "<td align=\"center\"><img src=\"$ENV{HTML_IMAGES_DIR}/rond-noir.jpg\" height=\"30px\" width=\"30px\" title=\"$Issues{$project}{$Build}{$platform}{msgs}{$folder}\" /></td><td>&nbsp;&nbsp;&nbsp;</td>";
                                    }
                                    else {
                                        $line .= "<td align=\"center\"><img src=\"$ENV{HTML_IMAGES_DIR}/rond-rouge.gif\" title=\"$Issues{$project}{$Build}{$platform}{msgs}{$folder}\" /></td><td>&nbsp;&nbsp;&nbsp;</td>";
                                    }
                                }
                                elsif($Issues{$project}{$Build}{$platform}{msgs}{$folder} =~ /WARNING/) { # if error => copy_done too late
                                    $line .= "<td align=\"center\"><img src=\"$ENV{HTML_IMAGES_DIR}/rond-orange.gif\" title=\"$Issues{$project}{$Build}{$platform}{msgs}{$folder}\" /></td><td>&nbsp;&nbsp;&nbsp;</td>";
                                }
                                elsif($Issues{$project}{$Build}{$platform}{msgs}{$folder} =~ /earlier/) { # check done too earlier
                                    $line .= "<td align=\"center\"><img src=\"$ENV{HTML_IMAGES_DIR}/rond-gris.gif\" title=\"$Issues{$project}{$Build}{$platform}{msgs}{$folder}\" /></td><td>&nbsp;&nbsp;&nbsp;</td>";
                                }
                                else {
                                    $line .= "<td align=\"center\"><img src=\"$ENV{HTML_IMAGES_DIR}/rond-vert.gif\" title=\"$Checks{$project}{$Build}{$platform}{passed}{$folder}\" /></td><td>&nbsp;&nbsp;&nbsp;</td>" if($Checks{$project}{$Build}{$platform}{passed}{$folder});
                                }
                            }
                            else {
                                if($Checks{$project}{$Build}{$platform}{passed}{$folder}) {
                                    $line .= "<td align=\"center\"><img src=\"$ENV{HTML_IMAGES_DIR}/rond-vert.gif\" title=\"$Checks{$project}{$Build}{$platform}{passed}{$folder}\" /></td><td>&nbsp;&nbsp;&nbsp;</td>";
                                }
                                else {
                                    $line .= "<td align=\"center\"><img src=\"$ENV{HTML_IMAGES_DIR}/rond-gris.gif\" title=\"no check required or transfer not found\" /></td><td>&nbsp;&nbsp;&nbsp;</td>";
                                }
                            }
                        }
                        else {
                            $line .= "<td align=\"center\"><img src=\"$ENV{HTML_IMAGES_DIR}/rond-gris.gif\" title=\"no check required\" /></td><td>&nbsp;&nbsp;&nbsp;</td>";
                        }
                    }
                    print HTML "$line</tr>\n";
                } #end foreach folder
                print HTML "<tr><td colspan=\"$nbPlatform\">&nbsp;</td></tr>\n";
            }
        } #end foreach checks
        print HTML "</table></center>\n";
        close HTML;
    }
}

sub insertDB() {

    my $nbElem = scalar keys %forDB;
    if($nbElem == 0) {
        print "nothing to insert in db\n";
        exit;
    }

    my $db_host   = $ENV{SBOP_DB_SRV}       || "vermw64mst05.dhcp.wdf.sap.corp";
    my $db_user   = $ENV{SBOP_DB_USER}      || "sbop";
    my $db_passwd = $ENV{SBOP_DB_PASSWORD}  || "sbop";
    my $db_name   = $ENV{SBOP_DB_NAME}      || 'sbop_dashboard';
    my $db_table  = $ENV{SBOP_DB_TABLE}     || 'build_availability';

    if( -e "$ENV{PWFDBFILE}" ) {
        if(open PWFDBFILE,"$ENV{PWFDBFILE}") {
            while(<PWFDBFILE>) {
                chomp;
                s-^\s+$--;
                next unless($_);
                next if(/^\#/); #skip comment
                if(/^db_host\=(.+?)$/i) {
                    $db_host   = $1;
                }
                if(/^db_user\=(.+?)$/i) {
                    $db_user   = $1;
                }
                if(/^db_passwd\=(.+?)$/i) {
                    $db_passwd = $1;
                }
                if(/^db_name\=(.+?)$/i) {
                    $db_name   = $1;
                }
                if(/^db_table\=(.+?)$/i) {
                    $db_table  = $1;
                }
            }
            close PWFDBFILE;
        }
    }

print "
DB infos:
db_host  = $db_host
db_user  = $db_user
db_name  = $db_name
db_table = $db_table

";

    my $dbh =  DBI->connect("DBI:mysql:$db_name:$db_host", $db_user, $db_passwd) or die "Unable to connect: $DBI::errstr\n";
    print "\n\n\tdata injection in $db_table\@$db_name\n\n";
    # create table $db_table (project VARCHAR(20) , buildName VARCHAR(50), rev SMALLINT, platform VARCHAR(20),path TEXT,time_available TIME, time_arrived TIME,current DATETIME) ;
    foreach my $project (keys %forDB) {
        foreach my $build (keys %{$forDB{$project}}) {
            foreach my $version (keys %{$forDB{$project}{$build}}) {
                foreach my $platform (keys %{$forDB{$project}{$build}{$version}}) {
                    foreach my $buildDir (keys %{$forDB{$project}{$build}{$version}{$platform}}) {
                        my $buildDir2 = $buildDir;
                        ($buildDir2) =~ s-\/-\\-g;
                        foreach my $timeAvailable (keys %{$forDB{$project}{$build}{$version}{$platform}{$buildDir}}) {
                            #check if not already in db
                            my $timeAvailableFordb = "$timeAvailable:00";
                            my $request
                            = "SELECT path FROM $db_table WHERE site = '$Site' AND project = '$project' AND buildName = '$build' AND rev = '$version' AND platform = '$platform' AND time_available = '$timeAvailableFordb'";
                            print "$request\n" if($Verbose);
                            my $searchBuild = $dbh->prepare($request);
                            $searchBuild->execute();
                            my $result      = $searchBuild->fetchrow_hashref();
                            my $resultPath  = $result->{path};
                            $searchBuild -> finish;
                            print "$buildDir | $resultPath" if($Verbose && $resultPath);
                            if($resultPath) { #if path found
                                print "$resultPath already in db\n";
                            }
                            else { #if path not found, should be insert indb
                                print "insert $buildDir in db\n";
                                foreach my $datetime_string (keys %{$forDB{$project}{$build}{$version}{$platform}{$buildDir}{$timeAvailable}}) {
                                    my $insertQuery = $dbh->prepare("INSERT INTO $db_table (site,project,buildName,rev,platform,path,time_available,time_arrived,current) VALUES(?,?,?,?,?,?,?,?,?)");
                                    $insertQuery->execute($Site,$project,$build,$version,$platform,$buildDir2,$timeAvailableFordb,$datetime_string,$currentTime);
                                    $insertQuery -> finish;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    $dbh -> disconnect;
}

sub sendMail($$$$$$$$@) {
    my ($build,$project,$version,$dropdir,$available,$from,$to,$title,@lines) = @_;
    my $Temp = $ENV{TEMP};
    if( ! -e $Temp ) {
        system "mkdir -p $Temp";
    }

    if( -e "$Temp/mail_sent_${project}_${build}_$version.done" ) {
        print "mail already sent for $project/$build/$version\n";
    }
    else {
        my $htmlFile  = "check_avaibility_$build.html";
        if($grCheck) {
            $htmlFile = "gr.$htmlFile";
        }
        if($localCheck) {
            $htmlFile = "local.$htmlFile";
        }
        my $builddir  = "$dropdir/$project/$build/$version";
        ($builddir)   =~ s-\/-\\-g; # windows style
        system "rm -f \"$Temp/$htmlFile\" " if( -e "$Temp/$htmlFile" );
        open HTML,">$Temp/$htmlFile" || die "ERROR: cannot create '$Temp/$htmlFile': $!";
        print HTML '
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<html>
 <head>
  <meta http-equiv=Content-Type content="text/html; charset=iso-8859-1">
  <title>Mail ',"$title",'</title>
 </head>
 <body>
<br/>
Hi,<br/>
<br/>
The build&nbsp;&nbsp;<strong><font color="blue">',"$build - $version - general check for this build : $available",'</font></strong>&nbsp;&nbsp;is not (yet) available for requested exports.<br/>
This mail is sent also to ',"$from",' &nbsp;.<br/>
The build should be in ',"$builddir",' &nbsp;.<br/>
<br/>
';

        foreach my $line (@lines) {
            if($line =~ /^platform\:(.+?)\s+\-\s+(.+?)$/) {
                my $avaibilityPlatform = $2;
                my $linePlatform = "<a href=\"$builddir\\$1\\release\">$1</a>&nbsp;-&nbsp;$avaibilityPlatform";
                print HTML  "<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$linePlatform<br/>\n";
            }
            if($line =~ /^folder\:(.+?)\:(.+?)$/) {
                my $thisFolder = $1;
                my $msg        = $2;
                if($msg =~ /instead of/i) {
                    ($msg) =~ s-too late at-too late at <font color=\"red\">-;
                    ($msg) =~ s-instead of-</font> instead of <font color=\"green\">-;
                    $msg  .=  "</font>";
                }
                ($msg) =~ s-ERROR-<strong><font color=\"red\">ERROR</font></strong>-        if($msg =~ /ERROR/);
                ($msg) =~ s-WARNING-<strong><font color=\"orange\">WARNING</font></strong>- if($msg =~ /WARNING/);
                print HTML  "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$thisFolder<br/>\n";
                print HTML  "$msg<br/>\n";
            }
        }

        print HTML '

<br/>Please contact <a href="mailto:',"$from",'">',"$from",'</a> for any further information.<br/>
<br/>
Thanks,<br/>
<br/>
THIS EMAIL IS SEND AUTOMATICALLY, PLEASE DO NOT REPLY<br/>
<br/>
  </body>
</html>
';
        close HTML;

        my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>90);
        $smtp->mail($from);
        $smtp->to(split('\s*;\s*', $to));
        $smtp->data();
        map({$smtp->datasend("To: $_\n")} split('\s*;\s*', $to));
        $smtp->datasend("Subject: $title\n");
        $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=$htmlFile\n");
        open HTML, "$Temp/$htmlFile" or die ("ERROR: cannot open '$Temp/$htmlFile': $!");
            while(<HTML>) { $smtp->datasend($_) } 
        close HTML;
        $smtp->dataend();
        $smtp->quit();
        system "touch $Temp/mail_sent_${project}_${build}_$version.done";
        print "\nSend Mail done for $build - $version\n";
    }
}

#my generic functions
sub Usage() {
    print "
    Usage   : perl $0 [options]
    Example : perl $0 -h

[options]
    -h|?        argument displays helpful information about builtin commands.
    -ini        choose an ini file, by default: -i=\$Site.ini
    -site       choose a site, sites available : Levallois | Walldorf | Vancouver | Bangalore | Paloalto | Lacrosse
    -build      choose a build to monitor, this build has to be also in \$Site.ini
    -mail       send mail
    -ot         override trace file, see in check.build.avaibility.txt
    -nt         no create/override trace file
    -db         update db
    -verbose    verbose mode
    -html       create html file
    -gr         check for gr builds
    -es         exit status, used for jenkins
    -br         check a specific build revision, much more for jenkins usage
    -prj        choose a project

";
    exit 0;
}
