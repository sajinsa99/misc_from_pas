#!/usr/bin/perl -w

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Getopt::Long;

die("ERROR: ARTIFACTDEPLOYER_HOME environment variable must be set.\nPlease see https://wiki.wdf.sap.corp/wiki/display/Omnivore/Artifact+Deployer+-+Release+Notes+0.2") unless($ENV{ARTIFACTDEPLOYER_HOME});
die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/[\\\/]\d+$//;
$TEMPDIR =~ s/\\/\//g;

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "extension=s"=>\$Extension, "folder=s"=>\$Folder, "gav=s"=>\$GAV, "password=s"=>\$Password, "repository=s"=>\$Repository, "user=s"=>\$User);  
Usage() if($Help);
unless($Folder)     { print(STDERR "the -f parameter is mandatory\n"); Usage() }
unless($GAV)        { print(STDERR "the -g parameter is mandatory\n"); Usage() }
unless($Repository) { print(STDERR "the -s parameter is mandatory\n"); Usage() }
unless($Password)   { print(STDERR "the -p parameter is mandatory\n"); Usage() }
unless($User)       { print(STDERR "the -u parameter is mandatory\n"); Usage() }

$Extension ||= 'zip';

########
# Main #
########

($Root, $Name) = $Folder =~ /^(.+)[\\\/]([^\\\/]+)$/; 
($GroupId, $ArtifactId, $Version, $Classifier) = split(':', $GAV);
$Classifier ||= "";
chdir($Root) or warn("ERROR: cannot chdir '$Root': $!");
if('jar' =~ /^$Extension/i)
{
    print("jar cf $TEMPDIR/$ArtifactId.jar $Name/\n");
    system("jar cf $TEMPDIR/$ArtifactId.jar $Name/");
}
elsif('zip' =~ /^$Extension/i)
{
   my $zip = Archive::Zip->new();
   $zip->addTree($Name);
   unless($zip->writeToFileNamed("$TEMPDIR/$ArtifactId.zip") == AZ_OK ) { die("ERROR: cannot create '$TEMPDIR/$ArtifactId.zip': $!") }
} else { die("ERROR: unknown extension '$Extension'.") }
    
open(GROOVY, ">$TEMPDIR/$ArtifactId.groovy") or die("ERROR: cannot open '$TEMPDIR/$ArtifactId.groovy': $!");
print(GROOVY "artifacts builderVersion:\"1.0\", {\n");
print(GROOVY "    artifact \"$ArtifactId\", group:\"$GroupId\", {\n");
print(GROOVY "        file \"$TEMPDIR/$ArtifactId.$Extension\", classifier:\"$Classifier\", extension:\"$Extension\"\n");
print(GROOVY "    }\n");
print(GROOVY "}\n");
close(GROOVY);

chdir("$ENV{ARTIFACTDEPLOYER_HOME}/bin") or warn("ERROR: cannot chdir '$ENV{ARTIFACTDEPLOYER_HOME}/bin': $!");
print("artifactdeployer.cmd pack -f $TEMPDIR/$ArtifactId.groovy -p $TEMPDIR/deploy.$Extension\n");
system("artifactdeployer.cmd pack -f $TEMPDIR/$ArtifactId.groovy -p $TEMPDIR/deploy.$Extension");

print("artifactdeployer.cmd deploy -p $TEMPDIR/deploy.$Extension --artifact-version $Version --repo-url $Repository --repo-user $User --repo-passwd $Password\n");
system("artifactdeployer.cmd deploy -p $TEMPDIR/deploy.$Extension --artifact-version $Version --repo-url $Repository --repo-user $User --repo-passwd $Password");

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : Deploy.pl -f -g -e -r -u -p 
   Example : Deploy.pl -h
             Deploy.pl -f=D:/a41_cbt32/win32_x86/release/bin/bex -g=com.sap:bex:2.1-SNAPSHOT -r=http://localhost:1081/nexus/content/repositories/snapshots -u=deployment -p=***

   [option]
   -help|?      argument displays helpful information about builtin commands.
   -e.xtension  specifies the filename extension to be used, the default is zip
   -f.older     specifies the folder to export to Nexus server.
   -g.av        specifies the GAV with the following syntax group:artifact:version[:classifier].
   -p.assword   specifies the Nexus server password.
   -r.epository specifies Nexus repository address.
   -u.ser       specifies the Nexus server user.
USAGE
    exit;
}