 #!/usr/bin/perl -w
 
use Getopt::Long;
use LWP::Simple;
use File::Path;
use XML::DOM;

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "context=s"=>\$ContextFile, "platform=s"=>\$PLATFORM);
Usage() if($Help);  
unless($ContextFile) { print(STDERR "the -c parameter is mandatory\n"); Usage() }
$PLATFORM ||= $ENV{PLATFORM};
unless($PLATFORM) { print(STDERR "the -p parameter is mandatory\n"); Usage() }

########
# Main #
########

$CONTEXT = XML::DOM::Parser->new()->parsefile($ContextFile); 
for my $AETHER (@{$CONTEXT->getElementsByTagName("aether")})
{
    my($Platform, $Name, $Src, $Dst) = ($AETHER->getAttribute("platform"), $AETHER->getAttribute("name"), $AETHER->getAttribute("src"), $AETHER->getAttribute("dst"));
    next unless($Platform eq $PLATFORM);
    my($GroupId, $ArtifactId, $Extension, $Classifier, $Version) = split(/:/, $Name);
    ($Version, $Classifier) = ($Classifier, $Version) unless($Version);
    next if($Src =~ /^file:\/\//);
    my($NexusServerAddress, $Repository) = $Src =~ /^(http:\/\/[^\\\/]*).*?([^\\\/]+)\/$/;
    my($DestinationPath, $DestinationFile) = $Dst =~ /^(.+)[\\\/]([^\\\/]+)$/;
    while($DestinationPath =~ /\${(.*?)}/g)
    {
        my $Name = $1;
        die("ERROR: cannot found '$Name' environment variable") unless(exists($ENV{$Name}));
        $DestinationPath =~ s/\${$Name}/$ENV{$Name}/;
    }
    mkpath($DestinationPath) or die("ERROR: cannot mkpath '$DestinationPath': $!") unless(-e $DestinationPath);
    if($Name =~ /maven-metadata\.xml/)
    {
    	(my $GroupIdPath = $GroupId) =~ s/\./\//g;
    	$GroupIdPath =~ s/\/xml$/.xml/;
    	$URL = "$Src/$GroupIdPath" . ($ArtifactId ? "/$ArtifactId" : "");
    }
    else { $URL = "$NexusServerAddress/nexus/service/local/artifact/maven/content?r=$Repository&g=$GroupId&a=$ArtifactId".($Version?"&v=$Version":"").($Extension?"&e=$Extension":"").($Classifier?"&c=$Classifier":"") }
    print("[INFO] gestore $URL\n");
    my $Status = getstore($URL, "$DestinationPath/$DestinationFile");
	warn("ERROR: cannot gestore '$URL': $Status") unless(is_success($Status)); 
}
$CONTEXT->dispose();

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : BuildLocalRepo.pl -c -p
   Example : BuildLocalRepo.pl -h
             BuildLocalRepo.pl -c=mvn_6degrees.context.xml

   [option]
   -help|?      argument displays helpful information about builtin commands.
   -c.ontext    specifies the context file.
   -p.latform   specifies the platform name. The default is PLATFORM environment variable.
USAGE
    exit;
}