#!/usr/bin/perl -w

$P4Version = '$Id: //internal/core.build.tools/1.0/REL/export/shared/Build.pl#254 $';

$SIG{__DIE__} = sub { SendMail(@_); die(@_) };

# core
use Date::Calc(qw(Today_and_Now Delta_DHMS Add_Delta_Days Add_Delta_DHMS));
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use POSIX qw(:sys_wait_h);
use File::Basename;
use Sys::Hostname;
use Getopt::Long;
use Data::Dumper;
use Digest::MD5;
use Tie::IxHash;
use Time::Local;
use File::Find;
use File::Path;
use File::Copy;
use File::Spec::Functions;
use SOAP::Lite;
use Net::SMTP;
use IO::File;
use XML::DOM;

use Config;
use Cwd;

# local
use FindBin;
use lib ($FindBin::Bin, "$FindBin::Bin/site_perl");
use XLogging;

use BuildPL;
# function prototypes
sub submitbuildresults($$$$);

# versioning file management variables
$COMPANYNAME = $ENV{COMPANYNAME} || "SAP SE";
$COPYRIGHT = $ENV{COPYRIGHT} || "Copyright 2020 $COMPANYNAME. All rights reserved.";

die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/[\\\/]\d+$//;
$SMTPFROM = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
$CURRENTDIR = $FindBin::Bin;
$PRODPASSACCESS_DIR = $ENV{PRODPASSACCESS_DIR} || "$CURRENTDIR/prodpassaccess";
($ENV{BUILD_BOOTSTRAP_DIR} = $CURRENTDIR) =~ s/(.+)(?:[\\\/].*?){2}$/$1/ unless($ENV{BUILD_BOOTSTRAP_DIR});
$JAVA       = $ENV{JAVA_HOME} ? "\"$ENV{JAVA_HOME}/bin/java\"" : "java";
$HOST       = hostname();
$ENV{HOSTNAME} ||= $HOST;
$ENV{BUILD_PID} = $$;
if($^O eq "MSWin32")  { $USER = $ENV{USERNAME} }
else { $USER = `id` =~ /^\s*uid\=\d+\((.+?)\).*?/ }
($USER) = $USER =~ /^\s*(.+)\s*$/;
$xgLogVerboseLevel = 0; # set XLogging verbose level, 0 = do not output to console
$BuildResult = 0;
%QACSites = (Levallois=>1, Vancouver=>2, Walldorf=>3, Bangalore=>4, Paloalto=>5);
%GTxSites = (Levallois=>Levallois, Vancouver=>Vancouver, Walldorf=>Walldorf, Bangalore=>Bangalore, Paloalto=>Paloalto);
eval
{
    my $POM = XML::DOM::Parser->new()->parsefile("$CURRENTDIR/pom.xml");
    $ScriptVersion = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("version", 0)->item(0)->getFirstChild()->getData();
    $POM->dispose();
    print("Build.pl $ScriptVersion\n") if($ScriptVersion);
};

##############
# Parameters #
##############

$CommandLine = "Build.pl @ARGV";
$UpdateLocalRepositoryOnly = ($CommandLine=~/-lo.*=yes/ && $CommandLine!~/\s-[A-Z]/) ? 1 : 0;
Usage() unless(@ARGV);
%Opt = ("help|?"=>\$Help,
        "All!"=>\$All,
        "Build!"=>\$Build,
        "Clean!"=>\$Clean,
        "Depends!"=>\$Dependencies,
        "Export!"=>\$Export,
        "Fetch!"=>\$Fetch,
        "GTx!"=>\$GTx,
        "Helpfetch!"=>\$Prefetch,
        "Import!"=>\$Import,
        "Mail!"=>\$Mail,
        "News!"=>\$News,
        "Package!"=>\$Package,
        "QAC!"=>\$QAC,
        "Report!"=>\$Report,
        "Smoke!"=>\$Smoke,
        "Test!"=>\$Test,
        "Version!"=>\$Versioning,
        "Walidation!"=>\$Validation,
        "ZTEC"=>\$Astec,
        "64!"=>\$Model,
        "area=s@"=>\@BuildCommands,
        "context:s"=>\$ContextParameter,
        "dashboard!"=>\$Dashboard,
        "exports=s"=>\$SpecificExport,
        "fclean!"=>\$ForceClean,
        "fsync!"=>\$ForceSync,
        "git_timediff=s"=>\$GITDiff,
        "ini=s"=>\$Config,
        "job=s"=>\$JobFile,
        "localrepo=s"=>\$SpecificLocalRepository,
        "labeling!"=>\$Labeling,
        "lego!"=>\$Lego,
        "mode=s"=>\$BUILD_MODE,
        "nsd!"=>\$NSD,
        "polling!"=>\$Polling,
        "pom!"=>\$isPOMUpdate,
        "qset=s@"=>\@Sets,
        "rank=i"=>\$Rank,
        "sharing=i"=>\$NumberOfComputers,
        "target=s@"=>\@Targets,
        "version=s"=>\$BuildNumber,
        "wordy=i"=>\$xgLogVerboseLevel,
        "warning=i"=>\$WarningLevel,
        "update!"=>\$Update
);
$Getopt::Long::ignorecase = 0;
$OptionParseStatus = GetOptions(%Opt);
Usage() if($Help || !$OptionParseStatus);

