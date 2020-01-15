use Getopt::Long;
use Sys::Hostname;

use File::Find;
use File::Path;
use File::Copy;
use File::Basename;

use FindBin;
use lib $FindBin::Bin;
use File::Path;

sub usage($);
sub execBuildPL($$);
sub makeGreatest($$);
sub syncRefClientSpec();
sub getClientSpecFromIniFile();
sub getContextFromIniFile();

use vars qw (
	$HOST
	$CURRENTDIR
	$TriggerLogFile
	$IniFile
	$BuildMode
	$objectModel
	$OBJECT_MODEL
	%AREAS_TO_BUILD
	%AREAS_TO_FETCH
	$Areas
	@AREAS
	$Branch
	$VersionIncluded
	$AllVersions
	$FetchDateTime
	$Steps
	$OutPutLog
	$Help
	$Greatest
	$RefPlatFormsCheckCompile
	$SyncRefClientSpec
	$Context
);

$HOST = hostname();
$CURRENTDIR = $FindBin::Bin;

$Getopt::Long::ignorecase = 0;
GetOptions(
	"l=s"		=>\$TriggerLogFile,
	"i=s"		=>\$IniFile,
	"m=s"		=>\$BuildMode,
	"64!"		=>\$objectModel,
	"ar=s"		=>\$Areas,
	"b=s"		=>\$Branch,
	"sv!"		=>\$VersionIncluded,
	"av"		=>\$AllVersions,
	"c=s"		=>\$FetchDateTime,
	"st=s"		=>\$Steps,
	"o=s"		=>\$OutPutLog,
	"help|h|?"	=>\$Help,
	"g"			=>\$Greatest,
	"rp"		=>\$RefPlatFormsCheckCompile,
	"sync"		=>\$SyncRefClientSpec
	);

$BuildMode = "release" unless($BuildMode);
if("debug"=~/^$BuildMode/i) {
	$BuildMode="debug";
} elsif("release"=~/^$BuildMode/i) {
	$BuildMode="release";
} elsif("releasedebug"=~/^$BuildMode/i) {
	$BuildMode="releasedebug";
} elsif("rd"=~/^$BuildMode/i) {
	$BuildMode="releasedebug";
} else {
	usage("ERROR: compilation mode '$BuildMode' is unknown [d.ebug|r.elease|releasedebug|rd]");
}
$OBJECT_MODEL = $objectModel ? "64" : ($ENV{OBJECT_MODEL} || "32"); 

$Areas				||= "tp";
@AREAS = split(',',$Areas);
$Branch				||= "REL";
$VersionIncluded	||= "yes";
$FetchDateTime		||= "17:00:00";
$Steps				||= "V,C,F,I,B,E,M";
$RefPlatFormsCheckCompile		||= "win32_x86";

$IniFile			||="contexts/thirdparties_1.0.ini";
my $baseIniFileName = basename("$IniFile");
$OutPutLog			||= "$CURRENTDIR/../../$baseIniFileName";
($OutPutLog) =~ s/ini$/log/i;

usage("") if($Help);
usage("no ini file") if( ! -e "$IniFile");

open(LOGFILE,$TriggerLogFile) or die ("ERROR: cannot open '$TriggerLogFile' : $!");

while(<LOGFILE>) {
	foreach my $Area (sort(@AREAS)) {
		next unless($Area);
		if(/^\/\/.+?\/$Area/) {
			my $line = $_;
			my ($area,$version) = $line =~ /^\/\/.+?\/($Area.*?)\/(.+?)\/$Branch/;
			$AREAS_TO_FETCH{$line} = 1;
			$AREAS_TO_BUILD{$area} = 1 if($area);
			if($version) {
				push(@{$area},$version) unless(grep /^$version$/,@{$area});
			}
		} else {
			$AREAS_TO_BUILD{$Area} = 2;
		}
	}
}
close(LOGFILE);

($Steps) =~ s/\,/ \-/g;
$Steps = " -$Steps";

print "\n\n\n=====>START of $0\n\n";
print "\n";
print "CURRENTDIR : $CURRENTDIR\n";
print "trigger log file : $TriggerLogFile\n";
print "ini file : $IniFile\n";
print "build mode : $BuildMode\n";
print "fetch date/time : $FetchDateTime\n";
print "OBJECT MODEL : $OBJECT_MODEL\n";
print "STEPS: $Steps\n";
print "Build.pl OUTPUT LOG: $OutPutLog\n";


if($SyncRefClientSpec) {
	$Context = getContextFromIniFile();
	print "sync ref clientspec\n\n";
	syncRefClientSpec();
} else {
	foreach my $area (sort(keys(%AREAS_TO_BUILD))) {
		next unless($area);
		if($AREAS_TO_BUILD{$area} == 1 ) {
			if($VersionIncluded eq "yes") {
				if($AllVersions) {
					execBuildPL($area,"*") unless($Greatest);
					makeGreatest($area,"*") if($Greatest);
				} else {
					foreach my $version (@{$area}) {
						execBuildPL($area,$version) unless($Greatest);
						makeGreatest($area,$version) if($Greatest);
					}
				}
			} else {
					execBuildPL($area,"") unless($Greatest);
					makeGreatest($area,"*") if($Greatest);
			}
		}
	}
}

