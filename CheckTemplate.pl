use Getopt::Long;
use File::Path;
use File::Copy;
use IO::File;
use FindBin;

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "previous=s"=>\$OldTemplate, "next=s"=>\$NewTemplate,);
Usage() if($Help);
unless($OldTemplate) { warn("ERROR: -p.revious option is mandatory."); Usage() }
unless($NewTemplate) { warn("ERROR: -n.ext option is mandatory."); Usage() }

die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/[\\\/]\d+$//;
$CURRENTDIR = $FindBin::Bin;

########
# Main #
########

$SrcDir = "$CURRENTDIR/contexts";
$DstDir = "$TEMPDIR/CheckTemplate/shared/contexts";
rmtree("$DstDir/../..") or die("ERROR: cannot rmtree '$DstDir/../..': $!") if(-e $DstDir);
mkpath($DstDir) or die("ERROR: cannot mkpath '$DstDir': $!");
copy("$CURRENTDIR/PreprocessIni.pl", "$DstDir/..") or die("ERROR: cannot copy '$CURRENTDIR/PreprocessIni.pl': $!");
opendir(CONTEXT, $SrcDir) or die("ERROR: cannot opendir '$SrcDir': $!");
while(defined(my $IniFile = readdir(CONTEXT)))
{
    next unless($IniFile =~ /\.ini$/);
    copy("$SrcDir/$IniFile", "$DstDir/$IniFile") or die("ERROR: cannot copy '$SrcDir/$IniFile': $!");
}
closedir(CONTEXT);

open(INI, $NewTemplate) or die("ERROR: cannot open '$NewTemplate': $!");
while(<INI>)
{
    if(($Define) = /^\s*\#ifdef\s+(.+)$/)  { $IfInTemplate{$Define}=undef }
    elsif(($Define) = /^\s*\#ifndef\s+(.+)$/) { $IfInTemplate{$Define}=undef }
}
close(INI);

opendir(CONTEXT, $DstDir) or die("ERROR: cannot opendir '$DstDir': $!");
INI: while(defined(my $IniFile = readdir(CONTEXT)))
{
    next unless($IniFile =~ /\.ini$/);
    next if($NewTemplate =~ /$IniFile$/ or $OldTemplate =~ /$IniFile$/);
    foreach my $Age (qw(Old New))
    { 
        copy(${"${Age}Template"}, "$DstDir") or die("ERROR: cannot copy '", ${"${Age}Template"}, "': $!");
        open(DST, ">$DstDir/../$IniFile$Age") or die("ERROR: cannot open '$DstDir/../$IniFile$Age': $!");
        open(SRC, "perl $DstDir/../PreprocessIni.pl $DstDir/$IniFile 2>&1 |") or die("ERROR: cannot execute 'perl PreprocessIni.pl $DstDir/$IniFile': $!");
        while(<SRC>)
        {
            if(/^ERROR:/) { print; next INI if(/^ERROR:/) }
            next if(/^s*#/);
            print DST;
        }
        close(SRC);
        close(DST);
    }
    if($Output=`diff -a -b -w -B -E $DstDir/../${IniFile}Old $DstDir/../${IniFile}New`) { print("\n", "="x40, "\n\nWARNING: $IniFile is impacted!\n$Output") }
    else { unlink(("$DstDir/../${IniFile}Old", "$DstDir/../${IniFile}New")) or warn("ERROR: cannot unlink '': $!") }
    my(%Defines, %Ifs, %Endifs);
    PreprocessIni("$DstDir/$IniFile", \%Defines, \%Ifs, \%Endifs);
    foreach my $Define (keys(%Defines)) { warn("WARNING: $Define is not defined in $SrcDir/$IniFile") unless(exists($Ifs{$Define})) }
    foreach my $Define (keys(%Ifs)) { delete($IfInTemplate{$Define}); warn("ERROR: missing '#endif $Define' in $SrcDir/$IniFile") if($Ifs{$Define}>$Endifs{$Define}) }
    foreach my $Define (keys(%Endifs)) { warn("ERROR: missing '#if[n]def $Define' in $SrcDir/$IniFile") if($Endifs{$Define}>$Ifs{$Define}) }
}
closedir(CONTEXT);

foreach my $Define (keys(%IfInTemplate)) { warn("WARNING: $Define in not used in '$NewTemplate'") }

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
        $Variable =~ s/\${$Name}/$ENV{$Name}/ if(!defined(${$Name}) && defined($ENV{$Name}));
    }
    return $Variable;
}

sub STORE
{
    my($rsVariable, $Value) = @_;
    ${$rsVariable} = $Value;
    foreach(@Environments) { ${$_} = FETCH($_) } 
}

sub PreprocessIni 
{
    my($File, $rhDefines, $rhIfs, $rhEndifs) = @_; Monitor(\$File); $File =~ s/[\r\n]//g;
    my(@Lines, $Define);
   
    my $fh = new IO::File($File, "r") or die("ERROR: cannot open '$File': $!");
    while(my $Line = $fh->getline())
    {
        if(my($Defines) = $Line =~ /^\s*\#define\s+(.+)$/) { @{$rhDefines}{split('\s*,\s*', $Defines)} = (undef) }
        elsif(($Define) = $Line =~ /^\s*\#ifdef\s+(.+)$/)  { ${$rhIfs}{$Define}++ }
        elsif(($Define) = $Line =~ /^\s*\#ifndef\s+(.+)$/) { ${$rhIfs}{$Define}++ }
        elsif(($Define) = $Line =~ /^\s*\#endif\s+(.+)$/)  { ${$rhEndifs}{$Define}++ }
        elsif(my($IncludeFile) = $Line =~ /^\s*\#include\s+(.+)$/) { push(@Lines, PreprocessIni($IncludeFile, $rhDefines, $rhIfs, $rhEndifs)) }
    }
    $fh->close();
    return @Lines;
}
sub Usage
{
   print <<USAGE;
   Usage   : CheckTemplate.pl -p=oldtemplate -n=newtemplate
   Example : CheckTemplate.pl -h
             CheckTemplate.pl -p=old_Template41.ini -n=new_Template41.ini

   [option]
   -help|?     argument displays helpful information about builtin commands.
   -n.ext      specifies the next template file.
   -p.revious  specifies the previous template file.
USAGE
    exit;
}
