#!/usr/bin/perl -w

use File::Find;
use File::Path;
use FindBin;
use JSON;

##############
# Parameters #
##############

die("ERROR: SRC_DIR environment variable must be set") unless($ENV{SRC_DIR});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});
die("ERROR: context environment variable must be set") unless($ENV{context});
die("ERROR: PLATFORM environment variable must be set") unless($ENV{PLATFORM});
die("ERROR: BUILD_MODE environment variable must be set") unless($ENV{BUILD_MODE});
$CURRENTDIR = $FindBin::Bin;

$ARTIFACTDEPLOYER_HOME = $ENV{ARTIFACTDEPLOYER_HOME} || "$CURRENTDIR/artifactdeployer";
$ContextFile = "$ENV{SRC_DIR}/Build/export/shared/contexts/$ENV{context}_$ENV{PLATFORM}_$ENV{BUILD_MODE}.context.zip";
$ContextFile = "$ENV{SRC_DIR}/Build/export/shared/contexts/$ENV{context}.context.xml" unless(-f $ContextFile);

########
# Main #
########

find(\&JSON, "$ENV{OUTPUT_DIR}/bin/contexts/shakuntala");
chdir("$ARTIFACTDEPLOYER_HOME/bin") or warn("ERROR: cannot chdir '$ARTIFACTDEPLOYER_HOME/bin': $!");	
foreach my $GAV (keys(%GAVs))
{
	my($GroupId, $ArtifactId, $Version) = split(':', $GAV);
	mkpath("$ENV{OUTPUT_DIR}/commonrepo/$ArtifactId") or warn("ERROR: cannot mkpath '$ENV{OUTPUT_DIR}/commonrepo/$ArtifactId': $!") unless(-d "$ENV{OUTPUT_DIR}/commonrepo/$ArtifactId");
	
	mkpath("$ENV{OUTPUT_DIR}/obj") or warn("ERROR: cannot mkpath '$ENV{OUTPUT_DIR}/obj': $!") unless(-d "$ENV{OUTPUT_DIR}/obj");
	open(GROOVY, ">$ENV{OUTPUT_DIR}/obj/mvn_deploy.groovy") or die("ERROR: cannot open '$ENV{OUTPUT_DIR}/obj/mvn_deploy.groovy': $!");
	print(GROOVY "artifacts builderVersion:\"1.1\", {\n");
	print(GROOVY "\tgroup \"$GroupId\", {\n");
	print(GROOVY "\t\tversion \"$Version\", {\n");
	print(GROOVY "\t\t\tartifact \"$ArtifactId\", {\n");
	foreach my $File (keys(%{$GAVs{$GAV}}))
	{
		my($Classifier, $Extension) = @{${$GAVs{$GAV}}{$File}};
		if($Extension eq 'pom') { print(GROOVY "\t\t\t\tpom file:\"$File\"\n") }
		else { print(GROOVY "\t\t\t\tfile \"$File\"", $Classifier?", classifier:\"$Classifier\"":"", "\n") }
	}
	print(GROOVY "\t\t\t}\n");
	print(GROOVY "\t\t}\n");
	print(GROOVY "\t}\n");
	print(GROOVY "}");
	close(GROOVY);

	print("artifactdeployer.cmd pack --metadata-type-name \"Metadata Build Context\" --metadata-file $ContextFile -f $ENV{OUTPUT_DIR}/obj/mvn_deploy.groovy -p $ENV{OUTPUT_DIR}/commonrepo/$ArtifactId/$ArtifactId.df\n");
	$Result = `artifactdeployer.cmd pack --metadata-type-id sbop.build.context --metadata-type-name "Metadata Sbop Build Context" --metadata-file $ContextFile -f $ENV{OUTPUT_DIR}/obj/mvn_deploy.groovy -p $ENV{OUTPUT_DIR}/commonrepo/$ArtifactId/$ArtifactId.df`;
	print("$Result\n") if($Result !~ /^\s*$/);
}

#############
# Functions #
#############

sub JSON
{
	return unless($File::Find::name=~/\.ARTIFACT_INSTALLED\.json$/);

	local $/;
	open(JSON, $File::Find::name) or die("ERROR: cannot open '': $!");
	my $raArtifacts = from_json(<JSON>);
	close(JSON);
	foreach my $rhArtifact (@{$raArtifacts})
	{
		my($GroupId, $ArtifactId, $Version, $Classifier, $Extension, $File) = @{$rhArtifact}{qw(groupId artifactId version classifier extension file)};
		$File =~ s/\\/\//g;
		${$GAVs{"$GroupId:$ArtifactId:$Version"}}{$File} = [$Classifier, $Extension];
	}
}