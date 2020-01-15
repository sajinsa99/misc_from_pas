use File::Find;
use File::Path;
use File::Copy;
use File::Basename;

use FindBin;
use lib $FindBin::Bin;
use File::Path;
use IO::File;

use XML::DOM;
use Getopt::Long;
use Sys::Hostname;

use vars qw (
	$CURRENTDIR
	$HOST
	$OBJECT_MODEL
	$Site
	$BUILD_MODE
	$PROJECT
	$Context
	$BuildNumber
	$fullBuildNumber
	%SCM_SVs
	%SCM_MVs
	%SCMs
	$cleanLogFile
	$SRC_DIR
	%AREAS
	%PIs
	$nbFiles
	$Model
	$Config
	$Details
	$OS_FAMILY
	$OsFamilyHtmlFile
	$dateTime
	$Consolidate
	@Status
	@Writables
	@Missings
	$P4Details
);
sub Usage($);
sub getBuildRev();
sub parseContext();
sub mainReport();

if($^O eq "MSWin32") {
	$cbtPath = "C:/core.build.tools/export/shared";
} else {
	$cbtPath = "$ENV{'HOME'}/core.build.tools/export/shared";
}
push(@INC,"$cbtPath");

###

$Getopt::Long::ignorecase = 0;
GetOptions(
	"site=s"		=>\$Site,
	"buildname=s"	=>\$Context,
	"ini=s"			=>\$Config,
	"64!"			=>\$Model,
	"m=s"			=>\$BUILD_MODE,
	"v=s"			=>\$BuildNumber,
	"d"				=>\$Details,
	"c"				=>\$Consolidate,
	"l=s"			=>\$cleanLogFile,
	"p4d"			=>\$P4Details,
);

