#!/usr/bin/perl -w

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Getopt::Long;
use LWP::Simple;
use File::Path;
use File::Copy;

die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/[\\\/]\d+$//;

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "extension=s"=>\$Extension, "artifact=s"=>\$Artifact, "gav=s"=>\$GAV, "output=s"=>\$OutputDir, "repository=s"=>\$RepositoryPath, "unzip!"=>\$Unzip,);  
Usage() if($Help);
unless($GAV) { print(STDERR "the -g parameter is mandatory\n"); Usage() }
unless($OutputDir || $ENV{OUTPUT_DIR}) { print(STDERR "the -o parameter is mandatory\n"); Usage() }
unless($RepositoryPath) { print(STDERR "the -r parameter is mandatory\n"); Usage() }
($NexusServerAddress, $Repository) = $RepositoryPath =~ /^(http:\/\/[^\\\/]*).*?([^\\\/]+$)/;
$Unzip = 1 unless(defined($Unzip));
$Extension ||= $Artifact? ($Artifact=~/\.([^.]+)$/, $1) : "zip";

########
# Main #
########

($GroupId, $ArtifactId, $Version, $Classifier) = split(':', $GAV);
($GroupPath = $GroupId) =~ s/\./\//g;
$URL = $Artifact ? "$RepositoryPath/$GroupPath/$ArtifactId/$Version/$Artifact" : "$NexusServerAddress/nexus/service/local/artifact/maven/content?r=$Repository&g=$GroupId&a=$ArtifactId&v=$Version&e=$Extension".($Classifier?"&c=$Classifier":"");
$Artifact ||= "$ArtifactId".($Classifier?"-$Classifier":"").".$Extension";
$Status = getstore($URL, "$TEMPDIR/$Artifact");
die("ERROR: cannot gestore '$URL': $Status") unless(is_success($Status));

$OutputDir ||= "$ENV{OUTPUT_DIR}/bin/$ArtifactId";
mkpath($OutputDir) or die("ERROR: cannot mkpath '$OutputDir': $!") unless(-e $OutputDir);
if($Unzip)
{
	chdir($OutputDir) or die("ERROR: cannot chdir '$OutputDir': $!");
	if('jar' =~ /^$Extension/)
	{
	    system("jar -xf $TEMPDIR/$ArtifactId.$Extension $ArtifactId") and die("ERROR: cannot extract jar '$TEMPDIR/$Artifact': $!");
	}
	elsif('zip' =~ /^$Extension/)
	{
        my $zip = Archive::Zip->new("$TEMPDIR/$Artifact");
        unless($zip->extractTree()==AZ_OK) { die("ERROR: cannot extract tree: $!") }
    }
} else { copy("$TEMPDIR/$Artifact", $OutputDir) or die("ERROR: cannot copy '$TEMPDIR/$Artifact': $!") }

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : Unpack.pl -g -o -r -u
   Example : Unpack.pl -h
             Unpack.pl -r=http://localhost:1081/nexus/content/repositories/snapshots -g=com.sap:bex:2.1-SNAPSHOT

   [option]
   -help|?      argument displays helpful information about builtin commands.
   -a.rtifact   specifies the artifact name to fetch from Nexus.
   -e.xtension  specifies the filename extension to be used
   -g.av        specifies the GAV to fetch from Nexus server.
   -o.utput     specifies the output directory, default is \$ENV{OUTPUT_DIR}/bin/<artifactId>.
   -r.epository specifies Nexus repository address.
   -u.nzip      unzip the artifact file (-u.nzip) or copy the artifact (-nou.nzip), default is -u.nzip.   
USAGE
    exit;
}