$OBJECT_MODEL = $Model ? "64" : "32" if(defined($Model));
$ENV{OBJECT_MODEL} = $OBJECT_MODEL ||= $ENV{OBJECT_MODEL} || "32";
unless($PLATFORM = $ENV{MY_PLATFORM})
{
    if($^O eq "MSWin32")    { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64" : "win32_x86"  }
    elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc"  }
    elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64" : "aix_rs6000"  }
    elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64" : "hpux_pa-risc" }
    elsif($^O eq 'linux')
    { 
        if($Config{'archname'}=~/ppc64le/) { $PLATFORM='linux_ppc64le' }
        elsif($Config{'archname'}=~/ppc64/) { $PLATFORM='linux_ppc64' }
        else { $PLATFORM=$OBJECT_MODEL==64 ? 'linux_x64' : 'linux_x86' }
    }
    elsif($^O eq "darwin")  { $PLATFORM = $OBJECT_MODEL==64 ? "mac_x64" : "mac_x86" }
}
@Platform32to64{qw(win32_x86 solaris_sparc aix_rs6000 hpux_pa-risc linux_x86 mac_x86 linux_ppc32 linux_ppc32le)} = qw(win64_x64 solaris_sparcv9 aix_rs6000_64 hpux_ia64 linux_x64 mac_x64 linux_ppc64 linux_ppc64le);
unless($ENV{NUMBER_OF_PROCESSORS})
{
    if($^O eq "solaris")   { ($ENV{NUMBER_OF_PROCESSORS}) = `psrinfo -v | grep "Status of " | wc -l` =~ /(\d+)/ }
    elsif($^O eq "aix")    { ($ENV{NUMBER_OF_PROCESSORS}) = `lsdev -C | grep Process | wc -l` =~ /(\d+)/ }
    elsif($^O eq "hpux")   { ($ENV{NUMBER_OF_PROCESSORS}) = `ioscan -fnkC processor | grep processor | wc -l` =~ /(\d+)/ }
    elsif($^O eq "linux")  { ($ENV{NUMBER_OF_PROCESSORS}) = `cat /proc/cpuinfo | grep processor | wc -l` =~ /(\d+)/ }
    elsif($^O eq "darwin") { ($ENV{NUMBER_OF_PROCESSORS}) = `hostinfo | grep "physically available"` =~ /(\d+)/ }
    warn("ERROR: the environement variable NUMBER_OF_PROCESSORS is unknow") unless($ENV{NUMBER_OF_PROCESSORS});
}
$NULLDEVICE = $^O eq "MSWin32" ? "nul" : "/dev/null";

#Default value if not set
$Update = 1 if(!defined $Update);
$isPOMUpdate = 1 unless(defined($isPOMUpdate));
unless($Config)  { print(STDERR "ERROR: -i.ni option is mandatory (type Build.pl -h).\n"); exit(1) };
$BUILD_MODE ||= $ENV{BUILD_MODE} || "release";
if("debug"=~/^$BUILD_MODE/i) { $BUILD_MODE="debug" } elsif("release"=~/^$BUILD_MODE/i) { $BUILD_MODE="release" } elsif("releasedebug"=~/^$BUILD_MODE/i) { $BUILD_MODE="releasedebug" }
else { print(STDERR "ERROR: compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease|releasedebug]\n"); Usage() }
foreach (@Sets)
{
    my($Variable, $String) = /^(.+?):(.*)$/;
    Monitor(\${$Variable});
    ${$Variable} = $ENV{$Variable} = $String;
}
ReadIni();
$IGNORE_P4 = (exists($ENV{IGNORE_P4})) ? $ENV{IGNORE_P4} : 0;
($SRC_DIR = ExpandVariable(\$SRC_DIR)) =~ s/\\/\//g;
$SRC_DIR ||= $ENV{SRC_DIR};
# set SITE and PROJECT environment variables before include Site.pm
$ENV{PROJECT} = $Project if($Project);
require Site;
require XProcessLog;
if($BuildOptions)
{
    @ARGV = split(0xc2a7, `perl -e "print join(0xc2a7, \@ARGV)" -- $BuildOptions`);
    map({my $Dummy; $Opt{$_}=\$Dummy if(ref($Opt{$_}) eq "ARRAY" ? defined(${$Opt{$_}}[0]) : defined(${$Opt{$_}}))} keys(%Opt));
    GetOptions(%Opt);
}           
$WarningLevel = 2 unless(defined($WarningLevel));
$WarningMessage = $WarningLevel>0 ? "ERROR" : "WARNING";
unless($Version)  { print(STDERR "ERROR: the section [version] is mandatory in the ini file.\n"); exit(1) };
if($Clean && @BuildCommands)  { print(STDERR "ERROR: the parameters -Clean and -a are incompatibles.\n"); exit(1) };
$NumberOfComputers ||= 1;
$Rank ||= 1;
$NSD = 1 unless(defined($NSD));
$REMOTE_REPOSITORY ||= "no";
$ASTEC_DIR = $ENV{ASTEC_DIR};
my $LoginName = getlogin() || getpwuid($<) || "unknown";
$LoginName = lc($LoginName);
unless(exists($ENV{BUILD_DASHBOARD_ENABLE}))
{
    $ENV{BUILD_DASHBOARD_ENABLE} = ($LoginName eq "pblack" || $LoginName eq "builder" || $LoginName eq "psbuild" || $LoginName eq "ablack" || $LoginName eq "unknown" ) ? 1:0;
}
$ENV{BUILD_CIS_DASHBOARD_ENABLE} = 1 unless(exists($ENV{BUILD_CIS_DASHBOARD_ENABLE}));
$CACHEREPORT_ENABLE = 1 unless(defined($CACHEREPORT_ENABLE));
if($Dashboard && !-w $ENV{HTTP_DIR})
{
    $Dashboard = 0;
    print(STDERR "WARNING: You don't have permission for the update of the dashboard in '$ENV{HTTP_DIR}'.\n") 
}
$ENV{BUILD_CIS_DASHBOARD_ENABLE} = 0 if(defined($Dashboard) && $Dashboard == 0);
unless($Dashboard) {$Lego=0 }
elsif(!defined($Lego)) { $Lego = 1 }
$ENV{SUBMIT_LOG} = $Lego;
$QACcontext       ||= " ";
$QACphase         ||= " ";
$QACdb            ||= "prod";
$QACbuildpriority ||= "";
$QAClanguage      ||= "";
$QACsuite         ||= "";
$QACbatch         ||= "";
$QACuser          ||= "";
$QACtest          ||= "";
$QACsite          ||= "";
our($GTxSID, $GTXLabel, $GTxPassword, $GTxProtocol, $GTXPath, $GTxUsername, $GTxVerbose, $GTxHostname, $GTxPRG, $GTxReplicationSites, $GTxPRGNAME);
our($CWBurl, $CWBuser, $CWBpassword, $CWBpurpose, $CWBcredential, $CWBmaster);
unless(@QACPackages) { $ENV{'BUILDTYPE_BUSINESSOBJECTS'}="BOE_$Context"; $ENV{'BUILDTYPE_CRYSTALREPORTS'}="CR_$Context" }  
if($All)
{
    foreach my $Variable (qw(Clean Prefetch Fetch Versioning Import Build Package Export QAC GTx Report Test Smoke Validation News))
    {
        ${$Variable} = 1 unless(defined(${$Variable}));
    }
}
$ENV{BUILD_MODE} = $BUILD_MODE;
$ENV{context}    = $Context;
$ENV{PLATFORM}   = $PLATFORM;
$ENV{Client}     = $Client;
$DROP_DIR        = $ENV{DROP_DIR};
$DROP_NSD_DIR    = $ENV{DROP_NSD_DIR};
$IMPORT_DIR      = $ENV{IMPORT_DIR};
$HTTPDIR         = "$ENV{HTTP_DIR}/$Context";
($ShortMode = $BUILD_MODE) =~ s/^(.).*(.)$/$1$2/;
$ENV{TMP}        = $ENV{TEMP} = $TEMPDIR .= "/$Context/$OBJECT_MODEL/$ShortMode";
($ss, $mn, $hh, $dd, $mo, $yy) = (localtime)[0..5];
our($YY, $MO, $DD, $HH, $MN, $SS) = ($yy+1900, sprintf("%02d", $mo+1), sprintf("%02d", $dd), sprintf("%02d", $hh), sprintf("%02d", $mn), sprintf("%02d", $ss));
$ENV{BUILD_DATE} = $BuildDate = sprintf("%04d/%02d/%02d:%02d:%02d:%02d", $yy+1900, $mo+1, $dd, $hh, $mn, $ss);
$ENV{BUILD_DATE_EPOCH}=time();
$SpecificLocalRepository ||= "yes";
$IsIniCopyDone = 0;
$SubmitContext = defined($ENV{SUBMIT_CONTEXT}) ? $ENV{SUBMIT_CONTEXT} : 1;
$DEEP_CONTEXT = defined($ENV{DEEP_CONTEXT}) ? $ENV{DEEP_CONTEXT} : 4;
$PW_DIR = $ENV{PW_DIR} || (($^O eq "MSWin32") ? '\\\\build-drops-wdf\dropzone\aurora_dev\.xiamen' : '/net/build-drops-wdf/dropzone/aurora_dev/.xiamen');
$CREDENTIAL = "$PW_DIR/.credentials.properties";
$MASTER = "$PW_DIR/.master.xml";
if(-f $CREDENTIAL && -f $MASTER)
{
    open(CRED, $CREDENTIAL) or warn("ERROR: cannot open '$CREDENTIAL': $!");
    while(<CRED>)
    {
        next unless(my($Purpose) = /^\s*(.+)\.user\s*=/);
        $ENV{"${Purpose}_USER"} ||= `$PRODPASSACCESS_DIR/bin/prodpassaccess --credentials-file $CREDENTIAL --master-file $MASTER get $Purpose user`; chomp($ENV{"${Purpose}_USER"});
        $ENV{"${Purpose}_PASSWORD"} ||= `$PRODPASSACCESS_DIR/bin/prodpassaccess --credentials-file $CREDENTIAL --master-file $MASTER get $Purpose password`; chomp($ENV{"${Purpose}_PASSWORD"});
    }
    close(CRED);
} 

# To be removed after all scripts depending on lower case are fixed:
$ENV{platform} = $PLATFORM;
mkpath($TEMPDIR) or die("ERROR: cannot mkpath '$TEMPDIR': $!") unless(-e $TEMPDIR);
$IsDropDirWritable = 0;
for my $Attempt (1..3)
{
    `ls -ld $DROP_DIR/` unless(exists($ENV{RE_MODULE}) and $ENV{RE_MODULE} eq 'XProcessLogREDoc.pm');
    if(-w $DROP_DIR) { $IsDropDirWritable=1; last }
    sleep(5);
}
warn("WARNING: You don't have permission for the drop zone updating in '$DROP_DIR'.") if(!$IsDropDirWritable && $Export);

## clean maven repositories ##
$LocalRepository = ($SpecificLocalRepository=~/^(?:yes|no)$/i) ? "$CURRENTDIR/../../LocalRepos/$Context/$PLATFORM/$BUILD_MODE/repository" : $SpecificLocalRepository;
($TempViews = $LocalRepository) =~ s/[^\\\/]+$/views/;
if(($Fetch || $Import) && $SpecificLocalRepository=~/yes/i)
{
    rmtree($TempViews) or warn("ERROR: cannot rmtree '$TempViews': $!") if(-e $TempViews);
    rmtree("$LocalRepository/com/sap") or warn("ERROR: cannot rmtree '$LocalRepository/com/sap': $!") if(-e "$LocalRepository/com/sap");
}

unless($BuildNumber)
{
    $BuildNumber = 0;
    if(open(VER, "$DROP_DIR/$Context/version.txt"))
    {
        chomp($BuildNumber = <VER>);
        $BuildNumber = int($BuildNumber);
        close(VER);
    }
    else # If version.txt does not exists or opening failed, instead of restarting from 1, look for existing directory versions & generate the hightest version number based on the hightest directory version
    {
        # open current context dir to find the hightest directory version inside
        if(opendir(BUILDVERSIONSDIR, "$DROP_DIR/$Context"))
        {
            while(defined(my $next = readdir(BUILDVERSIONSDIR)))
            {
                $BuildNumber = $1 if ($next =~ /^(\d+)(\.\d+)?$/ && $1 > $BuildNumber && -d "$DROP_DIR/$Context/$next"); # Only take a directory with a number as name, which can be a number or a float number with a mandatory decimal value & optional floating point
            }   
            closedir(BUILDVERSIONSDIR);
        }
    }
    if($Versioning || $BuildNumber == 0)
    {
        $BuildNumber++ ;
        if($IsDropDirWritable)
        {
            eval { mkpath("$DROP_DIR/$Context") or warn("ERROR: cannot mkpath '$DROP_DIR/$Context': $!") } unless(-e "$DROP_DIR/$Context");
            if(-e "$DROP_DIR/$Context" && open(VER, ">$DROP_DIR/$Context/version.txt"))
            {
                print(VER "$BuildNumber\n");
                close(VER);
            } else { warn("ERROR: Automatic versioning managed by Build.pl but a write permission is mandatory for this on the drop zone in '$DROP_DIR/$Context': $!\n\tOr disable this feature by using the -noV parameter & by setting your own version number with -v= !")  }
        }
    }
}
($buildnumber, $precision) = $BuildNumber =~ /^(\d+)(\.?\d*)/; 
$ENV{build_number} = "$BuildNumber";
($ENV{MAJOR}, $ENV{MINOR}, $ENV{SLIP}) = split('\.', $Version);
$ENV{BUILDREV} = $ENV{FILEREV} = $buildnumber;
$ENV{BOTAG}    = "$Version.$buildnumber";
$buildnumber = sprintf("%05d", $BuildNumber).$precision;
$ENV{BUILD_NAME} = $BuildName = "${Context}_$buildnumber";
$ENV{URL_REPOSITORY} ||= "${CURRENTDIR}/../../repositories";
$ENV{REF_WORKSPACE} ||= '//${Client}/%%ArtifactId%%/%%Version%%/...';
$EXPORT_METADATA = defined($ENV{EXPORT_METADATA}) ? $ENV{EXPORT_METADATA} : 1;
($Repositories = $ENV{URL_REPOSITORY}) =~ s/^file:[\\\/][\\\/]//;
my $RootGroupId;
if($ENV{ROOT_GAV})
{
    if(($RootStaging, $RootGroupId, $RootArtifactId, $RootVersion) = $ENV{ROOT_GAV} =~ /^([^:]+):([^:]+):([^:]+):([^:]+)$/) { $POMFile = "$Repositories/$RootStaging/$RootArtifactId/$RootVersion/pom.xml" }
    elsif(($RootStaging, $POMFile) = $ENV{ROOT_GAV} =~ /^([^:]+):(.+)$/) { }
    else { warn("ERROR: wrong syntax in \$ENV{ROOT_GAV}=$ENV{ROOT_GAV}") }
}
$IsRobocopy = $^O eq "MSWin32" ? (`which robocopy.exe 2>&1`=~/robocopy.exe$/i  ? 1 : 0) : 0;
$MVN_OPTIONS = $ENV{MVN_OPTIONS} || "";
$ROBOCOPY_OPTIONS = $ENV{ROBOCOPY_OPTIONS} || "/MIR /NP /NFL /NDL /R:3";
if($Dashboard && $ENV{BUILD_CIS_DASHBOARD_ENABLE})
{
    unless(-e "$HTTPDIR/$BuildName/Host_$Rank")
    {
        sleep(5);
        eval { mkpath ("$HTTPDIR/$BuildName/Host_$Rank") };
        warn("ERROR: cannot mkpath '$HTTPDIR/$BuildName/Host_$Rank': $!") if($@);
    }
}

## Perforce Initialization ##
unless($IGNORE_P4) { require Perforce; $p4 = new Perforce }
if($p4 && ($Fetch || $Import))
{
    eval { $p4->Login("-s") };
    if($@)
    {
        if($WarningLevel<2) { warn("$WarningMessage: User not logged : $@") } 
        else { die("ERROR: User not logged : $@") }
        $p4 = undef;    
    } 
    elsif($p4->ErrorCount())
    {
        if($WarningLevel<2) { warn("$WarningMessage: User not logged : ", @{$p4->Errors()}) } 
        else { die("ERROR: User not logged : ", @{$p4->Errors()}) }
        $p4 = undef;
    }
    if($p4)
    {
        eval
        {
            my($CurrentRev) = $P4Version =~ /#(\d+)/;
            my $rafstat = $p4->fstat("$CURRENTDIR/Build.pl");
            foreach (@{$rafstat})
            {
                if(my($HeadRev) = /headRev\s+(\d+)/)
                {
                    print(STDERR "WARNING: a newer version of Build.pl exists in P4. We recommend you to update your script (#$CurrentRev to #$HeadRev).\n") if($CurrentRev < $HeadRev);
                    last;
                }
            }
        };
    }
}
$p4->SetOptions("-c \"$Client\"") if($p4);

if(defined($ContextParameter) && $ContextParameter !~ /^\d{2}:\d{2}:\d{2}$/)
{
    if($ContextParameter=~/\.zip/ && ($Fetch || $Import || $Build))
    {
        my $Zip = Archive::Zip->new();
        die("ERROR: cannot read '': $!") unless($Zip->read($ContextParameter)==AZ_OK); 
        mkpath("$TEMPDIR/$$/contexts") or warn("ERROR: cannot mkpath '$TEMPDIR/$$/contexts': $!") unless(-d "$TEMPDIR/$$/contexts");
        $Zip->extractTree("contexts", "$TEMPDIR/$$/contexts");
    }
    @Views = @GITViews = @Imports = @NexusImports = ();
    if($Fetch)
    {
        $XMLContext = ($ContextParameter=~/\.zip/) ? "$TEMPDIR/$$/contexts/$Context.context.xml" : $ContextParameter;  
        eval
        {        
            my $CONTEXT = XML::DOM::Parser->new()->parsefile($XMLContext);  
            for my $SYNC (@{$CONTEXT->getElementsByTagName("fetch")})
            {
                my($File, $Revision, $Workspace) = ($SYNC->getFirstChild()->getData(), $SYNC->getAttribute("revision"), $SYNC->getAttribute("workspace"));
                $Workspace =~ s/\/\/[^\/]+\//\/\/$Client\//;
                push(@Views, [$File, $Workspace, $Revision]);
            }
            for my $GIT (@{$CONTEXT->getElementsByTagName('git')})
            {
                my($Repository, $RefSpec, $Destination, $StartPoint) = ($GIT->getAttribute('repository'), $GIT->getAttribute('refspec'), $GIT->getAttribute('destination'), $GIT->getAttribute('startpoint'));
                $Destination =~ s/^.+?[\\\/]src[\\\/]/$SRC_DIR\//;
                push(@GITViews, [$Repository, $RefSpec, $Destination, $StartPoint]);
            }
            $CONTEXT->dispose();
        };
        die("ERROR: cannot parse '$XMLContext': $@; $!") if($@);
    }
    if($Import)
    {
        $XMLContext = ($ContextParameter=~/\.zip/) ? "$TEMPDIR/$$/contexts/$Context.context.xml" : $ContextParameter;  
        eval
        {
            my $CONTEXT = XML::DOM::Parser->new()->parsefile($XMLContext);  
            for my $IMPORT (@{$CONTEXT->getElementsByTagName("import")})
            {
                my($Area, $Version) = ($IMPORT->getFirstChild()->getData(), $IMPORT->getAttribute("version"));
                push(@Imports, [$Area, "=$Version", "no"]);
            }
            for my $NEXUSIMPORT (@{$CONTEXT->getElementsByTagName("nexusimport")})
            {
                my($Platform, $MappingFile, $TargetDir, $Log1, $Log2, $Options) = ($NEXUSIMPORT->getAttribute('platform'), $NEXUSIMPORT->getAttribute('mapping'), $NEXUSIMPORT->getAttribute('target'), $NEXUSIMPORT->getAttribute('log1'), $NEXUSIMPORT->getAttribute('log2'), $NEXUSIMPORT->getAttribute('options'));
                push(@NexusImports, [$Platform, $MappingFile, $TargetDir, $Log1, $Log2, $Options]);
            }
            $CONTEXT->dispose();
        };
        die("ERROR: cannot parse '$XMLContext': $@; $!") if($@);
    }
}

# fill repository
$IsGetCommand = 0;
if(($Fetch || $Import || $UpdateLocalRepositoryOnly) && $p4)
{
	my $StartTime = time();
    xLogOpen("$LocalRepository/fill_repository.log");
    xLogH2("Fill start: ".time() );
    xLogH1("Dependencies...\n");

    foreach my $raCommand (@Imports, @Views) # command parsing
    {
        my($Command, $Workspace, $Revision) = @{$raCommand};
        if(my($GAV) = $Command =~ /^git.+?\s+(.+)$/i)
        {
            my($Staging, $GroupId, $ArtifactId, $Version) = split(/\s*:\s*/, $GAV);
            eval
            { 
                my $POM = XML::DOM::Parser->new()->parsefile("$Repositories/$Staging/$ArtifactId/$Version/pom.xml");
                for my $CLASSIFIER (@{$POM->getElementsByTagName("classifier")})
                {
                    my($Classifier) = $CLASSIFIER->getFirstChild()->getData();
                    my($Repository) = $Classifier =~ /repository=([^\n]+)/; 
                    my($RefSpec) = $Classifier =~ /refspec=([^\n]+)/;
                    my($Destination) = $Classifier =~ /destination=([^\n]+)/; 
                    my($StartPoint) = $Classifier =~ /startpoint=([^\n]+)/; 
                    push(@GITViews, [$Repository, $RefSpec, "$SRC_DIR/$Destination", $StartPoint]);
                }
                $POM->dispose();
            };
            warn("ERROR: cannot parse '$Repositories/$Staging/$ArtifactId/$Version/pom.xml': $@; $!") if($@);
        }
        next unless($Command =~ /^get/);
        $IsGetCommand = 1;
    }
    if($IsGetCommand)
    {
        my $RepoPOMFile;
        if("yes" !~ /^$REMOTE_REPOSITORY/i && $SpecificLocalRepository=~/^yes$/i) # Fill repository
        {
            $RepoPOMFile = RepositoryPOM($POMFile);
            # Default POMs #
            my @Stagings = $ENV{STAGING_PRIORITY} ? split(",", $ENV{STAGING_PRIORITY}) : ($RootStaging);
            foreach my $Staging (reverse(@Stagings))
            {
                if(opendir(AREA, "$Repositories/$Staging")) 
                {
	                while(defined(my $Area = readdir(AREA)))
	                {
	                    next if($Area =~ /^\.\.?/);
	                    if(opendir(VER, "$Repositories/$Staging/$Area")) 
	                    {
		                    while(defined(my $Version = readdir(VER)))
		                    {
		                        next if($Version =~ /^\.\.?/);
		                        RepositoryPOM("$Repositories/$Staging/$Area/$Version/pom.xml");
		                    }
		                    closedir(VER);
	                    } else { warn("ERROR: cannot opendir '$Repositories/$Staging/$Area': $!"); }
	                }
		            closedir(AREA);
                } else { warn("ERROR: cannot opendir '$Repositories/$Staging': $!"); }  # fill repository with latest POMs
            }
            # fill the repository from the context POMs
            if(my($XMLContextFile) = $ENV{REF_REVISION} =~ /^=(.+)$/)
            {
                $XMLContextFile .= "/$1.context.xml" if($XMLContextFile =~ /([^\\\/]+)[\\\/]\d+$/);
                $XMLContextFile = "$IMPORT_DIR/$XMLContextFile" unless(-e $XMLContextFile);
                warn("ERROR: cannot open '$XMLContextFile': $!") unless(-e $XMLContextFile);
                my %DepotSources;
                eval
                {
                    my $CONTEXT = XML::DOM::Parser->new()->parsefile($XMLContextFile);  
                    for my $FETCH (reverse(@{$CONTEXT->getElementsByTagName("fetch")}))
                    {
                        my($DepotSource, $Revision) = ($FETCH->getFirstChild()->getData(), $FETCH->getAttribute("revision"));                        
                        ($DepotSource) = $DepotSource =~ /(\/(?:\/[^\/]+){4})/;
                        if($DepotSource =~ /\*/)
                        {
                            my $raDirs = $p4->Dirs("$DepotSource/*");
                            warn("ERROR: cannot dirs '$DepotSource/*': ", @{$p4->Errors()}) if($p4->ErrorCount());
                            foreach my $Dir (@{$raDirs})
                            {
                                ($Dir) = $Dir =~ /(\/(?:\/[^\/]+){4})/;
                                $DepotSources{$Dir} = $Revision;
                            }
                        } else { $DepotSources{$DepotSource} = $Revision }
                    }
                    $CONTEXT->dispose();
                };
                die("ERROR: cannot parse '$XMLContextFile': $@; $!") if($@);
                while(my($DepotSrc, $Revision) = each(%DepotSources))
                {
                    $DepotSrc .= "/pom.xml";
                    (my $WorkspaceDestination = $DepotSrc) =~ s/^\/\/[^\/]+/$TempViews/;
                    if($isPOMUpdate)
                    {
                        xLogInf1("\tp4->print1  $WorkspaceDestination $DepotSrc $Revision\n");
                        $p4->print("-o", $WorkspaceDestination, "$DepotSrc$Revision");
                        if($p4->ErrorCount() && ${$p4->Errors()}[0]=~/no such file\(s\).$/) { warn("WARNING: '$DepotSrc$Revision' does not contain pom.xml file (from $XMLContextFile)"); next } 
                        warn("ERROR: cannot print '$DepotSrc$Revision' (from : $XMLContextFile)", @{$p4->Errors()}, " ") if($p4->ErrorCount());
                    }
                    RepositoryPOM($WorkspaceDestination);
                }
            }
            # Fill the repository from the ini POMs #
            xLogInf1("\t=== calling MVN for DependenciesTree on LocalRepo from [".defined $RepoPOMFile?$RepoPOMFile:"undef"."]  or [".defined $POMFile?$POMFile:"undef"."] \n");
            $raGAVs = DependenciesTree($ENV{ROOT_GAV} =~ /^[^:]+:[^:]+:[^:]+:[^:]+$/ ? $RepoPOMFile : $POMFile);       
            %GAVFullDepends = ();
            GAVDepends($raGAVs, 0);
            ARTIFACTID: foreach my $GAV1 (keys(%GAVFullDepends))
            {
                my $NumberOfDepends = scalar(keys(%{$GAVFullDepends{$GAV1}})); 
                foreach my $GAV2 (keys(%{$GAVFullDepends{$GAV1}}))
                {
                    @{$GAVFullDepends{$GAV1}}{keys(%{$GAVFullDepends{$GAV2}})} = (undef);
                }
                redo ARTIFACTID if(keys(%{$GAVFullDepends{$GAV1}}) > $NumberOfDepends);
            }
            foreach my $raCommand (@Imports, @Views)
            {
                my($Command, $Folder, $Revision) = @{$raCommand};
                if(my($GAVs) = $Command =~ /^get.+?\s+(.+)$/i)
                {
                    my $IsRecursive = $GAVs =~ s/\s*-R\s//;
                    $GAVs =~ s/\s*-(R|O|C)\s+//;
                    my $rhExpandedGAVs = ExpandGAVs($GAVs);
                    my @GAVs = map({"${$rhExpandedGAVs}{$_}:$_"} keys(%{$rhExpandedGAVs}));
                    if($IsRecursive)
                    {
                        my(%FullTreeGAVs);
                        foreach my $GAV (@GAVs)
                        {
                            my($RefStaging, $RefGroupId, $RefArtifactId, $RefVersion) = split(/\s*:\s*/, $GAV);
                            @FullTreeGAVs{map({"$RefStaging:$_"} keys(%{$GAVFullDepends{"$RefGroupId:$RefArtifactId:$RefVersion"}}))} = (undef);                        
                        }
                        foreach my $GAV (@GAVs) { delete($FullTreeGAVs{$GAV}) }
                        @GAVs = (keys(%FullTreeGAVs), @GAVs);
                    }
                    foreach my $GAV (@GAVs)
                    {
                        my($RefStaging, $RefGroupId, $RefArtifactId, $RefVersion) = split(/\s*:\s*/, $GAV);
                        my $RealPOM = "$Repositories/$RefStaging/$RefArtifactId/$RefVersion/pom.xml";
                        unless(-e $RealPOM)
                        { 
                            if(opendir(VER, "$Repositories/$RefStaging/$RefArtifactId"))
                            {
	                            while(defined(my $Version = readdir(VER)))
	                            {
	                                next if($Version =~ /^\.\.?$/);
	                                next unless(-e "$Repositories/$RefStaging/$RefArtifactId/$Version/pom.xml");
	                                eval
	                                {
	                                    my $POM = XML::DOM::Parser->new()->parsefile("$Repositories/$RefStaging/$RefArtifactId/$Version/pom.xml");
	                                    my $RealVersion = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("version", 0)->item(0)->getFirstChild()->getData();
	                                    $POM->dispose();
	                                    $RealPOM = "$Repositories/$RefStaging/$RefArtifactId/$Version/pom.xml" if($RealVersion eq $RefVersion);
	                                };
	                                warn("ERROR: cannot parse '$Repositories/$RefStaging/$RefArtifactId/$RefVersion/pom.xml': $@") if($@);
	                            }
	                            closedir(VER);
                            } else { warn("WARNING: cannot opendir '$Repositories/$RefStaging/$RefArtifactId': $!"); }
                        }
                        unless(-e $RealPOM) { warn("WARNING: '$RealPOM' not found"); next }
                        my $DepotSource;
                        eval
                        {
                            my $POM = XML::DOM::Parser->new()->parsefile($RealPOM);
                            ($DepotSource = $POM->getElementsByTagName("scm")->item(0)->getElementsByTagName("connection")->item(0)->getFirstChild()->getData()) =~ s/^scm:perforce://;
                            $POM->dispose();
                        };
                        $DepotSource =~ s/^\$Id:\s*//;
                        $DepotSource =~ s/#\d+\s*\$//;
                        if($@) { warn("ERROR: cannot parse '$RealPOM': $@"); next }
                        xLogInf1("Revision: ".(defined $Revision?$Revision:"undefined")."\n");
                        my $FilePomRevision = "";
                        if(my($XMLContextFile) = $Revision =~ /^=(.+)$/) # matching with the context
                        {
                            $XMLContextFile .= "/$1.context.xml" if($XMLContextFile =~ /([^\\\/]+)[\\\/]\d+$/);
                            $XMLContextFile = "$IMPORT_DIR/$XMLContextFile" unless(-e $XMLContextFile);
                            warn("ERROR: '$XMLContextFile' not found") unless(-e $XMLContextFile);
                            (my $Version = $RefVersion) =~ s/-SNAPSHOT//;
                            my($DepotSource1) = $DepotSource =~ /(\/(?:\/[^\/]+){4})/;
                            eval
                            {
                                my $CONTEXT = XML::DOM::Parser->new()->parsefile($XMLContextFile);  
                                xLogInf1("Looking for Ref in ".(defined $XMLContextFile?$XMLContextFile:"undef")."\n");
                                for my $FETCH (reverse(@{$CONTEXT->getElementsByTagName("fetch")}))
                                {
                                    my($DepotSource2, $Rev) = ($FETCH->getFirstChild()->getData(), $FETCH->getAttribute("revision"));                        
                                    ($DepotSource2) = $DepotSource2 =~ /(\/(?:\/[^\/]+){4})/;
                                    if($DepotSource2 =~ /$DepotSource1/i) { $FilePomRevision = $Rev; last }
                                }
                                xLogInf1("Ref:".(defined $DepotSource1?$DepotSource1:"undef")." ".(defined $Revision?$Revision:"undef")." ".(defined $FilePomRevision?$FilePomRevision:"undef")."\n");
                                $CONTEXT->dispose();
                            };
                            xLogH1("ERROR: cannot parse '$XMLContextFile' at ". __FILE__. " line ". __LINE__. ": $@") if($@);
                            die("ERROR: cannot parse '$XMLContextFile': $@; $!") if($@);
                            if($FilePomRevision =~ /^=/) { warn("ERROR: '$DepotSource' does not match in $XMLContextFile\n"); next }
                        }
                        (my $WorkspaceDestination = $DepotSource) =~ s/^\/\/[^\/]+/$TempViews/;
                        if($isPOMUpdate)
                        {
                            xLogInf1("\tp4->print2  $WorkspaceDestination $DepotSource $Revision $FilePomRevision\n");
                            $p4->print("-o", $WorkspaceDestination, "$DepotSource$FilePomRevision");
                            if($p4->ErrorCount() && ${$p4->Errors()}[0]=~/no such file\(s\).$/) { warn("WARNING: '$DepotSource$FilePomRevision' no such file (see $RealPOM)"); next }
                            warn("ERROR: cannot print '$DepotSource$Revision' (see $RealPOM): ", @{$p4->Errors()}, " ") if($p4->ErrorCount());
                        }
                        RepositoryPOM($WorkspaceDestination);
                    }
                }
            }
        }
        else
        {
            if($ENV{ROOT_GAV} =~ /^[^:]+:[^:]+:[^:]+:[^:]+$/)
            {
                my($Staging, $GroupId, $ArtifactId, $Version) = split(/\s*:\s*/, $ENV{ROOT_GAV});
                (my $GroupIdPath = $GroupId) =~ s/\./\//g;
                $RepoPOMFile = "$LocalRepository/$GroupIdPath/$ArtifactId/$Version/pom.xml";
            }
            else { $RepoPOMFile = $POMFile }
        }
        # Read dependencies #
        Properties($ENV{ROOT_GAV} =~ /^[^:]+:[^:]+:[^:]+:[^:]+$/ ? $RepoPOMFile : $POMFile);
        xLogInf1("\t=== calling MVN for DependenciesTree on LocalRepo from [".defined $RepoPOMFile?$RepoPOMFile:"undef"."]  or [".defined $POMFile?$POMFile:"undef"."] \n");
        $raGAVs = DependenciesTree($ENV{ROOT_GAV} =~ /^[^:]+:[^:]+:[^:]+:[^:]+$/ ? $RepoPOMFile : $POMFile);
        my %Artifacts;
        @Artifacts{map({"${$_}[1]:${$_}[2]:${$_}[3]"} @{$raGAVs})} = (undef);
        foreach my $raCommand (@Imports, @Views)
        {
            my($Command, $Folder, $Revision) = @{$raCommand};
            if(my($GAVs) = $Command =~ /^get.+?\s+(.+)$/i)
            {
                $GAVs =~ s/\s*-(R|O|C)\s+//;
                my @GAVs = split(/\s*,\s*/, $GAVs);
                foreach my $GAV (@GAVs)
                {
                    my($Staging, $GroupId, $ArtifactId, $Version) = split(/\s*:\s*/, $GAV);
                    if($GAV !~ /\*/ && !exists($Artifacts{"$GroupId:$ArtifactId:$Version"}))
                    {
                        push(@AdditionalArtifacts, [0, $GroupId, $ArtifactId, $Version]);
                    }
                }
            }
        }
        # $ArtifactIds{$GAV} = [\%ProvidersOfGAV, \%ClientsOfGAV, \%FullTree, $Packaging];
        foreach my $raGAV (@{$raGAVs}, @AdditionalArtifacts)
        {
            my($Level1, $GroupId1, $ArtifactId1, $Version1) = @{$raGAV};
            ${${$ArtifactIds{"$GroupId1:$ArtifactId1:$Version1"}}[2]}{"$GroupId1:$ArtifactId1:$Version1"} = undef;
            (my $GroupIdPath = $GroupId1) =~ s/\./\//g;
            my $POMFullName = "$LocalRepository/$GroupIdPath/$ArtifactId1/$Version1/$ArtifactId1-$Version1.pom";
            eval
            { 
                my $POM = XML::DOM::Parser->new()->parsefile($POMFullName);
                my $PROJECT = $POM->getElementsByTagName("project")->item(0);
                my $Packaging = $PROJECT->getElementsByTagName("packaging", 0)->getLength() ? $PROJECT->getElementsByTagName("packaging", 0)->item(0)->getFirstChild()->getData() : "jar";
                ${${$ArtifactIds{"$GroupId1:$ArtifactId1:$Version1"}}[2]}{"$GroupId1:$ArtifactId1:$Version1"} = undef;
                ${$ArtifactIds{"$GroupId1:$ArtifactId1:$Version1"}}[3] = (grep({"${$_}[1]:${$_}[2]:${$_}[3]" eq "$GroupId1:$ArtifactId1:$Version1"} @AdditionalArtifacts)) ? $Packaging : "";
                my $DEPENDENCIES = $PROJECT->getElementsByTagName("dependencies", 0)->item(0);
                if($DEPENDENCIES)
                {
                    for my $DEPENDENCY (@{$DEPENDENCIES->getElementsByTagName("dependency", 0)})
                    {
                        my($GroupId2, $ArtifactId2, $Version2);
                        eval
                        { 
                            $GroupId2 = $DEPENDENCY->getElementsByTagName("groupId", 0)->item(0)->getFirstChild()->getData();
                            $ArtifactId2 = $DEPENDENCY->getElementsByTagName("artifactId", 0)->item(0)->getFirstChild()->getData();
                            $Version2 = $DEPENDENCY->getElementsByTagName("version", 0)->item(0)->getFirstChild()->getData();
                        };
                        if($@) { warn("ERROR: dependency wrong in '$POMFullName': $!"); next }
                        ${${$ArtifactIds{"$GroupId1:$ArtifactId1:$Version1"}}[0]}{"$GroupId2:$ArtifactId2:$Version2"} = undef;
                        ${${$ArtifactIds{"$GroupId1:$ArtifactId1:$Version1"}}[2]}{"$GroupId2:$ArtifactId2:$Version2"} = undef;
                        ${${$ArtifactIds{"$GroupId2:$ArtifactId2:$Version2"}}[1]}{"$GroupId1:$ArtifactId1:$Version1"} = undef;
                        ${$ArtifactIds{"$GroupId2:$ArtifactId2:$Version2"}}[3] = "" unless(defined(${$ArtifactIds{"$GroupId2:$ArtifactId2:$Version2"}}[3]));
                    }
                }
                $POM->dispose();
            };
            die("ERROR: cannot parse '$POMFullName': $@; $!") if($@);
        }
        ARTIFACTID: foreach my $ArtifactId (keys(%ArtifactIds))
        {
            my $NumberOfKeys = scalar(keys(%{${$ArtifactIds{$ArtifactId}}[2]})); 
            foreach my $ArtifactId1 (keys(%{${$ArtifactIds{$ArtifactId}}[2]}))
            {
                @{${$ArtifactIds{$ArtifactId}}[2]}{keys(%{${$ArtifactIds{$ArtifactId1}}[2]})} = (undef);
            }
            redo ARTIFACTID if(keys(%{${$ArtifactIds{$ArtifactId}}[2]}) > $NumberOfKeys);
        }
    }
    xLogH2("Fill stop: ".time());
    xLogClose();

}

### Import Section Parsing ##
if($Fetch || $Import || $UpdateLocalRepositoryOnly)
{
    my @AreaExcludes;
    for(my $i=0; $i<@Imports; $i++) # Treatement of GAV
    {
        my($Command, $Folder, $Revision, $Option) = @{$Imports[$i]};            
        next unless(my($GAVs) = $Command =~ /^get.+?\s+(.+)$/i);
        my $IsRecursive = $GAVs =~ s/\s*-R\s//;
        my $IsClients = $GAVs =~ s/\s*-C\s//;
        $Folder ||= "bin/\%\%ArtifactId\%\%";
        $Revision ||= $ENV{REF_REVISION};
        $Revision = ($Revision =~ /^=/) ? "=".ContextBuildNumber($Revision) : "=$Context/$Revision";

        my $rhExpandedGAVs = ExpandGAVs($GAVs);
        my @GAVs = map({"${$rhExpandedGAVs}{$_}:$_"} keys(%{$rhExpandedGAVs}));
        my @ProviderGAVs;
        if($Command =~ /^getProviderBinaries/ || $IsRecursive)
        {
            foreach my $GAV (@GAVs)
            {
                my($Staging, $GroupId, $ArtifactId, $Version) = split(/\s*:\s*/, $GAV);
                my $ProviderId = $IsRecursive ? 2 : 0; # tree of GAV or providers level 1 of GAV
                push(@ProviderGAVs, map({"$Staging:$_"} keys(%{${$ArtifactIds{"$GroupId:$ArtifactId:$Version"}}[$ProviderId]})));
                next unless($IsClients);
                foreach my $GAV1 (keys(%{${$ArtifactIds{"$GroupId:$ArtifactId:$Version"}}[1]})) # clients of GAV
                {
                    push(@ProviderGAVs, map({"$Staging:$_"} keys(%{${$ArtifactIds{$GAV1}}[0]}))); # providers of clients of GAV
                }
            }
            @GAVs = () if($Command =~ /^getProviderBinaries/);
        }
        my %Seen = ();
        @GAVs = grep({ !$Seen{$_}++  } (@GAVs, @ProviderGAVs));
        foreach my $GAV (@GAVs)
        {
            my($Staging, $GroupId, $ArtifactId, $Version) = split(/\s*:\s*/, $GAV);
            (my $SrcFolder = $Folder) =~ s/\%\%ArtifactId\%\%/$ArtifactId/g;                
            my $DstFolder = my $TmpFolder = $SrcFolder;
            if($SrcFolder =~ /\%\%Version\%\%/)
            {
                if(my $Property = $Properties{$ArtifactId} || $Properties{$GAV})
                {
                    foreach my $PropertyVersion (split(";", $Property))
                    {
                        $SrcFolder = $DstFolder = $TmpFolder;
                        my($SrcVersion, $DstVersion) = $PropertyVersion =~ /:/ ? split(":", $PropertyVersion) : ($PropertyVersion, $PropertyVersion);
                        $SrcFolder =~ s/\%\%Version\%\%/$SrcVersion/g;
                        if($DstVersion) { $DstFolder =~ s/\%\%Version\%\%/$DstVersion/g }
                        else { $DstFolder =~ s/[\\\/]\%\%Version\%\%//g }
                        push(@Imports, [$ArtifactId, $Revision, $Option, $SrcFolder, $DstFolder]);
                    }
                }
                else
                {
                    (my $StrippedVersion = $Version) =~ s/-SNAPSHOT$//;
                    $SrcFolder =~ s/\%\%Version\%\%/$StrippedVersion/g;
                    $DstFolder =~ s/[\\\/]\%\%Version\%\%//g;
                    push(@Imports, [$ArtifactId, $Revision, $Option, $SrcFolder, $DstFolder]);
                }
            }                
            else { push(@Imports, [$ArtifactId, $Revision, $Option, $SrcFolder, $DstFolder]) }
        }
    }
    @Imports = grep({${$_}[0]!~/^get.+?\s/} @Imports);
    foreach my $raImport (@Imports)
    {
        $BuildNb = undef; 
        my($Area, $Revision, $Option, $SrcFolder, $DstFolder) = @{$raImport};
        $Revision ||= "";
        Monitor(\$Area); Monitor(\$Revision); Monitor(\$Option); Monitor(\$SrcFolder); Monitor(\$DstFolder);
        if($SrcFolder)
        {
            if(my($Ctxt, $BuildNb) = $Revision =~ /^=(.+)[\\\/](\d+)$/) { push(@ImportVersions, [$Area, "$Ctxt/$BuildNb", $Option, $SrcFolder, $DstFolder]) }
            else { push(@ImportVersions, [$Area, "$Context/$Revision", $Option, $SrcFolder, $DstFolder]) }
        }
        else
        {
            if(my($XMLFile) = $Revision =~ /^=(.+\.xml)$/)
            {
                my $XML = (-f $XMLFile) ? $XMLFile : "$IMPORT_DIR/$XMLFile";
                die("ERROR: '$XML' from the [import] section in '$Config' doesn't exist") unless(-e $XML);
                eval
                {
                    my $CONTEXT = XML::DOM::Parser->new()->parsefile($XML);
                    my($Ctxt);
                    for my $IMPORT (@{$CONTEXT->getElementsByTagName("import")})
                    {
                        my($Ar, $Version) = ($IMPORT->getFirstChild()->getData(), $IMPORT->getAttribute("version"));
                        if($Ar eq $Area)
                        {
                            ($Ctxt, $BuildNb) = split(/\//, $Version);
                            last if(-e "$IMPORT_DIR/$Ctxt/$BuildNb/$PLATFORM/$BUILD_MODE");
                            ($Ctxt, $BuildNb) = (undef, undef);
                        }
                    }
                    $BuildNb ||= ($CONTEXT->getElementsByTagName("version")->item(0)->getFirstChild()->getData() =~ /(\d+)$/, $1);
                    $Ctxt    ||= $CONTEXT->getElementsByTagName("version")->item(0)->getAttribute("context");
                    if($Area =~ /^\s*\*\s*$/)
                    {
                        foreach my $Type (qw(bin deploymentunits))
                        {
                            if(opendir(TYPE, "$IMPORT_DIR/$Ctxt/$BuildNb/$PLATFORM/$BUILD_MODE/$Type"))
                            {
                                while(defined(my $Area = readdir(TYPE)))
                                {
                                    next if(grep(/^$Area$/i, @Exports));
                                    push(@ImportVersions, [$Area, "$Ctxt/$BuildNb", $Option]) if($Area!~/^\.\.?$/ && -d "$IMPORT_DIR/$Ctxt/$BuildNb/$PLATFORM/$BUILD_MODE/$Type/$Area");
                                }
                                closedir(TYPE);
                            }
                        }
                    }
                    elsif($Area =~ /^\+/)   { $Area=~s/^\+//; foreach my $Ar (split(/\s*,\s*/, $Area)) { push(@ImportVersions, [$Ar, "$Ctxt/$BuildNb", $Option]); @AreaExcludes = grep(!/^$Ar$/, @AreaExcludes) }}
                    elsif($Area =~ /^[^-]/) { $Area=~s/^\+//; push(@ImportVersions, [$Area, "$Ctxt/$BuildNb", $Option]) }
                    else                    { $Area=~s/^\-//; push(@AreaExcludes, $Area) }
                    $CONTEXT->dispose();
                };
                die("ERROR: cannot parse '$XML': $@; $!") if($@);
            }
            elsif($Area =~ s/^\+//)
            {
                foreach my $Ar (split(/\s*,\s*/, $Area))
                {
                    push(@ImportVersions, [$Ar, "$Ctxt/$BuildNb", $Option]) if(($Ctxt,$BuildNb) = $Revision =~ /^=(.*)[\\\/](\d+)$/);
                    @AreaExcludes = grep(!/^$Ar$/, @AreaExcludes);
                }
            }
            else
            {
                $Area2 = "".$Area."";
                if ($Area2 =~ s/^-//)
                { 
                    foreach my $Ar (split(/\s*,\s*/, $Area))
                    {
                        if(my($GAV) = $Ar =~ /([^:\\\/]+:[^:]+:[^:]+:[^:\\\/]+)/)
                        {
                            if($GAV =~ s/\*/.+/g)
                            {
                                my($RefStaging, $RefGroupId, $RefArtifactId, $RefVersion) = split(/\s*:\s*/, $GAV);
                                $raArtifacts = DependenciesTree($POMFile) unless($raArtifacts);
                                foreach my $raArtifact (@{$raArtifacts})
                                {
                                    my($Level, $GroupId, $ArtifactId, $Version) = @{$raArtifact};
                                    if("$GroupId:$ArtifactId:$Version" =~ /^$RefGroupId:$RefArtifactId:$RefVersion$/)
                                    {
                                        (my $Artifact = $Ar) =~ s/[^:\\\/]+:[^:]+:([^:]+):[^:\\\/]+/$ArtifactId/;
                                        push(@AreaExcludes, $Artifact);
                                        $ExcludePOMs{"$GroupId:$ArtifactId:$Version"} = undef;
                                    }
                                }
                            }
                            else
                            {
                                my($Staging, $GroupId, $ArtifactId, $Version) = split(/\s*:\s*/, $GAV);
                                push(@AreaExcludes, $ArtifactId);
                                $ExcludePOMs{"$GroupId:$ArtifactId:$Version"} = undef;
                            }
                        } else { $Ar=~s/^-//; push(@AreaExcludes, $Ar) }
                    }
                }
                elsif(($Ctxt,$BuildNb) = $Revision =~ /^=(.*)[\\\/](\d+)$/) { push(@ImportVersions, [$Area, "$Ctxt/$BuildNb", $Option]) }
                else { push(@ImportVersions, [$Area, $Revision, $Option]) }
            }
        }
    }

    my $AreaExcludes = join("|", @AreaExcludes); # remove doubloons and redundancy
    my $AreaExcludesRE = qr/$AreaExcludes/;
    @ImportVersions = grep({ ${$_}[0] !~ /^$AreaExcludesRE$/ } @ImportVersions) if(@AreaExcludes);
    for(my $i=0; $i<@ImportVersions; $i++)
    {
        my($Area, $Version, $Option, $SrcFolder, $DstFolder) = @{$ImportVersions[$i]};
        $Option ||= "";
        next unless($SrcFolder);
        for(my $j=$i+1; $j<@ImportVersions; $j++)
        {
            my($Area1, $Version1, $Option1, $SrcFolder1, $DstFolder1) = @{$ImportVersions[$j]};
            $Option1 ||= "";
            next unless($Area eq $Area1 && Option1 eq $Option && $SrcFolder1 && $SrcFolder=~/^$SrcFolder1/);
            ${$ImportVersions[$i]}[3] = ${$ImportVersions[$i]}[4] = $SrcFolder1;
        }
    }    
    my %Seen = ();
    @ImportVersions = reverse(grep({ ${$_}[3]||=""; ${$_}[0]=~/^all$/i || ${$_}[0]=~/^windows$/i || ${$_}[0]=~/^unix$/i || ${$_}[0] eq $PLATFORM || ${$_}[0] eq $OBJECT_MODEL || !$Seen{"${$_}[0]:${$_}[3]"}++ } reverse(@ImportVersions)));
}

## Perforce Initialization ## 
if(($Fetch || $Import || $UpdateLocalRepositoryOnly) && $p4)
{
    my $rhClient = $p4->FetchClient($Client);
    if($WarningLevel<2) { warn("ERROR: cannot fetch client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount()) } 
    else { die("ERROR: cannot fetch client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount()) }

    ${$rhClient}{Options} = $Options if($Options);
    if($SRC_DIR) { ${$rhClient}{Root} = $SRC_DIR } else { ($SRC_DIR = ${$rhClient}{Root}) =~ s/^\s+// }
    if(@Views)
    {
        my @ExpandedViews;
        foreach my $raView (@Views) # compute filters
        {
            my($File, $Workspace, $Revision) = @{$raView};
            my $RefRevision = $ENV{REF_REVISION};  Monitor(\$RefRevision);
            $Workspace ||= $ENV{REF_WORKSPACE} || '//${Client}/%%ArtifactId%%/%%Version%%/...'; Monitor(\$Workspace);
            my $WorkspaceExport = $Workspace;
            $WorkspaceExport =~ s/\.\.\.$/export\/.../ unless($WorkspaceExport=~/[\\\/]export[\\\/]/);
            if(my($GAVs) = $File =~ /^get.+?\s+(.+)$/i)
            {
                my $IsRecursive   = $GAVs =~ s/\s*-R\s//;
                my $IsProviders = $GAVs !~ s/\s*-O\s//;
                my $IsClients   = $GAVs =~ s/\s*-C\s//;
                $IsProviders = 0 if($IsRecursive);
                my $rhExpandedGAVs = ExpandGAVs($GAVs);
                my @GAVs = map({"${$rhExpandedGAVs}{$_}:$_"} keys(%{$rhExpandedGAVs}));
                if($IsRecursive)
                {
                    my(%FullTreeGAVs);
                    foreach my $GAV (@GAVs)
                    {
                        my($RefStaging, $RefGroupId, $RefArtifactId, $RefVersion) = split(/\s*:\s*/, $GAV);
                        @FullTreeGAVs{keys(%{${$ArtifactIds{"$RefGroupId:$RefArtifactId:$RefVersion"}}[2]})} = (undef);                        
                    }
                    foreach my $GAV (@GAVs)
                    {
                        my($RefStaging, $RefGroupId, $RefArtifactId, $RefVersion) = split(/\s*:\s*/, $GAV);
                        delete($FullTreeGAVs{"$RefGroupId:$RefArtifactId:$RefVersion"});                        
                    }
                    @GAVs = (map({"$RootStaging:$_"} keys(%FullTreeGAVs)), @GAVs);
                }
                my %Uniq;
                tie %Artifacts, "Tie::IxHash";
                print("LATESTS\n");
                foreach my $GAV (reverse(@GAVs))
                {
                    my($Staging, $GroupId, $ArtifactId, $Version) = split(/\s*:\s*/, $GAV);
                    next if(exists($Uniq{"$GroupId:$ArtifactId:$Version"}));
                    print("\t$GAV | $Workspace | $Revision\n");
                    $Artifacts{$GAV} = [$Revision, $Workspace];
                    if(my $Property = $Properties{$ArtifactId} || $Properties{$GAV})
                    {
                        foreach my $PropertyVersion (split(";", $Property))
                        {
                            my($SrcVersion, $DstVersion) = $PropertyVersion =~ /:/ ? split(":", $PropertyVersion) : ($PropertyVersion, $PropertyVersion);
                            (my $gav = "$GroupId:$ArtifactId:$Version") =~ s/:[^:]+-SNAPSHOT$/:$SrcVersion-SNAPSHOT/;
                            print("\t\t$Staging:$gav\n");
                            $Uniq{$gav} = undef;
                        }
                    }
                    $Uniq{"$GroupId:$ArtifactId:$Version"} = undef;
                }
                if($IsClients)
                {
                    print("CLIENTS\n");
                    my(@ExcludeAreas);
                    foreach my $GAV (reverse(@GAVs))
                    {
                        my($RefStaging, $RefGroupId, $RefArtifactId, $RefVersion) = split(/\s*:\s*/, $GAV);
                        foreach my $ClientGAV (keys(%{${$ArtifactIds{"$RefGroupId:$RefArtifactId:$RefVersion"}}[1]})) # clients of GAV
                        {
                            unless(exists($Uniq{$ClientGAV}))
                            {
                                my($GroupId, $ArtifactId, $Version) = split(':', $ClientGAV);
                                if(my $Property = $Properties{$ArtifactId} || $Properties{"$RootStaging:$ClientGAV"})
                                {
                                    my $IsGAVDisplayed = 0;
                                    foreach my $PropertyVersion (split(";", $Property))
                                    {
                                        my($SrcVersion, $DstVersion) = $PropertyVersion =~ /:/ ? split(":", $PropertyVersion) : ($PropertyVersion, $PropertyVersion);
                                        (my $gav = $ClientGAV) =~ s/:[^:]+-SNAPSHOT$/:$SrcVersion-SNAPSHOT/;
                                        unless(exists($Uniq{$gav}))
                                        {
                                            unless($IsGAVDisplayed) { print("\t$RootStaging:$ClientGAV | $Workspace | $RefRevision\n"); $Artifacts{"$RootStaging:$ClientGAV"}=[$RefRevision, $Workspace]; $IsGAVDisplayed=1 }
                                            print("\t\t$RootStaging:$gav\n");
                                            $Uniq{$gav} = undef;
                                        }
                                    }
                                }
                                else
                                {
                                    print("\t$RootStaging:$ClientGAV | $Workspace | $RefRevision\n");
                                    $Artifacts{"$RootStaging:$ClientGAV"} = [$RefRevision, $Workspace];
                                }
                                $Uniq{$ClientGAV} = undef;
                            }
                            if(exists($ExcludePOMs{"$RefGroupId:$RefArtifactId:$RefVersion"}))
                            {
                                my($GroupId, $ArtifactId, $Version) = split(/\s*:\s*/, $ClientGAV);
                                push(@ExcludeAreas, $ArtifactId);
                            }
                        }
                    }
                    my $ExcludeAreas = join("|", @ExcludeAreas);
                    my $ExcludeAreasRE = qr/$ExcludeAreas/;
                    @ImportVersions = grep({ !${$_}[3] || ${$_}[0] !~ /^$ExcludeAreasRE$/ } @ImportVersions) if(@ExcludeAreas);
                }
                if($IsProviders)
                {
                    print("PROVIDERS\n");
                    foreach my $GAV (reverse(@GAVs))
                    {
                        my($RefStaging, $RefGroupId, $RefArtifactId, $RefVersion) = split(/\s*:\s*/, $GAV);
                        foreach my $ProviderGAV (keys(%{${$ArtifactIds{"$RefGroupId:$RefArtifactId:$RefVersion"}}[0]})) # providers of GAV
                        {
                            next if(exists($Uniq{$ProviderGAV}));
                            my($GroupId, $ArtifactId, $Version) = split(':', $ProviderGAV);
                            if(my $Property = $Properties{$ArtifactId} || $Properties{"$RootStaging:$ProviderGAV"})
                            {
                                my $IsGAVDisplayed = 0;
                                foreach my $PropertyVersion (split(";", $Property))
                                {
                                    my($SrcVersion, $DstVersion) = $PropertyVersion =~ /:/ ? split(":", $PropertyVersion) : ($PropertyVersion, $PropertyVersion);
                                    (my $gav = $ProviderGAV) =~ s/:[^:]+-SNAPSHOT$/:$SrcVersion-SNAPSHOT/;
                                    unless(exists($Uniq{$gav}))
                                    {
                                        unless($IsGAVDisplayed) { print("\t$RootStaging:$ProviderGAV | $WorkspaceExport | $RefRevision\n"); $Artifacts{"$RootStaging:$ProviderGAV"}=[$RefRevision, $WorkspaceExport]; $IsGAVDisplayed=1 }
                                        print("\t\t$RootStaging:$gav\n");
                                        $Uniq{$gav} = undef;
                                    }
                                }
                            }
                            else
                            {
                                print("\t$RootStaging:$ProviderGAV | $WorkspaceExport | $RefRevision\n");
                                $Artifacts{"$RootStaging:$ProviderGAV"} = [$RefRevision, $WorkspaceExport];
                            }
                            $Uniq{$ProviderGAV} = undef;
                        }
                        if($IsClients)
                        {
                            foreach my $ClientGAV (keys(%{${$ArtifactIds{"$RefGroupId:$RefArtifactId:$RefVersion"}}[1]}))
                            {
                                foreach my $ProviderGAV (keys(%{${$ArtifactIds{$ClientGAV}}[0]}))
                                {
                                    next if(exists($Uniq{$ProviderGAV}));
                                    my($GroupId, $ArtifactId, $Version) = split(':', $ProviderGAV);
                                    if(my $Property = $Properties{$ArtifactId} || $Properties{"$RootStaging:$ProviderGAV"})
                                    {
                                        my $IsGAVDisplayed = 0;
                                        foreach my $PropertyVersion (split(";", $Property))
                                        {
                                            my($SrcVersion, $DstVersion) = $PropertyVersion =~ /:/ ? split(":", $PropertyVersion) : ($PropertyVersion, $PropertyVersion);
                                            (my $gav = $ProviderGAV) =~ s/:[^:]+-SNAPSHOT$/:$SrcVersion-SNAPSHOT/;
                                            unless(exists($Uniq{$gav}))
                                            {
                                                unless($IsGAVDisplayed) { print("\t$RootStaging:$ProviderGAV | $WorkspaceExport | $RefRevision\n"); $Artifacts{"$RootStaging:$ProviderGAV"}=[$RefRevision, $WorkspaceExport]; $IsGAVDisplayed=1 }
                                                print("\t\t$RootStaging:$gav\n");
                                                $Uniq{$gav} = undef;
                                            }
                                        }
                                    }
                                    else
                                    {
                                        print("\t$RootStaging:$ProviderGAV | $WorkspaceExport | $RefRevision\n");
                                        $Artifacts{"$RootStaging:$ProviderGAV"} = [$RefRevision, $WorkspaceExport];
                                    }
                                    $Uniq{$ProviderGAV} = undef;
                                }
                            }
                        }
                    }
                }
                foreach my $GAV (keys(%Artifacts))
                {
                    my($Tag, $Workspace) = @{$Artifacts{$GAV}};
                    my $Folder = $Workspace =~ /[\/\\](export[\/\\].+)$/ ? $1 : "...";
                    my($Staging, $GroupId, $ArtifactId, $Version) = split(':', $GAV);
                    (my $GroupIdPath =  $GroupId) =~ s/\./\//g;
                    my($P4Port, $DepotDir);
                    eval
                    {
                        my $POM = XML::DOM::Parser->new()->parsefile("$LocalRepository/$GroupIdPath/$ArtifactId/$Version/$ArtifactId-$Version.pom");
                        ($DepotDir = $POM->getElementsByTagName("scm")->item(0)->getElementsByTagName("connection")->item(0)->getFirstChild()->getData()) =~ s/^scm:perforce://;
                        $POM->dispose();
                    };
                    warn("ERROR: cannot parse '$LocalRepository/$GroupIdPath/$ArtifactId/$Version/$ArtifactId-$Version.pom': $@; $!") if($@);
                    ($P4Port, $DepotDir) = $DepotDir =~ /^\s*(.*)\$Id\:\s*(.+)$/;
                    $DepotDir =~ s/[\\\/][^\\\/]+\#\d+\s*\$//;
                    $P4Port =~ s/\s*:$//;
                    $P4Port = $Site::P4PORTManagement{$P4Port} if(exists($Site::P4PORTManagement{$P4Port})); 
                    $Authorities{$P4Port} = undef;
                    (my $Workdir = $Workspace) =~ s/\%\%ArtifactId\%\%/$ArtifactId/g;
                    $Tag =~ s/\%\%ArtifactId\%\%/$ArtifactId/g;
                    if(my $Property = $Properties{$ArtifactId} || $Properties{$GAV}) # multiversionning
                    {
                        foreach my $PropertyVersion (sort({$a=~/:$/ && $b=~/:$/ ? 0 : ($a=~/:$/ ? -1 : ($b=~/:$/ ? 1 : $a cmp $b))} split(";", $Property)))
                        {
                            my($SrcVersion, $DstVersion) = $PropertyVersion =~ /:/ ? split(":", $PropertyVersion) : ($PropertyVersion, $PropertyVersion);
                            my $Wk = $Workdir;
                            $DepotDir =~ s/(^\/\/[^\/]+\/[^\/]+\/)[^\/]+/$1$SrcVersion/;
                            if($DstVersion) { $Wk =~ s/\%\%Version\%\%/$DstVersion/g }
                            else { $Wk =~ s/[\/\\]\%\%Version\%\%//g }
                            (my $gav = $GAV) =~ s/:[^:]+-SNAPSHOT$/:$SrcVersion-SNAPSHOT/;
                            push(@ExpandedViews, ["$DepotDir/$Folder", $Wk, $Tag, $Client, $P4Port, $gav]);
                            #print("=$PropertyVersion==***===$DepotDir/$Folder, $Wk, $Tag, $P4Port, $gav\n");
                        }
                    }
                    else
                    {
                        $Workdir =~ s/[\/\\]\%\%Version\%\%//g;
                        #print("===***===$DepotDir/$Folder, $Workdir, $Tag, $P4Port, $GAV\n");
                        push(@ExpandedViews, ["$DepotDir/$Folder", $Workdir, $Tag, $Client, $P4Port, $GAV]);
                    }
                }
            }
            else
            { 
                my($P4Port) = ${$raView}[0] =~ /^[\+\-]?(.*?):\/\//;
                $P4Port ||= "";
                ${$raView}[0] =~ s/$P4Port:// if($P4Port);
                $P4Port = $Site::P4PORTManagement{$P4Port} if(exists($Site::P4PORTManagement{$P4Port})); 
                $Authorities{$P4Port} = undef;
                push(@ExpandedViews, [${$raView}[0], ${$raView}[1], ${$raView}[2], $Client, $P4Port, undef])
            }   
        }
        @Views = @ExpandedViews;
        for(my $i=0; $i<@Views; $i++) # eliminate doubles
        {
            next unless($Views[$i] && ${$Views[$i]}[5]);
            my($File1, $Workspace1, $Revision1, $P4View1, $P4Port1, $GAV1) = @{$Views[$i]};
            (my $gav1 = $GAV1) =~ s/^.+?://;
            for(my $j=$i+1; $j<@Views; $j++)
            {
                next unless($Views[$j] && ${$Views[$j]}[5]);
                my($File2, $Workspace2, $Revision2, $Client2, $P4Port2, $GAV2) = @{$Views[$j]};
                (my $gav2 = $GAV2) =~ s/^.+?://;
                if($gav1 eq $gav2) { $Views[$i]=undef; last }
            }
        }
        @Views = grep({$_} @Views);        

        print "\nBuilding Perforce client spec...\n";
        my @Authorities = (sort(keys(%Authorities)));
        for(my $i=0; $i<@Authorities; $i++)
        {
            my $MyClient = $Authorities[$i] ? "${Client}_$i" :  $Client;
            $Authorities[$i] ? $p4->SetOptions("-p \"$Authorities[$i]\"") : $p4->SetOptions("");
            my $rhClient = $p4->FetchClient($MyClient);
            die("ERROR: cannot fetch client '$MyClient': ", @{$p4->Errors()}) if($p4->ErrorCount());
            ${$rhClient}{Options} = $Options if($Options);
            if($SRC_DIR) { ${$rhClient}{Root} = $SRC_DIR } else { ($SRC_DIR = ${$rhClient}{Root}) =~ s/^\s+// }
            delete ${$rhClient}{View};
            for(my $j=0; $j<@Views; $j++)
            {
                my($File, $Workspace, $Revision, $P4Client, $P4Port, $GAV) = @{$Views[$j]};
                next unless($P4Port eq $Authorities[$i]);
                ${$Views[$j]}[3] = $MyClient;
                $Workspace =~ s/$Client/$MyClient/;
                while($File =~ /^(.+\(.*?\)\/?)/g)
                {
                    my $RE = $1;
                    $RE =~ s/\//\\\//g;
                    if(my($XMLContextFile) = $Revision =~ /^=(.+)$/)   # greatest or latest file
                    {
                        $XMLContextFile = "$IMPORT_DIR/$XMLContextFile" unless(-e $XMLContextFile);
                        die("ERROR: cannot open '$XMLContextFile': $!") unless(-e $XMLContextFile);
                        eval 
                        {
                            my $CONTEXT = XML::DOM::Parser->new()->parsefile($XMLContextFile);  
                            for my $COMPONENT (reverse(@{$CONTEXT->getElementsByTagName("fetch")}))
                            {
                                my($DepotSource, $Rev) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute("revision"));
                                if(my($Field) = $DepotSource =~ /$RE/) { $File =~ s/\(.*?\)/$Field/; last };
                            }
                            $CONTEXT->dispose();
                        };
                        warn("ERROR: cannot parse '$XMLContextFile': $@; $!") if($@);
                    }
                }
                $Revision = MatchFileInContext($File, $Revision) if($Revision =~ /^=/) ;
                if($Revision =~ /^=/) { warn("ERROR: $File not found in $Revision ") ; next }
                ${$Views[$j]}[0] = $File;
                push(@{${$rhClient}{View}}, "$File $Workspace");
            }
            print "done\n";
            print "Saving Perforce client spec...\n";
            $p4->SaveClient($rhClient) if($Update==1);
            if($p4->ErrorCount()) {
                print Data::Dumper->Dump([$rhClient], ["*Client"]);
                die("ERROR: cannot save client '$MyClient': ", @{$p4->Errors()}) ;
            } else {
                print "done\n";
            }
        }
    }
}
$ENV{SRC_DIR} = $SRC_DIR = "\l$SRC_DIR";
$ENV{OUTPUT_DIR} = $OUTPUT_DIR  = $ENV{OUTPUT_DIR} || (($ENV{OUT_DIR} || ($SRC_DIR=~/^(.*)[\\\/]/, "$1/$PLATFORM"))."/$BUILD_MODE");
$ENV{OUTLOG_DIR} = $OUTLOG_DIR  = $ENV{OUTLOG_DIR} || "$OUTPUT_DIR/logs";
$ENV{PACKAGES_DIR} = $ENV{PACKAGES_DIR} || ($OUTPUT_DIR=~/^(.*)[\\\/]/, "$1/packages");
mkpath($OUTLOG_DIR) or warn("ERROR: cannot mkpath '$OUTLOG_DIR': $!") unless(-e $OUTLOG_DIR);
if(exists($ENV{SHAKUNTALA_ENABLE}) && "yes" =~ /^$ENV{SHAKUNTALA_ENABLE}/i && $Build && (!defined($ContextParameter) or $ContextParameter!~/\.zip/))
{
    $ENV{MAVEN_OPTS} .= " -Dmaven.ext.class.path=$CURRENTDIR/shakuntala/shakuntala-core.jar";
    $ENV{SHAKUNTALA_CONF} = "$CURRENTDIR/shakuntala/shakuntala.conf";
}
if(defined($ContextParameter) && $ContextParameter=~/\.zip/ && ($Fetch || $Import || $Build))
{
    system("perl $CURRENTDIR/LocalRepositoryGenerator.pl $TEMPDIR/$$/contexts") ;
    rmtree("$TEMPDIR/$$/contexts") or warn("ERROR: cannot rmtree '$TEMPDIR/$$/contexts': $!");
    $ENV{MY_MVN_OPTS} .= " --offline"
}

exit(0) if($UpdateLocalRepositoryOnly);

if($Fetch && $p4)
{
    if(defined($ContextParameter) && $ContextParameter =~ /^\d{2}:\d{2}:\d{2}$/) # time
    {
        my $rhInfos = $p4->info();
        die("ERROR: cannot p4 info: ", @{$p4->Errors()}) if($p4->ErrorCount());
        my($Date, $Time) = ${$rhInfos}{"Server date"} =~ /(\d{4}\/\d{2}\/\d{2})\s+(\d{2}:\d{2}:\d{2})/;
        if(($ContextParameter cmp $Time) > 0)
        {
            my($Year, $Month, $Day) = $Date =~ /(\d{4})\/(\d{2})\/(\d{2})/; 
            ($Year, $Month, $Day) = Add_Delta_Days($Year, $Month, $Day, -1);
            $Date = sprintf("%d/%02d/%02d", $Year, $Month, $Day);
        }
        map({ ${$_}[2]="\@$Date:$ContextParameter" if(${$_}[2] =~ /\@now/)} @Views); # change '@now' revision only
        ($P4Year, $P4Month, $P4Day) = $Date =~ /(\d{4})\/(\d{2})\/(\d{2})/ if($GITDiff);
    }
    
    # fill @P4Syncs for the fetch step #
    my %Files;
    foreach my $raView (@Views)
    {
        my($File, $Workspace, $Revision, $P4Client, $P4Port, $GAV) = @{$raView};
        my $LogicalRevision = $Revision;

        $P4Port ? $p4->SetOptions("-p \"$P4Port\"") : $p4->SetOptions("");
        my $Change = $Authorities{$P4Port};
        unless($Change)
        {
            my $raChanges = $p4->changes('-m1');
            die("ERROR: cannot p4 changes: ", @{$p4->Errors()}) if($p4->ErrorCount());
            ($Change) = ${$raChanges}[0] =~ /^Change\s+(\d+)/;
            $Authorities{$P4Port} = $Change;
        }

        $Workspace =~ s/$Client/$P4Client/;
        my $BuildRev;
        if($Revision =~ /^\@latestlabel$/i)                 # latestlabel keyword
        {
            my @Labels = map({${$_}{label}} sort({${$b}{Update} <=> ${$a}{Update}} $p4->Labels($File)));
            $Revision = "\@$Labels[0]";
        }
        elsif($Revision =~ /^=/)   # greatest or latest file
        {
            ($Revision, $BuildRev) = MatchFileInContext($File, $Revision);
        }
        elsif(my($Rev) = $Revision =~ /^\@putlabel=(.+)/i)  # putlabel keyword
        {
            if($Labeling)
            {
                my $rhLabel = $p4->FetchLabel("${Context}_$BuildNumber");
                die("ERROR: cannot 'fetchlabel': ", @{$p4->Errors()}) if($p4->ErrorCount());
                $p4->SaveLabel($rhLabel);
                die("ERROR: cannot 'savelabel': ", @{$p4->Errors()}) if($p4->ErrorCount());
                $p4->LabelSync("-l${Context}_$BuildNumber", "$File$Rev");
                die("ERROR: cannot 'labelsync': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/label in sync.$/);
                $Revision = "\@${Context}_$BuildNumber";
            } else { $Revision = $Rev }
        }
        $Revision = "\@$Change" if($Revision =~ /^\@now$/i || !$Revision);
        warn("WARNING: p4 sync $File is duplicated") if(exists($Files{$File}));
        $Files{$File} = undef;
        my $P4Options = "-c \"$P4Client\"" . ($P4Port ? " -p $P4Port" : "");
        if($Workspace=~/\/Build\/export\/shared\/contexts\/\.\.\./ && $P4Options=~/-c\s*([^\s]+)/)
        {
            $ClientForContext = $1;
            ($P4PortForContext) = $P4Port || $ENV{P4PORT} || (`p4 set P4PORT` =~ /=(.+)\s+\(set\)$/, $1);
        }
        push(@P4Syncs, ["$File$Revision", $Workspace, $P4Options, $GAV, $LogicalRevision, $BuildRev]);
    }
}

$IsVariableExpandable = 1;
my $Dummy = ${${$MonitoredVariables[0]}[0]};
$IsVariableExpandable = 0;

if($Fetch && @GITViews)
{
    for(my $i=0; $i<@GITViews; $i++)
    {
        my($Repository, $RefSpec, $Destination, $StartPoint) = @{$GITViews[$i]};
        ${$GITViews[$i]}[4] = ($StartPoint ||= 'FETCH_HEAD');
        if($StartPoint =~ /^=/)
        {
            my($CtxtFile) = $StartPoint =~ /^=(.+)$/;    
            eval
            {
                my $CONTEXT = XML::DOM::Parser->new()->parsefile($CtxtFile);  
                my $Version = $CONTEXT->getElementsByTagName("version")->item(0)->getFirstChild()->getData();
                for my $GIT (reverse(@{$CONTEXT->getElementsByTagName("git")}))
                {
                    my($Rpstr, $Rfspc, $StrtPnt) = ($GIT->getAttribute('repository'), $GIT->getAttribute('refspec'), $GIT->getAttribute('startpoint'));
                    if($Rpstr eq $Repository && $Rfspc eq $RefSpec) { ${$GITViews[$i]}[3] = $StrtPnt; last }
                }
                $CONTEXT->dispose();                
                die("ERROR: cannot match $Repository and $RefSpec in $CtxtFile") if(${$GITViews[$i]}[3] =~ /^=/);
            };
            die("ERROR: cannot parse '$CtxtFile': $@; $!") if($@);
        }
    }
}

########
# Main #
########

if(-d "$DROP_DIR/$Context/$BuildNumber")
{
    print("\n\t#######################################################\n");
    print("\t### WARNING: THE LOG FILES WILL BE OVERLOADED IN 3s ###\n");
    print("\t#######################################################\n");
    sleep(3);    
}

# copying job file into the dropzone if specified on the command line
if($JobFile && -f $jobFile && $IsDropDirWritable==1)
{
	unless(-e "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/logs/$HOST")
	{
		eval { mkpath ("$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/logs/$HOST") };
		warn("ERROR: cannot mkpath '$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/logs/$HOST': $!") if ($@);
	}
	copy($jobFile,"$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/logs/$HOST/job_$Rank.dat");
}

Trace("start $BuildName BUILD_MODE=$BUILD_MODE");
PollingTrace("start $BuildName") if($Polling);
my @Start = Today_and_Now();
$BuildStepTime = "0h 00 mn 00 s";

## Clean Step ##
if($Clean)
{
    my $StartTime = time();
    rmtree($OUTLOG_DIR) or warn("ERROR: cannot rmtree '$OUTLOG_DIR': $!") if(-e $OUTLOG_DIR);
    mkpath("$OUTLOG_DIR/Build") or warn("ERROR: cannot mkpath '$OUTLOG_DIR/Build': $!");

    xLogOpen("$OUTLOG_DIR/Build/clean_step.log");
    xLogH2("Build start: ".time());
    xLogH1("Clean $SRC_DIR...\n");
    my @StartClean = Today_and_Now();
    my @Commands = grep({my $Name=${$_}[1]; grep({/$Name/} @Targets)} @CleanCmds);
    @Commands = @CleanCmds unless(@Commands);
    foreach my $raCommand (@Commands)
    { 
        my($Platform, $CommandName, $Command) = @{$raCommand};
        next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL); 
        xLogH2(sprintf("Start at %s\n", scalar(localtime())));
        xLogInf1("\t$Command\n");
        xLogRun("$Command");
        xLogH2(sprintf("Stop at %s\n", scalar(localtime())));
    }
    my %Clients;
    if(-e "$SRC_DIR/Build/export/shared/contexts/$Context.context.xml")
    {
        my $CONTEXT = XML::DOM::Parser->new()->parsefile("$SRC_DIR/Build/export/shared/contexts/$Context.context.xml");
        for my $COMPONENT (@{$CONTEXT->getElementsByTagName("fetch")})
        {
            my($Workspace, $P4Port) = ($COMPONENT->getAttribute("workspace"), $COMPONENT->getAttribute("authority"));
            my($Client) = $Workspace =~ /^\/\/(.+?)\//;
            $Clients{$Client} = $P4Port;
        }
        $CONTEXT->dispose();
    }
    unless(exists($ENV{EXECUTE_P4CLEAN}) && $ENV{EXECUTE_P4CLEAN}==0)
    {  
        if(keys(%Authorities)>1 || keys(%Clients)>1) { xLogRun("perl $CURRENTDIR/P4Clean.pl ".($ForceClean ? "-f":"")." -x=$SRC_DIR/Build/export/shared/contexts/$Context.context.xml") }
        else { xLogRun("perl $CURRENTDIR/P4Clean.pl ".($ForceClean ? "-f":"")." -c=$Client") }
    }
    xLogH1(sprintf("Clean took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartClean, Today_and_Now()))[1..3], scalar(localtime())));
    
    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/clean_step.log", 1, "step", "Clean");
    Dashboard("Clean");
}
mkpath("$OUTLOG_DIR/Build") or warn("ERROR: cannot mkpath '$OUTLOG_DIR/Build': $!") unless(-e "$OUTLOG_DIR/Build");

$ClientForContext ||= $Client;
$XMLContext ||= "$SRC_DIR/Build/export/shared/contexts/$Context.context.xml";
if((!defined($ContextParameter) || $ContextParameter =~ /^\d{2}:\d{2}:\d{2}$/) && (($Fetch && @Views && $p4) || $Import) && !@GITViews)
{
    CreateContext();
    SubmitContext($ClientForContext, $XMLContext);
}

# Prefetch Step #
if($Prefetch)
{
    my $StartTime = time();
    xLogOpen("$OUTLOG_DIR/Build/prefetch_step.log");
    xLogH2("Build start: ".time());

    xLogH1("Prefetch...\n");
    my @StartPrefetch = Today_and_Now();
    $ENV{rmbuild_type} = 'Prefetch';
    Run("Prefetch", \@PrefetchCmds);
    xLogH1(sprintf("Prefetch took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartPrefetch, Today_and_Now()))[1..3], scalar(localtime())));
        
    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/prefetch_step.log", 1, "step", "Prefetch");
    Dashboard("Prefetch");
}

## Fetch Step ##
if($Fetch)
{
    xLogOpen("$OUTLOG_DIR/Build/fetch_step.log");
    xLogH2("Build start: ".time());
    xLogH1("Fetch $SRC_DIR...");
    my @StartFetch = Today_and_Now();

    my $NumberOfSyncs = @P4Syncs;
    for(my $i=0; $i<$NumberOfSyncs; $i++)
    {
        my($Sync, $Workspace, $P4Opts, $GAV) = @{$P4Syncs[$i]};
        next if($Sync =~ /^\-/);
        $Sync =~ s/^\+//;
        $Sync =~ s/^"\+/"/;
        $p4->SetOptions($P4Opts) if($P4Opts);
        xLogH1("\tp4 $P4Opts sync ".($ForceSync?"-f ":"")."$Sync (".($i+1)." of $NumberOfSyncs)");
        my $raResults = $ForceSync ? $p4->sync("-f", $Sync) : $p4->sync($Sync);
        if($GAV || $WarningLevel<2) { warn("ERROR: cannot sync '$Sync': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/) }
        else { die("ERROR: cannot sync '$Sync': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/)}
        map({print("\t\t$_")} @{$raResults});
    }
    for(my $i=0; $i<@GITViews; $i++)
    {
        my($Repository, $RefSpec, $Destination, $StartPoint) = @{$GITViews[$i]};
        $Destination ||= $SRC_DIR;
        $StartPoint ||= 'FETCH_HEAD';
        mkpath($Destination) or warn("ERROR: cannot mkpath '$Destination': $!") unless(-e "$Destination");        
        chdir($Destination) or warn("ERROR: cannot chdir '$Destination': $!");
        print("====    git init\n");
        system("git init");
        print("====    git fetch $Repository $RefSpec\n");
        system("git fetch $Repository $RefSpec");
        if($StartPoint eq 'FETCH_HEAD' && defined($ContextParameter) && $ContextParameter =~ /^\d{2}:\d{2}:\d{2}$/)
        {
            my($GITYY, $GITMO, $GITDD) = ($YY, $MO, $DD);
            my($GITHH, $GITMM, $GITSS) = $ContextParameter =~ /^(\d{2}):(\d{2}):(\d{2})$/;
            if($GITDiff && $P4Year && $P4Month && $P4Day)
            {
                my($Dd, $Dh, $Ds) = $GITDiff =~ /^(\d{2}):(\d{2}):(\d{2})$/;
                ($GITYY, $GITMO, $GITDD, $GITHH, $GITMM, $GITSS) = Add_Delta_DHMS($P4Year, $P4Month, $P4Day, $GITHH, $GITMM, $GITSS, 0, $Dd, $Dh, $Ds);
                ($GITMO, $GITDD, $GITHH, $GITMM, $GITSS) = (sprintf("%02d", $GITMO), sprintf("%02d", $GITDD), sprintf("%02d", $GITHH), sprintf("%02d", $GITMM), sprintf("%02d", $GITSS));
            }
            print("====    git rev-list -n 1 --before=\"$GITYY-$GITMO-$GITDD $GITHH:$GITMM:GITSS\" FETCH_HEAD\n");
            $StartPoint= ${$GITViews[$i]}[4] = `git rev-list -n 1 --before="$GITYY-$GITMO-$GITDD $GITHH:$GITMM:$GITSS" FETCH_HEAD`;            
        }
        print("====    git checkout $StartPoint\n");
        system("git checkout $StartPoint");        
    }
    chdir($CURRENTDIR) or warn("ERROR: cannot chdir '$CURRENTDIR': $!") if(@GITViews);
    if((!defined($ContextParameter) || $ContextParameter =~ /^\d{2}:\d{2}:\d{2}$/) && @GITViews)
    {
        CreateContext();
        SubmitContext($ClientForContext, $XMLContext);
    }    	
    xLogH1(sprintf("Fetch took %u h %02u mn %02u s at %s", (Delta_DHMS(@StartFetch, Today_and_Now()))[1..3], scalar(localtime())));        
    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults( "$OUTLOG_DIR/Build/fetch_step.log", 1, "step", "Fetch");
    Dashboard("Fetch");
}

# Import Step #
if($Import)
{
    my $StartTime = time();
    xLogOpen("$OUTLOG_DIR/Build/import_step.log");
    xLogH2("Build start: ".time());
    
    xLogH1("Import...\n");
    my @StartImport = Today_and_Now();
    
    if(@ImportVersions)
    {
        my($DROPDIR, %Maps);
        if($^O eq "MSWin32" && !$IsRobocopy) { ($DROPDIR) = `net use * "$IMPORT_DIR"` =~ /^Drive (\w:)/; $Maps{$IMPORT_DIR}=$DROPDIR; for(1..60) { last if(`if exist $DROPDIR echo 1`); sleep(1) }; sleep(10); system("net use"); system("dir $DROPDIR") }
        else { $DROPDIR = $IMPORT_DIR }
        $NumberOfFork = $NumberOfCopy = 0;
        foreach my $raImport (@ImportVersions)
        {
            my($Area, $Version, $Option, $SrcFolder, $DstFolder) = @{$raImport}; ; Monitor(\$Version); Monitor(\$Option);
            if($Area=~/^all$/i || $Area eq $PLATFORM || ($^O eq "MSWin32" && $Area=~/^windows$/i) || ($^O ne "MSWin32" && $Area=~/^unix$/i) || $Area eq $OBJECT_MODEL)
            {
                xLogH2($Version);
                xLogRun($Version);
                $NumberOfCopy++;
            }
            elsif($SrcFolder)
            {
                $BuildNb = $Version;
                my $dropdir = $Option || "$IMPORT_DIR/$BuildNb/$PLATFORM/$BUILD_MODE"; Monitor(\$dropdir);
                my $DD = $dropdir;
                unless(-e $dropdir) { warn("WARNING: '$dropdir' not found"); next }
                if($^O eq "MSWin32" && !$IsRobocopy)
                {
                    if(exists($Maps{$dropdir})) { $DD = $Maps{$dropdir} }
                    else { ($DD) = `net use * "$dropdir"` =~ /^Drive (\w:)/; $Maps{$dropdir}=$DD; for(1..60) { last if(`if exist $DD echo 1`); sleep(1) }; sleep(10); system("net use"); system("dir $DD") }
                }
                if(-e "$DD/$SrcFolder") { CopyFork("$DD/$SrcFolder", "$OUTPUT_DIR/$DstFolder", "\tfrom $dropdir/$SrcFolder\n") }
                else { warn("WARNING: '$dropdir/$SrcFolder' not found") }
            }
            else
            {
                my $PDB = $Option || "";
                my($Ar) = (-e $Area) ? $Area =~ /[\\\/](?:bin|packages|prepackage|deploymentunits)[\\\/](.+)$/ : $Area =~ /^(.*?)[^\\\/]*$/;
                $Ar ||= $Area;
                if($Version !~ /\d+$/)
                {
                    $BuildNb = 0;
                    if(opendir(VER, "$IMPORT_DIR/$Version"))
                    {
	                    while(defined(my $Ver = readdir(VER)))
	                    {
	                        $BuildNb = $1 if($Ver=~/^(\d+)$/ && $1>$BuildNb && -e "$IMPORT_DIR/$Version/$1/$PLATFORM/$BUILD_MODE/bin/$Ar");
	                    }
	                    closedir(VER);
                    } else { warn("ERROR: cannot opendir '$IMPORT_DIR/$Version': $!");}
                    $Version .= "/$BuildNb";
                } else { $BuildNb = $Version }                
                foreach my $Type (qw(bin pdb deploymentunits prepackage packages))
                {
                    next if($Type eq "pdb" && "no"=~/^$PDB/i);
                    if(-e $Area)
                    {
                        next if($Type eq "bin" && $Area !~ /[\\\/]bin[\\\/]/);
                        next if($Type eq "packages" && $Area !~ /[\\\/]packages[\\\/]/);
                        next if($Type eq "prepackage" && $Area !~ /[\\\/]prepackage[\\\/]/);
                        next if($Type eq "deploymentunits" && $Area !~ /[\\\/]deploymentunits[\\\/]/);
                    }
                    else 
                    { 
                        next if($Type eq "packages"); 
                        next if($Type eq "prepackage"); 
                    }
                    my $SrcFolder = (-e $Area) ? $Area : "$DROPDIR/$Version/$PLATFORM/$BUILD_MODE/$Type/$Area";
                    my $DstFolder = ("no"=~/^$PDB/i || "yes"=~/^$PDB/i) ? "$OUTPUT_DIR/$Type/$Ar" : $Option;  
                    CopyFork($SrcFolder, $DstFolder, "\tfrom $SrcFolder\n") if(($Type ne "pdb" && $Type ne "deploymentunits") || -e $SrcFolder);
                }
            }
        }
        while(waitpid(-1, WNOHANG) != -1) { sleep(1) }
        foreach(keys(%Maps)) { `net use $Maps{$_} /DELETE /YES` if($Maps{$_}) }
    } elsif(@Imports) { warn("ERROR: Imports not found") }

    foreach(@NexusImports)
    {
        my($Platform, $MappingFile, $TargetDir, $Log1, $Log2, $Options) = @{$_};
        next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL);
	    system("perl $CURRENTDIR/importFromNexus.pl -f=$MappingFile -t=$TargetDir -lst=$Log1 -al=$Log2 $Options");
        $NumberOfCopy++;
    }
    
    warn("ERROR: any import") unless($NumberOfCopy);
    xLogH1(sprintf("Import took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartImport, Today_and_Now()))[1..3], scalar(localtime())));

    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/import_step.log", 1, "step", "Import");
    Dashboard("Import");
}

# Build Step #
if($Build)
{
    my $StartTime = time();
    xLogOpen("$OUTLOG_DIR/Build/build_step.log");
    xLogH2("Build start: ".time());
    
    xLogH1("Build...\n");
    my @StartBuild = Today_and_Now();

    if($Polling)
    {
        my %g_read;
        #data 
        open(DAT, "$OUTPUT_DIR/bin/depends/$Project.read.dat") or warn("ERROR: cannot open '$OUTPUT_DIR/bin/depends/$Project.read.dat': $!");
        LINE: while(<DAT>)
        {
            if(my($AreaBuild) = /\@\{\$g_read\{'(.+)'\}\}/)
            {
                while(<DAT>)
                {
                    redo LINE if(/\@\{\$g_read\{'(.+)'\}\}/);
                    if(my($File) = /'(.+)'/) { $g_read{$AreaBuild}{$File} = undef }
                }
            }
        } 
        close(DAT);
        #units
        my @Areas = Read("AREAS", $IncrementalCmds[2]);
        my @Versions = map({/^\/{2}(?:[^\/]*[\/]){3}(.+)\#\d+/; "\$SRC_DIR/$1"} @NewVersions);
        my %Units;
        foreach my $AreaUnit (keys(%g_read))
        {
            next unless(grep({$AreaUnit=~/^$_\./} @Areas));
            foreach my $File (@Versions)
            {
                if(exists(${$g_read{$AreaUnit}}{$File})) { PollingTrace("\t$AreaUnit : $File"); $Units{$AreaUnit}=undef; last }
            }
        }
        if(%Units)
        {
            my $rhDepends = Depends($IncrementalCmds[2]);
            foreach my $Area (keys(%{$rhDepends}))
            {
                foreach my $Unit (keys(%{${$rhDepends}{$Area}}))
                {
                    next if(exists($Units{"$Area.$Unit"}));
                    if(IsDescendant($Area, $Unit, \%Units, $rhDepends)) { PollingTrace("\t$Area.$Unit"); $Units{"$Area.$Unit"}=undef }
                }
            }
            #filter
            if(@Exports && $Exports[0] !~ /^\s*\*\s*$/)
            {
                my %ExportAreas;
                @ExportAreas{@Exports} = ();
                foreach my $AreaUnit (keys(%Units))
                {
                    my($Area, $Unit) = split(/\./, $AreaUnit);
                    delete $Units{$AreaUnit} unless(exists($ExportAreas{$Area}));
                } 
            }
        }
        #commands
        my %BuildUnits;
        foreach my $AreaUnit (keys(%Units))
        {
            my($Area, $Unit) = split(/\./, $AreaUnit);
            $BuildUnits{$Area}{$Unit} = undef;
        }
        @BuildCommands = map({"$_:".join(',', keys(%{$BuildUnits{$_}}))} keys(%BuildUnits));
    }
    
    if(@BuildCommands)
    {
        @BuildCmds = ();
        die("ERROR: the [incrementalcmd] section is not defined in $Config. You can't use -a option.") unless($IncrementalCmd);
        $BuildCmds[0] = [$PLATFORM, $IncrementalCmds[0], "$IncrementalCmd ".join(' ', map({my($Area,$BuildUnits)=split(':'); $Area =~ /\*/ ? "-g=$IncrementalCmds[2]=$_" : "-g=$SRC_DIR/$Area/$Area.gmk".($BuildUnits?"=$BuildUnits":"")} @BuildCommands))];
    } elsif($Polling) { @BuildCmds = () }

    # resources #
    modifyVersionedFiles($COMPANYNAME,$COPYRIGHT,$BuildDate,$buildnumber,\%ENV,"$SRC_DIR/Build/export/iface","$TEMPDIR",1);

    $ENV{rmbuild_type} = 'Compile';
    $NumberOfErrors = Run("Build", \@BuildCmds);
    if($Rank > 1) # copy binaries to rank 1
    {
        open(HOST, "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/logs/host_1.dat") or warn("ERROR: cannot open '$DROP_DIR/$Context/$BuildName/$PLATFORM/$BUILD_MODE/logs/host_1.dat': $!");
        my($Hst, $Src, $Out) = split(/\s*\|\s*/, <HOST>);
        close(HOST);
        my $DestinationRoot;
        if($^O eq "MSWin32") { ($DestinationRoot = "\\\\$Hst\\$Out") =~ s/:/\$/; ($DestinationRoot)=`net use * "$DestinationRoot"`=~/^Drive (\w:)/ }
        else {} # TO DO 

        $NumberOfFork = 0;
        if(opendir(BIN, "$OUTPUT_DIR/bin"))
        {
	        while(defined(my $Area = readdir(BIN)))
	        {
	            next if($Area=~/^\.\.?$/ || !-d "$OUTPUT_DIR/bin/$Area");
	            CopyFork("$OUTPUT_DIR/bin/$Area", "$DestinationRoot/bin/$Area", "\tfrom bin/$Area to $Hst\n");   
	        }
	        closedir(BIN);
        } else {warn("ERROR: cannot opendir '$OUTPUT_DIR/bin': $!");}
        while(waitpid(-1, WNOHANG) != -1) { sleep(1) }
        `net use $DestinationRoot /DELETE /YES` if($^O eq "MSWin32");
    }   

    if((-d "$OUTPUT_DIR/bin/contexts/shakuntala" || -f "$SRC_DIR/cms/$ENV{MY_DITA_PROJECT_ID}.project.mf.xml") && (!defined($ContextParameter) || $ContextParameter =~ /^\d{2}:\d{2}:\d{2}$/))
    {
        mkpath("$OUTPUT_DIR/bin/contexts") or warn("ERROR: cannot mkpath '$OUTPUT_DIR/bin/contexts': $!") unless(-e "$OUTPUT_DIR/bin/contexts");
        if(-f $XMLContext)
        {
            chmod(0755, $XMLContext) or warn("ERROR: cannot chmod '$XMLContext': $!");
            copy($XMLContext, "$OUTPUT_DIR/bin/contexts") or warn("ERROR: cannot copy '$XMLContext': $!") ;
        }
        if(-f "$SRC_DIR/cms/$ENV{MY_DITA_PROJECT_ID}.project.mf.xml")
        {
            chmod(0755, "$SRC_DIR/cms/$ENV{MY_DITA_PROJECT_ID}.project.mf.xml") or warn("ERROR: cannot chmod '$SRC_DIR/cms/$ENV{MY_DITA_PROJECT_ID}.project.mf.xml': $!");
            copy("$SRC_DIR/cms/$ENV{MY_DITA_PROJECT_ID}.project.mf.xml", "$OUTPUT_DIR/bin/contexts") or warn("ERROR: cannot copy '$SRC_DIR/cms/$ENV{MY_DITA_PROJECT_ID}.project.mf.xml': $!") ;
        }
        chmod(0755, "$SRC_DIR/Build/export/shared/contexts/${Context}_${PLATFORM}_$BUILD_MODE.context.zip") or warn("ERROR: cannot chmod '$SRC_DIR/Build/export/shared/contexts/${Context}_${PLATFORM}_$BUILD_MODE.context.zip': $!") if(-e "$SRC_DIR/Build/export/shared/contexts/${Context}_${PLATFORM}_$BUILD_MODE.context.zip");
        my $Zip = Archive::Zip->new();
        $Zip->addTree("$OUTPUT_DIR/bin/contexts", 'contexts');
        warn("ERROR: cannot write '$SRC_DIR/Build/export/shared/contexts/${Context}_${PLATFORM}_$BUILD_MODE.context.zip': $!") unless($Zip->writeToFileNamed("$SRC_DIR/Build/export/shared/contexts/${Context}_${PLATFORM}_$BUILD_MODE.context.zip") == AZ_OK);        
        mkpath("$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files") or warn("ERROR: cannot mkpath '$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files': $!") unless(-d "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files");
        copy("$SRC_DIR/Build/export/shared/contexts/${Context}_${PLATFORM}_$BUILD_MODE.context.zip", "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files/${Context}_${PLATFORM}_$BUILD_MODE.context.zip") or warn("ERROR: cannot copy '$SRC_DIR/Build/export/shared/contexts/${Context}_${PLATFORM}_$BUILD_MODE.context.zip': $!");
        SubmitContext($ClientForContext, "$SRC_DIR/Build/export/shared/contexts/${Context}_${PLATFORM}_$BUILD_MODE.context.zip");
    }

    $BuildStepTime = sprintf("%u h %02u mn %02u s", (Delta_DHMS(@StartBuild, Today_and_Now()))[1..3]);
    xLogH1(sprintf("Build took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartBuild, Today_and_Now()))[1..3], scalar(localtime())));
    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/build_step.log", 1, "step", "Build");
    Dashboard("Build");
}

# Package Step #
if($Package)
{
    my $StartTime = time();
    xLogOpen("$OUTLOG_DIR/Build/package_step.log" );
    xLogH2("Build start: ".time());
    
    my @StartPackage = Today_and_Now();
    xLogH1("Package...\n");
    $ENV{rmbuild_type} = 'Package';
    Run("Package", \@PackageCmds) if($Rank == 1);
    xLogH1(sprintf("Package took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartPackage, Today_and_Now()))[1..3], scalar(localtime())));
    
    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/package_step.log", 1, "step", "Package");
    Dashboard("Package");
}

# Dependencies Step #
if($Dependencies)
{
    my $StartTime = time();
    xLogOpen("$OUTLOG_DIR/Build/dependencies_step.log");
    xLogH2("Build start: ".time() );
    xLogH1("Dependencies...\n");
    my @StartDependencies = Today_and_Now();
    my @Commands = grep({my $Name=${$_}[1]; grep({/$Name/} @Targets)} @DependenciesCmds);
    @Commands = @DependenciesCmds unless(@Commands);
    foreach my $raCommand (@Commands)
    { 
        my($Platform, $CommandName, $Command) = @{$raCommand};
        next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL); 
        xLogInf1("\t$Command\n");
        system($Command);
    }
    xLogH1(sprintf("Dependencies analyzis took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartDependencies, Today_and_Now()))[1..3], scalar(localtime())));
    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/dependencies_step.log", 1, "step", "Dependencies");    
    Dashboard("Dependencies");
}

# News Feeds RSS Step #
if($News)
{
    my $StartTime = time();
    xLogOpen("$OUTLOG_DIR/Build/news_step.log" );
    xLogH2("Build start: ".time() );

    xLogH1("News...\n");
    my @StartNews = Today_and_Now();
    
    if($BUILD_MODE eq "release")
    {
        my($rhIssues, $rhUsers, $rhDepends) = DefectsByUser();
        
        if(open(XML, ">$HTTPDIR/${Context}_$PLATFORM.rss.xml"))
        {
            print(XML "<?xml version=\"1.0\" encoding=\"ISO-8859-1\" ?>
            <?xml-stylesheet type=\"text/xsl\" href=\"http://dewdfxlp00003.pgdev.sap.corp:1080/cis/htdocs/rss.xsl\" ?>
            <rss version=\"2.0\">
              <channel>
                <title>$Context $PLATFORM</title>
                <link>http://dewdfxlp00003.pgdev.sap.corp:1080/cis/cgi-bin/CIS.pl?tag=$BuildName&amp;streams=$Context</link>
                <description>$Context $PLATFORM</description>
            
                <item>
                  <title>$BuildName $PLATFORM ", scalar(gmtime(time())), " GMT</title>
                  <link>http://dewdfxlp00003.pgdev.sap.corp:1080/cis/cgi-bin/CIS.pl?tag=$BuildName&amp;streams=$Context</link>
                  <description>");
                    if(keys(%{$rhIssues}))
                    {
                        print(XML "Resulting compile issues are in ", join(", ", sort(keys(%{$rhIssues}))), "&lt;br/&gt;");
                        print(XML "&lt;ul&gt;");
                        foreach my $User (sort(keys(%{$rhUsers}))) 
                        { 
                            print(XML "&lt;li&gt;&lt;b&gt;$User&lt;/b&gt; (", join(', ', @{${${$rhUsers}{$User}}[0]}), ")&lt;/li&gt;");
                            print(XML "&lt;ul&gt;");
                            foreach my $AreaUnit (keys(%{${${$rhUsers}{$User}}[1]}))
                            {
                                my($Area, $Unit) = split('\.', $AreaUnit);
                                print(XML "&lt;li&gt;$AreaUnit", exists(${$rhDepends}{$Unit}) ? " (depends on ".join(", ", @{${$rhDepends}{$Unit}}).")" : "", "&lt;/li&gt;");
                            }
                            print(XML "&lt;/ul&gt;");
                        }
                        print(XML "&lt;/ul&gt;");
                    } else { print(XML "no issue\n") }
                  print(XML "</description>    
                  <pubDate>", scalar(gmtime(time())), " GMT</pubDate>
                </item>
              </channel>
            </rss>
            ");
            close(XML);
        }
        else { warn("ERROR: cannot open '$HTTPDIR/${Context}_$PLATFORM.rss.xml': $!") }
    }
    xLogH1(sprintf("News took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartNews, Today_and_Now()))[1..3], scalar(localtime())));

    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/news_step.log", 1, "step", "News");    
    Dashboard("News");
}

# Export Step #
if($Export)
{
    my(@exports, %ExpandedExports);
    if($SpecificExport) { @Exports = ($SpecificExport); Monitor(\$Exports[-1]) }

    my $DROPDIR;
    if($^O eq "MSWin32" && !$IsRobocopy) { ($DROPDIR) = `net use * "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE"` =~ /^Drive (\w:)/; for(1..60) { last if(`if exist $DROPDIR echo 1`); sleep(1) }; system("net use"); system("dir $DROPDIR") }
    else { $DROPDIR = "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE" }

    foreach (@Exports)
    {
        foreach (split(/\s*;\s*/, $_))
        {
            my $Prefix  = /^([^,]+)[\\\/]/ ? "$1/" : "";
            foreach my $Export (split(/\s*,\s*/, $_))
            {
                my @Folders;
                if(my($GAV) = $Export =~ /([^:\\\/]+:[^:\s]+:[^:\s]+:[^:\\\/]+)/)
                {
                    if($GAV =~ s/\*/.+/g)
                    {
                        my($RefStaging, $RefGroupId, $RefArtifactId, $RefVersion) = split(/\s*:\s*/, $GAV);
                        $raArtifacts = DependenciesTree($POMFile) unless($raArtifacts);
                        foreach my $raArtifact (@{$raArtifacts})
                        {
                            my($Level, $GroupId, $ArtifactId, $Version) = @{$raArtifact};
                            if("$GroupId:$ArtifactId:$Version" =~ /^$RefGroupId:$RefArtifactId:$RefVersion$/)
                            {
                                (my $Expt = $Export) =~ s/[^:\\\/]+:[^:]+:([^:]+):[^:\\\/]+/$ArtifactId/;
                                push(@Folders, ["$Prefix$Expt", "$DROPDIR/$Prefix$Expt"]);
                            }
                        }
                    }
                    else { my($ArtifactId) = $GAV =~ /^[^:]+:[^:]+:([^:]+)/; push(@Folders, ["$Prefix$ArtifactId", "$DROPDIR/$Prefix$ArtifactId"]) } 
                }
                else
                {
                    if($Export =~ /\|/)
                    {
                        my($Platform, $Source, $Destination) = split('\s*\|\s*', $Export);
                        next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL); 
                        if(-e "$OUTPUT_DIR/$Source" || -e $Source)
                        {
                            $Destination ||= "$DROPDIR/$Source";
                            push(@Folders, [$Source, $Destination]);
                        }
                        else
                        {
                            xLogH2($Destination);
                            xLogRun($Destination);
                        }
                    }
                    else { push(@Folders, [$Export, "$DROPDIR/$Export"]) }
                }
                foreach (@Folders)
                {
                    my($Source, $Destination) = @{$_};
                    if($Source=~/[\\\/]/ || -e "$OUTPUT_DIR/$Source" || $Source=~/oneinstaller/i || $Source=~/packages/i || $Source=~/patches/i || $Source=~/logs/i || $Source=~/prepackage/i || $Source=~/pdb/i || $Source=~/commonrepo/i || $Source=~/^-/ ) { $ExpandedExports{$Source}=$Destination }
                    else { @ExpandedExports{("oneinstaller", "packages", "patches", "deploymentunits/$Source", "bin/$Source", "logs", "prepackage", "pdb", "commonrepo")}=("$DROPDIR/oneinstaller", "$DROPDIR/packages", "$DROPDIR/patches", "$DROPDIR/deploymentunits/$Source", "$DROPDIR/bin/$Source", "$DROPDIR/logs", "$DROPDIR/prepackage", "$DROPDIR/pdb", "$DROPDIR/commonrepo") }
                }
            }
        }
    }
    my @ExcludeExports;
    foreach my $Source (keys(%ExpandedExports))
    {
        my $Destination = $ExpandedExports{$Source};
        $Source =~ s/^\+//;
        $Destination =~ s/^\+//;
        if($Source=~/^\s*-/)
        {
            (my $Src = $Source) =~ s/^\s*-//;
            push(@ExcludeExports, $Src);
            $ExpandedExports{$Source} = undef;
        }
        my($Dir, $ExportRE) = $Source =~ /^(.+)[\\\/]([^\\\/]*)$/;
        if($ExportRE && $ExportRE =~ s/\*/\.\*/g)
        {
            $ExportRE = qr/$ExportRE/;
            my $IsExclude = $Dir =~ s/^\s*-//;
            if(opendir(DIR, "$OUTPUT_DIR/$Dir"))
            {
                while(defined(my $SubDir = readdir(DIR)))
                {
                    next if($SubDir=~/^\.\.?$/ || !-d "$OUTPUT_DIR/$Dir/$SubDir");
                    ($IsExclude ? $ExpandedExports{"$Dir/$SubDir"}=undef : $ExpandedExports{"$Dir/$SubDir"}="$DROPDIR/$Dir/$SubDir") if($SubDir =~ /$ExportRE/);
                }
                closedir(DIR);
            } else { warn("WARNING: cannot opendir '$OUTPUT_DIR/$Dir': $!") }
            $ExpandedExports{$Source} = undef;
        }
    }
    my $ExcludeExports = join("|", @ExcludeExports);
    my $ExcludeExportsRE = qr/$ExcludeExports/;
    map({delete $ExpandedExports{$_} if(!$ExpandedExports{$_} || (@ExcludeExports && /$ExcludeExportsRE$/)) } keys(%ExpandedExports));
    
    mkpath("$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE") or warn("ERROR: cannot mkpath '$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE': $!") unless(-e "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE");
    $ENV{rmbuild_type} = 'Export';
    foreach my $Folder (qw(oneinstaller64 oneinstaller patches packages64 packages deploymentunits bin commonrepo)) # export by priority
    {
        next unless(grep(/^$Folder$/ || /^$Folder[\\\/]/, keys(%ExpandedExports)));
        my $StartTime = time();
        xLogOpen("$OUTLOG_DIR/Build/export_${Folder}_step.log" );
        xLogH2("Build start: ".time() );
        xLogH1("Export $Folder ...");
        my @StartExport = Today_and_Now();
        open(INPROGRESS, ">$DROPDIR/${Folder}_copy_in_progress") or warn("WARNING: cannot open '$DROPDIR/${Folder}_copy_in_progress': $!");
        close(INPROGRESS);
        unlink("$DROPDIR/$Folder/${Folder}_copy_done") or warn("WARNING: cannot unlink '$DROPDIR/$Folder/${Folder}_copy_done': $!") if(-e "$DROPDIR/$Folder/${Folder}_copy_done");

        $NumberOfFork = 0;
        foreach my $Source (grep(/^$Folder/, keys(%ExpandedExports)))
        {
            unless(-e "$OUTPUT_DIR/$Source") { warn("WARNING: '$OUTPUT_DIR/$Source' not found"); next }
            if($Source =~ /packages/ && $Astec)
            {
                if(opendir(PACKAGES, "$OUTPUT_DIR/$Source"))
                { 
        	        while(defined($PackageName = readdir(PACKAGES)))
        	        {
        	            next if($PackageName =~ /^\.\.?$/);
        	            next unless(-d "$OUTPUT_DIR/$Source/$PackageName");
        	            CopyFork("$OUTPUT_DIR/$Source/$PackageName", "$ExpandedExports{$Source}/$PackageName", "\tfrom $Source/$PackageName\n");
        	            ASTECStep($PackageName, $Source eq "packages64"?1:0);
        	        }
                    closedir(PACKAGES);
                } else { CopyFork("$OUTPUT_DIR/$Source", $ExpandedExports{$Source}, "\tfrom $Source\n") }
            } else { CopyFork("$OUTPUT_DIR/$Source", $ExpandedExports{$Source}, "\tfrom $Source\n") }
        }
        while(waitpid(-1, WNOHANG) != -1) { sleep(1) }
        unlink("$DROPDIR/${Folder}_copy_in_progress") or warn("WARNING: cannot unlink '$DROPDIR/${Folder}_copy_in_progress': $!");
        open(INPROGRESS, ">$DROPDIR/$Folder/${Folder}_copy_done") or warn("WARNING: cannot open '$DROPDIR/$Folder/${Folder}_copy_done': $!");
        print(INPROGRESS "This file is significant only here:\n");
        print(INPROGRESS "SITE=$ENV{SITE}\n");
        print(INPROGRESS "DROPDIR=$DROPDIR/$Folder\n");
        close(INPROGRESS);

        xLogH1(sprintf("Export $Folder took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartExport, Today_and_Now()))[1..3], scalar(localtime())));
        xLogH2("\nBuild stop: ".time());
        xLogClose();
        submitbuildresults("$OUTLOG_DIR/Build/export_${Folder}_step.log", 1, "step", "Export$Folder");

        NSDTransfert($Folder);
        if($Folder eq "packages") { QACStep() if($QAC); GTxStep() if($GTx); ASTECStep() if($Astec) }
    }

    my $StartExportTime = time();
    xLogOpen("$OUTLOG_DIR/Build/export_step.log" );
    xLogH2("Build start: ".time() );
    xLogH1("Export ...");
    my @StartExportStep = Today_and_Now();

    if($PLATFORM eq "win64_x64" && $EXPORT_METADATA)
    {
        CopyFiles($CURRENTDIR, "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/core.build.tools/export/shared", "\tfrom $CURRENTDIR") if(-e $CURRENTDIR);
        CopyFiles($LocalRepository, "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/LocalRepo", "\tfrom $LocalRepository") if(-e $LocalRepository);
        NSDTransfert("../../contexts");
    }
    
    $NumberOfFork = 0;
    foreach my $Source (keys(%ExpandedExports))
    {
        next if($Source=~/^oneinstaller$/ || $Source=~/^oneinstaller[\\\/]/ || $Source=~/^oneinstaller64$/ || $Source=~/^oneinstaller64[\\\/]/ ||$Source=~/^packages$/ || $Source=~/^packages[\\\/]/ || $Source=~/^packages64$/ || $Source=~/^packages64[\\\/]/ || $Source=~/^patches$/ || $Source=~/^patches[\\\/]/ || $Source=~/^deploymentunits$/ || $Source=~/^deploymentunits[\\\/]/ || $Source=~/^bin$/ || $Source=~/^bin[\\\/]/ || $Source=~/^commonrepo$/ || $Source=~/^commonrepo[\\\/]/);
        my $Destination = $ExpandedExports{$Source};
        $Source = "$OUTPUT_DIR/$Source" unless(-e $Source);
        unless(-e $Source) { warn("WARNING: '$Source' not found"); next }
        $Destination =~ s/[\\\/]logs[\\\/]/\/logs\/$HOST\//;
        $Destination =~ s/[\\\/]logs$/\/logs\/$HOST/;
        CopyFork($Source, $Destination, "\tfrom $Source\n");
        NSDTransfert("../../contexts/allmodes/core.build.tools") if($Source=~/[\\\/]core.build.tools$/ || $Source=~/[\\\/]core.build.tools[\\\/]/);
        NSDTransfert("../../contexts/allmodes/LocalRepo") if($Source=~/[\\\/]LocalRepos$/ || $Source=~/[\\\/]LocalRepos[\\\/]/);
        NSDTransfert("pdb") if($Source=~/[\\\/]pdb$/ || $Source=~/[\\\/]pdb[\\\/]/);
        NSDTransfert("logs") if($Source=~/[\\\/]logs$/ || $Source=~/[\\\/]logs[\\\/]/);
    }
    while(waitpid(-1, WNOHANG) != -1) { sleep(1) }
    `net use $DROPDIR /DELETE /YES` if($^O eq "MSWin32" && !$IsRobocopy);

    verify_copy("$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files/$Context.context.xml", "$DROP_DIR/$Context/latest.xml");

    Run("Export", \@ExportCmds);

    xLogH1(sprintf("Export took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartExportStep, Today_and_Now()))[1..3], scalar(localtime())));
    xLogH2("\nBuild stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/export_step.log", 1, "step", "ExportStep");
    Dashboard("Export");
}

# QAC Step #
QACStep() if($QAC && !$Export);

# GTx Step #
GTxStep() if($GTx && !$Export);

# ASTEC Step #
ASTECStep() if($Astec && !$Export);
    
# Dashboard Step #
if($Report)
{
    my $StartTime = time();
    xLogOpen( "$OUTLOG_DIR/Build/report_step.log" );
    xLogH2( "Build start: ".time() );
    
    xLogH1("Report...\n");
    my @StartReport = Today_and_Now();
    my $OutputFile = "$OUTLOG_DIR/NewRevisions.dat";
    my $PreviousBuildNumber;
    for($PreviousBuildNumber=$BuildNumber-1; $PreviousBuildNumber>0; $PreviousBuildNumber--)
    {
        last if(-e "$DROP_DIR/$Context/$PreviousBuildNumber/contexts/allmodes/files/$Context.context.xml");
    }
    my $FromContext = $PreviousBuildNumber ? "-f=$DROP_DIR/$Context/$PreviousBuildNumber/contexts/allmodes/files/$Context.context.xml" : "";
    foreach (@Adapts)
    {
        foreach my $Adapt (split('\s*,\s*', $_))
        { 
            if(my($Artifact) = $Adapt =~ /[^:]+:[^:]+:([^:]+):[^:]+/) { push(@Adapts, $Artifact) }
        }
    }
    my $Areas = join(',', grep({/^\s*\*\s*$/ || ("yes"!~/^$_/i && !/[^:]+:[^:]+:[^:]+:[^:]+/)} @Adapts));
    $Areas = $ENV{DIFFCONTEXT_AREAS} || '*' unless($Areas);
    my $Comment = sprintf("%s_%05d,%s_%05d\n", $Context, $PreviousBuildNumber, $Context, $BuildNumber);
    unlink($OutputFile) or warn("WARNING: cannot unlink '$OutputFile': $!") if(-e $OutputFile);
    unlink("$OUTLOG_DIR/Adapts.txt") or warn("WARNING: cannot unlink '$OUTLOG_DIR/Adapts.txt': $!") if(-e "$OUTLOG_DIR/Adapts.txt");
    unlink("$OUTLOG_DIR/Jiras.txt") or warn("WARNING: cannot unlink '$OUTLOG_DIR/Jiras.txt': $!") if(-e "$OUTLOG_DIR/Jiras.txt");
    unlink("$OUTLOG_DIR/CWB.txt") or warn("WARNING: cannot unlink '$OUTLOG_DIR/CWB.txt': $!") if(-e "$OUTLOG_DIR/CWB.txt");
    my $CMD = "perl $CURRENTDIR/DiffContext.pl $FromContext -t=$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files/$Context.context.xml deep=$DEEP_CONTEXT -w=$Areas -outdat=$OutputFile -adapt=$OUTLOG_DIR/Adapts.txt -jira=$OUTLOG_DIR/Jiras.txt -CWB=$OUTLOG_DIR/CWB.txt -comment=$Comment";
    system($CMD);
    if($CWBurl)
    {
        $CWBpurpose ||= 'CWB';
        $CWBcredential ||= $ENV{MY_CREDENTIAL} || "$PW_DIR/.credentials.properties";
        $CWBmaster ||= $ENV{MY_MASTER} || "$PW_DIR/.master.xml";
        $CWBuser ||= `$PRODPASSACCESS_DIR/bin/prodpassaccess --credentials-file $CWBcredential --master-file $CWBmaster get $CWBpurpose user`; chomp($CWBuser);
        $CWBpassword ||= `$PRODPASSACCESS_DIR/bin/prodpassaccess --credentials-file $CWBcredential --master-file $CWBmaster get $CWBpurpose password`; chomp($CWBpassword);
        xLogH1("Update CWB...\n");
        system("$JAVA -jar $CURRENTDIR/../java/UpdateCWBCRs.jar -u $CWBurl -n $CWBuser -p \"$CWBpassword\" -f \"$OUTLOG_DIR/CWB.txt\"");
    }
    # Adapts insertion
    if(@Adapts)
    {
        my $CMD = "perl $CURRENTDIR/CreateAdaptBuildInfo.pl $BuildName $Context $OUTLOG_DIR/Adapts.txt $OUTLOG_DIR/Adapts.log > $NULLDEVICE";
        print "$CMD\n";
        system($CMD);
    }
    $ENV{rmbuild_type} = 'Report';
    Run("Report", \@ReportCmds);

    xLogH1(sprintf("Report took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartReport, Today_and_Now()))[1..3], scalar(localtime())));  
    xLogH2( "Build stop: ".time() );
    xLogClose();
    submitbuildresults( "$OUTLOG_DIR/Build/report_step.log", 1, "step", "Report" );  
    Dashboard("Report");
}

# Test Step #
if($Test)
{
    my $StartTime = time();
    xLogOpen("$OUTLOG_DIR/Build/test_step.log");
    xLogH2("Build start: ".time());

    xLogH1("Test...\n");
    my @StartTest = Today_and_Now();
    $ENV{rmbuild_type} = 'Test';
    Run("Test", \@TestCmds);
    xLogH1(sprintf("Test took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartTest, Today_and_Now()))[1..3], scalar(localtime())));

    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/test_step.log", 1, "step", "Test");  
    Dashboard("Test");
}

# Smoke Step #
if($Smoke)
{
    my $StartTime = time();
    xLogOpen("$OUTLOG_DIR/Build/smoke_step.log");
    xLogH2("Build start: ".time());

    xLogH1("Smoke...\n");
    my @StartSmoke = Today_and_Now();
    $ENV{rmbuild_type} = 'Smoke';
    Run("Smoke", \@SmokeCmds);
    xLogH1(sprintf("Smoke took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartSmoke, Today_and_Now()))[1..3], scalar(localtime())));

    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/smoke_step.log", 1, "step", "Smoke");  
    Dashboard("Smoke");
}

# Validation Step #
if($Validation)
{
    my $StartTime = time();
    xLogOpen("$OUTLOG_DIR/Build/bat_step.log");
    xLogH2("Build start: ".time());

    xLogH1("Validation...\n");
    my @StartValidation = Today_and_Now();
    $ENV{rmbuild_type} = 'Validation';
    Run("Validation", \@ValidationCmds);
    xLogH1(sprintf("Validation took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartValidation, Today_and_Now()))[1..3], scalar(localtime())));

    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/bat_step.log", 1, "step", "Validation");  
    Dashboard("Validation");
}

# Mail Step #
if($Mail)
{
    my $StartTime = time();
    xLogOpen("$OUTLOG_DIR/Build/mail_step.log");
    xLogH2("Build start: ".time());

    xLogH1("Mail...\n");
    my @StartMail = Today_and_Now();
    if($Polling)
    {
        if($NumberOfErrors)
        {
            my @Versions = map({ /^(.*#\d+)\s+\-\s+/; $1 } grep(!/^\s*$/, @NewVersions));
            my %Users;
            foreach my $Version (@Versions)
            {
                my $raFileLog = $p4->filelog("-m1", "\"$Version\"");
                warn("ERROR: cannot filelog '$Version': ", @{$p4->Errors()}) if($p4->ErrorCount());
                foreach (@{$raFileLog}) { if(/by\s+(.+?)\@/) { $Users{$1} = undef; last } }
            }
            foreach my $User (keys(%Users))
            {
                my $rhUser = $p4->user("-o", $User);
                die("ERROR: cannot user '$User': ", @{$p4->Errors()}) if($p4->ErrorCount());
                ($Users{$User}) = ${$rhUser}{Email} =~ /^\s*(.+)\s*$/;
            } 
            system("perl $CURRENTDIR/SendMail.pl -t=$BuildName -m=$BUILD_MODE -p=$PLATFORM -r=".(join(';', values(%Users))));
        }
    }
    else
    {
        if(@MailCmds)
        {
            $ENV{rmbuild_type} = 'Mail';
            Run("Mail", \@MailCmds);
        } else { system("perl $CURRENTDIR/Mail.pl -t=$BuildName -m=$BUILD_MODE -p=$PLATFORM")}
    }
    xLogH1(sprintf("Mail took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartMail, Today_and_Now()))[1..3], scalar(localtime())));

    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/mail_step.log", 1, "step", "Mail");  
    Dashboard("Mail");
}

Trace(sprintf("stop $BuildName (%u h %02u mn %02u s)", (Delta_DHMS(@Start, Today_and_Now()))[1..3]));
PollingTrace(sprintf("stop $BuildName ($BuildStepTime)", (Delta_DHMS(@Start, Today_and_Now()))[1..3])) if($Polling);
printf("execution took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);
    
END { $p4->Final() if($p4) }

#############
# Functions #
#############

sub verify_copy
{
    my($Src, $Dst) = @_;

    for my $Attempt (1..5)
    {
        unless(copy($Src, $Dst))
        {
            warn("ERROR: cannot copy (attempt : $Attempt) '$Src' to '$Dst': $!");
            sleep(int(rand(20)));
            next;
        }
        
        open(SRC, $Src) or warn("ERROR: cannot open '$Src': $!\n");
        my $SrcMD5 = Digest::MD5->new->addfile(*SRC)->digest();
        close(SRC);
        open(DST, $Dst) or warn("ERROR: cannot open '$Dst': $!\n");
        my $DstMD5 = Digest::MD5->new->addfile(*DST)->digest();
        close(DST);
        
        return if($SrcMD5 eq $SrcMD5);
        sleep(int(rand(20)));
    }
    warn("ERROR: cannot copy '$Src' to '$Dst' after 5 attempts");
}

sub GAVDepends
{
    my($raGAVs, $LineNumber) = @_;
    my($Level1, $GroupId1, $ArtifactId1, $Version1) = @{${$raGAVs}[$LineNumber]};
    $GAVFullDepends{"$GroupId1:$ArtifactId1:$Version1"} = undef unless(exists($GAVFullDepends{"$GroupId1:$ArtifactId1:$Version1"}));
    for(my $i=$LineNumber+1; $i<@{$raGAVs}; $i++)
    {
        my($Level2, $GroupId2, $ArtifactId2, $Version2) = @{${$raGAVs}[$i]};
        if($Level2 == $Level1 + 1) 
        {
            $GAVFullDepends{"$GroupId2:$ArtifactId2:$Version2"} = undef unless(exists($GAVFullDepends{"$GroupId2:$ArtifactId2:$Version2"}));
            ${$GAVFullDepends{"$GroupId1:$ArtifactId1:$Version1"}}{"$GroupId2:$ArtifactId2:$Version2"} = undef;
        }
        elsif($Level2 > $Level1 + 1) { my $j = GAVDepends($raGAVs, $i); $i = $j>$i?$j:$i }
        else { return --$i }
    }
}

sub ContextBuildNumber
{
    my($Revision) = @_;
    my($Ctxt, $BuildNb);
    if(($Ctxt, $BuildNb) = $Revision =~ /^=(.+)[\\\/](\d+)$/) { }
    elsif(my($XMLContextFile) = $Revision =~ /^=(.+)$/)
    {
        $XMLContextFile .= "/$1.context.xml" if($XMLContextFile =~ /([^\\\/]+)[\\\/]\d+$/);
        $XMLContextFile = "$IMPORT_DIR/$XMLContextFile" unless(-e $XMLContextFile);
        warn("ERROR: '$XMLContextFile' not found") unless(-e $XMLContextFile);
        eval
        {
	        my $CONTEXT = XML::DOM::Parser->new()->parsefile($XMLContextFile);
	        $BuildNb = ($CONTEXT->getElementsByTagName("version")->item(0)->getFirstChild()->getData() =~ /(\d+)$/, $1);
	        $Ctxt    = $CONTEXT->getElementsByTagName("version")->item(0)->getAttribute("context");
	        $CONTEXT->dispose();
		};
	    warn("ERROR: cannot parse '$XMLContextFile': $@; $!") if($@);		
    }
    return "$Ctxt/$BuildNb";
}

sub ExpandGAVs
{
    my($GAVs) = @_;
    my %ExpandedGAVs;
    foreach my $GAV (reverse(split(/\s*,\s*/, $GAVs)))
    {
        if($GAV =~ s/\*/.+/g) 
        {
            my($RefStaging, $RefGroupId, $RefArtifactId, $RefVersion) = split(/\s*:\s*/, $GAV);
            my $Expanded = 0;
            foreach my $raGAV (@{$raGAVs})
            {
                my($Level, $GroupId, $ArtifactId, $Version) = @{$raGAV};
                if("$GroupId:$ArtifactId:$Version" =~ /^$RefGroupId:$RefArtifactId:$RefVersion$/ && !exists($ExpandedGAVs{"$GroupId:$ArtifactId:$Version"}))
                {
                    $ExpandedGAVs{"$GroupId:$ArtifactId:$Version"} = $RefStaging;
                    $Expanded = 1;
                }
            }                    
            warn("ERROR: '$GAV' cannot be expanded") unless($Expanded); 
        }
        else
        { 
            my($RefStaging, $RefGroupId, $RefArtifactId, $RefVersion) = split(/\s*:\s*/, $GAV);
            $ExpandedGAVs{"$RefGroupId:$RefArtifactId:$RefVersion"} = $RefStaging unless(exists($ExpandedGAVs{"$RefGroupId:$RefArtifactId:$RefVersion"}));
        }
    }
    return \%ExpandedGAVs;
}

sub Properties
{
    my($File) = @_;
	eval
	{
	    my $POM = XML::DOM::Parser->new()->parsefile($File);
	    for my $PROJECT (@{$POM->getElementsByTagName("project")})
	    {
	        for my $PROPERTIES (@{$PROJECT->getElementsByTagName("properties")})
	        {
	            foreach my $Properties ($PROPERTIES->getChildNodes())
	            {
	                if($Properties->getNodeType() == ELEMENT_NODE)
	                {
	                    my($Name, $Value) = ($Properties->getNodeName(), $Properties->getFirstChild()->getData());
	                    $Properties{$Name} = $Value;
	                }
	            }
	        }
	    }
	    $POM->dispose();
	};
    warn("ERROR: cannot parse '$File': $@; $!") if($@);
}

sub RepositoryPOM
{
    my($POMFile) = @_; 
    return unless($POMFile && -e $POMFile);
    my($RealGroupIdPath, $RealArtifactId, $RealVersion);
    eval
    {
        my $POM = XML::DOM::Parser->new()->parsefile($POMFile);
        ($RealGroupIdPath = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("groupId", 0)->item(0)->getFirstChild()->getData()) =~ s/\./\//g;
        $RealArtifactId = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("artifactId", 0)->item(0)->getFirstChild()->getData();
        $RealVersion    = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("version", 0)->item(0)->getFirstChild()->getData();
        $POM->dispose();
    };
    warn("ERROR:cannot parse '$POMFile': $@; $!") if($@);
    mkpath("$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion") or warn("ERROR: cannot mkpath '$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion': $!") unless(-d "$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion");
    chmod(0755, "$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/pom.xml") or warn("ERROR: cannot chmod '$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/pom.xml': $!") if(-e "$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/pom.xml");
    copy($POMFile, "$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion") or warn("ERROR: cannot copy '$POMFile': $!");
    chmod(0755, "$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/pom.xml") or warn("ERROR: cannot chmod '$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/pom.xml': $!");
    chmod(0755, "$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/$RealArtifactId-$RealVersion.pom") or warn("ERROR: cannot chmod '$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/$RealArtifactId-$RealVersion.pom': $!") if(-e "$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/$RealArtifactId-$RealVersion.pom");
    copy($POMFile, "$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/$RealArtifactId-$RealVersion.pom") or warn("ERROR: cannot copy '$POMFile': $!");
    chmod(0755, "$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/$RealArtifactId-$RealVersion.pom") or warn("ERROR: cannot chmod '$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/$RealArtifactId-$RealVersion.pom': $!");
    open(JAR, ">$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/$RealArtifactId-$RealVersion.jar") or warn("ERROR: cannot open '$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/$RealArtifactId-$RealVersion.jar': $!");
    close(JAR);
    return "$LocalRepository/$RealGroupIdPath/$RealArtifactId/$RealVersion/pom.xml";
}

sub DependenciesTree
{
    my($POMFile) = @_;
    
    my(@GAVs);
    my @StartMVN = Today_and_Now();
    printf("MVN Start at %s\n", scalar(localtime()));
    print("mvn $MVN_OPTIONS -Dverbose -Dmaven.repo.local=$LocalRepository -f $POMFile dependency:tree\n");
    open(MVN, "mvn $MVN_OPTIONS -Dverbose -Dmaven.repo.local=$LocalRepository -f $POMFile dependency:tree |") or warn("ERROR: cannot execute 'mvn': $!");
    while(<MVN>)
    {
        if(/\[ERROR\]/)
        {
            print;
            while(<MVN>) { print }
            die("ERROR: maven error from '$POMFile'");
        }
        next unless(/^\[INFO\]\s*\[dependency:tree\s*(.*)?]/);
        while(<MVN>)
        {
            if(/\[ERROR\]/)
            {
                print;
                while(<MVN>) { print }
                die("ERROR: maven error from '$POMFile'");
            }
            last if(/^\[INFO\]\s*------/);
            next if(/ - omitted for cycle\)$/);
            chomp;
            next unless(my($Level, $GroupId, $ArtifactId, $Version) = /^\[INFO\]([|+-\\\s]+)\(?([^:]+):([^:]+):[^:]+:([^:]+)/);
            $Level = (length($Level)-1)/3;
            push(@GAVs, [$Level, $GroupId, $ArtifactId, $Version]);
        }
        while(<MVN>)
        {
            if(/\[ERROR\]/)
            {
                print;
                while(<MVN>) { print }
                die("ERROR: maven error from '$POMFile'");
            }
        }
    }
    close(MVN);
    printf("MVN took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartMVN, Today_and_Now()))[1..3], scalar(localtime()));
    chdir($CURRENTDIR) or warn("ERROR: cannot chdir '$CURRENTDIR': $!");
    return \@GAVs;
}

sub CopyFiles
{
    my($Source, $Destination, $Message) = @_;
    my $Result;
    if($^O eq "MSWin32")
    { 
        $Source =~ s/\//\\/g;
        if(-e $Source)
        {
            $Destination =~ s/\//\\/g;
            $Destination =~ s/\\$//;
            ($Destination) = $Destination =~ /^(.*\\)[^\\]+$/ if(-f $Source);
            my $CopyCmd;
            if($IsRobocopy && !(-f $Source)) { $CopyCmd = "robocopy $ROBOCOPY_OPTIONS" }
            else { $CopyCmd = "xcopy " . (-f $Source ? "/CQRYD" : "/ECIQHRYD") }
            mkpath($Destination) or warn("ERROR: cannot mkpath '$Destination': $!") unless(-e $Destination);
            $Result = system("$CopyCmd \"$Source\" \"$Destination\"");
            $Result &= 0xff;
            warn("ERROR: cannot copy '$Source' to '$Destination': $! at ". (scalar(localtime()))) if($Result);
        } else { warn("ERROR: '$Source' not found") }
    }
    else
    { 
        $Source =~ s/\\/\//g;
        if(-e $Source)
        {
            $Destination =~ s/\\/\//g;
            mkpath($Destination) or warn("ERROR: cannot mkpath '$Destination': $!") unless(-e $Destination);
            for my $Attempt (1..3)
            {
                print("new attempt ($Attempt/3)\n") if($Attempt>1);
                if(-d $Source) { $Result = system("cp -dRuf --preserve=mode,timestamps \"$Source/.\" $Destination 1>$NULLDEVICE") }
                else { $Result = system("cp -dRuf --preserve=mode,timestamps \"$Source\" $Destination 1>$NULLDEVICE") }
                last unless($Result);
                warn(($Attempt==3?"ERROR":"WARNING").": cannot copy '$Source/.' to '$Destination' (attempt $Attempt/3): $!");
                sleep(24);    
            }
        } else { warn("ERROR: '$Source' not found") }
    }   
    print($Message) if($Message);
    return $Result;
}

sub Monitor
{
    my($rsVariable) = @_;
    return undef unless(tied(${$rsVariable}) || (${$rsVariable} && ${$rsVariable}=~/\$\{.*?\}/));
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
        unless(ExpandVariable(\${$MonitoredVariables[$i]}[1]) =~ /\$\{.*?\}/)
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
    while($Variable =~ /\$\{(.*?)\}/g)
    {
        my $Name = $1;
        $Variable =~ s/\$\{$Name\}/${$Name}/ if(defined(${$Name}));
        $Variable =~ s/\$\{$Name\}/$ENV{$Name}/ if(!defined(${$Name}) && defined($ENV{$Name}));
    }
    ${$rsVariable} = $Variable if($IsVariableExpandable);
    return $Variable;
}

sub ParseErrors
{
    my($Log) = @_;
    my($Start, $Stop, $NumberOfErrors) = (0, 0, 0);
    my($File, $Area) = $Log =~ /^(.*?([^\\\/]+)).log$/;
    $ENV{area}  = $Area;
    $ENV{order} = 1;
    my @processresult;
    XProcessLog::processlog($Lego, $Log, 1, \@processresult);
    foreach (@processresult)
    { 
        if(/^=\+=Errors detected: (\d+)/i) { $NumberOfErrors = $1 }
        elsif(/^=\+=Start: (.+)$/i)        { $Start = $1 }
        elsif(/^=\+=Stop: (.+)$/i)         { $Stop = $1 }
    }
    @Errors = ($NumberOfErrors);
    push(@Errors, [$NumberOfErrors, $File, $Area, 1, $Start, $Stop]);

    if(open(LOG, $Log))
    {
        my($File, $Area, $Order, $Start, $Stop);
        while(<LOG>)
        {
            if(/^=\+=Summary log file created: (.+)\.summary\.txt$/) { $File = $1 }
            elsif(/^=\+=Area: (.+)$/)  { $Area = $1 }
            elsif(/^=\+=Order: (.+)$/) { $Order = $1 }
            elsif(/^=\+=Start: (.+)$/) { $Start = $1 }
            elsif(/^=\+=Stop: (.+)$/)  { $Stop = $1 }
            elsif(/^=\+=Errors detected: (\d+)$/)
            {
                $Errors[0] += $1;
                push(@Errors, [$1, $File, $Area, $Order||1, $Start, $Stop]);
            }
        }
        close(LOG);
    } else { warn("ERROR: cannot open '$Log': $!") }
	delete($ENV{area});
	delete($ENV{order});
    return \@Errors;
}

sub Run
{
    my($Step, $raCommands) = @_;
    my $NumberOfErrors = 0;

    my @Commands = grep({my $Name=${$_}[1]; grep({/$Name/} @Targets)} @{$raCommands});
    @Commands = @{$raCommands} unless(@Commands);
    foreach my $raCommand (@Commands)
    { 
        my($Platform, $CommandName, $Command) = @{$raCommand};
        next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL); 
        my @StartCmd = Today_and_Now();
        xLogH1("\t$CommandName: ");
        open(LOG, ">$OUTLOG_DIR/Build/$CommandName.log");
        print(LOG "=== Build start: ", time(), "\n");
        print(LOG join('', map({"$_=$ENV{$_}\n"} grep({!/PASSW/i and !/MY_FULL_TEXTML/i} sort(keys(%ENV))))));
        close(LOG);
        $ENV{build_steptype}="sub_step"; $ENV{build_cmdline}=$Command; $ENV{build_parentstepname}=$Step; $ENV{build_stepname}=$CommandName;
        my $Result = system("$Command >>$OUTLOG_DIR/Build/$CommandName.log 2>&1");
        if ($Result == -1) { system("echo === Command invocation error: $! >>$OUTLOG_DIR/Build/$CommandName.log 2>&1") }
        else
        {
            $Result = $Result >> 8;
            system("echo === exit code: $Result >>$OUTLOG_DIR/Build/$CommandName.log 2>&1");
        }
        system("echo === Build stop: ".time()." >>$OUTLOG_DIR/Build/$CommandName.log 2>&1");
        my $raErrors = ParseErrors("$OUTLOG_DIR/Build/$CommandName.log");
        $NumberOfErrors += ${$raErrors}[0];
        $BuildResult ||= ( $Result != 0 || $NumberOfErrors != 0 ) ? 1 : 0;
        Dashboard($Step, $raErrors, 1);
        delete $ENV{build_steptype} if(exists $ENV{build_steptype}); delete $ENV{build_cmdline} if(exists $ENV{build_cmdline}); delete $ENV{build_parentstepname} if(exists $ENV{build_parentstepname}); delete $ENV{build_stepname} if(exists $ENV{build_stepname});
        xLogH1(sprintf("%d e.rror(s) %u h %02u mn %02u s at %s\n", ${$raErrors}[0], (Delta_DHMS(@StartCmd, Today_and_Now()))[1..3], scalar(localtime())));
    }
    return $NumberOfErrors;
}

sub Dashboard
{
    return unless($Dashboard && $ENV{BUILD_CIS_DASHBOARD_ENABLE});

    my($Step, $raErrors, $IsSubStep) = @_;

    unless(-e "$HTTPDIR/$BuildName/Host_$Rank")
    {
        sleep(5);
        eval { mkpath ("$HTTPDIR/$BuildName/Host_$Rank") };
        warn("ERROR: cannot mkpath '$HTTPDIR/$BuildName/Host_$Rank': $!") if($@);
    }

    unless(-e "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/logs/$HOST")
    {
        eval { mkpath ("$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/logs/$HOST") };
        warn("ERROR: cannot mkpath '$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/logs/$HOST': $!") if ($@);
    }

    # Host #
    if($Step ne "Test" && $Step ne "Smoke" && $Step ne "Validation")
    {
        my $HostFile = "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/logs/host_$Rank.dat";
        if(open(DAT, ">$HostFile"))
        {
            print(DAT "$HOST | $SRC_DIR | $OUTPUT_DIR");
            close(DAT);
    	} else { warn("ERROR: cannot open '$HostFile': $!") }
        copy($HostFile, "$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_host_$Rank.dat") or warn("ERROR: cannot copy '$HostFile': $!");
    }
    
    # Build Version #
    if(open(DAT, ">$HTTPDIR/$BuildName/Version.dat"))
    {
        print(DAT "$Version.$BuildNumber");
        close(DAT);
    } else { warn("ERROR: cannot open '$HTTPDIR/$BuildName/Version.dat': $!") }

    # INI File #
    chdir($CURRENTDIR) or warn("ERROR: cannot chdir '$CURRENTDIR': $!");
    unless($IsIniCopyDone)
    {
        my($Name) = $Config =~ /([^\\\/]+)$/;
        (my $ExpandedConfigFile = $Name) =~ s/\.ini/.expanded.ini/;
        Unix2Dos($Config, "$DROP_DIR/$Context/$BuildNumber/$Name");
        Unix2Dos($Config, "$HTTPDIR/$BuildName/$Name");
        system("perl $CURRENTDIR/PreprocessIni.pl $Config >$TEMPDIR/$ExpandedConfigFile");
        Unix2Dos("$TEMPDIR/$ExpandedConfigFile", "$HTTPDIR/$BuildName/$ExpandedConfigFile");
        $IsIniCopyDone = 1;
    }
    
    # Config #
    my $ConfigHTM = $ConfigFile ? $ConfigFile : "$CURRENTDIR/Config.htm";
    copy("$ConfigHTM", "$DROP_DIR/$Context/$BuildNumber/Config.htm") or warn("WARNING: cannot copy '$ConfigHTM'");
    copy("$ConfigHTM", "$HTTPDIR/$BuildName/Config.htm")             or warn("WARNING: cannot copy '$ConfigHTM'");
    
    # New Revisions #
    if($Step eq "Report")
    {
        my $OutputFile = "$OUTLOG_DIR/NewRevisions.dat";
        copy($OutputFile, "$HTTPDIR/$BuildName/NewRevisions.dat") or warn("ERROR: cannot copy 'NewRevisions.dat': $!");
        copy("$OUTLOG_DIR/Adapts.txt", "$HTTPDIR/$BuildName/Adapts.txt") or warn("ERROR: cannot copy 'Adapts.txt': $!");
        copy("$OUTLOG_DIR/Jiras.txt", "$HTTPDIR/$BuildName/Jiras.txt") or warn("ERROR: cannot copy 'Jiras.txt': $!");
        copy("$OUTLOG_DIR/CWB.txt", "$HTTPDIR/$BuildName/CWB.txt") or warn("ERROR: cannot copy 'CWB.txt': $!");
    }
    
    # Infrastructure Errors #
    unless($IsSubStep)
    {
        my @Errors = (0);
        if(opendir(DIR, "$OUTLOG_DIR/Build")) 
        {
	        while(defined($File = readdir(DIR)))
	        {
	            next unless(my($Area) = $File =~ /^(.+_step)\.log$/);
	            my($Errors, $Start, $Stop) = (0, 0, 0);
	            if(open(SUM, "$OUTLOG_DIR/Build/$Area.summary.txt"))
	            {
	                while(<SUM>)
	                {
	                    if(/^\[ERROR\s+\@\d+\]/)             { $Errors++ }
	                    elsif(/^== Build start.+\((\d+)\)$/) { $Start = $1 }
	                    elsif(/^== Build end.+\((\d+)\)$/)   { $Stop = $1 }
	                }
	                close(SUM);
	            }
	            else { warn("ERROR: cannot open '$OUTLOG_DIR/Build/$Area.summary.txt': $!") }
	            $Errors[0] += $Errors;
	            push(@Errors, [$Errors, "$OUTLOG_DIR/Build/$Area", $Area, 1, $Start, $Stop]);
	        }
	        closedir(DIR);
        } else {warn("ERROR: cannot opendir '$OUTLOG_DIR/Build': $!");}
        UpdateDAT(\@Errors, "$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_infra_$Rank.dat", "infra", undef);
    }
    
    # Package Errors #
    if($Step eq "Package" && $Rank==1)
    {
        if(-e "$OUTLOG_DIR/packages")
        {
            if(opendir(DIR, "$OUTLOG_DIR/packages"))
            {
	            while(defined($Folder = readdir(DIR)))
	            {
	                next if($Folder =~ /^\.\.?$/ || !-e "$OUTLOG_DIR/packages/$Folder/Reports");
	                CopyFiles("$OUTLOG_DIR/packages/$Folder/Reports", "$HTTPDIR/$BuildName/Host_1/$PLATFORM/$BUILD_MODE/packages/$Folder/Reports");
	            }
	            closedir(DIR);
            } else {warn("ERROR: cannot opendir '$OUTLOG_DIR/packages': $!");}
        }
        UpdateDAT($raErrors, "$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_setup_$Rank.dat", "setup", \@PackageCmds);
    }
    # Prefetch Errors #
    UpdateDAT($raErrors, "$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_prefetch_$Rank.dat", "prefetch", \@PrefetchCmds) if($Step eq "Prefetch");
    
    # Build Errors #
    UpdateDAT($raErrors, "$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_build_$Rank.dat", "build", \@BuildCmds) if($Step eq "Build");

    # Dependencies Errors #
    UpdateDAT($raErrors, "$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_dependencies_$Rank.dat", "dependencies", \@DependenciesCmds) if($Step eq "Dependencies");
    
    # Test Errors #
    if($Step eq "Test" && $Rank==1)
    { 
        UpdateDAT($raErrors, "$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_test_$Rank.dat", "test", \@TestCmds);
        foreach my $raCommand (@TestCmds)
        {
            my($Platform, $CommandName, $Command) = @{$raCommand};
            next unless(-e "$OUTLOG_DIR/Build/$CommandName.log");
            open(LOG, "$OUTLOG_DIR/Build/$CommandName.log") or warn("ERROR: cannot open '$OUTLOG_DIR/Build/$CommandName.log': $!");
            while(<LOG>)
            {
                #===TestResults in ${OUTBIN_DIR}\<AREA>\<TestResultFileName>.xml===
                next unless(/TestResults in (.+)/);
                my $ResultFile = $1;
                my($Extension) = $ResultFile =~ /\.([^.])$/;
                while($ResultFile =~ /\$\{(.*?)\}/g)
                {
                    my $Name = $1;
                    $ResultFile =~ s/\${$Name}/${$Name}/ if(defined(${$Name}));
                }
                if(-d $ResultFile) { CopyFiles($ResultFile, "$HTTPDIR/$BuildName/Host_$Rank/$PLATFORM/${BUILD_MODE}/$CommandName") }
                else { copy($ResultFile, "$HTTPDIR/$BuildName/Host_$Rank/$CommandName.$Extension") or warn("ERROR: cannot copy '$ResultFile': $!") }
                last;
            }
            close(LOG);
        }
    }

    # Smoke Errors #
    UpdateDAT($raErrors, "$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_smoke_$Rank.dat", "smoke", \@SmokeCmds) if($Step eq "Smoke" && $Rank==1);

    # Validation Errors #
    UpdateDAT($raErrors, "$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_bat_$Rank.dat", "bat", \@ValidationCmds) if($Step eq "Validation" && $Rank==1);
}

sub UpdateDAT
{
    my($raErrors, $DATFile, $Phase, $raCmds) = @_;
    tie %CurrentErrors, "Tie::IxHash";
    foreach (sort({${$a}[3] <=> ${$b}[3]} @{$raErrors}[1..$#{$raErrors}]))  # sorted by Order
    {
        my($Errors, $File, $Area, $Order, $Start, $Stop) = @{$_};
        next unless($Area);
        my($Name) = $File =~ /([^\\\/]+)$/;
        copy("$File.log", "$HTTPDIR/$BuildName/Host_$Rank/$Name=${PLATFORM}_${BUILD_MODE}_${Phase}.log") or warn("ERROR: cannot copy '$File.log': $!");
        copy("$File.summary.txt", "$HTTPDIR/$BuildName/Host_$Rank/$Name=${PLATFORM}_${BUILD_MODE}_summary_${Phase}.txt") or warn("ERROR: cannot copy '$File.summary.txt': $!");
        my($BuildUnit) = $File =~ /([^\\\/]+)$/;
        $CurrentErrors{$Area}{$BuildUnit} = [$Errors, "Host_$Rank/$Name=${PLATFORM}_${BUILD_MODE}_${Phase}.log", "Host_$Rank/$Name=${PLATFORM}_${BUILD_MODE}_summary_${Phase}.txt", $Area, $Start, $Stop];
    }
    my @Errors = (0);
    if(-e $DATFile)
    {
        open(DAT, $DATFile) or warn("ERROR: cannot open '$DATFile': $!");
        eval <DAT>; close(DAT);
    }
    elsif($raCmds)
    {
        foreach my $raCommand (@{$raCmds})
        {
            my($Platform, $CommandName, $Command) = @{$raCommand};
            next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i)); 
            push(@Errors, [undef, "Host_$Rank/$CommandName=${PLATFORM}_${BUILD_MODE}_${Phase}.log"]);
        }
    }
    $Errors[0] = 0;
    my %PreviousErrors;
    foreach(my $i=1; $i<@Errors; $i++)
    {
        my($NumberOfErrors, $LogFile, $SummaryFile, $Area, $Start, $Stop) = @{$Errors[$i]};
        my($BuildUnit) = $LogFile =~ /[\\\/](.+?)=/;
        $Area ||= $BuildUnit;
        $Errors[$i] = $CurrentErrors{$Area}{$BuildUnit} if(exists($CurrentErrors{$Area}{$BuildUnit}));
        $Errors[0] += ${$Errors[$i]}[0] if(${$Errors[$i]}[0]);
        $PreviousErrors{$Area}{$BuildUnit} = undef;
    }
    foreach my $Area (keys(%CurrentErrors))
    {
        foreach my $BuildUnit (keys(%{$CurrentErrors{$Area}}))
        {
            next if(exists($PreviousErrors{$Area}{$BuildUnit}));
            push(@Errors, $CurrentErrors{$Area}{$BuildUnit});
            $Errors[0] += ${$CurrentErrors{$Area}{$BuildUnit}}[0];
        }
    }
    if(open(DAT, ">$DATFile"))
    {
        $Data::Dumper::Indent = 0;
        print DAT Data::Dumper->Dump([\@Errors], ["*Errors"]);
        close(DAT);
    }
    else { warn("ERROR: cannot open '$DATFile': $!") }
}

sub CopyFork
{
    my($From, $To, $Message) = @_;
    $NumberOfCopy++;
    CopyFiles($From, $To, $Message);
}

sub submitbuildresults($$$$)
{
    my ($logpath, $Infra, $szBuildType, $szBuildStepName) = @_;
    
    $ENV{build_steptype}=$szBuildType; $ENV{build_stepname}=$szBuildStepName;
    if ($Infra) {
        $ENV{build_parentstepname}= $ENV{rmbuild_type} = 'Infrastructure';
        $ENV{area} = 'Build';
        }
    XProcessLog::processlog($Lego, $logpath, 1);
    delete $ENV{build_steptype} if(exists $ENV{build_steptype}); delete $ENV{build_stepname} if(exists $ENV{build_stepname}); delete $ENV{build_parentstepname} if(exists $ENV{build_parentstepname});

    #Create Report Instances if Torch is enabled 
    if($CACHEREPORT_ENABLE && $ENV{BUILD_DASHBOARD_ENABLE})
    {
        print("Creating Report Instance for step: $szBuildStepName\n");
        my $CMD = "perl $CURRENTDIR/CreateReportInstances.pl $Context $BuildNumber $OUTLOG_DIR/TorchReportInstance_$szBuildStepName.log > $NULLDEVICE";
        system($CMD);
    }
}

sub Trace
{
    my($Message) = @_;

    print("$Message\n");

    return unless($Dashboard);
   
    unless(-e "$HTTPDIR")
    {
        eval { mkpath ($HTTPDIR) };
        return 0 if ($@);
    }
    
    open(DIARY, ">>$HTTPDIR/Build_$Context.log") or warn("WARNING: cannot open '$HTTPDIR/Build_$Context.log': $!");
    print(DIARY scalar(gmtime()), ": $PLATFORM: $BUILD_MODE: $Message [$CommandLine on $HOST]\n");
    close(DIARY);
    
    open(DIARY, ">>$HTTPDIR/Build_$Context.dat") or warn("WARNING: cannot open '$HTTPDIR/Build_$Context.dat': $!");
    my($Action, $Duration) = ($Message=~/\((.*)\)/) ? ("stop", $1) : ("start", "");   
    my($WDay, $Month, $MDay, $Hour, $Min, $Sec, $Year) = gmtime() =~ /^([a-zA-Z]{3})\s([a-zA-Z]{3})\s+(\d+)\s(\d{2}):(\d{2}):(\d{2})\s(\d{4})$/; 
    print(DIARY "['$WDay', '$Month', '$MDay', '$Hour', '$Min', '$Sec', '$Year', '$PLATFORM', '$BUILD_MODE', '$Action', '$Context', '$buildnumber', '$Duration', '$CommandLine', '$HOST'],\n");
    close(DIARY);
}

sub PollingTrace
{
    my($Message) = @_;
    mkpath($HTTPDIR) or die("ERROR: cannot mkpath '$HTTPDIR': $!") unless(-e "$HTTPDIR");
    open(DIARY, ">>$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_Roll.log") or warn("WARNING: cannot open '$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_Roll.log': $!");
    print(DIARY ($Message !~ /^\t/) ? scalar(gmtime()).": " : "", "$Message\n");
    close(DIARY);
}

sub Unix2Dos
{
    my($In, $Out) = @_;
    if(open(IN, $In))
    {
        if(open(OUT, ">$Out"))
        {
            while(<IN>)
            {
                s/^\n/\r\n/;
                s/([^\r])\n/$1\r\n/;
                print(OUT);
            }
            close(OUT);
        }
        else { warn("ERROR: cannot open '$Out': $!") }
        close(IN);
   }
   else { warn("ERROR: cannot open '$In': $!") }
}

sub Depends
{
    my($Makefile) = @_;
    my @Areas = Read("AREAS", $Makefile);
    my %Depends;
    foreach my $Area (@Areas)
    {
        if(open(DEP, "$SRC_DIR/$Area/$Area.$PLATFORM.dep"))
        {
            while(<DEP>)
            {
                if(/^\s*(.+)_deps\s*=\s*\$\(.+,\s*([^,]*?)\s*\)/)
                {
                    my @Depends = split(/\s+/, $2);
                    @{$Depends{$Area}{$1}}{@Depends} = ();   
                }
            }
            close(DEP);
        } else { warn("WARNING: cannot open '$SRC_DIR/$Area/$Area.$PLATFORM.dep': $!")}
    }
    return \%Depends;
}

sub IsDescendant
{
    my($Area, $Unit, $rhUnits, $rhDepends) = @_;
    foreach my $Depend (keys(%{${$rhDepends}{$Area}{$Unit}}))
    {
        my $DependArea;
        AREA: foreach my $Ar (keys(%{$rhDepends}))
        {
            foreach my $Unt (keys(%{${$rhDepends}{$Ar}}))
            { 
                if($Unt eq $Depend) { $DependArea=$Ar; last AREA } 
            }
        }
        #warn("ERROR: area not found for $Depend Unit") unless($DependArea);
        return 1 if(exists(${$rhUnits}{"$DependArea.$Depend"}) || IsDescendant($DependArea, $Depend, $rhUnits, $rhDepends));
    }
    return 0;   
}

sub Read 
{
    my($Variable, $Makefile) = @_;

    my $Values;
    my $CurrentDir = getcwd();
    my($DirName) = $Makefile =~ /^(.+)[\\\/]/;
    chdir($DirName) or die("ERROR: cannot chdir '$DirName': $!");
    if(open(MAKE, "make -f $Makefile display_\L$Variable 2>$NULLDEVICE |"))
    {
        while(<MAKE>)
        {
            last if(($Values) = /\s*$Variable\s*=\s*(.+)$/i);
        }
        close(MAKE);
    }
    chdir($CurrentDir) or die("ERROR: cannot chdir '$CurrentDir': $!");
    unless($Values)
    {
        if($Makefile && open(MAKE, $Makefile))
        {
            while(<MAKE>)
            {
                next unless(($Values) = /^\s*$Variable\s*:?=\s*([^\\]+)\s*/);
                if(/\\\s*$/)
                {
                    while(<MAKE>)
                    {
                        next if(/^#/);
                        chomp;
                        $Values .= " $1" if(/\s*([^\\]+)\s*\\?/);
                        last unless(/\\\s*$/);
                    }
                }
                last;
            }
            close(MAKE);
        } else { warn("ERROR: cannot open '$Makefile': $!") }
    }
    warn("ERROR: $Variable not found in '$Makefile'") if(!$Values && $Variable ne "AREAS");
    $Values ||= "";
    chomp($Values);
    $Values =~ s/^\s+//;
    $Values =~ s/\s+$//;
    return split(/\s+/, $Values);
}

sub CreateContextFile
{
    my($XMLContext, $Wrk) = @_;

    # create context #
    mkpath("$SRC_DIR/Build/export/iface") or warn("ERROR: cannot mkpath '$SRC_DIR/Build/export/iface': $!") unless(-e "$SRC_DIR/Build/export/iface");
    open(PROPERTIES, ">$SRC_DIR/Build/export/iface/context.properties") or warn("ERROR: cannot open '$SRC_DIR/Build/export/iface/context.properties': $!");
    open(XML, ">$TEMPDIR/$$.context.xml") or warn("ERROR: cannot open '$TEMPDIR/$$.context.xml': $!");    
    print(XML "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    print(XML "<context>\n");
    foreach(@P4Syncs)
    {
        my($Sync, $Workspace, $P4Opts, $GAV, $LogicalRev, $BuildRev) = @{$_};
        $Workspace =~ s/^\/\/[^\/]+\//\/\/$Wrk\// if($Wrk);
        my($File, $Revision) = $Sync =~ /^([^#@]+)(.*)$/;
        my $Authority = ($P4Opts =~ /-p\s*(.+)\b/) ? " authority=\"$1\"" : "";

        # Perforce path may be surrounded by quotes in order to support space in path. Escape those quotes when writting to context file:
        $Workspace =~ s/^"(.*)"$/&quot;$1&quot;/;

        print(XML "\t<fetch revision=\"$Revision\" workspace=\"$Workspace\"$Authority logicalrev=\"$LogicalRev\"", defined($BuildRev)?" buildrev=\"$BuildRev\"":"", ($LogicalRev=~/^=/ and !$Revision) ? " comment=\"ERROR: Requested perforce path could not be found in $LogicalRev\"":"", ">$File</fetch>\n");
        my($Area) = $File =~ /\/\/[^\/]+\/([^\/]+)/;
        print(PROPERTIES "$Area.revision=$Revision\n"); 
    }
    foreach(@GITViews)
    {
        my($Repository, $RefSpec, $Destination, $StartPoint, $LogicalStartPoint) = @{$_};
        $Destination ||= $SRC_DIR;
        my $StrtPnt = ($StartPoint ||= 'FETCH_HEAD');
        if($StrtPnt =~ /^FETCH_HEAD$/)
        {
            chdir($Destination) or warn("ERROR: cannot chdir '$Destination': $!");
            ($StrtPnt) = (`git log -1`=~/^commit\s+([0-9a-z]*)/);
            chdir($CURRENTDIR) or warn("ERROR: cannot chdir '$CURRENTDIR': $!");
        } 
        print(XML "\t<git repository=\"$Repository\" refspec=\"$RefSpec\" destination=\"$Destination\" startpoint=\"$StrtPnt\" logicalstartpoint=\"$LogicalStartPoint\"/>\n");
    }
    foreach my $raImport (@ImportVersions)
    {
        my($Area, $Version) = @{$raImport};
        (my $Ver = $Version) =~ s/\"/'/g;
        print(XML "\t<import version=\"$Ver\">$Area</import>\n");
    }
    foreach(@NexusImports)
    {
        my($Platform, $MappingFile, $TargetDir, $Log1, $Log2, $Options) = @{$_};
        print(XML "\t<nexusimport platform=\"$Platform\" mapping=\"$MappingFile\" target=\"$TargetDir\" log1=\"$Log1\" log2=\"$Log2\" options=\"$Options\"><\/nexusimport>\n");
    }
    print(XML "\t<version context=\"$Context\">$Version.$ENV{BUILDREV}</version>\n");
    print(XML "</context>");
    close(XML);
    close(PROPERTIES);
    chmod(0755, $XMLContext) or warn("ERROR: cannot chmod '$XMLContext': $!") if(-e $XMLContext);
    copy("$TEMPDIR/$$.context.xml", $XMLContext) or warn("ERROR: cannot copy '$TEMPDIR/$$.context.xml': $!");
    unlink("$TEMPDIR/$$.context.xml") or warn("ERROR: cannot unlink '$TEMPDIR/$$.context.xml': $!");
}

sub CreateContext
{
    # create context #
    if($p4)
    {
        $p4->SetOptions("-c \"$ClientForContext\"");
        $p4->sync($XMLContext);
        warn("ERROR: cannot 'sync': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/no such file\(s\).$/ && ${$p4->Errors()}[0]!~/up-to-date.$/);
    }
    mkpath("$SRC_DIR/Build/export/shared/contexts") or warn("ERROR: cannot mkpath '$SRC_DIR/Build/export/shared/contexts': $!") unless(-e "$SRC_DIR/Build/export/shared/contexts");
    CreateContextFile($XMLContext, undef);
    
    # copy context #   
    if($Dashboard && (!defined($ContextParameter) || $ContextParameter =~ /^\d{2}:\d{2}:\d{2}$/))
    {
        if($IsDropDirWritable)
        {   
            eval { mkpath("$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files") or warn("ERROR: cannot mkpath '$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files': $!") } unless(-e "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files");
            if(-e "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files")
            {
                CreateContextFile("$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files/$Context.context.xml",'${Client}');
                verify_copy($XMLContext, "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files/${Context}_${PLATFORM}_$BUILD_MODE.context.xml");
                NSDTransfert("../../contexts/allmodes/files");
            }
        }
        eval { mkpath("$HTTPDIR/$BuildName") or warn("ERROR: cannot mkpath '$HTTPDIR/$BuildName': $!") } unless(-e "$HTTPDIR/$BuildName");
        if(-e "$HTTPDIR/$BuildName")
        {
            copy($XMLContext, "$HTTPDIR/$BuildName/$BuildName.context.xml") or warn("ERROR: cannot copy '$XMLContext': $!");
            copy($XMLContext, "$HTTPDIR/$BuildName/${BuildName}_${PLATFORM}_$BUILD_MODE.context.xml") or warn("ERROR: cannot copy '$XMLContext': $!");
        }
        mkpath("$OUTLOG_DIR/Build") or warn("ERROR: cannot mkpath '$OUTLOG_DIR/Build': $!") unless(-e "$OUTLOG_DIR/Build");
        copy($XMLContext, "$OUTLOG_DIR/Build") or warn("ERROR: cannot copy '$XMLContext': $!");
        copy($Config, "$OUTLOG_DIR/Build") or warn("ERROR: cannot copy '$Config': $!");
    }
    else
    {
        mkpath("$OUTLOG_DIR/Build") or warn("ERROR: cannot mkpath '$OUTLOG_DIR/Build': $!") unless(-e "$OUTLOG_DIR/Build");
        copy($XMLContext, "$OUTLOG_DIR/Build") or warn("ERROR: cannot copy '$XMLContext': $!");
    }
}

sub DefectsByUser
{
    my(%Issues, %Users, %Depends, %g_read);
    # errors
    {
        local $/ = undef;
        open(DAT, "$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_build_1.dat") or warn("ERROR: cannot open '$HTTPDIR/$BuildName/$BuildName=${PLATFORM}_${BUILD_MODE}_build_1.dat': $!");
        eval <DAT>; 
        close(DAT);    
    }
    foreach(@Errors[1..$#Errors])
    {
        my($Errors, $Log, $Area) = @{$_}[0,1,3];
        if($Errors)
        {
            my($Unit) = $Log =~ /\/(.*?)=/;
            $Issues{$Unit} = [$Errors, $Area];
        }
    }
        
    if($Errors[0])
    {
        # Dependencies
        my $DEPENDS_DIR = "$ENV{IMPORT_DIR}/${Context}"; 
        my $DepBuildNumber = int($BuildNumber); # Is the current build a Depends build & ALSO exported, if yes, take in the last version of the actual build which is the actual one, generally the current exported one	
        unless(-e "$DEPENDS_DIR/$DepBuildNumber/$PLATFORM/$BUILD_MODE/bin/depends") # This is not a depends build or the actual one was not exported, so take a look in all exported Depends build
        {
            foreach my $szCurrentDependsDir("$ENV{IMPORT_DIR}/${Context}","$ENV{IMPORT_DIR}/${Context}_Dep") # first take a look in actual contexts in the case of the actual context is a depends builds, also search into corresponding depends build (for example when in a Titan_Stable, take a look in Titan_Stable_Dep builds)
            {
                $DEPENDS_DIR = $szCurrentDependsDir; # If not checking in the current build before, it will resolve a _Dep_Dep if this code is run from a Depends build context
                $DepBuildNumber = 0;
                if(opendir(VER, $DEPENDS_DIR))
                {
                    while(defined(my $Version = readdir(VER)))
                    {
                        $DepBuildNumber = $1 if($Version=~/^(\d+)$/ && $1>$DepBuildNumber && -e "$DEPENDS_DIR/$1/$PLATFORM/$BUILD_MODE/bin/depends/depends.read.dat");
                    }
                    closedir(VER);
	            }
	            else { warn("WARNING: cannot opendir '$DEPENDS_DIR': $!"); }
	            last if($DepBuildNumber!=0); # a Depends dir was found, stop the loop
	        }
    	}
	    if($DepBuildNumber!=0)
	    {
		    $DEPENDS_DIR = $DEPENDS_DIR."/$DepBuildNumber/$PLATFORM/$BUILD_MODE/bin/depends";
	        {
	            local $/ = undef;
	            if(open(DAT, "$DEPENDS_DIR/depends.read.dat"))
	            {
	                eval <DAT>; 
	                close(DAT);
	            }
	            else { warn("ERROR: cannot open '$DEPENDS_DIR/depends.read.dat': $!") }
	        }
	    }
        my $rhDepends = Depends($IncrementalCmds[2]);
        foreach my $Unit (keys(%Issues))
        {
            my($Errors, $Area) = @{$Issues{$Unit}};
            foreach my $Depend (keys(%{${$rhDepends}{$Area}{$Unit}}))
            {
                push(@{$Depends{$Unit}}, $Depend) if(exists($Issues{$Depend}));  
            }        
        }
                   
        # Revisions and changes
        my $PreviousBuildNumber;
        for($PreviousBuildNumber=$BuildNumber-1; $PreviousBuildNumber>0; $PreviousBuildNumber--)
        {
            last if(-e "$DROP_DIR/$Context/$PreviousBuildNumber/contexts/allmodes/files/$Context.context.xml");
        }
        my $FromContext = $PreviousBuildNumber ? "$DROP_DIR/$Context/$PreviousBuildNumber/contexts/allmodes/files/$Context.context.xml" : "";
        my $ToContext   = "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files/$Context.context.xml";
        eval
        {
            $CONTEXT = XML::DOM::Parser->new()->parsefile($FromContext);	
            for my $COMPONENT (reverse(@{$CONTEXT->getElementsByTagName("fetch")}))
            {
            	my($File, $Revision) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute("revision"));
                $Contexts{$File} = [$Revision, ""];
            }
            $CONTEXT->dispose();
        };
        warn("ERROR:cannot parse '$FromContext': $@; $!") if($@);
        eval
        {
            $CONTEXT = XML::DOM::Parser->new()->parsefile($ToContext);	
            for my $COMPONENT (reverse(@{$CONTEXT->getElementsByTagName("fetch")}))
            {
            	my($File, $Revision) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute("revision"));
                if(exists($Contexts{$File})) { ${$Contexts{$File}}[1] = $Revision }
                else { $Contexts{$File} = ["", $Revision] }
            }
            $CONTEXT->dispose();
        };
        warn("ERROR:cannot parse '$ToContext': $@; $!") if($@);
        for my $File (keys(%Contexts))
        {
            if($File =~ s/^\-//)
            {
                $File =~ s/\*/[^\/]*/g;      # *   Matches all characters except slashes within one directory.
                $File =~ s/\.\.\./\.\*/g;    # ... Matches all files under the current working directory and all subdirectories.
                push(@RevisionExcludes, $File);
            }
        }
        if(@RevisionExcludes)
        {
            $RevisionExcludes = join("|", @RevisionExcludes);
            $RevisionExcludesRE = qr/$RevisionExcludes/;
        }
        for my $File (keys(%Contexts))
        {
            next if($File =~ /^\-/);
            $File =~ s/^\+//;
        
            my($FromRevision, $ToRevision) = @{$Contexts{$File}};
            next if(!$FromRevision || !$ToRevision || $FromRevision eq $ToRevision);
            
            my $raChanges = $p4->changes("$File$FromRevision,$ToRevision");
            warn("ERROR: cannot p4 changes: ", @{$p4->Errors()}) if($p4->ErrorCount());
            foreach(@{$raChanges})
            {
                my($Change, $User) = /^Change (\d+) on.*?by ([^@]*)/;
                my $raDescribe = $p4->describe("-s", $Change); 
                warn("ERROR: cannot p4 describe: ", @{$p4->Errors()}) if($p4->ErrorCount());
                my @Files;
                foreach(@{$raDescribe})
                {
                    if(my($File) = /(\/\/.+?)\#\d+/)
                    {
                        push(@Files , $File) unless(@RevisionExcludes &&  $File =~ /$RevisionExcludesRE/);
                    }
                }
                push(@{$Changes{$User}}, [$Change, \@Files]) if(@Files);
            }
        }
        foreach my $User (keys(%Changes))
        {
            next if($User eq "builder");
            foreach(@{$Changes{$User}})
            {
                ($Change, $raFiles) = @{$_};
                foreach my $File (@{$raFiles})
                {
                    $File =~ s/^\/\/([^\/]+\/){3}/\$SRC_DIR\//;
                    foreach my $Unit (keys(%Issues))
                    {
                        my($Errors, $Area) = @{$Issues{$Unit}};
                        my $AreaUnit = "$Area.$Unit";
                        ${${$Users{$User}}[1]}{$AreaUnit} = undef if(exists(${$g_read{$AreaUnit}}{$File}));
                    }
                }
            }
            push(@{${$Users{$User}}[0]}, $Change) if(exists($Users{$User}));
        }
    }
    return(\%Issues, \%Users, \%Depends);
}

sub NSDTransfert 
{
    my($Folder) = @_;
    return unless($NSD && -e "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$Folder");
    
    (my $FolderPath = "$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$Folder") =~ s/\\/\//g;
    while($FolderPath =~ s/[^\/.]+[\/]\.\.[\/]//g) { }
    (my $FolderName = $FolderPath) =~ s/[\\\/]/-/g;    
    my $NSD_DIR = $ENV{NSD_DIR};
    (my $drop_dir = $DROP_NSD_DIR) =~ s/\\/\//g;

    eval
    {
        print SOAP::Lite->uri("$ENV{GLOBAL_REPLICATION_SERVER}/gr_trig")->proxy("$ENV{GLOBAL_REPLICATION_SERVER}:1080/cgi-bin/trigger-gr")->dailyBuild('john,doe', "$drop_dir/$FolderPath,$Project/$FolderPath,")->result();
    };
    warn("ERROR: NSD transfert failed: $@; $!") if($@);
}

sub QACStep
{
    my $StartTime = time();
    xLogOpen( "$OUTLOG_DIR/Build/qac_step.log" );
    xLogH2("Build start: ".time());

    xLogH1("QAC registration...\n");
    my @StartQAC = Today_and_Now();
    QACRegistration();
    xLogH1(sprintf("QAC took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartQAC, Today_and_Now()))[1..3], scalar(localtime())));

    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/qac_step.log", 1, "step", "QAC");  
    Dashboard("QAC");
}

sub GTxRecording($;$)
{
	my($CurrentGTxPRGNAME,$bRegisterAll)=@_;
	
	my($ss, $mn, $hh, $dd, $mo, $yy) = (gmtime(time))[0..5];
	my $gmttime = sprintf("%04d/%02d/%02d:%02d:%02d:%02d", $yy+1900, $mo+1, $dd, $hh, $mn, $ss);
	my($Year, $Month, $Day, $Hour, $Minute, $Second) = $gmttime =~ /^(\d{4})\/(\d{2})\/(\d{2}):(\d{2}):(\d{2}):(\d{2})$/;
    
    my $CMDBase = "$JAVA -jar $CURRENTDIR/registerbuildgtx.jar";
    $CMDBase .= " -U $GTxUsername" if($GTxUsername);
    $CMDBase .= " -P $GTxPassword" if($GTxPassword);
    $CMDBase .= " -s $GTxSID";
    $CMDBase .= " -h $GTxHostname" if($GTxHostname);
    $CMDBase .= " -p $GTxProtocol" if($GTxProtocol);
    $CMDBase .= " -v $GTxVerbose" if($GTxVerbose);
    $CMDBase .= " prg=$GTxPRG" if($GTxPRG);
	$CMDBase .= " prgname=\"$CurrentGTxPRGNAME\"";

    foreach (@GTxPackages)
    {
        my($GTxPackage, $GTxExtend, $GTxLanguage, $GTxPatch, $GTxReplicationSites) = @{$_};
		my $PACKAGE_PATH = "packages";
        my $CMD = " id=$ENV{BOTAG}";
        $CMD .= " date=$Year-$Month-$Day";
        $CMD .= " time=$Hour:$Minute:$Second";
        $CMD .= " extend=\"$GTxExtend\"";
        $CMD .= " context=$Context";
        $CMD .= " platform=$PLATFORM";
        $CMD .= " language=$GTxLanguage";
        my $CMDPACKAGE .= " package=$GTxPackage";
		my $PathList = "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$PACKAGE_PATH/$GTxPackage";
		if($^O eq "MSWin32"){
			$Setup    = (-f "/package/$GTxPackage.msi") ?  "/$PACKAGE_PATH/$GTxPackage.msi" : "/setup.exe";
			$Setup =~ s/\//\\/g; 
		}
		else 
		{ 
			$Setup = (-f "/DISK_1/install.sh") ? "/DISK_1/install.sh" : "/setup.sh";
			$Setup =~ s/\\/\//g;
		}
		my $LABEL = " label="."$ENV{BOTAG}".".$GTxPackage"."_$Context";
		my $CMDPACKAGE_PATH = " path=$PathList$Setup";
        my $LOCALSITE = " site=" . ($GTxsite ? $GTxsite : $GTxSites{$ENV{SITE}});
		my $execute = "$CMDBase"."$CMDPACKAGE"."$CMD"."$LABEL"."$LOCALSITE"."$CMDPACKAGE_PATH";
		#package registration
		#print $execute."\n";
		xLogRun($execute);
		
		next if("no" =~ /$bRegisterAll/i);

		# replication sites for packages
		if ($GTxReplicationSites) {
			@GTxReplicationSites = split('\s*:\s*', $GTxReplicationSites);
			foreach $GTxReplicationSite (@GTxReplicationSites) {
				my $remotedropdir = Site::getremotedropdir($GTxReplicationSite);
				my $REMOTESITE = " site=".$GTxReplicationSite;
				$PathList = $remotedropdir."/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$PACKAGE_PATH/$GTxPackage";
				$CMDPACKAGE_PATH = " path=$PathList$Setup";
				$execute = "$CMDBase"."$CMDPACKAGE"."$CMD"."$LABEL"."$REMOTESITE"."$CMDPACKAGE_PATH". " prereg";
				#print $execute."\n";
				xLogRun($execute);
			}
		}

		# patches
		if (($GTxPatch) && ($GTxPatch eq "yes")) {
            foreach my $PACKAGE_PATH (qw(patches oneinstaller))
            {
                my $Extension = $PACKAGE_PATH eq 'patches' ? 'Patch' : 'One';
                my $CMDPATCH .= " package=$GTxPackage"."_$Extension";
                $PathList = "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$PACKAGE_PATH/$GTxPackage"."_$Extension";
                if($^O eq "MSWin32"){
                    $Setup    = (-f "/$PACKAGE_PATH/$GTxPackage.msi") ?  "/$PACKAGE_PATH/$GTxPackage.msi" : "/setup.exe";
                    $Setup =~ s/\//\\/g;
                }
                else 
                { 
                    $Setup = (-f "/DISK_1/install.sh") ? "/DISK_1/install.sh" : "/setup.sh";
                    $Setup =~ s/\\/\//g;
                }
                $CMDPATCHES_PATH = " path=$PathList$Setup";
                $LABEL = " label="."$ENV{BOTAG}".".$GTxPackage"."_$Extension"."_$Context";
                $execute = "$CMDBase"."$CMDPATCH"."$CMD"."$LABEL"."$LOCALSITE"."$CMDPATCHES_PATH";
                # patch registration for each defined package
                #print $execute."\n";
                xLogRun($execute);

                # replication sites for patches
                if ($GTxReplicationSites) {
                    foreach $GTxReplicationSitePatches (@GTxReplicationSites) {
                        my $remotedropdir_patch = Site::getremotedropdir($GTxReplicationSitePatches);
                        my $REMOTESITE = " site=".$GTxReplicationSitePatches;
                        my $PathListPatch = $remotedropdir_patch."/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$PACKAGE_PATH/$GTxPackage"."_$Extension";
                        my $CMDPACKAGE_PATH_PATCH = " path=$PathListPatch$Setup";
                        $execute = "$CMDBase"."$CMDPATCH"."$CMD"."$LABEL"."$REMOTESITE"."$CMDPACKAGE_PATH_PATCH". " prereg";
                        #print $execute."\n";
                        xLogRun($execute);
                    }
                }
            }
        }
    }
}
sub GTxStep
{
    my $StartTime = time();
    xLogOpen( "$OUTLOG_DIR/Build/gtx_step.log" );
    xLogH2("Build start: ".time());
    xLogH1("GTx registration...\n");
    my @StartGTx = Today_and_Now();

    # Syntax can be 
    # GTxPRGNAME=MY_PROGNAME    -> default value will be yes to register all
    # GTxPRGNAME=MY_PROGNAME:no -> Only the build will be registered in the GTx without replications & others
    # GTxPRGNAME=MY_PROGNAME1:no;MY_PROGNAME2;MY_PROGNAME3:yes -> all registrations (replications, ...) will be done for this build on programs MY_PROGNAME2 & 3 while MY_PROGNAME1 will be only registered in GTX without replications & others
    # :<no or yes> value following the program name is optional and is yes by default
    foreach my $prgNameAndRegisterMode (split(/\s*;\s*/,$GTxPRGNAME))
	{
		my($prgName, $prgRegisterMode)=split(/\s*:\s*/,$prgNameAndRegisterMode);
		# If this is the first loop or that all registrations has been asked for all programs say yes at the last param
		GTxRecording($prgName,$prgRegisterMode || "yes");
	}

    xLogH1(sprintf("GTx took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartGTx, Today_and_Now()))[1..3], scalar(localtime())));
    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/gtx_step.log", 1, "step", "GTx");  
    Dashboard("GTx");
}

sub QACRegistration
{
    my $ClassPath = $^O eq "MSWin32" ? ".;axiom-api-1.2.5.jar;axiom-impl-1.2.5.jar;axis2-adb-1.3.jar;axis2-kernel-1.3.jar;commons-codec-1.3.jar;commons-httpclient-3.0.1.jar;commons-logging-1.1.jar;createbuild.jar;junit-4.4.jar;opencsv.jar;QACWSClient.jar;QACWSSDK.jar;wsdl4j-1.6.2.jar;XmlSchema-1.3.2.jar" : ".:axiom-api-1.2.5.jar:axiom-impl-1.2.5.jar:axis2-adb-1.3.jar:axis2-kernel-1.3.jar:commons-codec-1.3.jar:commons-httpclient-3.0.1.jar:commons-logging-1.1.jar:createbuild.jar:junit-4.4.jar:opencsv.jar:QACWSClient.jar:QACWSSDK.jar:wsdl4j-1.6.2.jar:XmlSchema-1.3.2.jar";
    chdir($CURRENTDIR) or warn("ERROR: cannot chdir '$CURRENTDIR': $!");

    if(@QACPackages)
    {
        my $sReg = sub
        {
            my($mPathList, $mSetup, $mTest, $mQACextent, $mSuite, $mPhases, $reference, $Name, $BuildType, $mContext, $mPlatform) = @_;
            foreach my $mPhase (split('\s*;\s*', $mPhases))
            {
                next unless($mContext || ($mPhase && $mPhase !~ /^\s*$/));
                $mPhase       =~ s!^\s*!!;
                $mPhase       =~ s!\s*$!!;
                $mQACextent   =~ s!^\s*!!;
                $mQACextent   =~ s!\s*$!!;
                
                my $CMD = "$JAVA -classpath $ClassPath build.createbuild";
                $CMD .= " context=$mContext" if($mContext && $mContext!~/^\s*$/);
                $CMD .= " db=$QACdb" if($QACdb);
                $CMD .= " batch=$QACbatch" if($QACbatch);
                $CMD .= " suite=\"$mSuite\"" if($mSuite);
                $CMD .= " buildpriority=$QACbuildpriority" if($QACbuildpriority);
                $CMD .= " phase=\"$mPhase\"" if($mPhase);
                $CMD .= " user=$QACuser" if($QACuser);
                $CMD .= " extent=\"$mQACextent\"" if($mQACextent);
                $CMD .= " language=\"$QAClanguage\"" if($QAClanguage);
                $CMD .= " pathlist=\"$mPlatform=$mPathList\"" if($mPathList);
                $CMD .= " test=$mTest" if($mTest);
                $CMD .= " site=" . ($QACsite ? $QACsite : $QACSites{$ENV{SITE}});
                if($mTest eq "yes")
                {
                    unless(-e $mSetup) { warn("WARNING: setup '$mSetup' not found"); return }   
                    unless(open(VER, "$mPathList/ProductId.txt")) { warn("ERROR: cannot open '$mPathList/ProductId.txt': $!"); return } 
                    my($QACname) = <VER> =~ /BuildVersion\s*=\s*(.+)$/;
                    close(VER);
                    if ( $mQACextent =~ /64/) { $QACname = $QACname."_64" }
                    if($reference) { $CMD .= ($QACpatchType ? " type=$QACpatchType" : "") . " reference=\"$reference\"  name=\"${QACname}_Patch\"" }
                    else { $CMD .= ($QACtype ? " type=$QACtype" : "") . " name=\"$QACname\"" }
                }
                else { $CMD .= ($QACtype ? " type=$QACtype" : "") . " name=\"$ENV{BOTAG}.$BuildType\" checksetup=no" }
                print("$CMD\n");
                eval{ warn("WARNING: $Name registration failed with error code $?") if(system($CMD)) };
                warn("WARNING: $Name registration failed with msg '$@'") if($@);
            }
        };

        foreach my $qacContext (split('\s*;\s*', $QACcontext))
        {
            foreach (@QACPackages)
            {
                my($Name, $BuildType, $QACextent, $Suite, $Phase, $Reference) = @{$_};
                my $Setup;
                $Suite ||= $QACsuite;
                $Phase ||= $QACphase;
                my $PathList = "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/packages/$Name";
                if($^O eq "MSWin32"){
                    $PathList =~ s/\//\\/g; 
                    $Setup    = (-f "$PathList/package/$Name.msi") ?  "$PathList/package/$Name.msi" : "$PathList/setup.exe";
                }
                else 
                { 
                    $Setup = (-f "$PathList/DISK_1/install.sh") ? "$PathList/DISK_1/install.sh" : "$PathList/setup.sh";
                    $PathList =~ s/\\/\//g; 
                }
                &$sReg($PathList, $Setup, $QACtest, $QACextent, $Suite, $Phase, $Reference, $Name, $BuildType, $qacContext, $PLATFORM);
                if($Reference && $QACpatchType)
                { 
                    (my $PatchList = $PathList) =~ s/([\\\/])packages([\\\/][^\\\/]+$)/$1patches$2/i;
                     my $PatchSetup = $^O eq 'MSWin32' ? "$PatchList".'\\package\\'."$Name".'.msp' : "$PatchList".'/DISK_1/install.sh';
                     &$sReg($PatchList, $PatchSetup, $QACtest, $QACextent, $Suite, $Phase, $Reference, $Name, $BuildType, $qacContext, $PLATFORM);
                }
            }
        }
    }
    else 
    {
        my $CMD = "$JAVA -classpath $ClassPath -Djava.security.policy=file:QAC_CreateBuild.policy build.createbuild";
        $CMD .= " db=$QACdb" if($QACdb);
        $CMD .= " batch=$QACbatch" if($QACbatch);
        $CMD .= " suite=\"$QACsuite\"" if($QACsuite);
        $CMD .= " buildpriority=$QACbuildpriority" if($QACbuildpriority);
        $CMD .= " phase=\"$QACphase\"" if($QACphase);
        $CMD .= " user=$QACuser" if($QACuser);
        $CMD .= " language=\"$QAClanguage\"" if($QAClanguage);
        $CMD .= " test=$QACtest" if($QACtest);
        $CMD .= " type=$QACtype" if($QACtype);
        $CMD .= " site=" . ($QACsite ? $QACsite : $QACSites{$ENV{SITE}});
        $CMD .= " name=\"$ENV{BOTAG}.$Context\" extent=\"Products\" pathlist=\"$PLATFORM=$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE\" checksetup=no";
        foreach my $qacContext (split('\s*;\s*', $QACcontext))
        {
            $CMD .= " context=$qacContext" if($qacContext && $qacContext!~/^\s*$/);
            print("$CMD\n");
            xLogRun($CMD);
        }
    }
}

sub ASTECStep
{
    my($PkgName, $Is32to64) = @_;
    
    my $StartTime = time();
    xLogOpen( "$OUTLOG_DIR/Build/astec_step.log" );
    xLogH2("Build start: ".time());

    xLogH1("ASTEC registration...\n");
    my @StartASTEC = Today_and_Now();

    my $Platform = $Is32to64 ? $Platform32to64{$PLATFORM} : $PLATFORM;
    my $ObjectModel = $Is32to64 ? '64' : $OBJECT_MODEL; 
    my @Setups;
    if($PkgName)
    {
        my $Setup = "$DROP_DIR/$Context/$BuildNumber/$Platform/$BUILD_MODE/packages/$PkgName/" . (($^O eq "MSWin32") ? "setup.exe" : "setup.sh");
        ($^O eq "MSWin32") ? $Setup =~ s/\//\\/g : $Setup =~ s/\\/\//g;
        if(-e $Setup) { push(@Setups, [$PackageName, $Setup]) }
        else { warn("ERROR: '$Setup' does not exist\n") }
    }
	else
	{
	    foreach my $pkg (qw(packages patches oneinstaller))
	    {
	        next unless(${"ASTEC$pkg"});
	        foreach my $PackageName (split(/\s*,\s*/, ${"ASTEC$pkg"}))
	        {        
	            my $Setup = "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$pkg/$PackageName/" . (($^O eq "MSWin32") ? "setup.exe" : "setup.sh");
	            ($^O eq "MSWin32") ? $Setup =~ s/\//\\/g : $Setup =~ s/\\/\//g;
	            unless(-e $Setup) { warn("ERROR: '$Setup' does not exist"); next }
	            push(@Setups, [$PackageName, $Setup]);
	        }
		}
    }
    if(@Setups)
    {
        my $ASTECPath = "$ASTEC_DIR/$Project/$Context/$Platform";
        mkpath($ASTECPath) or warn("ERROR: cannot mkpath '$ASTECPath': $!") unless(-e $ASTECPath);
        my @TriggerFiles = $PkgName ? ("$PkgName.buildInfo.txt") : ("buildInfo.txt", "nightly.txt");
        foreach my $ASTECTriggerFile (@TriggerFiles)
        {
            next if($ASTECTriggerFile eq "nightly.txt" && $BuildNumber =~ /\./);
            if(open(ASTEC,">$ASTECPath/$ASTECTriggerFile"))
            {
            	$ASTECsuite ||= $Project;
                print(ASTEC "ARCHITECTURE=$ObjectModel\n");
                print(ASTEC "BUILD_INI_FILE=", basename($Config), "\n");
                print(ASTEC "BUILD_VERSION=$BuildNumber\n");
                print(ASTEC "BUILD_MODE=$BUILD_MODE\n");
                print(ASTEC "suite=", $ASTECsuite||'', "\n");
                for(my $i=0; $i<@Setups; $i++) 
                {        
                    my($PackageName, $SetupPath) = @{$Setups[$i]};
                    $SetupPath =~ s/[\\\/][^\\\/]+$//;
                    print(ASTEC "SETUP_PATH=$SetupPath\n") unless($i);
                    print(ASTEC "SETUP_PATH_$PackageName=$SetupPath\n");
                    print(ASTEC "TARGET_PLATFORM_$PackageName=$Platform\n");
                    print(ASTEC "TARGET_PACKAGE_$PackageName=$PackageName\n");
                }
                print(ASTEC "BUILD_PRODUCT_VERSION=$Version\n");
                print(ASTEC "BUILD_STREAM=$Context\n");
                close(ASTEC);
            } else { warn("ERROR: cannot create '$ASTECPath/$ASTECTriggerFile'") }
        }
    }
        
    xLogH1(sprintf("ASTEC registration took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@StartASTEC, Today_and_Now()))[1..3], scalar(localtime())));
    xLogH2("Build stop: ".time());
    xLogClose();
    submitbuildresults("$OUTLOG_DIR/Build/astec_step.log", 1, "step", "ASTEC");  
    Dashboard("ASTEC");
}

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
                next if(grep(/^$Key:/, @Sets));
                $Value = ExpandVariable(\$Value) if($Key=~/^PATH/);
                $Value = ExpandVariable(\$Value) if($Value =~ /\$\{$Key\}/);                
                ${$Key} = $Value;
                $ENV{$Key} = $Value;
                Monitor(\${$Key}); Monitor(\$ENV{$Key});
            }
            elsif($Section eq "localvar") 
            { 
                my($Platform, $Var) = split('\s*\|\s*', $_);
                unless($Var) { $Platform="all"; $Var=$_ }
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL); 
                my($Key, $Value) = $Var =~ /^(.*?)=(.*)$/;
                next if(grep(/^$Key:/, @Sets));
                $Value = ExpandVariable(\$Value) if($Value =~ /\$\{$Key\}/);
                ${$Key} = $Value;
                Monitor(\${$Key});
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

sub MatchFileInContext
{
    my($File, $Revision) = @_;    

    my($CtxtFile) = $Revision =~ /^=(.+)$/;    
    $CtxtFile .= "/$1.context.xml" if($CtxtFile =~ /([^\\\/]+)[\\\/]\d+$/);
    $CtxtFile = "$IMPORT_DIR/$CtxtFile" unless(-e $CtxtFile);
    die("ERROR: cannot open '$CtxtFile': $!") unless(-e $CtxtFile); 
    my $BuildRev;
    eval
    {
        my $CONTEXT = XML::DOM::Parser->new()->parsefile($CtxtFile);  
        $BuildRev = $CONTEXT->getElementsByTagName("version")->item(0)->getFirstChild()->getData();
        for my $COMPONENT (reverse(@{$CONTEXT->getElementsByTagName("fetch")}))
        {
            my($DepotSource, $Rev) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute("revision"));
            $DepotSource =~ s/\*/\[^\\\/\\\\\]\*/g;
            $DepotSource =~ s/^\+//;
            if($File =~ /$DepotSource/) { $Revision=$Rev; last };
        }
        if($Revision =~ /^=/)
        {
            for my $COMPONENT (reverse(@{$CONTEXT->getElementsByTagName("fetch")}))
            {
                my($DepotSource, $Rev) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute("revision"));
                $DepotSource =~ s/[\\\/]export[\\\/]\.\.\./\/\.\.\./;
                $DepotSource =~ s/\*/\[^\\\/\\\\\]\*/g;
                $DepotSource =~ s/^\+//;
                if($File =~ /$DepotSource/) { $Revision=$Rev; last };
            }
        }
        if($Revision =~ /^=/)
        {
            for my $COMPONENT (reverse(@{$CONTEXT->getElementsByTagName("fetch")}))
            {
                my($DepotSource, $Rev) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute("revision"));
                $DepotSource =~ s/\*/\[^\\\/\\\\\]\*/g;
                $DepotSource =~ s/^\+//;
                (my $StrippedFile = $File) =~ s/[\\\/]export[\\\/]\.\.\./\/\.\.\./;
                if($StrippedFile =~ /$DepotSource/) { $Revision=$Rev; last };
            }
        }
        if($Revision =~ /^=/)
        {
            for my $COMPONENT (reverse(@{$CONTEXT->getElementsByTagName("fetch")}))
            {
                my($DepotSource, $Rev) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute("revision"));
                $DepotSource =~ s/(\/(?:\/[^\/]+){4}).+/$1/;
                $DepotSource =~ s/\*/\[^\\\/\\\\\]\*/g;
                $DepotSource =~ s/^\+//;
                if($File =~ /$DepotSource/) { $Revision=$Rev; last };
            }
        }
        $CONTEXT->dispose();                
    };
    die("ERROR: cannot parse '$CtxtFile': $@; $!") if($@);
    return ($Revision, $BuildRev);
}

sub SendMail {
    return unless($SMTPTO_FOR_DIE);
    my @Messages = @_;
    
    open(HTML, ">$TEMPDIR/Mail$$.htm") or die("ERROR: cannot open '$TEMPDIR/Mail$$.htm': $!");
    print(HTML "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n");
    print(HTML "<html>\n");
    print(HTML "\t<head>\n");
    print(HTML "\t</head>\n");
    print(HTML "\t<body>\n");
    print(HTML "*****This email has been sent from an unmonitored automatic mailbox.*****<br/><br/>\n");
    print(HTML "Hi everyone,<br/><br/>\n");
    print(HTML "&nbsp;"x5, "We have the following error(s) in $0 on $HOST in build $ENV{BUILD_NAME} on $ENV{PLATFORM}/$ENV{BUILD_MODE}<br/>\n");
    foreach (@Messages) {
        print(HTML "&nbsp;"x5, "$_<br/>\n");
    }
    my $i = 1;
    print(HTML "Stack Trace:<br/>\n");
    while((my ($FileName, $Line, $Subroutine) = (caller($i++))[1..3])) {
        print(HTML "File \"$FileName\", line $Line, in $Subroutine.<br/>\n");
    }
    print(HTML "<br/>Best regards\n");
    print(HTML "\t</body>\n");
    print(HTML "</html>\n");
    close(HTML);

    my $smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60) or warn("ERROR: SMTP connection impossible: $!");
    $smtp->mail($SMTPFROM);
    $smtp->to(split('\s*;\s*', $SMTPTO_FOR_DIE));
    $smtp->data();
    $smtp->datasend("To: $SMTPTO_FOR_DIE\n");
    $smtp->datasend("Subject: [$0] Errors on $HOST in build $ENV{BUILD_NAME} on $ENV{PLATFORM}/$ENV{BUILD_MODE}\n");
    $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
    open(HTML, "$TEMPDIR/Mail$$.htm") or warn ("ERROR: cannot open '$TEMPDIR/Mail$$.htm': $!");
    while(<HTML>) { $smtp->datasend($_) } 
    close(HTML);
    $smtp->dataend();
    $smtp->quit();

    unlink("$TEMPDIR/Mail$$.htm") or warn("ERROR: cannot unlink '$TEMPDIR/Mail$$.htm': $!");
}

sub SubmitContext
{
    my($ClientForContext, $XMLContext) = @_;
    
    if($SubmitContext && $Dashboard && !$Polling && (!defined($ContextParameter) || $ContextParameter =~ /^\d{2}:\d{2}:\d{2}$/))
    {
        # P4 submit #
        if($p4)
        {
            my $Submit = 0;
            $p4->SetOptions("-c \"$ClientForContext\"");
            my $raDiff = $p4->diff("-f", $XMLContext);
            if($p4->ErrorCount())
            {
                if(${$p4->Errors()}[0]=~/file\(s\) not on client\./)
                {
                    $p4->add($XMLContext); 
                    if($p4->ErrorCount()) { warn("ERROR: cannot 'add': ", @{$p4->Errors()}) }
                    else { $Submit = 1 }
                } else { warn("ERROR: cannot p4 diff '$XMLContext' : ", @{$p4->Errors()}) }
            }
            elsif(@{$raDiff} > 1)
            {
                $p4->edit($XMLContext);
                if($p4->ErrorCount()) { warn("ERROR: cannot p4 edit '$XMLContext' : ", @{$p4->Errors()}) }
                else { $Submit = 1 }
            }               
            if($Submit)
            {
                $p4->resolve("-ay", $XMLContext);
                if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/no file\(s\) to resolve.$/) { warn("ERROR: cannot p4 resolve '$XMLContext' : ", @{$p4->Errors()}) }
                else
                { 
                    my $rhChange = $p4->fetchchange();
                    if($p4->ErrorCount()) { warn("ERROR: cannot p4 fetch change '$XMLContext' : ", @{$p4->Errors()}) }
                    else
                    {
                        ${$rhChange}{Description} = ["Summary*:$Context | $BuildName", "What*:$Context | $BuildName", "Reviewed by*:ditabuild"];
                        @{${$rhChange}{Files}} = grep({/$Context\.context\.xml/||/\.context\.zip/} @{${$rhChange}{Files}});
                        my $raChange = $p4->savechange($rhChange);
                        warn("ERROR: cannot p4 save change '$XMLContext' : ", @{$p4->Errors()}) if($p4->ErrorCount());
                        my($Change) = ${$raChange}[0] =~ /^Change (\d+)/;
                        $p4->submit("-c$Change") if($Change);
                        if($p4->ErrorCount())
                        { 
                            warn("ERROR: cannot p4 submit '$XMLContext' : ", @{$p4->Errors()});
                            $p4->revert($XMLContext);
                            if($p4->ErrorCount()) { warn("ERROR: cannot p4 revert  '$XMLContext' : '$XMLContext'", @{$p4->Errors()}) }
                            $p4->change("-d", $Change);
                            if($p4->ErrorCount()) { warn("ERROR: cannot p4 delete change '$XMLContext' : '$Change'", @{$p4->Errors()}) }
                        }
                        else
                        {
                            mkpath("$OUTPUT_DIR/obj") or warn("ERROR: cannot mkpath '$OUTPUT_DIR/obj': $!") unless(-d "$OUTPUT_DIR/obj");        
                            open(METADATA, ">$OUTPUT_DIR/obj/releaseMetadata.txt") or warn("ERROR: cannot open '$OUTPUT_DIR/obj/releaseMetadata.txt': $!");
                            print(METADATA "$P4PortForContext $Change $XMLContext\n");
                            print(METADATA "$BuildName $BuildDate");
                            close(METADATA);
                        }
                    }
                }
            }
        }
        # GIT submit #
        if($ENV{GITCONTEXT})
        {
            my($Repository, $Branch, $Filepattern) = $ENV{GITCONTEXT} =~ /^([^=]+)[\\\/]([^\\\/=]+)=?(.*)$/;
            ($Filepattern) = $XMLContext =~ /([^\\\/]+)$/ unless($Filepattern);
            my($FilePath, $FileName) = $Filepattern =~ /^(.*?)[\\\/]?([^\\\/]+)$/;
            $FilePath = $FilePath ? "$TEMPDIR/$$/$Branch/$FilePath" : "$TEMPDIR/$$/$Branch"; 
            rmtree("$TEMPDIR/$$") or warn("ERROR: cannot rmtree '$TEMPDIR/$$': $!") if(-e "$TEMPDIR/$$");
            mkpath("$TEMPDIR/$$") or warn("ERROR: cannot mkpath '$TEMPDIR/$$': $!");        
            chdir("$TEMPDIR/$$") or warn("ERROR: cannot chdir '$TEMPDIR/$$': $!");
            system("git clone -b $Branch $Repository $Branch");
            mkpath($FilePath) or warn("ERROR: cannot mkpath '$FilePath': $!");        
            copy($XMLContext, "$FilePath/$FileName") or warn("ERROR: cannot copy '$XMLContext': $!");
            chdir($FilePath) or warn("ERROR: cannot chdir '$FilePath': $!");
            system("git add $FileName");
            system("git commit $FileName -m \"$Context | $BuildName What*:$Context $BuildName Reviewed by*:pblack\"");
            system("git push $Repository $Branch");
            chdir($CURRENTDIR) or warn("ERROR: cannot chdir '$CURRENTDIR': $!");
            rmtree("$TEMPDIR/$$") or warn("ERROR: cannot rmtree '$TEMPDIR/$$': $!");
        }
    }
}

sub Usage
{
   print <<USAGE;
   Usage   : Build.pl [option]+ [step]+
   Example : Build.pl -h
             Build.pl -i=saturn.ini -All

   [option]
   -help|?        argument displays helpful information about builtin commands.
   -a.rea         build only the specified area. Syntax is -a=area[:unit,...]
   -c.ontext      specifies the project context file.
   -d.ashboard    update the dashboard (-d.ashboard) or not (-nod.ashboard), default is -nodashboard. 
   -e.xport       export only the specified target. Syntax is -e=packages,patches,bin,deploymentunits,logs,prepackage,pdb, by default it exports all these folders
   -fc.lean       force the opened and hijacked clean (-fc.lean) or not (-nofc.lean), default is -nofclean.
   -fs.ync        force the resynchronisation (-fs.ync) or not (-nofs.ync), default is -nofsync.
   -g.it_timediff specifies the difference of two servers p4 and git 
   -i.ni          specifies the configuration file.
   -j.ob          specifies the job file (optional, used when called by the queuing server)
   -la.beling     create label (-la.beling) or not (-nola.beling), default is -nolabeling.
   -le.go         updates lego dashboard (-le.go) or not (-nole.go), default is -lego.
   -lo.calrepo    force the update of the repository (yes) or not (no or maven local repository path), default is yes 
   -m.ode         debug or release or releasedebug, default is release.
   -ns.d          specifies NSD transfert (-ns.d) or not (-non.sd), default is -nsd.
   -pol.ling      wait checked files (-p.olling) or not (-nop.olling), default is -nop.olling.
   -pom           updates pom from P4 (-pom) or not (-nopom), default is -pom.
   -q.set         sets environment variables. Syntax is -q=variable:string
   -r.ank         specifies the rank of the computer, default is 1.
   -s.haring      specifies the number of computers, default is 1.
   -t.arget       build only specific targets from the ini file.
   -u.pdate	      force the P4 client to be updated regarding the current .ini configuration file or not (-nou.pdate), default is -update.
   -v.ersion      specifies the build number, by default the previous build number is incremented.
   -wo.rdy        specifies log verbose level (0..3), default is 0.
   -wa.rning      specifies warning level (valid values are 0-2), default is 2.
   -64            force the 64 bits compilation (-64) or not (-no64), default is -no64 i.e 32 bits.

   [step]
   -All         do all following steps (except Mail & Depends steps).
   -C.lean      do the clean step (-C.lean) or not (-noC.lean), default is -noClean.
   -H.elpfetch  do the prefetch step (-Helpfetch) or not (-noH.elpfetch), default if -noH.elpfetch.
   -F.etch      do the fetch step (-F.etch) or not (-noF.etch), default is -noFetch.
   -V.ersion    do the versioning step (-V.ersion) or not (-noV.ersion), default is -noVersion.
   -I.mport     do the import step (-I.mport) or not (-noI.mport), default is -noImport.
   -B.uild      do the build step (-B.uild) or not (-noB.uild), default is -noBuild.
   -D.epends    do the dependencies analyzis step (-D.ependencies do) or not (-noD.ependencies), default is -noD.epends
   -P.ackage    do the package step (-P.ackage) or not (-noP.ackage), default is -noPackage.
   -E.xport     do the export step (-E.xport) or not (-noE.xport), default is -noExport.
   -G.Tx        do the GTx registration step (-G.Tx) or not (-noG.Tx), default is -noGTx.
   -Q.AC        do the QAC registration step (-Q.AC) or not (-noQ.AC), default is -noQAC.
   -Z.TEC       do the ZTEC (ASTEC) step (-Z.TEC) or not (-noZ.TEC), default is -noZTEC.
   -R.eport     do the full report step (-R.eport) or not (-noR.eport), default is -noReport.
   -N.ews       do the news feeds RSS step (-N.ews) or not (-noN.ews), default is -noNews.
   -T.est       do the test step (-T.est) or not (-noT.test), default is -noTest.
   -S.moke      do the smoke test step (-S.moke) or not (-noS.moke), default is -noSmoke.
   -W.alidation do the validation test (BAT) step (-W.alidation) or not (-noW.alidation), default is -noWalidation.
   -M.ail       do the mail step (-M.ail) or not (-noM.ail), default is -noMail.
USAGE
    exit;
}
exit($BuildResult);
