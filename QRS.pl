#!/usr/bin/perl -w

use Sys::Hostname;
use Getopt::Long;
use FindBin;
use lib ($FindBin::Bin);
use XBM;

##############
# Parameters #
##############

$ENV{AC_TEST_PLAN}      or die("ERROR: the environment variable 'AC_TEST_PLAN' not found");
$ENV{AC_TEST_SUITE}     or die("ERROR: the environment variable 'AC_TEST_SUITE' not found");
$ENV{AC_TEST_MILESTONE} or die("ERROR: the environment variable 'AC_TEST_MILESTONE' not found");
$ENV{AC_TEST_USER}      or die("ERROR: the environment variable 'AC_TEST_USER' not found");
$ENV{AC_TEST_BUILD}     or die("ERROR: the environment variable 'AC_TEST_BUILD' not found");
$ENV{AC_TEST_CAMPAIGN}  or die("ERROR: the environment variable 'AC_TEST_CAMPAIGN' not found");
$ENV{AC_TEST_CONFIGID}  or die("ERROR: the environment variable 'AC_TEST_CONFIGID' not found");
$ENV{AC_TEST_SESSION} ||= "astec";

$BUILD_MODE = "release";
$OBJECT_MODEL = 32; 
defined($ENV{AC_TEST_OBJECT_MODEL}) ? print("INFO:BM: defined AC_TEST_OBJECT_MODEL=$ENV{AC_TEST_OBJECT_MODEL}\n") : print("INFO:BM: AC_TEST_OBJECT_MODEL is not defined\n");
if(defined $ENV{AC_TEST_OBJECT_MODEL} && ($ENV{AC_TEST_OBJECT_MODEL} eq "32" || $ENV{AC_TEST_OBJECT_MODEL} eq "64")){
    $OBJECT_MODEL=$ENV{AC_TEST_OBJECT_MODEL};
    print("INFO:BM: Valid AC_TEST_OBJECT_MODEL=$ENV{AC_TEST_OBJECT_MODEL}\n");
}
if($^O eq "MSWin32")    { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64"       : "win32_x86" }
elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc" }
elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64"   : "aix_rs6000" }
elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64"       : "hpux_pa-risc" }
elsif($^O eq "linux")   { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64"       : "linux_x86" }
GetOptions("help|?"=>\$Help, "ini=s"=>\$Config, "log=s"=>\@Logs, "output=s"=>\$QRSFile, "jre=s"=>\$JRE);
Usage() if($Help);
unless($Config || @Logs)  { warn("ERROR: -ini or -log option is mandatory."); Usage() }
$QRSFile ||= "$ENV{AC_TEST_PLAN}_$ENV{AC_TEST_SESSION}.qrs";
$HOST = hostname();

########
# Main #
########

open(QRS, ">$QRSFile") or die("ERROR: cannot open '$QRSFile': $!");
print(QRS "[GENERAL]\n");
print(QRS "TPName=$ENV{AC_TEST_PLAN}\n");
print(QRS "Suite=$ENV{AC_TEST_SUITE}\n");
print(QRS "Milestone=$ENV{AC_TEST_MILESTONE}\n");
print(QRS "User=$ENV{AC_TEST_USER}\n");
print(QRS "DefaultBuild=$ENV{AC_TEST_BUILD}\n");
print(QRS "CloseTPOnExit=TRUE\n");
print(QRS "Campaign=$ENV{AC_TEST_CAMPAIGN}\n");
print(QRS "ColumnsSeparator=,\n\n");

print(QRS "[CONFIGURATION]\n");
print(QRS "[CONFIGURATION_$HOST]\n");
print(QRS "ConfigID=$ENV{AC_TEST_CONFIGID}\n\n");

print(QRS "[LINES]\n");
print(QRS "Machine,TCName,Result,FRID\n");

my $rh = {};
if($Config)
{
    ReadIni();
    $OUTPUT_DIR  = $ENV{OUTPUT_DIR} || (($ENV{OUT_DIR} || ($SRC_DIR=~/^(.*)[\\\/]/, "$1/$PLATFORM"))."/$BUILD_MODE");
    foreach my $raCommand (@SmokeCmds)
    { 
        my($Platform, $CommandName, $Command) = @{$raCommand};
        my $Result;
        unless(open(LOG, "$OUTPUT_DIR/logs/Build/$CommandName.summary.txt")){
            warn("ERROR: cannot open '$OUTPUT_DIR/logs/Build/$CommandName.summary.txt': $!");
            last;
        }
        while(<LOG>)
        {
            next unless(/^== Sections with errors: (\d+)$/);
            $Result = $1 ? 2 : 3;
            last;
        }
        close(LOG);
        unless(defined($Result)){
            warn("ERROR: number of errors not found") ;
            last;
        }
        print(QRS "\"$HOST\",\"$CommandName\",$Result\n");
        $rh->{$CommandName} = (3 == $Result) ? 0 : 1;
    }
}
else
{ 
    foreach (@Logs)
    {
        my($CommandName, $Log) = split(/,/);
        my $Result = 0;
        $rh->{$CommandName} = 1;
        if(open(LOG, $Log))
        {
            while(<LOG>)
            {
                $Result += 1 if(/^ERROR:/);
            }
            close(LOG);
        }
        else { $Result = 1 }
        $Result = $Result ? 2 : 3;
        print(QRS "\"$HOST\",\"$CommandName\",$Result\n");
        $rh->{$CommandName} = 0 if(3 == $Result);
    }
}
close(QRS);
# May 4, 2009, turn off BM1
callBM2($rh);
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
}

sub ReadIni
{
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
            if($Section eq "context") { $Context=$_; Monitor(\$Context) } 
            elsif($Section eq "smokecmd") { push(@SmokeCmds, [split('\s*\|\s*', $_)]); Monitor(\${$SmokeCmds[-1]}[2]) }  
            elsif($Section eq "root")
            { 
                my($Platform, $Root) = split('\s*\|\s*', $_);
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i)); 
                ($SRC_DIR = $Root) =~ s/\\/\//g;
                Monitor(\$SRC_DIR);
            }
        } 
    }
    close(INI);
}

