#!/usr/bin/perl -w

use Sys::Hostname;
use Data::Dumper;
use File::Find;
use File::Path;
use File::Copy;

use FindBin;
use lib ($FindBin::Bin);
use Perforce;

die("ERROR: 'SRC_DIR' environment variable must be set") unless($ENV{SRC_DIR});
die("ERROR: 'OUTPUT_DIR' environment variable must be set") unless($ENV{OUTPUT_DIR});
die("ERROR: 'MY_BUILD_NAME' environment variable must be set") unless($ENV{MY_BUILD_NAME});
die("ERROR: 'Client' environment variable must be set") unless($ENV{Client});

########
# Main #
########

exit unless(-d "$ENV{OUTPUT_DIR}/../packages/chmhp00sap");
find(\&CHM, "$ENV{OUTPUT_DIR}/../packages/chmhp00sap");

$DataFile = "$ENV{SRC_DIR}/documentation/export/dat/$ENV{MY_BUILD_NAME}.dat";
chmod(0755, $DataFile) or warn("ERROR: cannot chmod '$DataFile': $!") if(-e $DataFile);
open(DAT, ">$DataFile") or die("ERROR: cannot open '$DataFile': $!");
$Data::Dumper::Indent = 0;
print DAT Data::Dumper->Dump([\%LoIOs], ["*LoIOs"]);
close(DAT);

$Submit = 0;
$p4 = new Perforce;
$p4->SetOptions("-c \"$ENV{Client}\"");
$raDiff = $p4->diff("-f", $DataFile);
if($p4->ErrorCount())
{
    if(${$p4->Errors()}[0]=~/file\(s\) not on client\./)
    {
        $p4->add($DataFile); 
        if($p4->ErrorCount()) { warn("ERROR: cannot 'p4 add $DataFile': ", @{$p4->Errors()}) }
        else { $Submit = 1 }
    } else { warn("ERROR: cannot 'p4 diff $DataFile': ", @{$p4->Errors()}) }
}
elsif(@{$raDiff} > 1)
{
    $p4->edit($DataFile);
    if($p4->ErrorCount()) { warn("ERROR: cannot 'p4 edit $DataFile': ", @{$p4->Errors()}) }
    else { $Submit = 1 }
}               
if($Submit)
{
    $p4->resolve("-ay", $DataFile);
    if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/no file\(s\) to resolve.$/) { warn("ERROR: cannot p4 resolve: ", @{$p4->Errors()}) }
    else
    { 
        my $rhChange = $p4->fetchchange();
        if($p4->ErrorCount()) { warn("ERROR: cannot 'p4 fetch change': ", @{$p4->Errors()}) }
        else
        {
            ${$rhChange}{Description} = ["Summary*:$DataFile | $ENV{MY_BUILD_NAME}", "Reviewed by*:pblack"];
            @{${$rhChange}{Files}} = grep(/$ENV{MY_BUILD_NAME}\.dat/, @{${$rhChange}{Files}});
			my $raChange = $p4->savechange($rhChange);
            warn("ERROR: cannot 'p4 save change': ", @{$p4->Errors()}) if($p4->ErrorCount());
            my($Change) = ${$raChange}[0] =~ /^Change (\d+)/;
            $p4->submit("-c$Change") if($Change);
			if($p4->ErrorCount())
			{ 
				warn("ERROR: cannot 'p4 submit $DataFile': ", @{$p4->Errors()});
				$p4->revert($DataFile);
				if($p4->ErrorCount()) { warn("ERROR: cannot p4 revert : '$$DataFile'", @{$p4->Errors()}) }
				$p4->change("-d", $Change);
				if($p4->ErrorCount()) { warn("ERROR: cannot p4 delete change : '$Change'", @{$p4->Errors()}) }
			}
        }
	}
}

END { $p4->Final() if($p4) }

############
# Function # 
############

sub CHM
{
    return unless(-f $File::Find::name);
    return unless($File::Find::name =~ /[\\\/]release[\\\/]/);
    return unless($File::Find::name =~ /\.chm$/i);
 
    my $FileName = $_;

    #return unless($FileName =~ /^00000001\.chm$/);   # Only for debug

    my $FilePath = "$ENV{OUTPUT_DIR}/obj/$FileName";
    system("C:\\Windows\\hh -decompile $FilePath $File::Find::name");
    opendir(LOIO, $FilePath) or warn("WARNING: cannot opendir '$FilePath': $!");
    while(defined(my $LoIO = readdir(LOIO)))
    {
        next unless($LoIO =~ /^\w{32,32}$/);
        warn("WARNING: LoIO '$LoIO' is duplicate in project '$ENV{MY_BUILD_NAME}' in '$File::Find::name' and '${$LoIOs{$ENV{MY_BUILD_NAME}}}{$LoIO}'") if(exists($LoIOs{$ENV{MY_BUILD_NAME}}) && exists(${$LoIOs{$ENV{MY_BUILD_NAME}}}{$LoIO}));
        ${$LoIOs{$ENV{MY_BUILD_NAME}}}{$LoIO} = "$FileName";
    }
    closedir(LOIO);
}