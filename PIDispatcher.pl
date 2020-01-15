#!/usr/bin/perl -w

use Sys::Hostname;
use Getopt::Long;
use File::Path;
use File::Copy;
use XML::DOM;
use FindBin;
use lib ($FindBin::Bin);
use Perforce;

$HOST = hostname();
$NULLDEVICE = $^O eq "MSWin32" ? "nul" : "/dev/null";
$PLATFORM = $^O eq "MSWin32" ? "windows" : "unix";

##############
# Parameters #
##############

GetOptions("help|?"=>\$Help, "project=s"=>\$Project, "template=s"=>\$Template);
Usage() if($Help);
unless($Project)  { print(STDERR "ERROR: -p.roject option is mandatory.\n"); Usage() }
unless($Template) { print(STDERR "ERROR: -t.emplate option is mandatory."); Usage() }

$ENV{PROJECT} = "\u$Project";
require Site;

@DEPOTS     = qw(//tp/ //internal/tp //components/);
$CURRENTDIR = $FindBin::Bin;
$SRC_DIR    = $PLATFORM eq "windows" ? "C:\\${Project}_Dispatcher\\src" : "";
$Client     = "${Project}_Dispatcher_$HOST";

########
# Main #
########

$p4 = new Perforce;
$p4->SetClient("Builder_\L$HOST");
$p4->sync("-f", "//.../$Template.ini");
die("ERROR: cannot sync '//.../$Template.ini': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);

ReadIni("$CURRENTDIR/contexts/$Template.ini");
foreach my $raView (@Views)
{
    my($File, $Workspace, $Revision) = @{$raView};
    next unless($File =~ /^include\s/);
    my($POMFile, $Repository, $LocalRepository) = $File =~ /^include\s+(((.+[\\\/]product.+?[\\\/]).+)[\\\/].+?[\\\/].+)$/;
    my($POMPath, $POMName) = $POMFile =~ /^(.+)[\\\/](.+)$/;
    opendir(AREA, $Repository) or warn("ERROR: cannot opendir '$LocalRepository': $!");
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
        print;
        next unless(/^\[INFO\]\s*\[dependency:tree]/);
        <MVN>;
        while(<MVN>)
        {
            last DEPENDENCY if(/^\[INFO\]\s*------/);
            next unless(/(com\.sap:.+)$/);
            $Artifacts{$1} = undef;
        }
    }
    close(MVN);
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

    foreach my $Artifact (sort(keys(%Artifacts)))
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
die("ERROR: cannot set client '$Client: ", @{$p4->Errors()}) if($p4->ErrorCount());
$p4->sync("-f", "//.../*.dep");
die("ERROR: cannot sync '//.../*.dep': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);
$p4->sync("-f", "//.../*.gmk");
die("ERROR: cannot sync '//.../*.gmk': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);

#$Units{$Unit} = [$Area, \%UnitProviders, \%UnitClients];
#$Areas{$Area} = [\%Units, \%AreaProviders, \%AreaClients]
@AreaList = Read("AREAS", "$SRC_DIR/$Project/export/$Project.gmk");
foreach my $Ar (sort(@AreaList))
{
    my $DirName = "$SRC_DIR/$Ar"; 
    $Ar =~ s/[\\\/][^\\\/]+$// unless(-e "$DirName/$Ar.$PLATFORM.dep");
    warn("ERROR: '$DirName/$Ar.$PLATFORM.dep' not found") unless(-e "$DirName/$Ar.$PLATFORM.dep");
    open(DEP, "$DirName/$Ar.$PLATFORM.dep") or warn("ERROR: cannot open '$DirName/$Ar.$PLATFORM.dep': $!");
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

# New Areas
foreach my $raView (@Views)
{
    my($File, $Workspace) = @{$raView};
    next if($File =~ /^-/);
    $File =~ s/^\+//;
    next unless(grep({$File=~/^$_/} @DEPOTS));
    my($Area) = $File =~ /^\/\/.+?\/(.*?)\//;
    next if(exists($NewAreas{$Area}));
    my $Greatest = -e "$ENV{IMPORT_DIR}/PI_Aurora_$Area/greatest.xml" ? "$ENV{IMPORT_DIR}/PI_Aurora_$Area/greatest.xml" : "$ENV{IMPORT_DIR}/$Template/greatest.xml";
    my $CONTEXT = XML::DOM::Parser->new()->parsefile($Greatest);  
    for my $COMPONENT (@{$CONTEXT->getElementsByTagName("fetch")})
    {
        my($DepotSource, $Rev) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute("revision"));
        $DepotSource =~ s/\*/\[^\\\/\\\\\]\*/g;
        $DepotSource =~ s/^\+//;
        if(my($Version) = $DepotSource =~ /^$File/) { $File =~ s/\(\.\+\?\)/$Version/; $Revision=$Rev;  last }
    }
    if($Revision)
    {
        open(DIFF2, "p4 diff2 -q $File$Revision $File |") or die("ERROR: cannot run diff2: $!");
    	while(<DIFF2>)    
    	{
    		next if(/\.dep#\d+/ || /\.dep\.new#\d+/ || /pom\.xml#\d+/);
    		$NewAreas{$Area} = $_;
    		last;
        }
        close(DIFF2);
    } else { $NewAreas{$Area} = "\n"; }
}

# Client Areas
foreach my $Area (keys(%NewAreas))
{
    next unless(exists($Areas{$Area}));
	%ProviderAreas = (%ProviderAreas, %{${$Areas{$Area}}[1]}) if(keys(%{${$Areas{$Area}}[1]}));
    %ClientAreas   = (%ClientAreas,   %{${$Areas{$Area}}[2]}) if(keys(%{${$Areas{$Area}}[2]}));
    foreach my $Client (keys(%ClientAreas))
    { 
        %ProviderAreas = (%ProviderAreas, %{${$Areas{$Client}}[1]}) if(exists($Areas{$Client}));
    }
}
foreach my $Client (keys(%ClientAreas)) { delete $ProviderAreas{$Client} }
foreach my $Area   (keys(%NewAreas))    { delete $ProviderAreas{$Area}; delete $ClientAreas{$Area} }
print("Area: ", join(',', sort(keys(%NewAreas))), "\n");
print("Providers:\n\t", join("\n\t", sort(keys(%ProviderAreas))), "\n") if(keys(%ProviderAreas));
print("Clients:\n\t", join("\n\t", sort(keys(%ClientAreas))), "\n") if(keys(%ClientAreas));

# Increment version
open(TXT, ">$ENV{DROP_DIR}/$Project.txt") or die("ERROR: cannot open '$ENV{DROP_DIR}/$Project.txt': $!");
foreach my $Area (sort(keys(%NewAreas), keys(%ClientAreas)))
{
	#print(TXT "\#$NewAreas{$Area}$Area\n");
	print(TXT "$Area\n") if(exists($NewAreas{$Area}));
	if(-e "$ENV{DROP_DIR}/PI_Aurora_$Area/version.txt")
    {
        open(VER, "$ENV{DROP_DIR}/PI_Aurora_$Area/version.txt") or die("ERROR: cannot open '$ENV{DROP_DIR}/PI_Aurora_$Area/version.txt': $!");
        chomp($BuildNumber = <VER>);
        $BuildNumber = int($BuildNumber);
        close(VER);
    }
    else
    {
        mkpath("$ENV{DROP_DIR}/PI_Aurora_$Area") or die("ERROR: cannot mkpath '$ENV{DROP_DIR}/PI_Aurora_$Area': $!") unless(-e "$ENV{DROP_DIR}/PI_Aurora_$Area");
        $BuildNumber = 0;
    }
    $BuildNumber++;
	open(VER, ">$ENV{DROP_DIR}/PI_Aurora_$Area/version.txt") or die("ERROR: cannot open '$ENV{DROP_DIR}/PI_Aurora_$Area/version.txt': $!");
	print(VER "$BuildNumber\n");
    close(VER);
}
close(TXT);
open(VER, "$ENV{DROP_DIR}/PI_Aurora/version.txt") or die("ERROR: cannot open '$ENV{DROP_DIR}/PI_Aurora/version.txt': $!");
chomp($BuildNumber = <VER>);
$BuildNumber = int($BuildNumber);
close(VER);
$BuildNumber++;
open(VER, ">$ENV{DROP_DIR}/PI_Aurora/version.txt") or die("ERROR: cannot open '$ENV{DROP_DIR}/PI_Aurora/version.txt': $!");
print(VER "$BuildNumber\n");
close(VER);

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
                my($Platform, $Env) = split('\s*\|\s*', $_);
                unless($Env) { $Platform="all"; $Env=$_ }
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i)); 
                my($Key, $Value) = split('\s*=\s*', $Env);
                ${$Key} = $ENV{$Key} = FETCH(\$Value);
                push(@Environments, \$ENV{$Key}) if($ENV{$Key}=~/\${(.*?)}/);
            } 
        }
    }
    close(INI);
}

sub Usage
{
   print <<USAGE;
   Usage   : PIDispatcher.pl [option]+
   Example : PIDispatcher.pl -h
             PIDispatcher.pl -p=Aurora -t=Aurora_assembling

   [option]
   -help|?      argument displays helpful information about builtin commands
   -p.roject    specifies the project name.
   -t.emplate   specifies the template context.
USAGE
    exit;
}