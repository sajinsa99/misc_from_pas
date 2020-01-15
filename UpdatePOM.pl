#!/usr/bin/perl -w

use Sys::Hostname;
use Getopt::Long;
use XML::DOM;
use Cwd;
use FindBin;
use lib ($FindBin::Bin);
use Perforce;

use File::Path;
use File::Copy;
use File::Find;

our $ReadDat_windows   = "windows/aurora.read.dat";
our $CreateDat_windows = "windows/aurora.create.dat";
our $ReadDat_unix      = "unix/aurora.read.dat";
our $CreateDat_unix    = "unix/aurora.create.dat";

$IsIncrementalMode = 1;
@Platforms = qw(windows unix);

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "ini=s"=>\$Config, "makefile=s"=>\$Makefile, "64!"=>\$Model, "CP"=>\$CopyPoms,"RP"=>\$RestorePoms);
Usage() if($Help);
unless($Config) { print(STDERR "ERROR: -i.ni option is mandatory.\n"); Usage() }

$repositoriesDir = ($^O eq "MSWin32") ? "C:/core.build.tools/repositories" : "$ENV{HOME}/core.build.tools/repositories";
restoreOrigPoms() if($RestorePoms);

$OBJECT_MODEL = $Model ? "64" : "32" if(defined($Model));
$ENV{OBJECT_MODEL} = $OBJECT_MODEL ||= $ENV{OBJECT_MODEL} || "32";
if($^O eq "MSWin32")    { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64" : "win32_x86"  }
elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc"  }
elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64" : "aix_rs6000"  }
elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64" : "hpux_pa-risc" }
elsif($^O eq "linux")   { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64" : "linux_x86"  }
our $HOST = hostname();
$NULLDEVICE = $^O eq "MSWin32" ? "nul" : "/dev/null";
die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/[\\\/]\d+$//;
our $CURRENTDIR = $FindBin::Bin;
ReadIni();
$Makefile ||= $IncrementalCmds[2];
$POMFile ||= "$SRC_DIR\\aurora\\pom.xml";

########
# Main #
########

$p4 = new Perforce;
$p4->SetClient($Client);
die("ERROR: cannot set client '$Client': ", @{$p4->Errors()}, " ") if($p4->ErrorCount());

copyUpdatedPoms() if($CopyPoms);

$p4->revert("-c default //.../pom.xml");
die("ERROR: cannot p4 revert 'default': ", @{$p4->Errors()}, " ") if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/not opened on this client\.$/);

#$Units{$Unit} = [$Area, \%UnitProviders, \%UnitClients];
#$Areas{$Area} = [\%Units, \%GAVProviders, \%GAVClients]
#$Files{$File} = [\%ReadAreaUnit, \%WriteAreaUnit];
print("============Read DAT files\n");
foreach my $Platform (@Platforms)
{
    open(DAT, ${"ReadDat_$Platform"}) or die("ERROR: cannot open '",${"ReadDat_$Platform"},"': $!");
    UNIT: while(<DAT>)
    {
        next unless(my($Area, $Unit) = /\@{\$g_read\{'(.+):(.+)'}}/);
        while(<DAT>)
        {
            chomp;
            next UNIT if(/^}/);
            next unless(my($File) = /'([^']+)'/);
            ${${$Files{$File}}[0]}{"$Area:$Unit"} = undef;
            $AreaListFromDAT{$Area} = $UnitListFromDAT{$Unit} = undef;
        }
    }
    close(DAT);
    open(DAT, ${"CreateDat_$Platform"}) or die("ERROR: cannot open '",${"CreateDat_$Platform"},"': $!");
    UNIT: while(<DAT>)
    {
        next unless(my($Area,$Unit) = /\@{\$g_create\{'(.+):(.+)'}}/);
        while(<DAT>)
        {
            chomp;
            next UNIT if(/^}/);
            next unless(my($File) = /'([^']+)'/);
            ${${$Files{$File}}[1]}{"$Area:$Unit"} = undef;
            $AreaListFromDAT{$Area} = $UnitListFromDAT{$Unit} = undef;
        }
    }
    close(DAT);
}