sub BM{
    my($rh) = @_;
    warn("INFO:BM: PLATFORM=$PLATFORM\n");
    unless(ref($rh) eq 'HASH' && scalar(keys(%$rh)) > 0){
        warn("ERROR:BM: invalid inputs");
        return 0;	
    }
    
    my ($rev, $stream) = ($ENV{AC_TEST_BUILD} =~ m<.+\.(\d+)\.[^_]+_(\w+)$>);
    unless($rev && $stream){
        warn("ERROR:BM: Failed to find revision or stream\n");
        return 0;
    }
    #_Patch is appended in Build.pl when registering patch builds
    $stream =~ s!_Patch$!!i;
    
    my $xbm = new XBM(undef, undef, 0, $ENV{TEMP}, $JRE);
    unless($xbm){
        warn("ERROR:BM: Failed to gen object.");
        XBM::objGenErrSmT($stream, $PLATFORM, $rev, $rh, $ENV{TEMP});
        return 0;	
    }
    	
    my $rc = $xbm->uploadSmT($stream, $PLATFORM, $rev, $rh);   
    callBM2($rh);
    return $rc;    
}
############
# BM2      #
############
sub callBM2{
    my ($rh) = @_;
    eval{
        my $rBMInfo = XBM::findBM2Info();
        if($rBMInfo){
            $rBMInfo->{'cases'} = $rh;
            if(bmSmTEnd($rBMInfo)){
                warn("INFO: successfully sent SmT start info to BM2\n");
            }
            else{
                warn("WARNING: BM2 failed in bmSmTEnd");
            }
        }
        else{
            warn("WARNING: BM2 failed to find info");
        }
    };
    if($@){ warn("WARNING: BM2 failed in call with err: $@");}	
}
############
sub bmSmTEnd{
    my ($rBM) = @_;
    unless($rBM){
        warn("WARNING: bmSmTStart received invalid arg.");
        return 0;	
    }
    my $xbm = new XBM(undef, undef, 0, $ENV{TEMP}, undef);
    unless($xbm){
        warn("ERROR:BM: Failed to gen object.");
        XBM::objGenErrBM2SmTEnd($rBM, $ENV{TEMP});
        return 0;	
    }
    	
    return $xbm->sendBM2SmT($rBM, 'smtEnd');
}
############
sub Usage
{
   print <<USAGE;
   Usage   : QRS.pl -h -i
   Example : QRS.pl -h
             QRS.pl -i=config.ini

   -help|?  argument displays helpful information about builtin commands.
   -i.ni    specifies the configuration file.
   -l.og    specifies one or more log files with syntax: -log=commandname,log path
   -o.utput specifies the output file, default is \$ENV{AC_TEST_PLAN}_\$ENV{AC_TEST_SESSION}.qrs
   -j.re    specifies the full path to jre 1.5
USAGE
    exit;
}