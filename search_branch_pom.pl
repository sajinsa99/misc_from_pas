#######################################################################################################################################################################################################
##### declare uses
use Getopt::Long;
use Sys::Hostname;

use File::Find;
use File::Path;
use File::Copy;
use File::Basename;

use FindBin;
use lib $FindBin::Bin;
use File::Path;
use IO::File;

use File::Temp qw/ tempfile tempdir /;

use XML::DOM;

use Perforce;


#######################################################################################################################################################################################################
##### declare vars
# options/parameters
use vars qw (
	$Help
	$Branch
	$Config
	$submit
	$P4ClientSpec
	@QSets
	$NewIniFile
);

# P4
use vars qw (
	$P4ClientSpec
	$Description
	$DescrUpd
	$DescrAdd
	$P4USER
	$p4
);

#for script itself
use vars qw (
	%AREAS
	%AREAS_UPDATE
	%AREAS_TO_INSERT
	$repoPOMS
	$CURRENTDIR
	$HOST
	$HOME
);


#######################################################################################################################################################################################################
##### declare functions
sub search_branch_pom ;
sub getGroupInPOM($);
sub endscript;
sub CreateChange($);
sub Usage();


#######################################################################################################################################################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
	"help|?"		=>\$Help,
	"branch=s"		=>\$Branch,
	"ini=s"			=>\$Config,
	"submit"		=>\$submit,
	"client=s"		=>\$P4ClientSpec,
	"qset=s@"		=>\@QSets,
	"newini"		=>\$NewIniFile,
);
&Usage() if($Help);
die("\nERROR -b=branch missed\n")	unless($Branch);
die("\nERROR -i=ini file missed\n")	unless($Config);


#######################################################################################################################################################################################################
##### init vars
# system vars
$CURRENTDIR = $FindBin::Bin;
$ENV{CURRENTDIR}=$CURRENTDIR;
$HOST = hostname();
$HOME = $ENV{HOME} if($^O ne "MSWin32");

# for the script
$repoPOMS = ($^O eq "MSWin32") ? "C:/core.build.tools/repositories" : "$HOME/core.build.tools/repositories";

foreach (@QSets)
{
    my($Variable, $String) = /^(.+?):(.*)$/;
    Monitor(\${$Variable});
    ${$Variable} = $ENV{$Variable} = $String;
}


#######################################################################################################################################################################################################
##### MAIN
print "\n=> START of '$0', at ",scalar(localtime),"\n\n";

# 0 back up ini file
$P4USER = $ENV{P4USER} || (`p4 set P4USER`=~/^P4USER=(\w+)/,$1);
$ENV{P4USER} = $P4USER ;
$P4ClientSpec ||= ($ENV{P4USER}=~/^pblack$/i ? "$ENV{P4USER}_$HOST" : "\u\L$ENV{P4USER}_\L$HOST"); #inspired by UpdateBootstrap.pl, line 78
system("p4 -c $P4ClientSpec sync -f $Config");
system("cp -f $Config $Config.orig");

# 1 check if folder FEAT_CUV exists, if you, there is a chance to have a pom inside
if( ! -e "$repoPOMS/$Branch" ) {
	print("$repoPOMS/$Branch not found\n");
	&endscript;
}
# 2 search pom inside
find(\&search_branch_pom, "$repoPOMS/$Branch");

# 2.1 exit if nothing found
unless(defined(%AREAS)) {
	print "\nWARNING, no pom found in $repoPOMS/$Branch\n";
	&endscript;
}
# 2.2 print found
print "
ini file: $Config
ClientSpec : $P4ClientSpec
search in : $repoPOMS/$Branch
BRANCH : $Branch
AREAS found in $repoPOMS:
";
while ( my ($area,$versiongroup) = each(%AREAS) ) {
	my ($version,$group) = split(',',$versiongroup);
	print "\t$Branch:$group:$area:$version\n";
}

#to put here

# 3 rewrite ini file