print("============Read makefiles\n");
#$p4->sync("-f", "//.../*.gmk");
#die("ERROR: cannot sync '//.../*.gmk': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date\.$/);

@AreaList = sort(Read("AREAS", $Makefile));
#@AreaList = qw(DSL);
for(my $i=0; $i<@AreaList; $i++)
{
    my $Area = $AreaList[$i];
    (my $Ar = $Area) =~ s/[\\\/][^\\\/]+$//;
    unless(exists($AreaListFromDAT{$Area})) { warn("ERROR: '$Area/pom.xml' won't be update ($Area not found in DAT files)"); $AreaList[$i]=undef; next }
    unless(-e "$SRC_DIR/$Area/$Ar.gmk") { warn("ERROR: '$Area/pom.xml' won't be update ($SRC_DIR/$Area/$Ar.gmk not found)"); $AreaList[$i]=undef; next }
    @{${$Areas{$Area}}[0]}{Read("UNITS", "$SRC_DIR/$Area/$Ar.gmk")} = ();
    foreach my $Unit (keys(%{${$Areas{$Area}}[0]}))  { ${$Units{$Unit}}[0] = $Area }
}
@AreaList = grep({$_} @AreaList);

print("=========== Compute dependencies\n");
Properties($POMFile);
foreach my $File (keys(%Files))
{
	foreach my $ReadAreaUnit (keys(%{${$Files{$File}}[0]}))
	{
		my($ReadArea, $ReadUnit) = split(':', $ReadAreaUnit);		
		unless(exists($Areas{$ReadArea})) { warn("ERROR: '$ReadArea' area not found in the makefile '$Makefile'"); next }
		unless(exists($Units{$ReadUnit})) { warn("ERROR: '$ReadAreaUnit' unit not found in the makefile '$SRC_DIR/$ReadArea/$ReadArea.gmk'"); next }
		if(keys(%{${$Files{$File}}[1]}))
		{
    		foreach my $WriteAreaUnit (keys(%{${$Files{$File}}[1]}))
    		{
    			my($WriteArea, $WriteUnit) = split(':', $WriteAreaUnit);
    			unless(exists($Areas{$WriteArea})) { warn("ERROR: '$WriteArea' not found in the makefile '$Makefile'"); next }
    			unless(exists($Units{$WriteUnit})) { warn("ERROR: '$WriteAreaUnit' not found in the makefile '$Makefile'"); next }
                if($File !~ /\/$WriteArea\// || $File !~ /\/$WriteUnit\//) { warn("ERROR: multiple write of '$File' by $WriteAreaUnit"); next }
                if($WriteArea ne $ReadArea)
                {                    			
                    my $GAV = GAV($File);
                    next unless($GAV);
                    ${${$Areas{$ReadArea}}[1]}{$GAV} = undef;
                    #${${$Areas{$WriteArea}}[2]}{$ReadArea} = undef;
                }
    			#if($WriteUnit ne $ReadUnit)
    			#{
    			#	${${$Units{$ReadUnit}}[1]}{$WriteUnit} = undef;
    			#	${${$Units{$WriteUnit}}[2]}{$ReadUnit} = undef;
    			#}			
            }		
        }
        elsif(my($Area) = $File =~ /\$SRC_DIR\/([^\/]+)/)
        {
        	(my $readarea = $ReadArea) =~ s/\/.*$/$1/;
            next if($Area eq "aurora" || $Area eq "Build" || $readarea eq $Area);
            my $GAV = GAV($File);
            next unless($GAV);
            ${${$Areas{$ReadArea}}[1]}{$GAV} = undef;
        }
        else { warn("ERROR: '$File' is ignored") }		
	}
}

print(scalar(keys(%Areas)), " areas.\n");
print(scalar(keys(%Units)), " build units.\n");

print("============ update POM\n");
$p4->sync("-f", "//.../pom.xml");
die("ERROR: cannot sync '//.../pom.xml': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date\.$/);

## Update POM ##
AREA: foreach my $Area1 (@AreaList)
{
    my $rhProviders = ${$Areas{$Area1}}[1];
    my(%Dependencies1,%Dependencies2);
    print("$SRC_DIR/$Area1/pom.xml\n");
    eval
    {
        my $POM = XML::DOM::Parser->new()->parsefile("$SRC_DIR/$Area1/pom.xml");
        for my $DEPENDENCY (@{$POM->getElementsByTagName("dependency")})
        {
            my $GroupId    = $DEPENDENCY->getElementsByTagName("groupId", 0)->item(0)->getFirstChild()->getData();
            my $ArtifactId = $DEPENDENCY->getElementsByTagName("artifactId", 0)->item(0)->getFirstChild()->getData();
            my $Version    = $DEPENDENCY->getElementsByTagName("version", 0)->item(0)->getFirstChild()->getData();
            $Dependencies1{"$GroupId:$ArtifactId:$Version"} = undef;
        }
  	    $POM->dispose();
	};
	warn("ERROR:cannot parse '$SRC_DIR/$Area1/pom.xml': $@; $!") if($@);
    foreach my $GAV (keys(%{$rhProviders}))
    {
        $Dependencies2{$GAV} = undef;
    }         
    my %Dependencies;
    if($IsIncrementalMode) { @Dependencies{keys(%Dependencies1), keys(%Dependencies2)} = undef }
    else { %Dependencies = %Dependencies2 }
    my $ToUpdate = 0;
    foreach my $GAV (keys(%Dependencies1)) { $ToUpdate = 1 unless(exists($Dependencies{$GAV})) }
    foreach my $GAV (keys(%Dependencies)) { $ToUpdate = 1 unless(exists($Dependencies1{$GAV})) }
    next AREA unless($ToUpdate);
    print("update $SRC_DIR/$Area1/pom.xml\n");        
    foreach my $Ar (keys(%Dependencies1)) { print("\t$Ar is obsolete\n") unless(exists($Dependencies2{$Ar})) }
    foreach my $Ar (keys(%Dependencies2)) { print("\t$Ar is new\n") unless(exists($Dependencies1{$Ar})) }
    UpdatePOM("$SRC_DIR/$Area1/pom.xml", \%Dependencies);
}

#($Prjct = $Project) =~ s/Aurora/aurora/;
#$POM = XML::DOM::Parser->new()->parsefile("$SRC_DIR/$Prjct/pom.xml");
#for my $DEPENDENCY (@{$POM->getElementsByTagName("dependency")})
#{
#    my $GroupId    = $DEPENDENCY->getElementsByTagName("groupId", 0)->item(0)->getFirstChild()->getData();
#    my $ArtifactId = $DEPENDENCY->getElementsByTagName("artifactId", 0)->item(0)->getFirstChild()->getData();
#    my $Version    = $DEPENDENCY->getElementsByTagName("version", 0)->item(0)->getFirstChild()->getData();
#    $Dependencies1{"$GroupId:$ArtifactId:$Version"} = undef;
#}
#foreach my $Area (@AreaList)
#{
#    my($rhClients, $GroupId, $ArtifactId, $Version) = @{$Areas{$Area}}[2..5];
#    next if(keys(%{$rhClients}));
#    $Dependencies{"$GroupId:$ArtifactId:$Version"} = undef;
#}
#$ToUpdate = 0;
#foreach my $GAV (keys(%Dependencies1)) { $ToUpdate = 1 unless(exists($Dependencies{$GAV})) }
#foreach my $GAV (keys(%Dependencies)) { $ToUpdate = 1 unless(exists($Dependencies1{$GAV})) }
#if($ToUpdate)
#{
#    my $rafstat = $p4->fstat("$SRC_DIR/$Prjct/pom.xml");
#    foreach (@{$rafstat})
#    {
#        $DepotFile = $1 if(/depotFile\s+(.+\/pom.xml)$/); 
#    }
#    UpdatePOM("$SRC_DIR/$Prjct/pom.xml", \%Dependencies);
#}


END 
{ 
    $p4->Final() if($p4); 
}

#############
# Functions #
#############

sub UpdatePOM
{
    my($POMFile, $rhDependencies) = @_;
    
    my $POM = XML::DOM::Parser->new()->parsefile($POMFile);
    # update <scm> tag
    foreach my $SCM (@{$POM->getElementsByTagName("scm")})
    {
        $POM->getDocumentElement()->removeChild($SCM);
    }
    my $SCM = $POM->createElement("scm");
    my $CONNECTION = $POM->createElement("connection");
    $CONNECTION->addText("scm:perforce:\$Id:\$");
    $SCM->appendChild($CONNECTION);        
    my $DEVELOPERCONNECTION = $POM->createElement("developerConnection");
    $DEVELOPERCONNECTION->addText("scm:perforce:\$Id:\$");
    $SCM->appendChild($DEVELOPERCONNECTION);
    $POM->getDocumentElement()->appendChild($SCM);
    # update <dependencies> tag
    foreach my $DEPENDENCIES (@{$POM->getElementsByTagName("dependencies")})
    {
        $POM->getDocumentElement()->removeChild($DEPENDENCIES);
    }
    my $DEPENDENCIES = $POM->createElement("dependencies");
    foreach my $GAV (sort(keys(%{$rhDependencies})))
    {
        my($GroupId, $ArtifactId, $Version) = split(':', $GAV);
        my $DEPENDENCY = $POM->createElement("dependency");
        my $GROUPID = $POM->createElement("groupId");
        $GROUPID->addText($GroupId);
        $DEPENDENCY->appendChild($GROUPID);
        my $ARTIFACTID = $POM->createElement("artifactId");
        (my $Ar=$ArtifactId) =~ s/[\\\/][^\\\/]*$//;
        $ARTIFACTID->addText($Ar);
        $DEPENDENCY->appendChild($ARTIFACTID);
        my $VERSION = $POM->createElement("version");
        $VERSION->addText($Version);
        $DEPENDENCY->appendChild($VERSION);
        $DEPENDENCIES->appendChild($DEPENDENCY);
    }
    $POM->getDocumentElement()->appendChild($DEPENDENCIES);
    $POM->printToFile("$TEMPDIR/pom_$$.xml");
    chmod(0755, $POMFile) or die("ERROR: cannot chmod '$POMFile': $!");
    open(SRC, "$TEMPDIR/pom_$$.xml") or die("ERROR: cannot open '$TEMPDIR/pom_$$.xml': $!");
    open(DST, ">$POMFile") or die("ERROR: cannot open '$POMFile': $!");
    my $WasBlank = 0;
    while(<SRC>)
    {
        next if($WasBlank && /^\s*$/);
        $WasBlank = /^\s*$/;
        if(/<scm><connection>/)
        {
            s/<scm>/    <scm>\n/g;
            s/<\/scm>/    <\/scm>\n\n/g;
            s/<connection>/        <connection>/g;
            s/<\/connection>/<\/connection>\n/g;
            s/<developerConnection>/        <developerConnection>/g;
            s/<\/developerConnection>/<\/developerConnection>\n/g;
            s/<dependencies>/    <dependencies>\n/g;
            s/<\/dependencies>/    <\/dependencies>\n\n/g;
            s/<dependency>/        <dependency>\n/g;
            s/<\/dependency>/        <\/dependency>\n/g;
            s/<groupId>/            <groupId>/g;
            s/<\/groupId>/<\/groupId>\n/g;
            s/<artifactId>/            <artifactId>/g;
            s/<\/artifactId>/<\/artifactId>\n/g;
            s/<version>/            <version>/g;
            s/<\/version>/<\/version>\n/g;
        }
        print(DST);
    }
    close(DST);     
    close(SRC);     
    unlink("$TEMPDIR/pom_$$.xml") or die("ERROR: cannot unlink '$TEMPDIR/pom_$$.xml': $!");
    $p4->edit("-t ktext", $POMFile);
    if($p4->ErrorCount())
    {
        if(${$p4->Errors()}[0]=~/already opened for add/) { }  
        else { die("ERROR: cannot p4 edit '$POMFile': ", @{$p4->Errors()}) }
    }
}

sub GAV
{
    my($File) = @_;
    
    my($Area, $AreaVersion, $POMFile);
    if($File =~ /\$SRC_DIR\//) { ($Area, $AreaVersion) = $File =~ /\$SRC_DIR\/([^\/]+)\/([^\/]+)/ }
    elsif($File =~ /\$OUTPUT_DIR\//) { ($Area, $AreaVersion) = $File =~ /\$OUTPUT_DIR\/[^\/]+\/([^\/]+)\/([^\/]+)/ }
    else { warn("ERROR: '$File' is ignored"); return }
    if(exists($Properties{$Area}{$AreaVersion}) && $Properties{$Area}{$AreaVersion} ne "default") { $POMFile = "$SRC_DIR/$Area/$Properties{$Area}{$AreaVersion}/pom.xml" }
    else { $POMFile = "$SRC_DIR/$Area/pom.xml" }
	unless(-e $POMFile) { warn("ERROR: not pom.xml find for '$File'"); return }
    return $GAVs{$POMFile} if(exists($GAVs{$POMFile}));
      
    my $POM = XML::DOM::Parser->new()->parsefile($POMFile);
    my $PROJECT = $POM->getElementsByTagName("project")->item(0);
    my $GroupId    = $PROJECT->getElementsByTagName("groupId", 0)->item(0)->getFirstChild()->getData();
    my $ArtifactId = $PROJECT->getElementsByTagName("artifactId", 0)->item(0)->getFirstChild()->getData();
    my $Version    = $PROJECT->getElementsByTagName("version", 0)->item(0)->getFirstChild()->getData();

    die("ERROR: groupId not found in $POMFile\n")    unless($GroupId);
    die("ERROR: artifactId not found in $POMFile\n") unless($ArtifactId);
    die("ERROR: version not found in $POMFile\n")    unless($Version);
    return $GAVs{$POMFile}="$GroupId:$ArtifactId:$Version";   
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

#######################################################################################################################################################################################################
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
                Monitor(\$SRC_DIR);
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
###################################################################################################

sub Properties
{
    my($POMFile) = @_;
    my $POM = XML::DOM::Parser->new()->parsefile($POMFile);
    for my $PROJECT (@{$POM->getElementsByTagName("project")})
    {
        for my $PROPERTIES (@{$PROJECT->getElementsByTagName("properties")})
        {
            foreach my $Properties ($PROPERTIES->getChildNodes())
            {
                if($Properties->getNodeType() == ELEMENT_NODE)
                {
                    my($Name, $Value) = ($Properties->getNodeName(), $Properties->getFirstChild()->getData());
                    foreach my $Versions (split(";", $Value))
                    {
                        my($SrcVersion, $DstVersion) = $Versions =~ /:/ ? split(":", $Versions) : ($Versions, $Versions);
                        $DstVersion ||= "default";
                        $Properties{$Name}{$DstVersion} = $SrcVersion;
                    }
                }
            }
        }
    }
    $POM->dispose();
}

### prepare test poms
sub copyUpdatedPoms {
	print "\nprepare $repositoriesDir for test\n\n";
	my %POMS = ListOfOPenedPOM();
	if(%POMS) {
		foreach my $artifactVersion (keys(%POMS)) {
			my ($artifact,$version)	=  $artifactVersion =~ /^(.+?)\_version(.+?)$/i;
			my $branch		=  $POMS{$artifactVersion}->[0];
			my $srcPomFile	=  $POMS{$artifactVersion}->[1];
			print "\t$artifact - $version  - $branch\n";
			if( -e "$srcPomFile" ) {
				my $destDir = "$repositoriesDir/$branch/$artifact/${version}-SNAPSHOT";
				my $destFile = "$destDir/pom.xml";
				mkpath("$destDir") if( -e "$destDir");
				if( -e "$destFile" ) {
					print "backup  : $destFile -> $destFile.orig\n";
					if( ! -e "$destFile.orig" ) {
						copy("$destFile","$destFile.orig") or warn("WARNING : cannot copy $destFile to $destFile : $!\n")
					}
				}
				print "copy    : $srcPomFile -> $destFile\n";
				copy("$srcPomFile","$destFile") or warn("WARNING : cannot copy $srcPomFile to $destFile : $!\n");
			} else {
				print "$srcPomFile not found, please check\n";
			}
			print "\n";
		}
	}
	$p4->Final() if($p4);
	print "\n";
	exit;
}

sub ListOfOPenedPOM {
	my @ClientSpecDescr = $p4->client("-o");
	(my $Root = $ClientSpecDescr[0]{Root}) =~ s-^\s+--; # get roo value
	($Root) =~ s-\\-\/-g;	#transform to unix style, supported under windows if no DOS command executed
	my @Views = @{$ClientSpecDescr[0]{View}}; #get views
	my %tmp;
	foreach my $openedFile ($p4->opened()) {
		foreach my $file (@$openedFile) {
			chomp($file);
			next unless($file =~ /\/pom.xml/);
			my ($depot,$artifact,$version,$branch) = $file =~ /^\/\/(.+?)\/(.+?)\/(.+?)\/(.+?)\//;
			foreach my $View (@Views) { # need to check for TPs sv/mv
				if($View =~ /^\/\/$depot\/$artifact\/$version\/$branch/) {
					my ($scm,$target) = $View =~ /^(.+?)\s+(.+?)$/ ;
					(my $srcPomFile = $target) =~ s-^\/\/$Client-$Root-;
					($srcPomFile) =~ s-\.\.\.$-pom.xml-;
					my $artifactVersion = "${artifact}_version$version";
					@{$tmp{$artifactVersion}} = ($branch,$srcPomFile);
				}
			}
			
		}
	}
	return %tmp if(%tmp);
}

sub restoreOrigPoms {
	print "\nrestore pom.xml.orig in $repositoriesDir, please wait ...\n\n";
	find(sub{if(/pom.xml.orig$/i){ restorePom($File::Find::name) }}, "$repositoriesDir");
	print "\n";
	exit;
}

sub restorePom($) {
	my ($pomOrig) = @_ ;
	(my $destFile = $pomOrig) =~ s-\.orig$--i;
	print "restore : $pomOrig -> $destFile\n";
	unlink($destFile) 			or warn ("WARNING : cannot unlink $destFile : $!") if( -e "$destFile");
	rename($pomOrig,$destFile)	or warn ("WARNING : cannot rename $pomOrig to $destFile : $!");
}

sub Usage
{
   print <<USAGE;
   Usage   : UpdatePOM.pl -i -m -64
             UpdatePOM.pl -h.elp|?
   Example : UpdatePOM.pl -i=contexts\\Aurora_Dep.ini
    
   [options]
   -help|?     argument displays helpful information about builtin commands.
   -i.ni       specifies the configuration file.
   -m.akefile  specifies the makefile name.
   -64         force the 64 bits compilation (-64) or not (-no64), default is -no64 i.e 32 bits.
   -CP	       prepare repositories to test updated poms before submitting them
   -RP	       restore repositories after testing updated poms (after -CP)
USAGE
    exit;
}