print "\n\n\n=====>END of $0\n\n";
exit;

###################################################################################################
###################################################################################################
###################################################################################################

sub execBuildPL($$) {
	my ($thisArea,$thisVersion) = @_ ;
		print "\n\t$thisArea\n";
		my $cmd = "perl Build.pl -d -nolego -m=$BuildMode -i=$IniFile -qset=MY_TARGET:$thisArea";
		$cmd .= "/$thisVersion" if($thisVersion);
		if($thisArea =~ /^tp\./) {
			$cmd .= " -qset=MY_AREAS:REL:com.sap.tp:$thisArea" if($thisVersion);
		} else {
			$cmd .= " -qset=MY_AREAS:REL:com.sap:$thisArea" if($thisVersion);
		}
		if($thisVersion) {
			$cmd .= ":$thisVersion";
			if($thisVersion=~ /^\*$/) {
				$cmd .= " -qset=MY_BUILDNAME:$thisArea";
			} else {
				$cmd .= " -qset=MY_BUILDNAME:${thisArea}_$thisVersion";
			}
		} else {
			$cmd .= " -qset=MY_BUILDNAME:$thisArea";
		}
		#$cmd .= " -qset=MY_VERSION:$thisVersion" if($thisVersion);
		$cmd .= " -qset=MY_P4_DRIVE:E" if($HOST =~ /lvwin026/i);
		$cmd .= " -c=$FetchDateTime $Steps";
		$cmd .= " -64" if($OBJECT_MODEL == 64);
		$cmd .= " > $OutPutLog 2>&1";
		print "RUN: $cmd\n";
		system("$cmd");
}

sub usage($) {
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
	usage	: perl $0 [options]
	Example	: perl $0 -h

[options]
	-h|?		argument displays helpful information about builtin commands.
	-l		-l=trigger logfile
	-i		specifies the configuration file.
	-m		choose a compile mode, same usage than Build.pl -m=, by default: -m=r
	-64		force the 64 bits compilation (-64) or not (-no64), default is -no64 i.e 32 bits, same usage than Build.pl
	-ar		area(s) to compile
	-b		branch, by default: -b=REL
	-sv		single version
	-av		compile all versions of an area
	-c		fetch date/time
	-st		list of steps to do throw Build.pl
	-o		output log for Build.pl
	-g		create automatically greatests
	-rp		reference platform to check the compile status to create the greatest
	-sync	sync the reference clientspec before trigger it

[examples]
";
	my $display;
	if($^O eq "MSWin32") {
		$display="-l=\\\\build-drops-lv\\dropzone\\components\\thirdparties_1.0\\trigger_for_tests.log";
	} else {
		$display="-l=/net/build-drops-lv/space5/drop/dropzone/components/thirdparties_1.0/trigger_for_tests.log";
	}
		print "
perl $0 $display -m=$BuildMode -c=$FetchDateTime -st=$Steps -i=$IniFile
";
	exit;
}

sub makeGreatest($$) {
	my ($thisArea,$thisVersion) = @_ ;
	my $BuildName = "$thisArea";
	if($thisVersion=~ /^\*$/) {
		$thisVersion = ""
	} else {
		$BuildName .= "_$thisVersion";
	}
	my $cmd = "perl $CURRENTDIR/core.build.tools/export/shared/CheckmakeGreatest.pl $BuildName $RefPlatFormsCheckCompile";
	print "\n\t$BuildName\n";
	print "$cmd\n";
}

sub syncRefClientSpec() {
	my $p4RefClientSpec = getClientSpecFromIniFile();
	foreach my $scm (sort(keys(%AREAS_TO_FETCH))) {
		next unless($scm);
		($scm) =~ s/\s+\-\s+.*?$//;
		my $p4SyncCommand = "p4 -c $p4RefClientSpec sync $scm";
		print "$p4SyncCommand\n";
	}	
}

sub getClientSpecFromIniFile() {
	my $thisClientSpec = "";

	open(INI, "$IniFile") or die("ERROR: cannot open ini file '$IniFile': $!");
	SECTION: while(<INI>) {
		next unless(my ($Section) = /^\[(.+)\]/);
		next unless($Section eq "client");
		while(<INI>) {
			chomp;
			redo SECTION if(/^\[(.+)\]/);
			next if(/^\s*$/ || /^\s*#/);
			s/\s*$//;
			s/\${(.*?)}/${$1}/g ;
			$thisClientSpec = $_ if($Section eq "client");
		}
	}
	close(INI);
	return $thisClientSpec if($thisClientSpec);
}

sub getContextFromIniFile() {
	my $thisContext = "";
	open(INI, "$IniFile") or die("ERROR: cannot open ini file '$IniFile': $!");
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
