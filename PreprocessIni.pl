use File::Spec::Functions;
use File::Basename;
use IO::File;
use FindBin;

Usage() unless(@ARGV);

($Config) = @ARGV;
$CURRENTDIR = $FindBin::Bin;

########
# Main #
########

@Lines = PreprocessIni($Config);
foreach(@Lines) { print }

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
    while($Variable =~ /\$\{(.*?)\}/g)
    {
        my $Name = $1;
        $Variable =~ s/\$\{$Name\}/${$Name}/ if(defined(${$Name}));
        $Variable =~ s/\$\{$Name\}/$ENV{$Name}/ if(!defined(${$Name}) && defined($ENV{$Name}));
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
    my($File, $rhDefines) = @_; Monitor(\$File); $File =~ s/[\r\n]//g;
    my(@Lines, $Define);
   
    my $fh = new IO::File($File, "r") or die("ERROR: cannot open '$File': $!");
    while(my $Line = $fh->getline())
    {
        $Line =~ s/^[ \t]+//; $Line =~ s/[ \t]+$//;
        if(my($Defines) = $Line =~ /^\s*\#define\s+(.+)$/) { @{$rhDefines}{split('\s*,\s*', $Defines)} = (undef) }
        elsif(($Define) = $Line =~ /^\s*\#ifdef\s+(.+)$/)
        { 
            next if(exists(${$rhDefines}{$Define}));
            while(my $Line = $fh->getline()) { last if($Line =~ /^\s*\#endif\s+$Define$/) }
        }
        elsif(($Define) = $Line =~ /^\s*\#ifndef\s+(.+)$/)
        { 
            next unless(exists(${$rhDefines}{$Define}));
            while(my $Line = $fh->getline()) { last if($Line =~ /^\s*\#endif\s+$Define$/) }
        }
        elsif($Line =~ /^\s*\#endif\s+/) { }
        elsif(my($IncludeFile) = $Line =~ /^\s*\#include\s+(.+)$/)
        {
            Monitor(\$IncludeFile); $IncludeFile =~ s/[\r\n]//g;
            unless(-f $IncludeFile)
            {
                my $Candidate = catfile(dirname($File), $IncludeFile);
                $IncludeFile = $Candidate if(-f $Candidate);
            }
            push(@Lines, PreprocessIni($IncludeFile, $rhDefines))
        }
        else { push(@Lines, $Line) }
    }
    $fh->close();
    return @Lines;
}

sub Usage
{
   print <<USAGE;
   Usage   : PreprocessIni.pl myinifile
   Example : PreprocessIni.pl contexts\aurora41_cbt.ini
USAGE
   exit;
}
