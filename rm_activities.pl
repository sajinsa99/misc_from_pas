use Sys::Hostname;

use File::Find;
use File::Path;
use File::Copy;
use File::Basename;

use Getopt::Long;

sub getContextFromIniFile($);
sub getProjectFromIniFile($);
sub getSrcDirFromIniFile($);
sub getpreviousRevision;
sub getcurrentRevision;
sub TimeDiff;
sub Usage($);

use vars qw (
			$buildName
			$iniFile
			$previousRevision
			$currentRevision
			$buildMode
			$objectModel
			$Help
			$ScriptStart
			$OBJECT_MODEL
			$PLATFORM
			$osFamily
			$PROJECT
			$Context
			$rootDir
			$DROP_DIR
			$HTTP_DIR
			$fullBldNameRevFirst
			$fullBldNameRevSecond
			$FirstContext
			$SecondContext
			$datFile
			$adaptFile
			$CMD
			$CISDIR
);

$Getopt::Long::ignorecase = 0;
GetOptions(
	"i=s"		=>\$iniFile,
	"p=s"		=>\$previousRevision,
	"v=s"		=>\$currentRevision,
	"m=s"		=>\$buildMode,
	"64!"		=>\$objectModel,
	"help|h|?"	=>\$Help,
          );
Usage("") if($Help);

printf("\nStart at %s\n", scalar(localtime()));
$ScriptStart = time ;