############ inits
#### system
$CURRENTDIR = $FindBin::Bin;
$HOST = hostname();
$OBJECT_MODEL = $Model ? "64" : "32" if(defined($Model));
$ENV{OBJECT_MODEL} = $OBJECT_MODEL ||= $ENV{OBJECT_MODEL} || "32";
unless($PLATFORM) {
	if($^O eq "MSWin32")    { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64" : "win32_x86"  }
	elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc"  }
	elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64" : "aix_rs6000"  }
	elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64" : "hpux_pa-risc" }
	elsif($^O eq "linux")   { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64" : "linux_x86"  }
}
$ENV{'PLATFORM'} = $PLATFORM;
$Site ||= $ENV{'SITE'} || "Walldorf";
if($^O eq "MSWin32") {
	$OS_FAMILY = "windows";
} else {
	$OS_FAMILY = "unix";
}

unless($Site eq "Levallois" || $Site eq "Walldorf" || $Site eq "Vancouver" || $Site eq "Bangalore"  || $Site eq "Paloalto" || $Site eq "Lacrosse") {
    die("\nERROR: SITE environment variable or 'perl $0 -s=my_site' must be set\navailable sites : Levallois | Walldorf | Vancouver | Bangalore | Paloalto | Lacrosse\n");
}
#### default values
$BUILD_MODE ||= $ENV{BUILD_MODE} || "release";
if("debug"=~/^$BUILD_MODE/i) { $BUILD_MODE="debug" } elsif("release"=~/^$BUILD_MODE/i) { $BUILD_MODE="release" } elsif("releasedebug"=~/^$BUILD_MODE/i) { $BUILD_MODE="releasedebug" }
else { Usage("compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease|releasedebug]"); }
$Context	||= "aurora41_cons";
$Config		||= "contexts/$Context.ini";

$ENV{PROJECT} = $Project || "aurora_dev";
require Site;

@Status = qw(Writables Missings);

$DROP_DIR ||= $ENV{'DROP_DIR'};
($DROP_DIR) =~ s /\\/\//g;

if( -e "$Config") {
	ReadIni();
} else {
	Usage("ini : '$Config' not found");
}

getBuildRev();

$HTTP_DIR = $ENV{'HTTP_DIR'};

###

getBuildRev();

$OsFamilyHtmlFile = "$DROP_DIR/$Context/filesRefetechedEachTime_$OS_FAMILY.html";
$dateTime  = scalar(localtime());

if($Consolidate) {
	mainReport();
	exit;
}

parseContext();
$cleanLogFile ||= "$HTTP_DIR/$Context/${Context}_$fullBuildNumber/Host_1/clean_step=${PLATFORM}_${BUILD_MODE}_infra.log";
($SRC_DIR = ExpandVariable(\$SRC_DIR)) =~ s/\\/\//g;
$SRC_DIR ||= $ENV{SRC_DIR};
$SRC_DIR .= "/";


open(CLEAN_LOG,"$cleanLogFile") or die("ERROR : cannot open '$cleanLogFile': $!\n");
	while(<CLEAN_LOG>) {
		chomp;
		if(/WARNING: update/) {
		    my ($fileStatus,$fullFile) = $_ =~ /WARNING\: update (writable|missing) (.+?) at /;
		    ($fullFile) =~ s-^$SRC_DIR--i;
		    my $area;
		    my ($areaCandidat,$versionCandidat) = $fullFile =~ /^(.+?)\/(.+?)\//;
		    my $Candidat = "$areaCandidat/$versionCandidat";
		    my $found = 0;
		    foreach my $areaInContext (sort(keys(%SCM_MVs))) {
	    		if($Candidat eq $areaInContext ) {
	    			$area = $areaInContext;
	    			$SCMs{$area} = $SCM_MVs{$areaInContext};
	    			$found = 1;
	    			last;
	    		}
		    }
		    if($found == 0) {
			    foreach my $areaInContext (sort(keys(%SCM_SVs))) {
		    		if($areaCandidat eq $areaInContext ) {
		    			$area = $areaInContext;
		    			$SCMs{$area} = $SCM_SVs{$areaInContext};
		    			last;
		    		}
			    }
		    }
			next if($area eq "Build");
			($area) =~ s-^\s+$--g;
			next unless($area);
			my $file = $fullFile;
			($file) =~ s-^$area\/--;
			push(@{$AREAS{$area}},$file);
			push(@Writables,"$SCMs{$area}/$file") if($fileStatus eq "writable");
			push(@Missings,"$SCMs{$area}/$file")  if($fileStatus eq "missing");
		}
	}
close(CLEAN_LOG);

my %PIs;
foreach my $area (sort(keys(%AREAS))) {
	if($area =~ /^tp\./) {
		push(@{$PIs{'aurora41_pi_tp'}},$area) unless( grep /^$area$/ , @{$PIs{'aurora41_pi_tp'}} );
		next;
	}
	my $ini = `grep -w $area $cbtPath/contexts/aurora41*.ini | grep -w MY_AREAS | grep -vi dev| grep -vi jlin| grep -vi patch| grep -vi sp| grep -vi feat| grep -vi cc_cpp| grep -vi cc_java| grep -vi QAC| grep -vi mwf| grep -vi fortify| grep -vi maint`;
	chomp($ini);
	if($ini) {
		my ($PI) = $ini =~ /\/contexts\/(.+?)\.ini\:/;
		if ($PI) {
			push(@{$PIs{$PI}},$area) unless( grep /^$area$/ , @{$PIs{$PI}} )
		}
	}
	$ini = "";
	$PI = "";
	$ini = `grep -w $area contexts/aurora41*.ini | grep -w MY_AREAS_COMPONENTS | grep -vi feat | grep -vi jlin`;
	chomp($ini);
	if($ini) {
		($PI) = $ini =~ /\/contexts\/(.+?)\.ini\:/;
		if ($PI) {
			push(@{$PIs{$PI}},$area) unless( grep /^$area$/ , @{$PIs{$PI}} )
		}
	}
}

if(open(HTML,">$OsFamilyHtmlFile")) {
	my $nbFiles=0;
	print HTML "
<!DOCTYPE html PUBLIC \"-\/\/W3C\/\/DTD XHTML 1.0 Transitional\/\/EN\" \"http:\/\/www.w3.org\/TR\/xhtml1\/DTD\/xhtml1-transitional.dtd\">
<html xmlns=\"http:\/\/www.w3.org\/1999\/xhtml\">
<head>
    <title>| files refetched - $Site - $PROJECT - $Context |<\/title>
    <meta http-equiv=\"content-type\" content=\"text\/html; charset=UTF-8\" \/>
    <meta http-equiv=\"content-language\" content=\"fr\" \/>
</head>
<body>
<br/>
<center><h3>files refetched by P4Clean due to RW mode in P4<br/>SITE : $Site<br/>PROJECT : $$ENV{PROJECT}<br/>Context : $Context<br/>Version : $BuildNumber<br/>OS FAMILY : $OS_FAMILY<br/>date : $dateTime</h3></center>
<br/>
<br/>
<br/>
<!-- START -->
<br/>
<br/>
<fieldset><legend><span onclick=\"document.getElementById('listAllFilesPerPI_$OS_FAMILY').style.display = (document.getElementById('listAllFilesPerPI_$OS_FAMILY').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">List All files per PI</span></legend>
<div style=\"display:none;\" id=\"listAllFilesPerPI_$OS_FAMILY\">
<br/>
";
}

###TO DO
if($P4Details) {
	my @NOTInP4;
	my @RWInP4;
	my @ROInP4;
	foreach my $PI (sort(keys(%PIs))) {
		foreach my $area (sort(@{$PIs{$PI}})) {
			foreach my $file (sort(@{$AREAS{$area}})) {
				my $scmFile = "$SCMs{$area}/$file";
				my $p4FileState;
				open(P4_FILE_STATE,"p4 fstat -Ol -Oh -C \"$scmFile\" 2>&1 |");
					while(<P4_FILE_STATE>) {
						chomp;
						if(/no such file/) {
							push(@NOTInP4,$scmFile);
							last;
						}
						if(/headType/) {
							if(/w/) {
								push(@RWInP4,$scmFile);
							} else {
								push(@ROInP4,$scmFile);
							}
							last;
						}
					}
				close(P4_FILE_STATE);
			}
		}
	}
	my @fileStatusInP4 = qw (NOTInP4 RWInP4 ROInP4) ;
	foreach my $statusInp4 (@fileStatusInP4) {
		$_ = $statusInp4;
		SWITCH:
		{
			/NOTInP4/		and print "\t-->not in perforce:\n";
			/RWInP4/		and print "\t-->rw mode in perforce:\n";
			/ROInP4/		and print "\t-->ro mode in perforce:\n";
		}
		foreach my $file (sort(@{$statusInp4})) {
			print "$file\n";
		}
		print "\n";
	}
	exit;
}


foreach my $PI (sort(keys(%PIs))) {
	my $nbFilesPerPI=0;
	foreach my $area (sort(@{$PIs{$PI}})) {
		$nbFilesPerPI = $nbFilesPerPI + (@{$AREAS{$area}});
	}
	print "\n$PI - $nbFilesPerPI file(s)\n";
	my $idPI = "${PI}_$OS_FAMILY";
	print HTML "
	<fieldset><legend><span onclick=\"document.getElementById('$idPI').style.display = (document.getElementById('$idPI').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">$PI - $nbFilesPerPI file(s)</span></legend>
	<div style=\"display:block;\" id=\"$idPI\">
	<br/>
	&nbsp;&nbsp;&nbsp;&nbsp;<u>List all files per area :</u><br/><br/>
";
	foreach my $area (sort(@{$PIs{$PI}})) {
		my $nbFilePerArea = (@{$AREAS{$area}});
		print "\t$area - $nbFilePerArea file(s)\n";
		my $idArea = $area;
		($idArea) =~ s-\/-_-g;
		$idArea = "${idPI}_$idArea";
		print HTML "
		&nbsp;&nbsp;&nbsp;&nbsp;<span onclick=\"document.getElementById('$idArea').style.display = (document.getElementById('$idArea').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\"><font color=\"blue\">$area - $nbFilePerArea file(s)</font></span>
		<div style=\"display:none;\" id=\"$idArea\">
		<br/>
		<table border=\"0\">
";
		foreach my $file (sort(@{$AREAS{$area}})) {
			my $scmFile = "$SCMs{$area}/$file";
			print "\t\t$scmFile\n" if($Details);
			my $statusFile;
			foreach my $search (@Writables) {
				if($search eq $scmFile) {
					$statusFile = "writable";
					last;
				}
			}
			foreach my $search (@Missings) {
				if($search eq $scmFile) {
					$statusFile = "missing";
					last;
				}
			}
			print HTML "			<tr onmouseover=\"this.style.backgroundColor='\#D3D3D3'\" onmouseout=\"this.style.backgroundColor='white'\"><td>$scmFile</td><td>$statusFile</td></tr>\n";
			$nbFiles++;
		}
		print HTML "
		</table>
		</div>
		<br/>
";
	}
	my $idPIAll = "${idPI}_all";
	print HTML "
	<br/>
	<hr align=\"center\" width=\"33%\" color=\"blue\" size=\"5\"> 
	&nbsp;&nbsp;&nbsp;&nbsp;<span onclick=\"document.getElementById('$idPIAll').style.display = (document.getElementById('$idPIAll').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\"><font color=\"blue\"><u>List all files of $PI</u></font></span>
	<div style=\"display:none;\" id=\"$idPIAll\">
	<br/>
	";
	foreach my $area (sort(@{$PIs{$PI}})) {
		foreach my $file (sort(@{$AREAS{$area}})) {
			my $scmFile = "$SCMs{$area}/$file";
			print HTML "$scmFile<br/>\n";
		}
	}
	print HTML "
	<br/>
	</div>
	<br/>
	</div>
	<br/>
	</fieldset>
	<br/>
	<br/>
";
}

print "
nb files: $nbFiles
";

		print HTML "
</div>
</fieldset>
<br/>
<hr></hr>
<br/>
<br/>
<fieldset><legend><span onclick=\"document.getElementById('listAllFiles_$OS_FAMILY').style.display = (document.getElementById('listAllFiles_$OS_FAMILY').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">List All files</span></legend>
<div style=\"display:none;\" id=\"listAllFiles_$OS_FAMILY\">
<br/>
";

		foreach $myStatus (@Status) {
			print HTML "
		&nbsp;&nbsp;&nbsp;&nbsp;<span onclick=\"document.getElementById('${myStatus}_$OS_FAMILY').style.display = (document.getElementById('${myStatus}_$OS_FAMILY').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\"><font color=\"blue\">$myStatus</font></span>
		<div style=\"display:none;\" id=\"${myStatus}_$OS_FAMILY\">
		<br/>
";
			foreach $file (@${myStatus}) {
				print HTML "$file<br/>\n";
			}
			print HTML "<br/></div><br/><br/>\n";
		}
	
		print HTML "
<br/>
</div>
</fieldset>
<br/>
<hr></hr>
<br/>
<br/>
Total files refetched all the time : $nbFiles
<br/>
<br/>
<!-- STOP -->
</body>
</html>
";
close(HTML);
print "\n$OsFamilyHtmlFile\n";

exit;

#######################################################################################################################################################################################################
sub mainReport() {
	if( ( -e "$DROP_DIR/$Context/filesRefetechedEachTime_windows.html" ) && ( -e "$DROP_DIR/$Context/filesRefetechedEachTime_unix.html" ) ) {
		my $MainReportHtmlFile = "$DROP_DIR/$Context/filesRefetechedEachTime.html";
		my @os_families = qw(windows unix);
		if(open(MAIN_REPORT,">$MainReportHtmlFile")) {
			print MAIN_REPORT "
<html>
<head>
    <title>| files refetched - $Site - $PROJECT - $Context |<\/title>
    <script language=\"javascript\" type=\"text/javascript\">
        function select(elem)
        {
            curNavBarElem.className	= 'wbar';
            elem.className = 'bbar';		
            curNavBarElem =	elem;
            document.all['windows'].style.display	= 'none';
            document.all['unix'].style.display	= 'none';
            document.all[elem.firstChild.nodeValue].style.display = '';
        }
    </script>
    <style type=\"text/css\">
        .bbar {width:120;background-color:3366cc;color:white;text-align:center;font-weight:bold;font-size:small;cursor:pointer}
        .wbar {width:120;background-color:cfcfcf;color:blue;text-align:center;font-size:small;cursor:pointer}
    </style>
</head>
<body>
<br/>
<center><h3><a href=\"https://tdwiki.pgdev.sap.corp/display/RM/no+RW+files+in+Perforce+to+skip+to+sync+them+by+P4Clean.pl+all+the+time\" target=\"_blank\">files refetched by P4Clean due to RW mode in P4</a><br/>SITE : $Site<br/>PROJECT : $$ENV{PROJECT}<br/>Context : $Context<br/>Version : $BuildNumber<br/>date : $dateTime</h3></center>
<br/>
<br/>
<br/>

<table id=\"navbar\" border=\"0\" cellpadding=\"0\"	cellspacing=\"0\">
    <tr>
        <td class=\"wbar\" config=\"windows\" nowrap onclick=select(this)>windows</td>
        <td width=\"1\" bgcolor=\"808080\"><img	width=\"1\" height=\"1\" alt=''></td>
        <td width=\"1\" bgcolor=\"white\"><img width=\"1\" height=\"1\"	alt=''></td>
        <td class=\"wbar\" config=\"unix\" nowrap onclick=select(this)>unix</td>
        <td width=\"1\" bgcolor=\"808080\"><img	width=\"1\" height=\"1\" alt=''></td>
        <td width=\"1\" bgcolor=\"white\"><img width=\"1\" height=\"1\"	alt=''></td>
    </tr>
</table>
<table width=\"100%\" cellpadding=\"2\"	cellspacing=\"0\" border=\"0\">
	<tr><td	bgcolor=\"3366CC\" nowrap>&nbsp;</td></tr>
</table>
<br/>
<ul>
<li>click on pi build to show/hide area(s) impacted</li>
<li>click on area(s) to show/hide file(s) impacted per area</li>
<li>click on 'List all files of \$PI build name' to show/hide file(s) impacted</li>
</ul>
<br/>
";
			foreach my $osFamily (@os_families) {
				print MAIN_REPORT "
<div id=\"$osFamily\" style=\"display:'block';text-align:justify;margin-left:1cm\">\n";
				if(open(PLATFORM,"$DROP_DIR/$Context/filesRefetechedEachTime_$osFamily.html")) {
						my $ok = 0;
						while(<PLATFORM>) {
							chomp;
							print MAIN_REPORT "$_\n" if ($ok == 1);
							$ok = 1 if(/^\<\!\-\-\s+START\s+\-\-\>/);
							$ok = 0 if(/^\<\!\-\-\s+STOP\s+\-\-\>/);
						}
					close(PLATFORM);
				} else {
					print MAIN_REPORT "no report\n";
				}
				print MAIN_REPORT "</div>\n";
			}
			print MAIN_REPORT "
<br/>
<br/>

<script language=\"javascript\" type=\"text/javascript\">
	var curNavBarElem = document.all.navbar.rows[0].cells[0];
</script>

</body>
</html>
";
			close(MAIN_REPORT);
			print "$MainReportHtmlFile\n";
		}
	}
}


sub getBuildRev() {
	if(open(VER, "$DROP_DIR/$Context/version.txt"))
	{
	    chomp($BuildNumber = <VER>);
	    $BuildNumber = int($BuildNumber);
	    close(VER);
	}
	$fullBuildNumber = sprintf("%05d", $BuildNumber);
}

sub parseContext() {
	my $XMLContext = "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files/$Context.context.xml";
	my $CONTEXT = XML::DOM::Parser->new()->parsefile($XMLContext);
	
	for my $SYNC (@{$CONTEXT->getElementsByTagName("fetch")}) {
	    my($File, $Revision, $Workspace) = ($SYNC->getFirstChild()->getData(), $SYNC->getAttribute("revision"), $SYNC->getAttribute("workspace"));
	    (my $area) = $Workspace =~ /\/\/\$\{Client\}\/(.+?)\/\.\.\./;
	    next if($area =~ /^Build/);
	    ($File) =~ s-\/\.\.\.$--;
	    if($area =~ /\//) {
	    	$SCM_MVs{$area}=$File;
	    } else {
	    	$SCM_SVs{$area}=$File;
	    }
	    #print "$area -> $File\n";
	}
	$CONTEXT->dispose();
}

#######################################################################################################################################################################################################

sub Usage($) {
	my ($msg) = @_ ;
	if($msg)
	{
		print STDERR "
\tERROR:
\t======
$msg
";
	}
	print "
	Usage	: perl $0 [options]
	Example	: perl $0 -h

[options]
	-h|?		argument displays helpful information about builtin commands.
	-s		choose a site, by default: -s=$Site
	-b		choose a buildname, by default: -b=$Context
	-i		choose an in file, by default: -i=contexts/buildname.ini,
			without -b option, -i=contexts/$Context.ini,
	-64		force the 64 bits compilation (-64) or not (-no64), default is -no64 i.e 32 bits,
			same usage than Build.pl
	-m		choose a compile mode,
			same usage than Build.pl -m=
	-r		choose a reference version
	-v		choose a new version as incremental build,
			same usage than Build.pl -v=
	-p		with deploymentunits (build units started by 'package.')
	-po		with ONLY deploymentunits (build units started by 'package.')
	-a		choose a list of failed areas, separated with ','
			eg.: -a=areaA,areaB,areaC
	-na		choose to skip a list of failed areas, separated with ','
			eg.: -na=areaA,areaB,areaC
	-ndt		Not Display Times, to skip display times
	-dto		Display Times Only, display only times
	-jm		build only missed build units (not compiled)
	-F		execute 'perl Build.pl ... -F'
	-nfe		display the N First Error(s)
	-N		No execution of Build.pl called in $0
			cannot use -N with -Q
	-Q		Quiet mode, Suppresses prompting to confirm you want to execute Build.pl called in $0
			cannot use -Q with -N

";
	exit;
}
###########################
### functions from Build.pl
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
            elsif($Section eq "prefetchcmd")     { push(@PrefetchCmds, [split('\s*\|\s*', $_)]); Monitor(\${$PrefetchCmds[-1]}[2]) } 
            elsif($Section eq "dependenciescmd") { push(@DependenciesCmds, [split('\s*\|\s*', $_)]); Monitor(\${$DependenciesCmds[-1]}[2]) } 
            elsif($Section eq "packagecmd")      { push(@PackageCmds, [split('\s*\|\s*', $_)]); Monitor(\${$PackageCmds[-1]}[2]) } 
            elsif($Section eq "cleancmd")        { push(@CleanCmds, [split('\s*\|\s*', $_)]); Monitor(\${$CleanCmds[-1]}[2]) } 
            elsif($Section eq "buildcmd")        { push(@BuildCmds, [split('\s*\|\s*', $_)]); Monitor(\${$BuildCmds[-1]}[2]) } 
            elsif($Section eq "mailcmd")         { push(@MailCmds, [split('\s*\|\s*', $_)]); Monitor(\${$MailCmds[-1]}[2]) } 
            elsif($Section eq "testcmd")         { push(@TestCmds, [split('\s*\|\s*', $_)]); Monitor(\${$TestCmds[-1]}[2]) } 
            elsif($Section eq "smokecmd")        { push(@SmokeCmds, [split('\s*\|\s*', $_)]); Monitor(\${$SmokeCmds[-1]}[2]) }  
            elsif($Section eq "reportcmd")       { push(@ReportCmds, [split('\s*\|\s*', $_)]); Monitor(\${$ReportCmds[-1]}[2]) }  
            elsif($Section eq "export")          { push(@Exports, $_); Monitor(\$Exports[-1]) } 
            elsif($Section eq "adapt")           { push(@Adapts, $_); Monitor(\$Adapts[-1]) } 
            elsif($Section eq "monitoring")      { push(@BMonitors, [split('\s*\|\s*', $_)]); Monitor(\${$BMonitors[-1]}[0]); Monitor(\${$BMonitors[-1]}[1]);}
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
                my($Platform, $Root) = split('\s*\|\s*', $_);
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
                $Value = ExpandVariable(\$Value) if($Value =~ /\${$Key}/);                
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
                $Value = ExpandVariable(\$Value) if($Value =~ /\${$Key}/);
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
        elsif(my($IncludeFile) = $Line =~ /^\s*\#include\s+(.+)$/) { push(@Lines, PreprocessIni($IncludeFile, $rhDefines)) }
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
	my($ss, $mn, $hh, $dd, $mm, $yy, $wd, $yd, $isdst) = localtime($Time);
	#return sprintf("%04u/%02u/%02u %02u:%02u:%02u", $yy+1900, $mm+1, $dd, $hh, $mn, $ss);
	return sprintf("%02u:%02u:%02u", $hh, $mn, $ss);
}

sub HHMMSS
{
	my($Difference) = @_;
	my $s = $Difference % 60;
	$Difference = ($Difference - $s)/60;
	my $m = $Difference % 60;
	$h = ($Difference - $m)/60;
	return sprintf("%02u:%02u:%02u", $h, $m, $s);
}