if($NewIniFile) {
	my %AREAS_IN_INI_FILE;
	my $MY_AREAS = `grep \"MY_AREAS\=\" $Config`;
	chomp($MY_AREAS);
	my $include;
	my $includeToAdd;
	unless($MY_AREAS) {
		$include = `grep \"\#include\" $Config | grep -vi template`;
		chomp($include);
		$includeToAdd = $include;
		($include) =~ s-^\#include\s+--;
		($include) =~ s-\$\{(.+?)\}-$ENV{$1}-g;
		if( -e $include ) {
			$MY_AREAS = `grep \"MY_AREAS\=\" $include`;
			chomp($MY_AREAS);
			($MY_AREAS) =~ s-^MY_AREAS\=--,
		}
	}
	if($MY_AREAS) {
		@BGAVS = split(',',$MY_AREAS);
		foreach my $bgav (@BGAVS) {
			my ($branch,$group,$area,$version);
			if($bgav =~/\:/) {
				($branch,$group,$area,$version) = split(':',$bgav);
				$AREAS_IN_INI_FILE{$area}=1;
			}
		}
		my $lines = "[view]\n";
		print "\n";
		foreach my $areaInIniFile (sort(keys(%AREAS_IN_INI_FILE))) {
			while ( my ($area,$versiongroup) = each(%AREAS) ) {
				if($areaInIniFile eq $area) {
					my ($version,$group) = split(',',$versiongroup);
					print "\tinsert $area\n";
					$lines .="getSources -O $Branch:$group:$area:$version\t| //\${Client}/%%ArtifactId%%/%%Version%%/...\n";
				}
			}
		}
		if($lines =~ /getSources/i) {
			my $iniNewFileName = ($include) ? $include : $Config;
			($iniNewFileName) =~ s-\.ini$-_$Branch\.ini-i;
			if(open(NEW_INI,">$iniNewFileName")) {
					print NEW_INI $lines;
				close(NEW_INI);
				($includeToAdd) =~ s-\.ini$-_$Branch\.ini-i;
				print "\nPlease add ini $Config:\n$includeToAdd\n";
				
			}
		} else {
			print "nothing to insert\n";
		}
	} else {
		print "WARNING : MY_AREAS not found\n";
	}
	&endscript;
}

my @lines;
my @views;

# 3.2 get lines from ini files
if(open(SRC_INI,"$Config")) {
	my $firstUpdate = 0;
	SECTION: while(<SRC_INI>) {
		chomp;
		my ($Section) = /^\[(.+)\]/;
		if($Section eq "view") {
			push(@lines,"to_replace");
		} else {
			push(@lines,"$_");
		}
		while(<SRC_INI>) {
			chomp;
			redo SECTION if(/^\[(.+)\]/);
			if($Section eq "view") {
				my $tmpLine = $_;
				if($tmpLine =~ /^getSources\s+\-O/) { # replace
					my ($branchIni,$groupIni,$areaIni,$versionIni) = $tmpLine =~ /^getSources\s+\-O\s+(.+?):(.+?):(.+?):(.+?)\s+\|/;
					if($AREAS{$areaIni}) {
						if($branchIni ne $Branch) {
							s-$branchIni-$Branch-;
							s-\$\{REF_WORKSPACE\}(.+?)$-\$\{REF_WORKSPACE\}-; # become latest version, remove fetch level part
							$DescrUpd .= ",$areaIni";
							$firstUpdate++;
							print "\n" if($firstUpdate == 1);
							print "\tupdate area $areaIni\n";
						}
						$AREAS_UPDATE{$areaIni}="$versionIni,$groupIni";
					}
				}
				push(@views,"$_");
			} else {
				push(@lines,"$_");
			}
		}
	}
	close(SRC_INI);
	#determine areas to insert
	while ( my ($area,$versiongroup) = each(%AREAS) ) {
		my ($version,$group) = split(',',$versiongroup);
		unless($AREAS_UPDATE{$area}) {
			$AREAS_TO_INSERT{$area}="$version,$group";
		}
	}
}

