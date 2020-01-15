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

$Parents=$Childs=1;

GetOptions("help|?"=>\$Help,
"ini=s"		=>\$Config,
"gmake=s"	=>\$Makefile,
"mode=s"	=>\$BUILD_MODE,
"source=s"	=>\$SRC_DIR,
"childs!"	=>\$Childs,
"parents!"	=>\$Parents,
"xml=s"		=>\$szXmlFile,
);

Usage() if($Help);

unless($Makefile) { print(STDERR "the -g parameter is mandatory\n\n"); Usage() }
unless($szXmlFile) { print(STDERR "the -x parameter is mandatory\n\n"); Usage() }

$BUILD_MODE ||= $ENV{BUILD_MODE} || "release";
if("debug"=~/^$BUILD_MODE/i) { $BUILD_MODE="debug" } elsif("release"=~/^$BUILD_MODE/i) { $BUILD_MODE="release" }
else { print(STDERR "ERROR: compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease]\n"); Usage() }

$CURRENTDIR = $FindBin::Bin;

ReadIni() if($Config) ;

$SRC_DIR    ||= $ENV{SRC_DIR};
unless($SRC_DIR) { print(STDERR "ERROR: The SRC_DIR environment variable (-d option) is mandatory\n\n"); Usage() }
$SRC_DIR =~ s/[\/\\]/\//g;


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

## Clean and Fetch ##
chdir($CURRENTDIR) or die("ERROR: cannot chdir '$CURRENTDIR': $!");

@StartTask = Today_and_Now(); print "  Initializing dependencies data ('$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.*.dat') at ".scalar(localtime())."\n";
my $DependenciesLinks=Dependencies::InitializeDependencies($ENV{OUTBIN_DIR}, $MakefileName, '$SRC_DIR', '$OUTPUT_DIR', $CASE_SENSITIVE);
printf("  Initializing dependencies data took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartTask, Today_and_Now()))[1..3]);

if(defined $Parents && $Parents==1)
{
}

print "Enter filename to resolve: ";
my $szRequestedFilename=<>; $szRequestedFilename=~ s/\n|\r//g;
print "Searching for '$szRequestedFilename' in files list...\n";
my @aFoundFiles;
my $nCurrentEntry=0;
foreach my $szCurrentKey(keys %{$DependenciesLinks->{"FileNames"}})
{
	next unless($szCurrentKey =~ /$szRequestedFilename/i);
	push(@aFoundFiles,$szCurrentKey);
}
print "Found corresponding file(s):\n";
foreach my $szCurrentKey(@aFoundFiles)
{
	print "\t[".++$nCurrentEntry."]\t$szCurrentKey\n";
}
if($nCurrentEntry>1)
{
	print "Multiple entries found, please select the desired file [1->$nCurrentEntry]: ";
	my $nTmpCurrentEntry=<>; $nTmpCurrentEntry=~ s/\n|\r//g;
	die("ERROR: Incorrect choice!") if(int($nTmpCurrentEntry)>$nCurrentEntry);
	$nCurrentEntry=$nTmpCurrentEntry;
}
die("ERROR: No corresponding entry found!") if(!$nCurrentEntry);
print "Selected choice: $nCurrentEntry...\n";

my $iCountFile=0;
mkpath("$OUTPUT_DIR/logs/packages") or die("ERROR: cannot create '$OUTPUT_DIR/logs/packages': $!") unless(-e "$OUTPUT_DIR/logs/packages");
my $hXMLFile=new IO::File ">$szXmlFile" or die("ERROR: cannot open '$szXmlFile': $!");
$hXMLFile->print('<?xml version="1.0" encoding="UTF-8"?>'."\n");
$hXMLFile->print("<files>\n");
$hXMLFile->print(" <file name='".$aFoundFiles[$nCurrentEntry-1]."' type='root' processid=''>\n");

if(defined $Parents && $Parents==1)
{
	@StartTask = Today_and_Now(); print "  Loading dependencies data ('$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.*.dat') at ".scalar(localtime())."\n";
	Dependencies::LoadDependenciesData($DependenciesLinks, $ENV{OUTBIN_DIR}, $MakefileName, '$SRC_DIR', '$OUTPUT_DIR', $CASE_SENSITIVE, Dependencies::PARENTS );
	printf("  Loading dependencies data took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartTask, Today_and_Now()))[1..3]);

	@StartTask = Today_and_Now(); print "  Analyzing parent dependencies at ".scalar(localtime())."\n";
	Dependencies::FindFinalDelivrableDependencies(++$iCountFile, $DependenciesLinks, undef, $aFoundFiles[$nCurrentEntry-1], undef, {'$SRC_DIR'=>"^".$SRC_DIR, '$OUTPUT_DIR'=>"^".$OUTPUT_DIR }, $CASE_SENSITIVE, $hXMLFile);
	printf("  Analyzing parent dependencies took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartTask, Today_and_Now()))[1..3]);
}


if(defined $Childs && $Childs==1)
{
	if(defined $Parents && $Parents==1)
	{
		@StartTask = Today_and_Now(); print "  Unloading dependencies data for reverse search at ".scalar(localtime())."\n";
		Dependencies::LoadDependenciesData($DependenciesLinks, $ENV{OUTBIN_DIR}, $MakefileName, '$SRC_DIR', '$OUTPUT_DIR', $CASE_SENSITIVE, Dependencies::CHILDREN );
		printf("  'Unloading dependencies data for reverse search' took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartTask, Today_and_Now()))[1..3]);
	}

	@StartTask = Today_and_Now(); print "  Loading dependencies for reverse search ('$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.*.dat') at ".scalar(localtime())."\n";
	Dependencies::LoadDependenciesData($DependenciesLinks, $ENV{OUTBIN_DIR}, $MakefileName, '$SRC_DIR', '$OUTPUT_DIR', $CASE_SENSITIVE, Dependencies::CHILDREN );
	printf("  'Loading dependencies for reverse search' took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartTask, Today_and_Now()))[1..3]);
	
	@StartTask = Today_and_Now(); print "  Analyzing child dependencies at ".scalar(localtime())."\n";
	$iCountFile=0;
	Dependencies::FindFinalDelivrableDependencies(++$iCountFile, $DependenciesLinks, undef, $aFoundFiles[$nCurrentEntry-1], undef, {'$SRC_DIR'=>"^".$SRC_DIR, '$OUTPUT_DIR'=>"^".$OUTPUT_DIR }, $CASE_SENSITIVE, $hXMLFile);
	printf("  Analyzing child dependencies took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartTask, Today_and_Now()))[1..3]);
}

$hXMLFile->print(" </file>\n");
$hXMLFile->print("</files>\n");
$hXMLFile->close();
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
	Usage   : FindDependencies.pl [option]+
	Example : FindDependencies.pl -h
	FindDependencies.pl -g=Saturn.gmk ...

	[option]
	-help|?  argument displays helpful information about builtin commands.
	-g.make     specifies the makefile name (-g=project.gmk or -g=area.gmk).
	-i.ni       specifies the configuration file (not mandatory, will force a build.pl call).
	-m.ode      debug or release, default is release.
	-s.ource    Specifies the root source dir, default is \$ENV{SRC_DIR}.
	-c.hilds    Returns childs (-c.hilds) or not (-noc.hilds), default is -childs
	-p.arents   Returns parents (-p.arents) or not (-nop.arents), default is -parents
	-x.ml       XML File to save search result (mandatory).
USAGE
	exit;
}
