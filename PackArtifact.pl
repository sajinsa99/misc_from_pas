#!/usr/bin/perl -w

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Getopt::Long;
use File::Path;

die("ERROR: ARTIFACTDEPLOYER_HOME environment variable must be set.\nPlease see https://wiki.wdf.sap.corp/wiki/display/Omnivore/Artifact+Deployer+-+Release+Notes+0.2") unless($ENV{ARTIFACTDEPLOYER_HOME});
die("ERROR: OUTPUT_DIR environment variable must be set.") unless($ENV{OUTPUT_DIR});
die("ERROR: SRC_DIR environment variable must be set.") unless($ENV{SRC_DIR});

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "build=s"=>\$BuildName, "classifier=s"=>\$Classifier, "folder=s"=>\$Folder, "groovy=s"=>\$GroovyFile, "package=s"=>\$PackageFile);
Usage() if($Help);
unless($Folder)      { print(STDERR "the -f parameter is mandatory\n"); Usage() }
unless($BuildName)   { print(STDERR "the -b parameter is mandatory\n"); Usage() }
unless($GroovyFile)  { print(STDERR "the -g parameter is mandatory\n"); Usage() }
unless($PackageFile) { print(STDERR "the -o parameter is mandatory\n"); Usage() }
($Root, $Area) = $Folder =~ /^(.+)[\\\/]([^\\\/]+)$/; 
$Classifier ||= "";

########
# Main #
########

mkpath("$ENV{OUTPUT_DIR}/obj/$Area") or die("ERROR: cannot mkpath '$ENV{OUTPUT_DIR}/obj/$Area': $!") unless(-e "$ENV{OUTPUT_DIR}/obj/$Area");
chdir($Root) or warn("ERROR: cannot chdir '$Root': $!");
my $zip = Archive::Zip->new();
$zip->addTree($Area);
die("ERROR: cannot create '$ENV{OUTPUT_DIR}/obj/$Area/$Area.zip': $!") unless($zip->writeToFileNamed("$ENV{OUTPUT_DIR}/obj/$Area/$Area.zip")==AZ_OK);

chdir("$ENV{ARTIFACTDEPLOYER_HOME}/bin") or die("ERROR: cannot chdir '$ENV{ARTIFACTDEPLOYER_HOME}/bin': $!");
system("artifactdeployer.cmd pack -Dout_dir=$ENV{OUTPUT_DIR} -Dclassifier=$Classifier -DPOM=$ENV{SRC_DIR}/$Area/pom.xml -DCONTEXT=$ENV{SRC_DIR}/Build/export/shared/contexts/$BuildName.context.xml -f $GroovyFile -p $PackageFile");

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : PackArtifact.pl -g -p -f -c -b
   Example : PackArtifact.pl -h
             PackArtifact.pl -f=cvom -g=cvom.groovy -b=cvom_2.0 -p=cvom.df

   [option]
   -help|?      argument displays helpful information about builtin commands.
   -b.uild      specifies the build name.
   -c.lassifier specifies the classifier (optional).
   -f.older     specifies the folder to export to Nexus server.
   -g.roovy     Specifies the Groovy script file to use.
   -p.ackage    specifies the package file to be created.
USAGE
    exit;
}