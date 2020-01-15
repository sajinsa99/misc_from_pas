#!/usr/bin/perl -w
use FindBin qw($Bin);
use lib ("$Bin", "$Bin/site_perl");

# core
use Sys::Hostname;
use Getopt::Long;
use File::Path;
use File::Basename;
use Cwd 'abs_path';

# site
use Date::Calc(qw(Today_and_Now Delta_DHMS));
# local
use Site;
use Perforce;
use Dependencies;
use XDepUploadDB;
# Required for multi-platform Depends, each Depends-(MSWin32,...).pl will contain platform specific code...
use Depends;

require "Depends/Depends-".$^O.".pl";
# End required for multi-platform Depends...
################################################################################################################
# Methods declaration
#########################################################################################################################
if($^O eq "MSWin32")    { $PLATFORM = "win32_x86"; }
elsif($^O eq "solaris") { $PLATFORM = "solaris_sparc" }
elsif($^O eq "aix")     { $PLATFORM = "aix_rs6000" }
elsif($^O eq "hpux")    { $PLATFORM = "hpux_pa-risc" }
elsif($^O eq "linux")   { $PLATFORM = "linux_x86" }
$HOST       = hostname();
$CASE_SENSITIVE=0; # if 0 case is insensitive else case is sensitive... 

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help,
"ini=s"		=>\$Config,
"Client:s"	=>\$Client,
"gmake=s"	=>\$Makefile,
"mode=s"	=>\$BUILD_MODE,
"directory=s"	=>\$SRC_DIR,
"stream=s"	=>\$szStream,
"version=s"	=>\$szBuildNumber,
"buildname=s"	=>\$szBuildName,
"fill!"		=>\$bFillDatabase,
"errors!"   	=>\$bErrorsTesting,
);

Usage() if($Help);

unless($Makefile) { print(STDERR "the -g parameter is mandatory\n\n"); Usage() }
unless($szStream) { print(STDERR "the -s parameter is mandatory\n\n"); Usage() }

$BUILD_MODE ||= $ENV{BUILD_MODE} || "release";
if("debug"=~/^$BUILD_MODE/i) { $BUILD_MODE="debug" } elsif("release"=~/^$BUILD_MODE/i) { $BUILD_MODE="release" }
else { print(STDERR "ERROR: compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease]\n"); Usage() }

$CURRENTDIR = $FindBin::Bin;

ReadIni() if($Config) ;

$SRC_DIR    ||= $ENV{SRC_DIR};
unless($SRC_DIR) { print(STDERR "ERROR: The SRC_DIR environment variable (or -d option) is mandatory\n\n"); Usage() }
$SRC_DIR =~ s/[\/\\]/\//g;

$Client ||= $ENV{Client};
if(!defined($Client) || $Client eq "") { print(STDERR "ERROR: The Client environment variable (or -c argument) is mandatory\n\n"); Usage() }

($ROOT_DIR) = $ENV{ROOT_DIR} || ($SRC_DIR=~/^(.*)[\/\\]/);
$ROOT_DIR   =~ s/[\/\\]/${\Depends::get_path_separator()}/g;
$ENV{SRC_DIR}      = $SRC_DIR;
$ENV{ROOT_DIR}    ||= $ROOT_DIR;
$ENV{build_mode}  = $ENV{BUILD_MODE}  = $BUILD_MODE;
($ENV{OUTPUT_DIR} ||= ($ENV{OUT_DIR} || ($SRC_DIR=~/^(.*)[\\\/]/, "$1/$PLATFORM"))."/$BUILD_MODE")=~ s/[\/\\]/\//g;
$OUTPUT_DIR = $ENV{OUTPUT_DIR};
$ENV{OUTBIN_DIR} ||= $ENV{OUTPUT_DIR}."/bin";
#$OUTLOGDIR = "$ENV{OUTPUT_DIR}/logs".($Output?"/$Output":"");
#$SRC_DIR =~ s/[\/\\]/${\Depends::get_path_separator()}/g;
$szBuildNumber ||= $ENV{build_number};
if(!defined $szBuildNumber) 
	{ print(STDERR "ERROR: The build_number environment variable (or -v option) is mandatory\n\n"); Usage() }
