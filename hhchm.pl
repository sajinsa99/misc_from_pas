#!/usr/bin/perl -w

use Getopt::Long;
use Data::Dumper;
use File::Find;
use File::Path;

##############
# Parameters #
##############

GetOptions("help|?"=>\$Help, "project=s"=>\$Project, "source=s"=>\$SRC_DIR, "file=s"=>\$DataFile);
Usage() if($Help);
unless($Project)  { print(STDERR "ERROR: the project parameter is missing\n"); Usage() }
unless($SRC_DIR)  { print(STDERR "ERROR: the folder parameter is missing\n"); Usage() }
unless($DataFile) { print(STDERR "ERROR: the file parameter is missing\n"); Usage() }
die("ERROR: TEMP environment variable must be set") unless($DST_DIR=$ENV{TEMP});
$$DST_DIR =~ s/[\\\/]\d+$//;

($SrcDir = $SRC_DIR) =~ s/\\/\//g;
($DstDir = $DST_DIR) =~ s/\\/\//g;

########
# Main #
########

find(\&CHM, $SrcDir);

############
# Function # 
############

sub CHM
{
    return unless(-f $File::Find::name);
    return unless($File::Find::name =~ /\.chm$/i);
    my $FileName = $_;

    #return unless($FileName =~ /^00000001\.chm$/);   # Only for debug

    (my $FilePath = $File::Find::name) =~ s/^$SrcDir/$DstDir/;
    $FilePath =~ s/\.chm$//;
    system("C:\\Windows\\hh -decompile $FilePath $File::Find::name");
    opendir(LOIO, $FilePath) or warn("WARNING: cannot opendir '$FilePath': $!");
    while(defined(my $LoIO = readdir(LOIO)))
    {
        next unless($LoIO =~ /^\w{32,32}$/);
        ${$LoIOs{$Project}}{$LoIO} = "$FileName";
    }
    closedir(LOIO);
    rmtree($FilePath) or warn("ERROR: cannot rmtree '$FilePath': $!") if(-e $FilePath);
}

open(DAT, ">$DataFile") or die("ERROR: cannot open '$DataFile': $!");
$Data::Dumper::Indent = 0;
print DAT Data::Dumper->Dump([\%LoIOs], ["*LoIOs"]);
close(DAT);

sub Usage
{
   print <<USAGE;
   Usage   : hhchm.pl -p -s -f
   Example : hhchm.pl -h
             hhchm.pl -p=i051358326920655 -s=c:\chm -f=chm.dat

   [option]
   -help|?    argument displays helpful information about builtin commands.
   -p.roject  specifies the project name
   -s.ource   specifies chm folder.
   -f.ile     specifies data file
USAGE
    exit;
}