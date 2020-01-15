#!/usr/bin/perl -w
 
use LWP::UserAgent;
use Getopt::Long;
use JSON;

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "context=s@"=>\@ContextFiles, "prefix=s"=>\$Prefix, "url=s"=>\$URL);  
Usage() if($Help);
unless(@ContextFiles) { print(STDERR "the -c parameter is mandatory\n"); Usage() }
unless($URL)          { print(STDERR "the -u parameter is mandatory\n"); Usage() }

if($Prefix)
{
    die("ERROR: cannot found environment variable '$Prefix'") unless($ENV{$Prefix});
    if($^O eq "MSWin32") { ($Pattern = $ENV{$Prefix}) =~ s/\//\\/g  }
    else                 { ($Pattern = $ENV{$Prefix}) =~ s/\\/\//g  }
}

($Platform) = $URL =~ /&platform=(.+?)&/;
$Platform ||= "";

########
# Main #
########

$ua  = LWP::UserAgent->new();
$Response = $ua->get($URL);
die("ERROR: cannot request: ", $Response->status_line()) unless($Response->is_success());
$JSONContent = $Response->content();

$json = JSON->new->allow_nonref;
$artifacts_from_json = $json->decode($JSONContent);
foreach my $artifact (@$artifacts_from_json)
{
    if (!(defined $artifact->{'repository'})) { warn("WARNING: cannot found repository"); next }
    #if ( $artifact->{'eventMask'} & 0x4) { warn("ERROR: ARTIFACT DESCRIPTOR INVALID"); next } 
    #elsif ( $artifact->{'eventMask'} & 0x8) { warn("ERROR: ARTIFACT DESCRIPTOR MISSING"); next } 
    #elsif ( $artifact->{'eventMask'} & 0x10) { warn("ERROR: METADATA INVALID"); next }
    #next unless ( $artifact->{'eventMask'} & 0x42);
    
    my $GAV = $artifact->{'artifactCoordinate'}->{'name'};
    next if($GAV =~ /maven-metadata\.xml$/);
    my($GroupPath, $ArtifactId, $Extension, $Classifier, $Version) = split(':', $GAV);
    unless($Classifier || $Version) { $Version = $Extension; $Extension = "jar" } 
    unless($Version) { $Version = $Classifier; $Classifier = "" }
    $Classifier = "-$Classifier" if($Classifier);
    $GroupPath =~ s/\./\\/g;
    my $Dst = "\${$Prefix}\\obj\\maven\\repository\\$GroupPath\\$ArtifactId\\$Version\\$ArtifactId-$Version$Classifier.$Extension";
    push(@Artifacts, [ $artifact->{'logTime'}, "\t<aether platform=\"$Platform\" name=\"$GAV\" src=\"$artifact->{'repository'}->{'name'}\" dst=\"$Dst\"/>\n"]);
}
@Artifacts = map({${$_}[1]} sort({${$a}[0]<=>${$b}[0]} @Artifacts));

foreach my $ContextFile (@ContextFiles)
{
    open(CTXT, "+<$ContextFile") or die("ERROR: cannot open '$ContextFile': $!");
    @Lines = grep({!/^\s*<aether\s+.*platform="$Platform"/} <CTXT>);
    for(my $i=0; $i<@Lines; $i++) 
    {
        next unless($Lines[$i] =~ /^\s*<version\s/);
        @Lines = (@Lines[0..$i-1], @Artifacts, @Lines[$i..$#Lines]);
        last
    }
    seek(CTXT, 0, 0);
    print(CTXT @Lines);
    truncate(CTXT, tell(CTXT)) or die("ERROR: cannot truncate '$ContextFile': $!");
    close(CTXT);
}

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : MvnContext.pl -c -p -u
   Example : MvnContext.pl -h
             MvnContext.pl -c=mvn_6degrees.context.xml -u=\"http://vantgvmlnx124.dhcp.pgdev.sap.corp:8080/torch/rest/artifacts?group=com.sap&project=6degrees&branch=1.0&mode=debug&platform=noarch&language=en&version=1.0.2-snapshot\" -p=OUTPUT_DIR
             Before to use MvnContext.pl you must install maven event spy (see https://tdwiki.pgdev.sap.corp/display/RM/How+to+inject+maven+build+results+into+Torch) and json perl module version 2.07

   [option]
   -help|?      argument displays helpful information about builtin commands.
   -c.ontext    specifies one or more context files.
   -p.refix     specifies the prefix name.
   -u.rl        specifies the torch URL.
USAGE
    exit;
}
