#!/usr/bin/perl -w

use File::Copy;

use FindBin;
use lib ($FindBin::Bin);
use Perforce;

$CURRENT_DIR = $FindBin::Bin;
$BUILD_DIR = $ENV{BUILD_DIR} || 'C:\Build\shared';

$p4 = new Perforce;
$p4->sync('-f', "$BUILD_DIR/jobs/documentation_daily_00.txt");
warn("ERROR: cannot sync '$BUILD_DIR/jobs/documentation_daily_00.txt': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);   

open(OUT, ">$CURRENT_DIR/documentation.txt") or die("ERROR: cannot open '$CURRENT_DIR/documentation_daily_00.txt': $!");
open(IN, "$BUILD_DIR/jobs/documentation_daily_00.txt") or die("ERROR: cannot open '$BUILD_DIR/jobs/documentation_daily_00.txt': $!");
while(<IN>)
{
    my $Line = $_;
    $Line =~ s/documentation_daily_00/documentation/;
    if(my($Project, $Server, $Port, $DocBase, $Mode, $Drive) = $Line =~ /^\s*command.+\s([^\s]+)\s+([^\s]+)\s+(\d+)\s+([^\s]+)\s+([^\s]+)\s+([A-Z])\s*\)/)
    {
        $Line = "\tcommand = cmd /c ( C:\\Builds\\queue.bat $Project $Server $Port $DocBase $Drive daily_00=$Mode )\n";
    }
    elsif(my($CycleMode) = $Line =~ /^\s*command.+\s([\S]+)\s*\)/)
    {
        my($Mode) = $CycleMode =~ /(release|releasedebug|debug)/;
        $Line =~ s/$CycleMode/daily_00=$Mode/;
    }
    print(OUT $Line);
}
close(IN);
close(OUT);

$P4File = "$BUILD_DIR/jobs/documentation.txt";
$p4->sync('-f', "\"$P4File\"");
if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/) { chomp(${$p4->Errors()}[-1]); die("ERROR: cannot sync '$P4File': ", @{$p4->Errors()}) }
$p4->edit("\"$P4File\"");
if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); die("ERROR: cannot p4 edit '$P4File': ", @{$p4->Errors()}) }
copy("$CURRENT_DIR/documentation.txt", $P4File) or die("ERROR: cannot copy '$CURRENT_DIR/documentation.txt': $!");
$rhChange = $p4->fetchchange();
if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); die("ERROR: cannot p4 fetch change: ", @{$p4->Errors()}) }
${$rhChange}{Description} = ["Summary*:new CMS builds", "Reviewed by*:pblack"];
$raChange = $p4->savechange($rhChange);
if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); die("ERROR: cannot p4 save change: ", @{$p4->Errors()}) }
($Change) = ${$raChange}[0] =~ /^Change (\d+)/;
$p4->submit("-c$Change") ;
if($p4->ErrorCount())
{
    chomp(${$p4->Errors()}[-1]);
    my @Errors = @{$p4->Errors()};
    $p4->revert("\"$P4File\"");
    if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); warn("ERROR: cannot p4 revert '$P4File': ", @{$p4->Errors()}) }
    $p4->change("-d", $Change);
    if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); warn("ERROR: cannot p4 delete change '$Change': ", @{$p4->Errors()}) }
    die("ERROR: cannot p4 submit change '$Change' ($P4File): @Errors");
}

END { $p4->Final() if($p4) }