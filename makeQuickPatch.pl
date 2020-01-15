use Getopt::Long;
use Sys::Hostname;

use File::Find;
use File::Path;
use File::Copy;
use File::Basename;

use FindBin;
use lib $FindBin::Bin;

use vars qw (
	$HOST
	$OBJECT_MODEL
	$iniFile
	$Changelists
	@AreaSBuildUnitS
	$IncrementalVersion
	$Model
	$OptionObjectModel
	$Help
	$QuietMode
	$Project
	$Context
	$Client
	$DROP_DIR
);

sub ReadIni();
sub getCurrentVersion();

$HOST = hostname();

$Getopt::Long::ignorecase = 0;
GetOptions(
	"i=s"		=>\$iniFile,
	"cl=s"		=>\$Changelists,
	"a=s@"		=>\@AreaSBuildUnitS,
	"iv=s"		=>\$IncrementalVersion,
	"64!"		=>\$Model,
	"help|h|?"	=>\$Help,
	"Quiet!"	=>\$QuietMode,
);

$iniFile ||= $ENV{'MY_INI_FILE'};
die("no -i=ini_file")	unless($iniFile);

if( -e "$iniFile" ) {
	ReadIni();
} else {
	die("'$iniFile' not found");
}

if(defined($Project)) { $ENV{PROJECT}=$Project; delete $ENV{DROP_DIR}; delete $ENV{DROP_NSD_DIR}; delete $ENV{IMPORT_DIR} } 
require Site;
$DROP_DIR = $ENV{DROP_DIR};

$CurrentVersion = getCurrentVersion();
$CurrentVersion .= ".$IncrementalVersion"  if($IncrementalVersion);
print "\n\tpatches : $Context - $CurrentVersion\n";

if($Changelists) {
	@changeLists = split(',',$Changelists) if($Changelists);
	foreach my $Changelist (sort(@changeLists)) {
		print "\nget changelist $Changelist\n";
		$Changelist = "@".$Changelist.",$Changelist";
		print("p4 -c $Client sync //...$Changelist\n");
		system("p4 -c $Client sync //...$Changelist");
	}
}

$ENV{'BUILD_DASHBOARD_ENABLE'}=0;
if($Model) {
	$OptionObjectModel = "-64";
}

my $AreaBuildUnit;
foreach my $aBU (@AreaSBuildUnitS) {
	$AreaBuildUnit .= " -a=$aBU";
}

unless($AreaBuildUnit) {
	print "\nno $0 -a=area:BUs, no compile\n\n";
	exit;
}

print "\ncompile $Changelists with $AreaBuildUnit\n";
print "perl Build.pl -m=r -d -nolego $OptionObjectModel -i=$iniFile -v=$CurrentVersion $AreaBuildUnit -B\n";

my $readRep;
unless($QuietMode) {
	#execute command line
	print "\nWould you like to execute this command ? (y/n)\n";
	$readRep = <STDIN> ;
	chomp($readRep);
} else {
	$readRep = "yes";
}
if($readRep =~ /^y/i) {
	system("perl Build.pl -m=r -d -nolego $OptionObjectModel -i=$iniFile -v=$CurrentVersion $AreaBuildUnit -B");
} else {
	print "bye\n";
}

print "\n";
exit;

sub ReadIni() {
    open(INI, $iniFile) or die("ERROR: cannot open '$iniFile': $!");
    SECTION: while(<INI>)
    {
        next unless(my($Section) = /^\[(.+)\]/);
        while(<INI>)
        {
            redo SECTION if(/^\[(.+)\]/);
            next if(/^\s*$/ || /^\s*#/);
            s/\s*$//;
            s/\${(.*?)}/${$1}/g ;
            chomp;
            if($Section eq "project") { $Project = $_; }
            if($Section eq "context")    { $Context = $_; } 
            if($Section eq "client")     { $Client = $_;  } 
        }
    }
    close(INI);
}

sub getCurrentVersion() {
    my $BuildNumber = 0;
    if(open(VER, "$DROP_DIR/$Context/version.txt")) {
        chomp($BuildNumber = <VER>);
        $BuildNumber = int($BuildNumber);
        close(VER);
    }
    return $BuildNumber;
}