#define PLATFORM
$OBJECT_MODEL = $objectModel ? "64" : ($ENV{OBJECT_MODEL} || "32"); 
if($^O eq "MSWin32")	{ $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64" : "win32_x86"  }
else { die("ERROR: $0 run only on windows"); }
$osFamily="windows";

#define compile mode
$buildMode ||= $ENV{BUILD_MODE} || "release";
if("debug"=~/^$buildMode/i) {
	$buildMode="debug";
} elsif("release"=~/^$buildMode/i) {
	$buildMode="release";
} elsif("releasedebug"=~/^$buildMode/i) {
	$buildMode="releasedebug";
} elsif("rd"=~/^$buildMode/i) {
	$buildMode="releasedebug";
} else {
	Usage("ERROR: compilation mode '$buildMode' is unknown [d.ebug|r.elease|releasedebug|rd]");
}

#ini
Usage("no -i or -i is empty") unless($iniFile);
if( -e $iniFile) {
	$buildName ||= getContextFromIniFile("$iniFile")
} else {
	Usage("'$iniFile' does not exist");
}


$PROJECT = getProjectFromIniFile("$iniFile");
$ENV{PROJECT} = $PROJECT;
$Context = $buildName;
$rootDir = getSrcDirFromIniFile($iniFile);
($rootDir) =~ s-\\-\/-g;
($rootDir) =~ s-\/src$--;

require Site;

$DROP_DIR = $ENV{DROP_DIR};
($DROP_DIR) =~ s-\\-\/-g;

$HTTP_DIR = $ENV{HTTP_DIR};
($HTTP_DIR) =~ s-\\-\/-g;


$previousRevision	= getpreviousRevision() unless($previousRevision);
if($previousRevision eq "greatest") {
	$previousRevision	= getpreviousRevision();
} else {
	$previousRevision	||= getpreviousRevision();
}
Usage("no first revision") unless($previousRevision);

$currentRevision		||= getcurrentRevision();
Usage("no second revision") unless($currentRevision);

$fullBldNameRevFirst = sprintf("%05d", $previousRevision);
$fullBldNameRevFirst = "${buildName}_$fullBldNameRevFirst";
$fullBldNameRevSecond = sprintf("%05d", $currentRevision);
$fullBldNameRevSecond = "${buildName}_$fullBldNameRevSecond";

$FirstContext = "$DROP_DIR/$buildName/$previousRevision/$buildName.context.xml";
if( ! -e $FirstContext ) {
	$FirstContext = "$HTTP_DIR/$buildName/$fullBldNameRevFirst/$fullBldNameRevFirst.context.xml";
	Usage("'$FirstContext' does not exist") if( ! -e $FirstContext );
}
$SecondContext = "$DROP_DIR/$buildName/$currentRevision/$buildName.context.xml";
if( ! -e $SecondContext ) {
	$SecondContext = "$HTTP_DIR/$buildName/$fullBldNameRevSecond/$fullBldNameRevSecond.context.xml";
	Usage("'$SecondContext' does not exist") if( ! -e $SecondContext );
}

mkpath("$rootDir/$PLATFORM/$buildMode/logs") or Usage("ERROR: cannot mkpath '$rootDir/$PLATFORM/$buildMode/logs': $!") unless(-e "$rootDir/$PLATFORM/$buildMode/logs");
$datFile = "$rootDir/$PLATFORM/$buildMode/logs/NewRevisions.dat";
$adaptFile = "$rootDir/$PLATFORM/$buildMode/logs/Adapts.txt";

$CMD="perl DiffContext.pl -f=$FirstContext -t=$SecondContext -w=* -outdat=$datFile -adapt=$adaptFile -c=$fullBldNameRevFirst,$fullBldNameRevSecond";
print "\n\t$buildName - $iniFile\n";
print "Activities between $fullBldNameRevFirst and $fullBldNameRevSecond\n\n";
print "cmd: $CMD\n";
system("$CMD");

$CISDIR = "$HTTP_DIR/$Context/$fullBldNameRevSecond";
if( -e $CISDIR ) {
	print "\n\tUpdate CIS\n";
	if( -e "$CISDIR/NewRevisions.dat") {
		rename("$CISDIR/NewRevisions.dat", "$CISDIR/NewRevisions.dat.orig") or warn("ERROR: cannot rename '$CISDIR/NewRevisions.dat': $!") if( ! -e "$CISDIR/NewRevisions.dat.orig");
	}
	system("cp -vf $datFile $CISDIR/NewRevisions.dat");
}

print("\n'$0' took : ", TimeDiff($ScriptStart, time), "\n");

print "\nEND\n\n";
exit 0;

sub getContextFromIniFile($) {
	my ($thisIniFile) = @_ ;
	my $thisContext = "";
	open(INI, "$thisIniFile") or die("ERROR: cannot open ini file '$thisIniFile': $!");
	SECTION: while(<INI>) {
		next unless(my ($Section) = /^\[(.+)\]/);
		next unless($Section eq "context");
		while(<INI>) {
			chomp;
			redo SECTION if(/^\[(.+)\]/);
			next if(/^\s*$/ || /^\s*#/);
			s/\s*$//;
			s/\${(.*?)}/${$1}/g ;
			$thisContext = $_ if($Section eq "context");
		}
	}
	close(INI);
	return $thisContext if($thisContext);
}

sub getProjectFromIniFile($) {
	my ($thisIniFile) = @_ ;
	my $thisProject = "";
	open(INI, "$thisIniFile") or Usage("ERROR: cannot open ini file '$thisIniFile': $!");
		SECTION: while(<INI>) {
			next unless(my ($Section) = /^\[(.+)\]/);
			next unless($Section eq "project");
			while(<INI>) {
				chomp;
				redo SECTION if(/^\[(.+)\]/);
				next if(/^\s*$/ || /^\s*#/);
				s/\s*$//;
				s/\${(.*?)}/${$1}/g ;
				$thisProject = $_ if($Section eq "project");
			}
		}
		close(INI);
	return $thisProject if($thisProject);
}

sub getSrcDirFromIniFile($) {
	my ($thisIniFile3) = @_ ;
	my $thisSrcDir = "";
	open(INI, "$thisIniFile3") or Usage("ERROR: cannot open ini file '$thisIniFile3': $!");
		SECTION: while(<INI>) {
			next unless(my ($Section) = /^\[(.+)\]/);
			next unless($Section eq "root");
			while(<INI>) {
				chomp;
				redo SECTION if(/^\[(.+)\]/);
				next if(/^\s*$/ || /^\s*#/);
				s/\s*$//;
				next if !( ( /^$osFamily/ ) || (/^$PLATFORM/) );
				if($Section eq "root") {
					s/\${(.*?)}/${$1}/g ;
					if( /^$osFamily/ ) { 
						($thisSrcDir) = $_ =~ /^$osFamily\s+\|\s+(.+?)$/;
					}
					if( /^$PLATFORM/ ) { 
						($thisSrcDir) = $_ =~ /^$PLATFORM\s+\|\s+(.+?)$/;
					}
				}
			}
		}
		close(INI);
	return $thisSrcDir if($thisSrcDir);
}

sub getpreviousRevision {
	my $rev = "";
	if( $previousRevision eq "greatest" ) {
		Usage("'$DROP_DIR/$buildName/greatest.xml' does not exist") if( ! -e "$DROP_DIR/$buildName/greatest.xml");
		my $currentGreatest = `grep \"version context\" $DROP_DIR/$buildName/greatest.xml | grep $buildName`;
		chomp($currentGreatest);
		($rev) = $currentGreatest =~ /\<version\s+context\=\"$buildName\"\>(.+?)\<\/version\>/;
		($rev) =~ s-^\d+\.\d+\.\d+\.--;
	} else {
		my $tmpCurrentVersion = getcurrentRevision();
		$rev = $tmpCurrentVersion - 1;
	}
	return $rev;
}

sub getcurrentRevision {
	my $lastVersion = 1;
	if( -e "$DROP_DIR/$buildName/version.txt" ) {
		$lastVersion = `cat $DROP_DIR/$buildName/version.txt`;
		chomp($lastVersion);
	}
	return $lastVersion;
}

sub TimeDiff {
	my $Diff = $_[1] - $_[0] ;
	my $ss = $Diff % 60 ;
	my $mm = (($Diff-$ss)/60)%60 ;
	my $hh = ($Diff-$mm*60-$ss)/3600 ;
	sprintf("%02d:%02d:%02d", $hh, $mm, $ss) ;
}

####################
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
	Description	:
'$0' calcul activities between 2 builds and update .dat in CIS (create a back-up before)
'$0' use DiffContext.pl

	Usage		:
perl $0 [options]

	options		:
-i	ini file [MANDATORY]
-p	previous build
	by default, version=`cat version.txt` - 1
	could be like -p=greatest
-v	by default, get version in version.txt
-m	build mode (release|debug|releasedebug|rd), by default, -m=r
-h|?	argument displays helpful information about builtin commands.

	examples	:
perl $0
perl $0 -i=contexts/Aurora_cons.ini
perl $0 -i=contexts/Aurora_cons.ini -p=200
perl $0 -i=contexts/Aurora_cons.ini -p=200 -v=202
perl $0 -i=contexts/Aurora_cons.ini -p=greatest -v=202
";
	exit 1;
}
