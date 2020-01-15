#!/usr/bin/perl -w

use File::Path;
use XML::DOM;

##############
# Parameters #
##############

die("ERROR: SRC_DIR environment variable must be set") unless($SRC_DIR=$ENV{SRC_DIR});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($OUTPUT_DIR=$ENV{OUTPUT_DIR});
die("ERROR: DROP_DIR environment variable must be set") unless($DROP_DIR=$ENV{DROP_DIR});
die("ERROR: context environment variable must be set") unless($Context=$ENV{context});
die("ERROR: build_number environment variable must be set") unless($BuildNumber=$ENV{build_number});
die("ERROR: BUILD_MODE environment variable must be set") unless($BUILD_MODE=$ENV{BUILD_MODE});
die("ERROR: PLATFORM environment variable must be set") unless($PLATFORM=$ENV{PLATFORM});
die("ERROR: HF_ID environment variable must be set") unless($HF_ID=$ENV{HF_ID});
die("ERROR: HF_MAJOR environment variable must be set") unless($HF_MAJOR=$ENV{HF_MAJOR});
die("ERROR: HF_MINOR environment variable must be set") unless($HF_MINOR=$ENV{HF_MINOR});
die("ERROR: HF_SP environment variable must be set") unless($HF_SP=$ENV{HF_SP});
die("ERROR: HF_PATCH environment variable must be set") unless($HF_PATCH=$ENV{HF_PATCH});
$Manifest = "$SRC_DIR/Build/export/shared/contexts/$HF_MAJOR.${HF_MINOR}_SP${HF_SP}_PATCH_$HF_PATCH.xml";

########
# Main #
########

$HOTFIXES = XML::DOM::Parser->new()->parsefile($Manifest);
for my $HOTFIX (@{$HOTFIXES->getElementsByTagName('hotfix')})
{  
    my($Id, $Major, $Minor, $SP, $Patch) = ($HOTFIX->getAttribute('id'), $HOTFIX->getAttribute('major'), $HOTFIX->getAttribute('minor'), $HOTFIX->getAttribute('sp'), $HOTFIX->getAttribute('patch'));
    if($Id eq $HF_ID and $Major eq $HF_MAJOR and $Minor eq $HF_MINOR and $SP eq $HF_SP and $Patch eq $HF_PATCH)
    {
        for my $PLTFRM (@{$HOTFIX->getElementsByTagName('platform')})
        {
            if($PLTFRM->getAttribute('id') eq $PLATFORM)
            {
                for my $AREA (@{$PLTFRM->getElementsByTagName('area')})
                {
                    $Areas{$AREA->getAttribute('id')} = undef;
                }
                last;
            }
            last;
        }
        last;
    }
    $HOTFIX = undef;
}
$HOTFIXES->dispose();

 foreach my $Area (keys(%Areas))
 {
    foreach my $Folder (qw(bin obj pdb deploymentunits))
    {
        next unless(-d "$OUTPUT_DIR/$Folder/$Area");
        if($^O eq "MSWin32") { system("robocopy /MIR /NP /NFL /NDL /R:3 \"$OUTPUT_DIR/$Folder/$Area\" \"$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$Folder/$Area\"") }
        else
        {
            mkpath("$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$Folder/$Area") or warn("ERROR: cannot mkpath '$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$Folder/$Area': $!") unless(-e "$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$Folder/$Area");
            system("cp -dRuf --preserve=mode,timestamps \"$OUTPUT_DIR/$Folder/$Area/.\" \"$DROP_DIR/$Context/$BuildNumber/$PLATFORM/$BUILD_MODE/$Folder/$Area\"");
        }        
    }
 }