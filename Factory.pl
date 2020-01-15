#!/usr/bin/perl -w

use POSIX qw(:sys_wait_h);
use Sys::Hostname;
use Getopt::Long;
use File::Copy;
use File::Path;
use XML::DOM;
use FindBin;
use lib ($FindBin::Bin);
use Perforce;

##############
# Parameters #
##############

@Pltfrms   = qw(win32_x86);
@MODES     = qw(release);
@TYPES     = qw(build);

$HOST       = hostname();
$CURRENTDIR = $FindBin::Bin;
$NULLDEVICE = $^O eq "MSWin32" ? "nul" : "/dev/null";
$BUILD_MODE  = "release";
$OBJECT_MODEL = "32"; 
if($^O eq "MSWin32")    { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64" : "win32_x86"  }
elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc"  }
elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64" : "aix_rs6000"  }
elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64" : "hpux_pa-risc" }
elsif($^O eq "linux")   { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64" : "linux_x86"  }
unless($ENV{NUMBER_OF_PROCESSORS})
{
    if($^O eq "solaris")  { ($ENV{NUMBER_OF_PROCESSORS}) = `psrinfo -v | grep "Status of " | wc -l` =~ /(\d+)/ }
    elsif($^O eq "aix")   { ($ENV{NUMBER_OF_PROCESSORS}) = `lsdev -C | grep Process | wc -l` =~ /(\d+)/ }
    elsif($^O eq "hpux")  { ($ENV{NUMBER_OF_PROCESSORS}) = `ioscan -fnkC processor | grep processor | wc -l` =~ /(\d+)/ }
    elsif($^O eq "linux") { ($ENV{NUMBER_OF_PROCESSORS}) = `cat /proc/cpuinfo | grep processor | wc -l` =~ /(\d+)/ }
    warn("ERROR: the environement variable NUMBER_OF_PROCESSORS is unknow") unless($ENV{NUMBER_OF_PROCESSORS});
}
$MAX_NUMBER_OF_PROCESSES ||= $ENV{MAX_NUMBER_OF_PROCESSES} || $ENV{NUMBER_OF_PROCESSORS}+2 || 8;
$Pltfrm = $^O eq "MSWin32" ? "windows" : "unix";

$Getopt::Long::ignorecase = 0;
GetOptions("help|?"=>\$Help, "All!"=>\$All, "Ini!"=>\$Ini, "Build!"=>\$Build, "Promotion!"=>\$Promotion, "area=s@"=>\@Areas, "project=s"=>\$Project, "template=s"=>\$Template, "view=s"=>\$View);
Usage() if($Help);

unless($Project)   { print(STDERR "ERROR: -p.roject option is mandatory.\n"); Usage() }
$Template ||= "${Project}_cons";
$View     ||= "PI_$Project";
$Client     = "${View}_$HOST";
$SRC_DIR    = $Pltfrm eq "windows" ? "D:/$View/src" : "/build/builder/$View/src";
$OUTPUT_DIR  = ($SRC_DIR=~/^(.*)[\\\/]/, "$1/$PLATFORM")."/$BUILD_MODE";
if($All)
{
    foreach my $Variable (qw(Ini Build Promotion)) { ${$Variable} = 1 unless(defined(${$Variable})) }
}
$ENV{PROJECT} = "\u$Project";
require Site;

########
# Main #
########

unless(@Areas)
{
    open(TXT, "$ENV{DROP_DIR}/$ENV{PROJECT}.txt") or die("ERROR: cannot open '$ENV{DROP_DIR}/$ENV{PROJECT}.txt': $!");
    while(<TXT>) { chomp; my($Area)=/^([^\r\n]+)/; push(@Areas, $Area) }
    close(TXT);
}
unless(@Areas) { warn("WARNING: Areas not found. Nothing to do"); exit }

$p4 = new Perforce;
$p4->SetClient("Builder_\L$HOST");
die("ERROR: cannot set client 'Builder_\L$HOST': ", @{$p4->Errors()}) if($p4->ErrorCount());
$p4->sync("-f", "//.../$Template.ini");
die("ERROR: cannot sync '//.../$Template.ini': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);

ReadIni("$CURRENTDIR/contexts/$Template.ini");

foreach my $raView (@Views)
{
    my($File, $Workspace, $Revision) = @{$raView};
    next unless($File =~ /^include\s/);
	my($POMPath, $POMName, $LocalRepository, $Repository, $rhArtifacts) = DependenciesTree($File);
	my %Properties;
    my $POM = XML::DOM::Parser->new()->parsefile("$POMPath/$POMName");
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

    foreach my $Artifact (sort(keys(%{$rhArtifacts})))
    {
        my($GroupId, $ArtifactId, $Packaging, $Version, $Phase) = split(':', $Artifact);
        my $POM = XML::DOM::Parser->new()->parsefile("$Repository/$ArtifactId/$Version/$ArtifactId-$Version.pom");
        for my $SCM (@{$POM->getElementsByTagName("scm")})
        {
            for my $CONNECTION (@{$SCM->getElementsByTagName("connection")})
            {
                (my $DepotDir = $CONNECTION->getFirstChild()->getData()) =~ s/^scm:perforce://;
                (my $Workdir = $Workspace) =~ s/\%\%ArtifactId\%\%/$ArtifactId/g;
                (my $Tag = $Revision) =~ s/\%\%ArtifactId\%\%/$ArtifactId/g;
                if(exists($Properties{$ArtifactId}))
                {
                    foreach my $Version (split(";", $Properties{$ArtifactId}))
                    {
                        my($SrcVersion, $DstVersion) = $Version =~ /:/ ? split(":", $Version) : ($Version, $Version);
                        (my $SrcDir = $DepotDir) =~ s/$ArtifactId[\\\/].+?[\\\/]/$ArtifactId\/$SrcVersion\//;
                        my $DstDir = $Workdir;
                        $DstDir =~ s/(.+)[\/\\](.+)$/$1\/$DstVersion\/$2/ if($DstVersion);
                        push(@Views, ["$SrcDir\/...", $DstDir, $Tag]);
                    }
                }
                else { push(@Views, ["$DepotDir\/...", $Workdir, $Tag]) }
            }
        }
    }
}
@Views = grep({${$_}[0]!~/^include\s/} @Views);

$rhClient = $p4->FetchClient($Client);
die("ERROR: cannot fetch client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount());
${$rhClient}{Root} = $SRC_DIR;
@{${$rhClient}{View}} = map({"${$_}[0] ${$_}[1]"} @Views);
$p4->SaveClient($rhClient);
die("ERROR: cannot save client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount());
$p4->SetClient($Client);
die("ERROR: cannot set client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount());
$p4->sync("-f", "//.../*.dep");
die("ERROR: cannot sync '//.../*.dep': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);
$p4->sync("-f", "//.../*.gmk");
die("ERROR: cannot sync '//.../*.gmk': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);

#$Units{$Unit} = [$Area, \%UnitProviders, \%UnitClients];
#$Areas{$Area} = [\%Units, \%AreaProviders, \%AreaClients]

@AreaL = @AreaList = Read("AREAS", "$SRC_DIR/$Project/export/$Project.gmk");
foreach my $Ar (sort(@AreaList))
{
    my $DirName = "$SRC_DIR/$Ar"; 
    $Ar =~ s/[\\\/][^\\\/]+$// unless(-e "$DirName/$Ar.$Pltfrm.dep");
    warn("ERROR: '$DirName/$Ar.$Pltfrm.dep' not found") unless(-e "$DirName/$Ar.$Pltfrm.dep");
    open(DEP, "$DirName/$Ar.$Pltfrm.dep") or warn("ERROR: cannot open '$DirName/$Ar.$Pltfrm.dep': $!");
    while(<DEP>)
    {
        if(my($Unit, $Dependencies) = /^\s*(.+)_deps\s*=\s*\$\(.+,\s*([^,]*?)\s*\)/)
        {
            ${$Units{$Unit}}[0] = $Ar;
            @{${$Units{$Unit}}[1]}{split(/\s+/, $Dependencies)} = (undef);
            ${${$Areas{$Ar}}[0]}{$Unit} = undef;
        }
    }
    close(DEP);
}
foreach my $Unit (keys(%Units))
{
    foreach my $Provider (keys(%{${$Units{$Unit}}[1]}))
    {
        next unless(exists($Units{$Provider}));
        ${${$Units{$Provider}}[2]}{$Unit} = undef;        
        ${${$Areas{${$Units{$Unit}}[0]}}[1]}{${$Units{$Provider}}[0]} = undef;
        ${${$Areas{${$Units{$Provider}}[0]}}[2]}{${$Units{$Unit}}[0]} = undef;
    }
}

foreach my $Area (@Areas)
{
    %ProviderAreas = (%ProviderAreas, %{${$Areas{$Area}}[1]}) if(keys(%{${$Areas{$Area}}[1]}));
    %ClientAreas   = (%ClientAreas,   %{${$Areas{$Area}}[2]}) if(keys(%{${$Areas{$Area}}[2]}));
    foreach my $Client (keys(%ClientAreas))
    { 
        %ProviderAreas = (%ProviderAreas, %{${$Areas{$Client}}[1]}) if(exists($Areas{$Client}));
    }
}
foreach my $Client (keys(%ClientAreas)) { delete $ProviderAreas{$Client} }
foreach my $Area   (@Areas)             { delete $ProviderAreas{$Area}; delete $ClientAreas{$Area} }
print("Area: ", join(',', sort(@Areas)), "\n");
print("Providers:\n\t", join("\n\t", sort(keys(%ProviderAreas))), "\n") if(keys(%ProviderAreas));
print("Clients:\n\t", join("\n\t", sort(keys(%ClientAreas))), "\n") if(keys(%ClientAreas));

if($Ini)
{
    open(SRC, "$CURRENTDIR/contexts/$Template.ini") or die("ERROR: cannot open '$CURRENTDIR/contexts/$Template.ini': $!");
    open(DST, ">$CURRENTDIR/contexts/$View.ini") or die("ERROR: cannot open '$CURRENTDIR/contexts/$View.ini': $!");
    SECTION: while(<SRC>)
    {
        if(my($Section) = /^\[(.+)\]/)
        {
            print(DST);
            while(<SRC>)
            {
                redo SECTION if(/^\[(.+)\]/);
                if(/^\s*$/ || /^\s*#/) { print(DST) }
                if($Section eq "context")  { print(DST "$View\n\n"); next SECTION }
                elsif($Section eq "client")   { print(DST "${View}_\${HOST}\n\n"); next SECTION }
                elsif($Section eq "root")     { print(DST "windows | D:/\${Context}/src\nunix    | /build/builder/\${Context}/src\n\n"); next SECTION }
                elsif($Section eq "buildcmd")
                {
                    my @Ars;
                    foreach my $Ar1 (@Areas, keys(%ClientAreas))
                    {
                        next unless(grep({/^$Ar1/} @AreaL));
                        my @Versions;
                        foreach my $Ar2 (@AreaL)
                        {
                            push(@Versions, $Ar2) if($Ar2=~/^$Ar1\//);
                        }                               
                        push(@Ars, @Versions ? @Versions : $Ar1);
                    }
                    print(DST "windows | checkenv | cscript /nologo ${CURRENTDIR}/checkenv.vbs\n");
                    print(DST "all     | init     | make -i -f \${SRC_DIR}/$Project/export/$Project.gmk init\n");
                    print(DST "all     | $View | \${IncrementalCmd} -g=\"\${SRC_DIR}/$Project/export/$Project.gmk=",join(',', sort(@Ars)),"\"\n");
                    foreach my $Ar1 (@Areas, keys(%ClientAreas))
                    {
                        next if(grep({/^$Ar1/} @AreaL));
                        print(DST "all     | PI_$Ar1 | make -f \"\${SRC_DIR}/$Ar1/$Ar1.gmk\"\n");
                    }
                    print(DST "\n");
                    next SECTION;
                }
                elsif($Section eq "view")
                {
                    foreach my $raView (@Views)
                    {
                        my($DepotPath, $WorkdirPath, $Revision) = @{$raView};
                        $WorkdirPath ||= "";
                        my($Ar) = $DepotPath =~ /^[\+\-]?\/\/.+?\/(.+?)\//; 
                        if(grep({$DepotPath =~ /\/\/.+?\/$_\//} @Areas)) { print(DST "$DepotPath | $WorkdirPath | \@now\n") }
                        elsif($Revision !~ /\@now/)
                        {
                            if($Revision =~ /\.xml$/)
                            {
                                 if(IsGreatestOK($Revision, $DepotPath)) { print(DST "$DepotPath | $WorkdirPath | $Revision\n") }
                                 else { print(DST "$DepotPath | $WorkdirPath\n") }
                            } else { print(DST "$DepotPath | $WorkdirPath | $Revision\n") }
                        }
                        else
                        { 
                            if(IsGreatestOK("$ENV{IMPORT_DIR}/${View}_$Ar/greatest.xml", $DepotPath))  { print(DST "$DepotPath | $WorkdirPath | =${View}_$Ar/greatest.xml\n") }
                            elsif(IsGreatestOK("$ENV{IMPORT_DIR}/$Template/greatest.xml", $DepotPath)) { print(DST "$DepotPath | $WorkdirPath | =$Template/greatest.xml\n") }
                            else { print(DST "$DepotPath | $WorkdirPath\n") }
                        }
                    }
                    print(DST "\n");
                    next SECTION;
                }
                elsif($Section eq "import")
                {
                    foreach my $raView (@Views)
                    {
                        my($DepotPath, $WorkdirPath, $Revision) = @{$raView};
                        $WorkdirPath ||= "";
                        my($Ar) = $DepotPath =~ /^[\+\-]?\/\/.+?\/(.+?)\//;
                        next unless(exists($ProviderAreas{$Ar}));
						next if(exists($Imports{$Ar}));
						$Imports{$Ar} = undef;
                        if(IsGreatestOK("$ENV{IMPORT_DIR}/${View}_$Ar/greatest.xml", $DepotPath))  { print(DST "$Ar | =${View}_$Ar/greatest.xml | no\n") }
                        elsif(IsGreatestOK("$ENV{IMPORT_DIR}/$Template/greatest.xml", $DepotPath)) { print(DST "$Ar | =$Template/greatest.xml | no\n") }
                        else { warn("ERROR: binaries for $Ar not found") }
                    }
                    print(DST "\${IMPORT_DIR}/../Titan/Mira_RTM/\${BuildNb}/\${PLATFORM}/\${BUILD_MODE}/bin/WebServices | =\${IMPORT_DIR}/../Titan/Mira_RTM/882_RTM/Mira_RTM.context.xml | no\n");
                    print(DST "\${IMPORT_DIR}/../Titan/Mira_RTM/\${BuildNb}/\${PLATFORM}/\${BUILD_MODE}/bin/WebI        | =\${IMPORT_DIR}/../Titan/Mira_RTM/882_RTM/Mira_RTM.context.xml | no\n");
                    print(DST "\n");
                    next SECTION;
                }   
#                elsif($Section eq "export")
#                {
#                    print(DST "$Area\n");
#                    print(DST "\n");
#                    next SECTION;
#                }   
                elsif(!/^\s*$/ && !/^\s*#/) { print(DST) }
            }
        }
    }
    close(DST);
    close(SRC);
}

if($Build)
{
    system("perl $CURRENTDIR/Build.pl -i=$CURRENTDIR/contexts/$View.ini -C -F -I -B");

    my $DROPDIR;
    if($^O eq "MSWin32") { ($DROPDIR) = `net use * "$ENV{DROP_DIR}"` =~ /^Drive\s+(\w:)/; for(1..60) { last if(`if exist $DROPDIR echo 1`); sleep(1) }; sleep(10); system("net use"); system("dir $DROPDIR") }
    else { $DROPDIR = $ENV{DROP_DIR} }
    $NumberOfFork = 0;
    foreach my $Area (@Areas, keys(%ClientAreas))
    { 
        my $BuildNumber = BuildNumber($Area);
        my $Dest = "$DROPDIR/${View}_$Area/$BuildNumber/$PLATFORM/$BUILD_MODE/bin/$Area";
        mkpath($Dest) or die("ERROR: cannot mkpath '$Dest: $!") unless(-e $Dest);
        CopyFork("$OUTPUT_DIR/bin/$Area", $Dest, "\tfrom bin/$Area\n") if(-e "$OUTPUT_DIR/bin/$Area");   
    }
    while(waitpid(-1, WNOHANG) != -1) { sleep(1) }
    `net use $DROPDIR /DELETE` if($^O eq "MSWin32");
}

if($Promotion)
{
    my $BuildNumber = BuildNumber(); 
    my $buildnumber = sprintf("%05d", $BuildNumber);
    my $Errors = 0;
    foreach my $Pltfrm (@Pltfrms)
    {
        foreach my $Mode (@MODES)
        {
            foreach my $Type (@TYPES)
            {
                my @Errors;
                open(DAT, "$ENV{HTTP_DIR}/$View/${View}_$buildnumber/${View}_$buildnumber=${Pltfrm}_${Mode}_${Type}_1.dat") or die("ERROR: cannot open '$ENV{HTTP_DIR}/$View/${View}_$buildnumber/${View}_$buildnumber=${Pltfrm}_${Mode}_${Type}_1.dat': $!"); 
                eval <DAT>; 
                close(DAT);
                $Errors += $Errors[0];
            }
        }
    }
#   #if($Errors) { warn("ERROR: errors in '$Context'. NO GREATEST") }
    if(0) { warn("ERROR: errors in '$View'. NO GREATEST") }
    else
    {
        foreach my $Area (@Areas, keys(%ClientAreas))
        { 
            my $Context = "${View}_$Area";
            my $AreaNumber = BuildNumber($Area); 
            open(SRC, "$ENV{DROP_DIR}/$View/$BuildNumber/$View.context.xml") or die("ERROR: cannot open '$ENV{DROP_DIR}/$View/$BuildNumber/$View.context.xml': $!");
            open(DST, ">$ENV{DROP_DIR}/$Context/greatest.xml") or die("ERROR: cannot open '$ENV{DROP_DIR}/$Context/greatest.xml': $!");
            while(<SRC>)
            {
                if(/<version.+<\/version>/)
                { 
                    (my $Line = $_) =~ s/$View/$Context/;
                    $Line =~ s/\.\d+</.$AreaNumber</;
                    print(DST $Line);
                }
                else { print DST }
            }
            close(DST);
            close(SRC);
        }
        system("perl $CURRENTDIR/PIMail.pl -p=$ENV{PROJECT} -c=$View -n=$buildnumber");
    }
}

END 
{ 
    $p4->Final() if($p4); 
}

#############
# Functions #
#############

sub DependenciesTree
{
    my($File) = @_;
    my($POMFile, $Repository, $LocalRepository) = $File =~ /^(?:include|maven)\s+(((.+[\\\/]repository)[\\\/].+)[\\\/].+?[\\\/].+)$/;
    my($POMPath, $POMName) = $POMFile =~ /^(.+)[\\\/](.+)$/;
    opendir(AREA, $Repository) or warn("ERROR: cannot opendir '$Repository': $!");
    while(defined(my $Area = readdir(AREA)))
    {
        next if($Area =~ /^\.\.?/);
        opendir(VER, "$Repository/$Area") or warn("ERROR: cannot opendir '$Repository/$Area': $!");
        while(defined(my $Version = readdir(VER)))
        {
            next unless(-d "$Repository/$Area/$Version");
            next unless(-e "$Repository/$Area/$Version/pom.xml");
            copy("$Repository/$Area/$Version/pom.xml", "$Repository/$Area/$Version/$Area-$Version.pom") or warn("ERROR: cannot copy '$Repository/$Area/$Version/pom.xml': $!");
            open(JAR, ">$Repository/$Area/$Version/$Area-$Version.jar") or warn("ERROR: cannot open '$Repository/$Area/$Version/$Area-$Version.jar': $!");
            close(JAR);
        }
        closedir(VER);
    }
    closedir(AREA);
    # pom dependencies
    chdir($POMPath) or warn("ERROR: cannot chdir '$POMPath': $!");
    my %Artifacts;
    open(MVN, "mvn -Dmaven.repo.local=$LocalRepository -f $POMName dependency:tree |") or warn("ERROR: cannot execute 'mvn': $!");
    DEPENDENCY:while(<MVN>)
    {
        next unless(/^\[INFO\]\s*\[dependency:tree]/);
        <MVN>;
        while(<MVN>)
        {
            last DEPENDENCY if(/^\[INFO\]\s*------/);
            next if(/^\[INFO\]\s*com\.sap:/);
            next unless(/(com\.sap:.+)$/);
            $Artifacts{$1} = undef;
        }
    }
    close(MVN);
    warn("ERROR: Artifact(s) not found from '$POMFile'") unless(%Artifacts);
    return ($POMPath, $POMName, $LocalRepository, $Repository, \%Artifacts);
}

sub BuildNumber
{
    my($Area) = @_;
    my $Context = $Area ? "${View}_$Area" : $View;
    
    my $BuildNumber;
    open(TXT, "$ENV{DROP_DIR}/$Context/version.txt") or warn("ERROR: cannot open '$ENV{DROP_DIR}/$Context/version.txt': $!");
    chomp($BuildNumber = <TXT>);
    $BuildNumber = int($BuildNumber);
    close(TXT);
    
   return $BuildNumber || 1;
}

sub CopyFork
{
    my($From, $To, $Message) = @_;

    if($NumberOfFork >= $MAX_NUMBER_OF_PROCESSES)
    {
        while(!waitpid(-1, WNOHANG)) { sleep(1) }
        $NumberOfFork--;
    }
    my $pid;
    if(!defined($pid=fork())) { die("ERROR: cannot fork: $!") }
    elsif($pid) { $NumberOfFork++ } 
    else { CopyFiles($From, $To, $Message); exit }
}

sub CopyFiles
{
    my($Source, $Destination, $Message) = @_;
    my $Result;
    if($^O eq "MSWin32")
    { 
        $Source =~ s/\//\\/g;
        $Destination =~ s/\//\\/g;
        $Destination =~ s/\\$//;
        my $XCopyFlags;
        if(-f $Source) { ($Destination) = $Destination =~ /^(.*\\)[^\\]+$/; $XCopyFlags = "/CQRYD" }
        else { $XCopyFlags = "/ECIQHRYD" } 
        warn("WARNING: '$Source' not found") unless(-e $Source);
        mkpath($Destination) or warn("ERROR: cannot mkpath '$Destination': $!") unless(-e $Destination);
        $Result = system("xcopy \"$Source\" \"$Destination\" $XCopyFlags") and warn("ERROR: cannot copy '$Source' to '$Destination': $! at ". (scalar(localtime())));
    }
    else
    { 
        $Source =~ s/\\/\//g;
        $Destination =~ s/\\/\//g;
        mkpath($Destination) or warn("ERROR: cannot mkpath '$Destination': $!") unless(-e $Destination);
        $Result = system("cp -dRuf --preserve=mode,timestamps \"$Source/.\" $Destination 1>$NULLDEVICE") and warn("ERROR: cannot copy '$Source/.' to '$Destination': $!");
    }   
    print($Message) if($Message);
    return $Result;
}

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
        $Variable =~ s/\${$Name}/${$Name}/ if(defined(${$Name}));
    }
    return $Variable;
}

sub STORE
{
    my($rsVariable, $Value) = @_;
    ${$rsVariable} = $Value;
    foreach(@Environments) { ${$_} = FETCH($_) } 
}

sub Read 
{
    my($Variable, $Makefile) = @_;

    my $Values;
    if(open(MAKE, "make -f $Makefile display_\L$Variable 2>$NULLDEVICE |"))
    {
        while(<MAKE>)
        {
            last if(($Values) = /\s*$Variable\s*=\s*(.+)$/i);
        }
        close(MAKE);
    }
    unless($Values)
    {
        if(open(MAKE, $Makefile))
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

sub ReadIni
{
    my($Config) = @_;
    
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
            if($Section eq "view")
            { 
                push(@Views, [split('\s*\|\s*', $_)]);
                ${$Views[-1]}[1] ||= (${$Views[-1]}[0]=~/^[-+]?\/{2}(?:[^\/]*[\/]){3}(.+)$/, "//\${Client}/$1"); 
                ${$Views[-1]}[2] ||= '@now';
                for my $n (0..2) { Monitor(\${$Views[-1]}[$n]) }
            }
            elsif($Section eq "environment") 
            { 
                my($Pltfrm, $Env) = split('\s*\|\s*', $_);
                unless($Env) { $Pltfrm="all"; $Env=$_ }
                next unless($Pltfrm=~/^all$/i || $Pltfrm eq $PLATFORM || ($^O eq "MSWin32" && $PLATFORM=~/^windows$/i) || ($^O ne "MSWin32" && $PLATFORM=~/^unix$/i)); 
                my($Key, $Value) = split('\s*=\s*', $Env);
                ${$Key} = $ENV{$Key} = FETCH(\$Value);
                push(@Environments, \$ENV{$Key}) if($ENV{$Key}=~/\${(.*?)}/);
            } 
        }
    }
    close(INI);
}

sub IsGreatestOK
{
    my($Greatest, $File) = @_;
    return 0 unless(-e $Greatest);
    my $Revision;
    my $CONTEXT = XML::DOM::Parser->new()->parsefile($Greatest);  
    for my $COMPONENT (@{$CONTEXT->getElementsByTagName("fetch")})
    {
        my($DepotSource, $Rev) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute("revision"));
        $DepotSource =~ s/\*/\[^\\\/\\\\\]\*/g;
        $DepotSource =~ s/^\+//;
        if($File =~ /$DepotSource/) { $Revision=$Rev; last };
    }
    return 0 unless($Revision);
    return 1;
}

sub Usage
{
   print <<USAGE;
   Usage   : Factory.pl [option]+ [step]+
   Example : Factory.pl -h
             Factory.pl -All -p=aurora -t=Aurora_cons -v=PI_Aurora -a=tp.perl

   [option]
   -help|?      argument displays helpful information about builtin commands
   -a.rea       specifies the area name, default according with the new sources
   -p.roject    specifies the project name
   -t.emplate   specifies the template context, default is <project>_cons
   -v.iew       specifies the client view name, default is PI_<project>
     
   [step]
   -All         do all following steps
   -I.ni        do the generate ini file step (-I.ni) or not (-noI.ni), default is -noIni.
   -B.uild      do the build step (-B.uild) or not (-noB.uild), default is -noBuild.
   -P.romotion  do the greatest step (-P.romotion) or not (-noP.romotion), default is -noPromotion.
USAGE
    exit;
}