$Context ||= $ENV{context};
$Context=$szBuildName if(defined $szBuildName); # Forcing to buildname if -b option set
if(!defined $Context) 
	{ print(STDERR "ERROR: The build/context name (-b or -i option) is mandatory\n\n"); Usage() }

## Read Makefile ##
my $MakefilePath;
my $MakefileName;
my $MakefileExtension;
{
	$Makefile=abs_path($Makefile); # First, get the absolute path to the current make file
	($MakefileName,$MakefilePath,$MakefileExtension)=fileparse($Makefile,'\..*'); # get directory, & basename of the makefile
	$MakefilePath=~ s/[\/\\]$//;
}

########
# Main #
########

printf("Starting...\n");
my @Start = Today_and_Now();

my $p4 = new Perforce;
$p4->SetClient($Client);
die("ERROR: cannot set client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount());


## Clean and Fetch ##
chdir($CURRENTDIR) or die("ERROR: cannot chdir '$CURRENTDIR': $!");

# If we have some errors in buildunits, so stop, do not continue because we need a green build if the -noe for no.error option is set !
my $nBuildErrors=0;
if(defined $bErrorsTesting && $bErrorsTesting==1)
{
	my %g_buildinfos;
	my $AllAreas=Build::GetAreasList($MakefileName, $Makefile);
	if($AllAreas)
	{
		foreach my $Area (@$AllAreas) # Load all data 
		{
			while (defined($next = <$ENV{OUTBIN_DIR}/$Area/depends/data/*.build>))  # scan .dat files in this directory
			{
				if(open (DATFILE, $next))
				{
					my @data=<DATFILE>; # read all the file & store it in data variable
					close(DATFILE);
					eval join("",@data);
					die("Errors in BUILD file (".$next.") : ".$@."\n") if($@); # evaluate file content to transform it into real PERL variables
				}
			}				
		}
	}
	foreach my $CurrentBuildEntry(keys %g_buildinfos)
	{
		if(exists $g_buildinfos{$CurrentBuildEntry}->[0])
		{
			my $nBuildUnitErrors=$g_buildinfos{$CurrentBuildEntry}->[0];
			$nBuildErrors=$nBuildErrors+$nBuildUnitErrors if($nBuildUnitErrors!=-1) ;
		}
	}
}

my @StartTask = Today_and_Now(); print "  Loading idcards at ".scalar(localtime())."\n";
my $DelivrableFiles = Dependencies::GetAllDelivrableFiles($OUTPUT_DIR, $CASE_SENSITIVE);
printf("    Number of found delivrable files in idcards: ".(defined $DelivrableFiles?(keys %$DelivrableFiles):0)."\n");
printf("  Loading idcards took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartTask, Today_and_Now()))[1..3]);
die("WARNING: No delivrable files found...\n") if(!defined $DelivrableFiles);

@StartTask = Today_and_Now(); print "  Loading dependencies data ('$ENV{OUTBIN_DIR}/depends/*.dependencies.*.dat') at ".scalar(localtime())."\n";
my $DependenciesLinks=Dependencies::InitializeDependencies($ENV{OUTBIN_DIR}, $MakefileName, $SRC_DIR, $OUTPUT_DIR, $CASE_SENSITIVE, Dependencies::PARENTS );
printf("  Loading dependencies data took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartTask, Today_and_Now()))[1..3]);

@StartTask = Today_and_Now(); print "  Loading P4 files list('$Client') at ".scalar(localtime())."\n";
my $raP4FilesList=$p4->Have();
die("ERROR: cannot retrieve P4 files '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount());

my %hashP4FilesList;
tie %hashP4FilesList , 'Tie::CPHash' if(!defined $CASE_SENSITIVE || $CASE_SENSITIVE==0);
foreach my $P4HaveEntry(@$raP4FilesList)
{
	next unless(my($DepotFile,$DiskFile) = $P4HaveEntry=~ /^(.+?)(?:#\d*)? - (.*)$/);
    $DiskFile=~ s/\\/\//g;
    $hashP4FilesList{$DiskFile}=$DepotFile;
}

printf("    Number of P4 files: ".(scalar @$raP4FilesList)."\n");
printf("  Loading P4 files list took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartTask, Today_and_Now()))[1..3]);

mkpath("$OUTPUT_DIR/logs/packages") or die("ERROR: cannot create '$OUTPUT_DIR/logs/packages': $!") unless(-e "$OUTPUT_DIR/logs/packages");

my %AlreadyAnalyzedClientFiles;
if(-e "$OUTPUT_DIR/logs/packages/$MakefileName.delivrables.done") # previous run interrupted, restart on undone job
{
    printf("  Reading recovery file: $OUTPUT_DIR/logs/packages/$MakefileName.delivrables.done\n");
    open(DEPENDENCIESDONE, "$OUTPUT_DIR/logs/packages/$MakefileName.delivrables.done") or die("ERROR: cannot open '$OUTPUT_DIR/logs/packages/$MakefileName.delivrables.done': $!");    
	while (defined(my $Line = <DEPENDENCIESDONE>))  
	{
		eval $Line;  
	}
    close(DEPENDENCIESDONE);
}
else # new job, add file header
{
	open(DEPENDENCIESRESULT, ">>$OUTPUT_DIR/logs/packages/$MakefileName.delivrables.dat") or die("ERROR: cannot open '$OUTPUT_DIR/logs/packages/$MakefileName.delivrables.dat': $!");
	print(DEPENDENCIESRESULT "[Params]\n");
	print(DEPENDENCIESRESULT "project=".$Context."\n");
	print(DEPENDENCIESRESULT "stream=".$szStream."\n");
	print(DEPENDENCIESRESULT "platform=".$PLATFORM."\n");
	print(DEPENDENCIESRESULT "revision=".int($szBuildNumber)."\n");
	print(DEPENDENCIESRESULT "datetime=".(localtime)."\n");
	
	print(DEPENDENCIESRESULT "\n[Mapping]\n");
	close(DEPENDENCIESRESULT);
}


@StartTask = Today_and_Now(); print "  Analyzing delivrable dependencies at ".scalar(localtime())."\n";
my $iCountFile=0;
my $iDelivrableFilesHavingP4Files=0;
my $iTotalFoundDelivrableFiles=0;

foreach my $DelivrableFile(keys %$DelivrableFiles)
{
	next if(exists $AlreadyAnalyzedClientFiles{$DelivrableFile});
	my $rhFoundP4ParentFilesForThisFile=Dependencies::FindFinalDelivrableDependencies(++$iCountFile, $DependenciesLinks, \%hashP4FilesList, $DelivrableFile, undef, undef, $CASE_SENSITIVE);
	if(defined $rhFoundP4ParentFilesForThisFile)
	{
		my $PrefixedDelivrableFile=Build::ConvertLogicalFilenameToPrefixedFilename($DelivrableFile,{'$SRC_DIR'=>"^".$SRC_DIR, '$OUTPUT_DIR'=>"^".$OUTPUT_DIR },$CASE_SENSITIVE);
		$iTotalFoundDelivrableFiles+=keys %$rhFoundP4ParentFilesForThisFile;
		open(DEPENDENCIESRESULT, ">>$OUTPUT_DIR/logs/packages/$MakefileName.delivrables.dat") or die("ERROR: cannot open '$OUTPUT_DIR/logs/packages/$MakefileName.delivrables.dat': $!");
		foreach my $DiskFile(keys %$rhFoundP4ParentFilesForThisFile)
		{
			print(DEPENDENCIESRESULT "".$hashP4FilesList{$DiskFile}." -> $PrefixedDelivrableFile\n");
		}
		close(DEPENDENCIESRESULT);
		$iDelivrableFilesHavingP4Files++;
	}
	open(DEPENDENCIESDONE, ">>$OUTPUT_DIR/logs/packages/$MakefileName.delivrables.done") or die("ERROR: cannot open '$OUTPUT_DIR/logs/packages/$MakefileName.delivrables.done': $!");    
	print(DEPENDENCIESDONE ('$AlreadyAnalyzedClientFiles{'."'".$DelivrableFile."'"."}=0;\n"));
	close(DEPENDENCIESDONE);
}

printf("    Deleting recovery file: $OUTPUT_DIR/logs/packages/$MakefileName.delivrables.done\n");
unlink("$OUTPUT_DIR/logs/packages/$MakefileName.delivrables.done");
printf("    Number of found delivrables: ".$iDelivrableFilesHavingP4Files."\n");
printf("    Number of P4 files having delivrables: ".$iTotalFoundDelivrableFiles."\n");
printf("  Analyzing delivrable dependencies took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartTask, Today_and_Now()))[1..3]);

# TODO : Add FillDatabase() call here
if(defined $bFillDatabase && defined $bFillDatabase==1)
{
	if(!defined $nBuildErrors || $nBuildErrors==0)
	{
		@StartTask = Today_and_Now(); print "  Filling database at ".scalar(localtime())."\n";
		XDepUploadDB::fillDatabase("$OUTPUT_DIR/logs/packages/$MakefileName.delivrables.dat");
		printf("  Filling database took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartTask, Today_and_Now()))[1..3]);	
	}
	else
	{
		printf("  ERROR: Database not filled! This build contains some errors($nBuildErrors)....\n");
	}
}
printf("Execution took: %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);
#############
# Functions #
#############
sub Monitor
{
	my($rsVariable) = @_;
	return tie ${$rsVariable}, 'main', ${$rsVariable}
}

sub TIESCALAR
{
	my($Pkg, $Variable) = @_;
	return bless(\$Variable);
}

sub FETCH
{
	my($rsVariable) = @_;

	my $Variable = ${$rsVariable};
	return "" unless(defined($Variable));
	while($Variable =~ /\${(.*?)}/g)
	{
		my $Name = $1;
		$Variable =~ s/\${$Name}/${$Name}/ if(${$Name} ne "");
	}
	return $Variable;
}

sub ReadIni
{
	open(INI, $Config) or die("ERROR: cannot open '$Config': $!");
	SECTION: while(<INI>)
	{
		next unless(my($Section) = /^\[(.+)\]/);
		while(<INI>)
		{
			redo SECTION if(/^\[(.+)\]/);
			next if(/^\s*$/ || /^\s*#/);
			s/\s*$//;
			chomp;
			if($Section eq "context")  { $Context = $_; Monitor(\$Context) }
			elsif($Section eq "client")   { $Client = $_; Monitor(\$Client) }
			elsif($Section eq "root")
			{
				my($Platform, $Root) = split('\s*\|\s*', $_);
				next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($PLATFORM ne "win32_x86" && $Platform=~/^unix$/i));
				$Root =~ s/\${(.+?)}/${$1}/g;
				($SRC_DIR = $Root) =~ s/\\/\//g;
			}
		}
	}
	close(INI);
}

sub Usage
{
	print <<USAGE;
	Usage   : FillDependenciesDB.pl [option]+
	Example : FillDependenciesDB.pl -h
	FillDependenciesDB.pl -g=Saturn.gmk -i=saturn_stable.ini

	[option]
	-help|?  argument displays helpful information about builtin commands.
	-c.lient    P4 client name (-c=[P4 Client name])
	-g.make     specifies the makefile name (-g=project.gmk or -g=area.gmk).
	-i.ni       specifies the configuration file (not mandatory, will force a build.pl call).
	-m.ode      debug or release, default is release.
	-d.irectory Specifies the root source dir, default is \$ENV{SRC_DIR}.
	-s.tream    Used stream (-s=Stable).
	-v.ersion   Version number (-v=1).
	-b.uildname Build/Context name (-v=Titan_Stable, not mandatory if -i set).
	-f.ill      Fill database (optional)
	-e.rrors    Tests if the build is red & does not submit in this case or not (-noe.rrors), default is -noe
USAGE
	exit;
}