# 3.3 create new ini file
if(open(TARGET_INI,">$Config.new")) {
	foreach my $line (@lines) {
		if($line eq "to_replace") {
			print TARGET_INI "[view]\n";
			my $putHere = 0;
			my @views2;
			foreach my $view (@views) {
				#please keep comment ini ini which it should be :
				#overlay to fetch $Branch branch
				#e.g.:
				#overlay to fetch FEAT_CUV branch
				if($view =~ /^\#overlay\s+to\s+fetch\s+(.+?)\s+branch/i) {
					($view) =~ s-$1-$Branch-;
					$putHere = 1;
					print TARGET_INI "$view\n";
				}
				if($putHere == 1) {
					next if($view =~ /^\#overlay\s+to\s+fetch\s+(.+?)\s+branch/i);
					if($view =~ /^getSources/) {
						print TARGET_INI "$view\n";
					} else {
						push(@views2,$view);
					}
				} else {
					print TARGET_INI "$view\n";
				}
			}
			#insert areas to add, just after last getsource
			my $firstInsert = 0;
			while ( my ($area,$versiongroup) = each(%AREAS_TO_INSERT) ) {
				my ($version,$group) = split(',',$versiongroup);
				print TARGET_INI "getSources -O $Branch:$group:$area:$version\t| //\${Client}/%%ArtifactId%%/%%Version%%/...\n";
				$DescrAdd .= ",$area";
				$firstInsert++;
				print "\n" if($firstInsert == 1);
				print "\tinsert area $area\n";
			}
			#write latest part of view
			foreach my $view (@views2) {
				print TARGET_INI "$view\n";
			}

		} else {
			print TARGET_INI "$line\n";
		}
	}
	close(TARGET_INI);
	system("cp -f $Config.new $Config");
}

if($submit) {
	print "\n";
	my $p4Scm;
	if(open(P4FILELOG,"p4 -c $P4ClientSpec filelog $Config 2>&1 |")) {
		while(<P4FILELOG>) {
			chomp;
			$p4Scm = $_ unless(/file\(s\) not on client/i);
			last;
		}
		close(P4FILELOG);
	}
	if($p4Scm) { # if already in perforce
		# revert if still opened
		if(open(OPENED,"p4 -c $P4ClientSpec opened $Config 2>&1 |")) { #revert if opened
			my $revert = 0;
			while(<OPENED>) {
				chomp;
				$revert = 1 if(/\s+-\s+edit\s+/);
			}
			close(OPENED);
			if($revert==1) {
				system("p4 -c $P4ClientSpec revert $Config");
			}
		}
		# delete pending changelist using same name in summary, in case of not submit
		if(P4CHANGES,"p4 changelists -c $P4ClientSpec -s pending | grep \"$Branch\" |") {
			my %changelists;
			while(<P4CHANGES>) {
				chomp;
				(my $changelist) = $_ =~ /^Change\s+(\d+)\s+/;
				$changelists{$changelist} = 1;
			}
			close(P4CHANGES);
			foreach my $cl (keys(%changelists)) {
				system("p4 -c $P4ClientSpec change -d $cl");
			}
		}
		
		if( (defined(%AREAS_UPDATE)) || (defined(%AREAS_TO_INSERT)) ) {
			#create new changelist
			$Description = "[$Branch]";
			if($DescrUpd) {
				($DescrUpd) =~ s-^\,--;
				$Description .= " update area(s) $DescrUpd";
			}
			if($DescrAdd) {
				($DescrAdd) =~ s-^\,--;
				if($DescrUpd) {
					$Description .= " ; add area(s) $DescrAdd";
				} else {
					$Description .= " add area(s) $DescrAdd";
				}
			}
			if(($Description =~ /\s+update\s+area/) || ($Description =~ /\s+add\s+area/)) { #if areas updated or added in ini, submit ini file
				print "\np4 submit summary : $Description\n";
				$p4 = new Perforce;
				$p4->SetClient($P4ClientSpec);
				my $Change=&CreateChange($Description);
				$p4->edit("-c",$Change,"\"$p4Scm\"");
				$p4->submit("-c",$Change);
				$p4->Final() if($p4);
			} else {
				print "nothing to submit\n";
			}
		} else {
			print "nothing to submit\n";
		}
	}
}

&endscript;
#######################################################################################################################################################################################################
### my functions
sub search_branch_pom {
	 if ($_=~/pom.xml$/) {
	 	my ($area,$version) = $File::Find::name =~ /$Branch\/(.+?)\/(.+?)\/pom.xml$/;
	 	my $group = &getGroupInPOM($File::Find::name);
		$AREAS{$area}="$version,$group";
	}
}

sub getGroupInPOM($) {
	my ($POMFile) = @_;
    my $POM = XML::DOM::Parser->new()->parsefile($POMFile);
    ($RealGroupIdPath = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("groupId", 0)->item(0)->getFirstChild()->getData());
    $POM->dispose();
    return $RealGroupIdPath;
}

sub endscript {
	# end script
	print "\n\n=> END of '$0', at ",scalar(localtime),"\n\n";
	exit;
}

sub Usage() {
	print "
	Usage	: perl $0 [options]
	Example	: perl $0 -h

[options]
	-h|?		argument displays helpful information about builtin commands.
	-b		!!! MANDATORY !!! , choose a branch
	-i		!!! MANDATORY !!! , choose an ini file, by default: -i=contexts/buildname.ini,
			in ini file, you should have this comment in 'view' section :
#overlay to fetch YOUR_BRANCH branch
			in the comment, please update YOUR_BRANCH by the branch you need
	-submit		to submit your ini file only if it changed

";
	exit;
}

#######################################################################################################################################################################################################
### functions getted from other script(s)
sub CreateChange($)
{
	my ($summary) = @_;
	my $Text="
Change:	new
Client:
User: $P4USER	
Status:	new
Description:
	Summary: $summary
	Reviewed by: $P4USER";
	my $machine= uc hostname();
	my ($fh, $tempfilename)= tempfile(); 
	open(FILE,">$tempfilename");
	print FILE "$Text\n";
	close(FILE);
	my $raChange=$p4->change("-i","<",$tempfilename);
    print("ERROR: cannot create change: ", @{$p4->Errors()}) if($p4->ErrorCount());
	unlink($tempfilename);
	my($Change) = ${$raChange}[0] =~ /^Change (\d+)/;
	chomp($Change);
	return $Change;
}
