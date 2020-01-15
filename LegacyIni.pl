#!/usr/bin/perl -w

use Getopt::Long;
use XML::DOM;
use FindBin;
use lib ($FindBin::Bin);
use Perforce;

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "ini=s"=>\$Config, "context:s"=>\$Context);
Usage() if($Help);
unless($Config) { print(STDERR "ERROR: -i.ni option is mandatory.\n"); Usage() }
unless($Context) { print(STDERR "ERROR: -c.ontext option is mandatory.\n"); Usage() }

########
# Main #
########

my $p4 = new Perforce;

open(INI, $Config) or die("ERROR: cannot open '$Config': $!");
while(<INI>)
{
    if(my($GAVs) = /^AREAS_TO_CHECK=(.+)$/)
    {
        foreach my $GAV (split(/\s*,\s*/, $GAVs))
        {
            my($Staging, $GroupId, $ArtifactId, $Version) = split(/\s*:\s*/, $GAV);
            $AreasToCheck{$ArtifactId} = undef;
        }
        last;
    }
}
close(INI);
($LegacyConfig = $Config) =~ s/\.ini$/_legacy.ini/;
open(SRC, $Config) or die("ERROR: cannot open '$Config': $!");
open(DST, ">$LegacyConfig") or die("ERROR: cannot open '$LegacyConfig': $!");
SECTION: while(<SRC>)
{
    my($Section) = /^\[(.+)\]/;
    if($Section && ($Section eq "view"))
    {
        print(DST);
        while(<SRC>) { last if(/^\[(.+)\]/) }
        
        $CONTEXT = XML::DOM::Parser->new()->parsefile($Context);	
        for my $COMPONENT (@{$CONTEXT->getElementsByTagName("fetch")})
        {
        	my($File, $Workspace, $Revision) = ($COMPONENT->getFirstChild()->getData(),$COMPONENT->getAttribute("workspace") , $COMPONENT->getAttribute("revision"));
            my($Area) = $File =~ /^[+-]?\/\/[^\/]+\/([^\/]+)/;
            $Workspace =~ s/^([+-]?\/\/)[^\/]+/$1\$\{Client\}/;
            if(exists($AreasToCheck{$Area})) { print(DST "$File | $Workspace\n") }
            else { print(DST "$File | $Workspace | \${REF_REVISION}\n") }
        }
        $CONTEXT->dispose();
        print(DST "\n");
        redo SECTION;
    }
    if($Section && ($Section eq "import"))
    {
        print(DST);
        while(<SRC>) { last if(/^\[(.+)\]/) }
        
        $CONTEXT = XML::DOM::Parser->new()->parsefile($Context);	
        for my $COMPONENT (@{$CONTEXT->getElementsByTagName("fetch")})
        {
        	my($File, $Workspace, $Revision) = ($COMPONENT->getFirstChild()->getData(),$COMPONENT->getAttribute("workspace") , $COMPONENT->getAttribute("revision"));
            if(my($Area) = $File =~ /^\/\/[^\/]+\/([^\/]+).+\/export\/\.\.\./) { print(DST "$Area | \${REF_REVISION}\n") }
        }
        $CONTEXT->dispose();
        print(DST "\n");
        redo SECTION;
    }
    else { print(DST) }
}   
close(SRC);
close(DST);

$p4->resolve("-ay", $LegacyConfig);
warn("ERROR: cannot p4 resolve: ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/no file\(s\) to resolve.$/);
my $rhChange = $p4->fetchchange();
warn("ERROR: cannot p4 fetch change: ", @{$p4->Errors()}) if($p4->ErrorCount());
${$rhChange}{Description} = ["Summary*:automatic update", "Reviewed by*:builder"];
@{${$rhChange}{Files}} = grep(/$Context\.context\.xml/, @{${$rhChange}{Files}});
my $raChange = $p4->savechange($rhChange);
warn("ERROR: cannot p4 save change: ", @{$p4->Errors()}) if($p4->ErrorCount());
$p4->submit();
warn("ERROR: cannot p4 submit: ", @{$p4->Errors()}) if($p4->ErrorCount());

END { $p4->Final() if($p4) }

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : LegacyIni.pl -i -c
             LegacyIni.pl -h.elp|?
   Example : LegacyIni.pl -i=Aurora_PI_WebI.ini -c=Aurora_PI_WebI.context.xml
    
   [options]
   -help|?     argument displays helpful information about builtin commands.
   -i.ni       specifies the ini file.
   -c.ontext   specifies the context file.
USAGE
    exit;
}
