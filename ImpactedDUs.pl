#!/usr/bin/perl -w

use File::Find;
use File::Copy;
use File::Path;
use XML::DOM;

use FindBin;
use lib ($FindBin::Bin);
use Perforce;

##############
# Parameters #
##############

die("ERROR: BUILD_NAME environment variable must be set") unless($BUILD_NAME=$ENV{BUILD_NAME});
die("ERROR: SRC_DIR environment variable must be set") unless($SRC_DIR=$ENV{SRC_DIR});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($OUTPUT_DIR=$ENV{OUTPUT_DIR});
die("ERROR: PLATFORM environment variable must be set") unless($PLATFORM=$ENV{PLATFORM});
die("ERROR: HOSTNAME environment variable must be set") unless($HOSTNAME=$ENV{HOSTNAME});
die("ERROR: HF_ID environment variable must be set") unless($HF_ID=$ENV{HF_ID});
die("ERROR: HF_MAJOR environment variable must be set") unless($HF_MAJOR=$ENV{HF_MAJOR});
die("ERROR: HF_MINOR environment variable must be set") unless($HF_MINOR=$ENV{HF_MINOR});
die("ERROR: HF_SP environment variable must be set") unless($HF_SP=$ENV{HF_SP});
die("ERROR: HF_PATCH environment variable must be set") unless($HF_PATCH=$ENV{HF_PATCH});
die("ERROR: BUILD_IB_FILE environment variable must be set") unless($ImpactedBinariesFile=$ENV{BUILD_IB_FILE});
die("ERROR: Client environment variable must be set") unless($Client=$ENV{Client});
die("ERROR: DROP_DIR environment variable must be set") unless($DROP_DIR=$ENV{DROP_DIR});
die("ERROR: context environment variable must be set") unless($Context=$ENV{context});
die("ERROR: BuildNumber environment variable must be set") unless($BuildNumber=$ENV{build_number});
$Manifest = "$SRC_DIR/Build/export/shared/contexts/$HF_MAJOR.${HF_MINOR}_SP${HF_SP}_PATCH_$HF_PATCH.xml";

########
# Main #
########

open(DAT, "$OUTPUT_DIR/obj/Users.dat") or warn("ERROR: cannot open '$OUTPUT_DIR/obj/Users.dat': $!");
eval <DAT>;
close(DAT);

open(TXT, $ImpactedBinariesFile) or warn("ERROR: cannot open '$ImpactedBinariesFile': $!");
while(<TXT>)
{
    chomp;
    (my $File = $_) =~ s/\\/\//g;
    $File =~ s/\r//g;
    $File =~ s/\n//g;
    my($Area) = $File =~ /bin\/([^\/]+)/;
    ${$ImpactedAreas{$Area}}{$File} = undef; 
}
close(TXT);

($output_dir = "\u$OUTPUT_DIR") =~ s/\\/\//g;
foreach my $Area (keys(%ImpactedAreas))
{
    unless(-d "$OUTPUT_DIR/deploymentunits/$Area") { warn("ERROR: '$OUTPUT_DIR/deploymentunits/$Area' not found'"); next }
    opendir(DU, "$OUTPUT_DIR/deploymentunits/$Area") or warn("ERROR: cannot opendir '$OUTPUT_DIR/deploymentunits/$Area': $!");
    while(defined($DU = readdir(DU)))
    {
        next unless(-f "$OUTPUT_DIR/deploymentunits/$Area/$DU/assemblylist.xml");
        my $ASSEMBLY = XML::DOM::Parser->new()->parsefile("$OUTPUT_DIR/deploymentunits/$Area/$DU/assemblylist.xml");
        for my $SOURCEDIR (@{$ASSEMBLY->getElementsByTagName('sourcedir')})
        {
            (my $SrcDir = $SOURCEDIR->getAttribute('id')) =~ s/\\/\//g;
            for my $FILE (@{$SOURCEDIR->getElementsByTagName('file')})
            {
                (my $Name = $FILE->getAttribute('name')) =~ s/\\/\//g;
                (my $File = "\u$SrcDir/$Name") =~ s/^$output_dir\///;
                ${$DUs{$File}}{$DU} = $Area;
            }
        }
        $ASSEMBLY->dispose();
        find(\&ImpactedJar, "$OUTPUT_DIR/bin/$Area");
    }   
    closedir(DU);
}

