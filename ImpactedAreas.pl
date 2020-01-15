#!/usr/bin/perl -w

use Data::Dumper;
use File::Path;
use XML::DOM;

use FindBin;
use lib ($FindBin::Bin);
use Perforce;

##############
# Parameters #
##############

die("ERROR: SRC_DIR environment variable must be set") unless($SRC_DIR=$ENV{SRC_DIR});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($OUTPUT_DIR=$ENV{OUTPUT_DIR});
die("ERROR: BUILD_DATE_EPOCH environment variable must be set") unless($BUILD_DATE_EPOCH=$ENV{BUILD_DATE_EPOCH});

########
# Main #
########

open(TXT, ">$OUTPUT_DIR/obj/BuildDateEPOCH.txt") or warn("ERROR: cannot open '$OUTPUT_DIR/obj/BuildDateEPOCH.txt': $!");
print(TXT $BUILD_DATE_EPOCH);
close(TXT);

opendir(SRC, $SRC_DIR) or die("ERROR: cannot opendir '$SRC_DIR': $!");
while(defined(my $Area = readdir(SRC)))
{
    next unless(-d "$SRC_DIR/$Area" && -f "$SRC_DIR/$Area/pom.xml");
    my $POM = XML::DOM::Parser->new()->parsefile("$SRC_DIR/$Area/pom.xml");
    for my $DEPENDENCY (@{$POM->getElementsByTagName('dependency')})
    {
        my $ArtifactId = $DEPENDENCY->getElementsByTagName('artifactId')->item(0)->getFirstChild()->getData();
        ${$ChildAreas{$ArtifactId}}{$Area} = undef;
    }
    $POM->dispose();
}
closedir(SRC);

$p4 = new Perforce;
open(LOG, "$OUTPUT_DIR/logs/Build/fetch_step.log") or die("ERROR: cannot open '$OUTPUT_DIR/logs/Build/fetch_step.log': $!");
while(<LOG>)
{
    next if(/\.context\.xml$/ or /\.du\.xml$/ or /[\\\/]src[\\\/]Build[\\\/]/);
    next unless(my($File, $Depot, $Area, $Action) = /^\s+(\/\/([^\/]+)\/([^\/]+)\/.*?)\s-\s(.+?)\s/);
    next if($Action eq 'deleted' or $Depot eq 'product');
    my @FileLogs = $p4->filelog("-m 1", "\"$File\""); 
    warn("ERROR: cannot p4 filelog '$File': ", @{$p4->Errors()}) if($p4->ErrorCount());
    my($Change, $User);
    foreach my $raFileLog (@FileLogs)
    {
        foreach my $Line (@{$raFileLog})
        {
            last if(($Change, $User) = $Line =~ /#\d+\s+change\s+(\d+)\s+.+?\s+by\s+(.+?)@/);
        }
    }
    my $rhUser = $p4->user("-o", $User); 
    warn("ERROR: cannot p4 user '$User': ", @{$p4->Errors()}) if($p4->ErrorCount());
    (my $Email = ${$rhUser}{Email}) =~ s/^\s+|\s+$//g;
    $AreasToCompile{$Area} = 1;
    @AreasToCompile{keys(%{$ChildAreas{$Area}})} = (0);
    ${$Users{$Email}}{$Change} = undef;
}
close(LOG);
$p4->Final();

open(TXT, ">$OUTPUT_DIR/obj/AreasToCompile.txt") or die("ERROR: cannot open '$OUTPUT_DIR/obj/AreasToCompile.txt': $!");
print(TXT join(';', map("$_:*", keys(%AreasToCompile))));
close(TXT);
for my $Area (keys(%AreasToCompile))
{
    next unless(-d "$OUTPUT_DIR/bin/$Area");
    if($^O eq "MSWin32") { system("robocopy /MIR /NP /NFL /NDL /R:3 \"$OUTPUT_DIR/bin/$Area\" \"$OUTPUT_DIR/bin.save/$Area\"") }
    else
    {
        mkpath("$OUTPUT_DIR/bin.save/$Area") or warn("ERROR: cannot mkpath '$OUTPUT_DIR/bin.save/$Area': $!") unless(-e "$OUTPUT_DIR/bin.save/$Area");
        system("cp -dRuf --preserve=mode,timestamps \"$OUTPUT_DIR/bin/$Area/.\" \"$OUTPUT_DIR/bin.save/$Area\"");
    }        
}

$Data::Dumper::Indent = 0;
open(DAT, ">$OUTPUT_DIR/obj/Users.dat") or die("ERROR: cannot open '$OUTPUT_DIR/obj/Users.dat': $!");
print DAT Data::Dumper->Dump([\%Users], ["*Users"]);
close(DAT);
open(DAT, ">$OUTPUT_DIR/obj/ImpactedAreas.dat") or die("ERROR: cannot open '$OUTPUT_DIR/obj/ImpactedAreas.dat': $!");
print DAT Data::Dumper->Dump([\%AreasToCompile], ["*AreasToCompile"]);
close(DAT);
