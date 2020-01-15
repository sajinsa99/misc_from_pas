#!/usr/bin/perl -w

use File::Path;

##############
# Parameters #
##############

die("ERROR: OUTPUT_DIR environment variable must be set") unless($OUTPUT_DIR=$ENV{OUTPUT_DIR});
die("ERROR: BUILD_IB_FILE environment variable must be set") unless($ImpactedBinariesFile=$ENV{BUILD_IB_FILE});

########
# Main #
########

open(TXT, $ImpactedBinariesFile) or warn("ERROR: cannot open '$ImpactedBinariesFile': $!");
while(<TXT>)
{
    chomp;
    (my $File = $_) =~ s/\\/\//g;
    $Files{$File} = undef; 
}
close(TXT);

foreach my $File (keys(%Files))
{
    my $Source = "$OUTPUT_DIR/$File";
    next unless(-f $Source);    
    (my $Destination = $Source) =~ s/\/bin\//\/bin.save\//;
    if($^O eq "MSWin32")
    {
        $Source =~ s/\//\\/g;
        $Destination =~ s/\//\\/g;
        system("xcopy /CQRYD \"$Source\" \"$Destination\"");
    }
    else
    {
        $Source =~ s/\\/\//g;
        $Destination =~ s/\\/\//g;
        system("cp -dRuf --preserve=mode,timestamps \"$Source\" \"$Destination\"")
    }
}

if($^O eq "MSWin32") { system("robocopy /NP /NFL /NDL /R:3 \"$OUTPUT_DIR/bin.save\" \"$OUTPUT_DIR/bin\"") }
else 
{
    mkpath("$OUTPUT_DIR/bin") or warn("ERROR: cannot mkpath '$OUTPUT_DIR/bin': $!") unless(-e "$OUTPUT_DIR/bin");
    system("cp -dRuf --preserve=mode,timestamps \"$OUTPUT_DIR/bin.save/.\" \"$OUTPUT_DIR/bin\"");
 }