foreach my $Area (keys(%ImpactedAreas))
{
    foreach $File (keys(%{$ImpactedAreas{$Area}}))
    {
        chomp($File);
        $File =~ s/\r//g;
        $File =~ s/\n//g;
        @{$ImpactedDUs{$Area}}{keys(%{$DUs{"$File"}})} = (undef) if(exists($DUs{"$File"}));
        @{$ImpactedDUs{$Area}}{keys(%{$Jars{"$File"}})} = (undef) if(exists($Jars{"$File"}));
    }
}

if(-e $Manifest) { chmod(0755, $Manifest) or warn("ERROR: cannot chmod '$Manifest': $!") }
else
{
    open(XML, ">$Manifest") or die("ERROR: cannot open '$Manifest': $!");
    print(XML "<hotfixes>\n");
    print(XML "</hotfixes>\n");
    close(XML);
}

$DOC = XML::DOM::Parser->new()->parsefile($Manifest);
$newPLATFORM = $DOC->createElement('platform');
$newPLATFORM->setAttribute('id', $PLATFORM);
$newPLATFORM->setAttribute('hostname', $HOSTNAME);
$newIMPACTEDAREAS = $newPLATFORM->appendChild($DOC->createElement('impacted_areas'));
foreach my $Area (keys(%ImpactedAreas))
{
    my $newArea = $newIMPACTEDAREAS->appendChild($DOC->createElement('area'));
    $newArea->setAttribute('id', $Area);
    my $newIMPACTEDDUS = $newArea->appendChild($DOC->createElement('impacted_dus'));
    foreach my $DU (keys(%{$ImpactedDUs{$Area}}))
    {
        my $newDU = $newIMPACTEDDUS->appendChild($DOC->createElement('du'));
        $newDU->setAttribute('id', $DU);
        my $newIMPACTEDBINARIES = $newDU->appendChild($DOC->createElement('impacted_binaries'));
        foreach my $File (keys(%{$ImpactedAreas{$Area}}))
        {
            if(exists($DUs{$File}) && exists(${$DUs{$File}}{$DU}))
            {
                my $newBINARY = $newIMPACTEDBINARIES->appendChild($DOC->createElement('binary'));
                $newBINARY->setAttribute('id', $File);
            }
        }
    }
}
$IsNewHotFix = 1;
HOTFIX: for my $HOTFIX (@{$DOC->getElementsByTagName('hotfix')})
{  
    my($Id, $Major, $Minor, $SP, $Patch) = ($HOTFIX->getAttribute('id'), $HOTFIX->getAttribute('major'), $HOTFIX->getAttribute('minor'), $HOTFIX->getAttribute('sp'), $HOTFIX->getAttribute('patch'));
    if($Id eq $HF_ID and $Major eq $HF_MAJOR and $Minor eq $HF_MINOR and $SP eq $HF_SP and $Patch eq $HF_PATCH)
    {
        $IsNewHotFix = 0;
        for my $PLTFRM (@{$HOTFIX->getElementsByTagName('platform')})
        {
            if($PLTFRM->getAttribute('id') eq $PLATFORM)
            {
                $PLTFRM->getParentNode()->replaceChild($newPLATFORM, $PLTFRM);
                last HOTFIX;
            }
        }
        my $PLATFORMS = $HOTFIX->getElementsByTagName('platforms')->item(0);
        $PLATFORMS->appendChild($newPLATFORM);
        last HOTFIX;
    }
    $HOTFIX = undef;
}
if($IsNewHotFix)
{
    my $newHOTFIX = $DOC->createElement('hotfix');
    $newHOTFIX->setAttribute('id', $HF_ID);
    $newHOTFIX->setAttribute('major', $HF_MAJOR);
    $newHOTFIX->setAttribute('minor', $HF_MINOR);
    $newHOTFIX->setAttribute('sp', $HF_SP);
    $newHOTFIX->setAttribute('patch', $HF_PATCH);
    $newHOTFIX->setAttribute('patch', $HF_PATCH);
    my $newCHANGELISTS = $newHOTFIX->appendChild($DOC->createElement('changelists'));
    foreach my $User (keys(%Users))
    {
        foreach my $Change (keys(%{$Users{$User}}))
        {
            my $newCHANGELIST = $newCHANGELISTS->appendChild($DOC->createElement('changelist'));
            $newCHANGELIST->setAttribute('id', $Change);
            $newCHANGELIST->setAttribute('developer', $User); 
        }
    }
    my $newPLATFORMS = $newHOTFIX->appendChild($DOC->createElement('platforms'));
    $newPLATFORMS->appendChild($newPLATFORM);
    $DOC->getElementsByTagName('hotfixes')->item(0)->appendChild($newHOTFIX);
}
$DOC->printToFile($Manifest);
$DOC->dispose();

mkpath("$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files") or warn("ERROR: cannot mkpath '$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files': $!") unless(-e "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files");
copy($Manifest, "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files/$HF_MAJOR.${HF_MINOR}_SP${HF_SP}_PATCH_$HF_PATCH.xml") or warn("ERROR: cannot copy '$Manifest': $!");

$p4 = new Perforce;
$Submit = 0;
$p4->SetOptions("-c \"$Client\"");
$raDiff = $p4->diff("-f", $Manifest);
if($p4->ErrorCount())
{
    if(${$p4->Errors()}[0]=~/file\(s\) not on client\./)
    {
        $p4->add($Manifest);
        if($p4->ErrorCount()) { warn("ERROR: cannot 'add': ", @{$p4->Errors()}) }
        else { $Submit = 1 }
    } else { warn("ERROR: cannot p4 diff: ", @{$p4->Errors()}) }
}
elsif(@{$raDiff} > 1)
{
    $p4->edit($Manifest);
    if($p4->ErrorCount()) { warn("ERROR: cannot p4 edit: ", @{$p4->Errors()}) }
    else { $Submit = 1 }
} 
if($Submit)
{
    $p4->resolve("-ay", $Manifest);
    if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/no file\(s\) to resolve.$/) { warn("ERROR: cannot p4 resolve '$Manifest': ", @{$p4->Errors()}) }
    else
    { 
        my $rhChange = $p4->fetchchange();
        if($p4->ErrorCount()) { warn("ERROR: cannot p4 fetch change: ", @{$p4->Errors()}) }
        else
        {
            ${$rhChange}{Description} = ["Summary*:$Context | $BUILD_NAME", "What*:$Context | $BUILD_NAME", "Reviewed by*:pblack"];
            @{${$rhChange}{Files}} = grep({/$HF_MAJOR.${HF_MINOR}_SP${HF_SP}_PATCH_$HF_PATCH.xml/} @{${$rhChange}{Files}});
            my $raChange = $p4->savechange($rhChange);
            warn("ERROR: cannot p4 save change: ", @{$p4->Errors()}) if($p4->ErrorCount());
            my($Change) = ${$raChange}[0] =~ /^Change (\d+)/;
            $p4->submit("-c$Change") if($Change);
            if($p4->ErrorCount())
            { 
                warn("ERROR: cannot p4 submit: ", @{$p4->Errors()});
                $p4->revert($Manifest);
                if($p4->ErrorCount()) { warn("ERROR: cannot p4 revert : '$Manifest'", @{$p4->Errors()}) }
                $p4->change("-d", $Change);
                if($p4->ErrorCount()) { warn("ERROR: cannot p4 delete change : '$Change'", @{$p4->Errors()}) }
            }
        }
    }
}
$p4->Final();

#############
# Functions #
#############

sub ImpactedJar
{
    #if($File::Find::name =~ /\/crystalreports.boe.clientactions.java\//) { $File::Find::prune = 1; return}   # bug
    return unless(-f $File::Find::name && $File::Find::name =~ /\.jar$/);
    open(LIST, "unzip -l $File::Find::name |") or warn("ERROR: cannot unzip '$File::Find::name'");
    while(<LIST>)
    {
        next unless(/\.jar$/ && !/^Archive:/);
        ${$Jars{"$File::Find::name"}}{$DU} = undef;
    }
    close(LIST);
}
