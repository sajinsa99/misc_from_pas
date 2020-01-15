#!/usr/bin/perl -w

use JSON;
use File::Find;
use File::Path;
use LWP::Simple qw(getstore is_error);
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);

##############
# Parameters #
##############

die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});

$HTTP = $ENV{NEXUS_HTTP} || 'http://nexus.wdf.sap.corp:8081/nexus/service/local/artifact/maven/content';
$Repository = $ENV{NEXUS_REPOSITORY} || 'build.snapshots';
$ShakuntalaDir = $ARGV[0] || "$ENV{OUTPUT_DIR}/bin/contexts/shakuntala";

########
# Main #
########

$json = JSON->new->utf8;
find(\&JSONFiles, $ShakuntalaDir);
foreach my $Key (keys(%Nexus)) 
{
	my($Path, $Name) = $Nexus{$Key} =~ /^(.+)[\\\/]([^\\\/]+)$/;
	$Path =~ s/^.+?[\\\/]bin[\\\/]/$ENV{OUTPUT_DIR}\/bin\//;
	mkpath($Path) or die("ERROR: cannot mkpath '$Path': $!") unless(-d $Path);
	my $URI = "$HTTP?$Key";
	my $rc = getstore($URI, "$Path/$Name");
	die("ERROR: cannot getstore '$URI': $rc") if(is_error($rc));
}

#############
# Functions #
#############

sub JSONFiles
{
    return unless($File::Find::name =~ /\.ARTIFACT_RESOLVED\.json$/i);
	open(JS, $File::Find::name) or die("ERROR: cannot open '$File::Find::name': $!");
	{
		local $/;
		my $raDatas = $json->decode(<JS>);
		foreach my $rhData (@{$raDatas})
		{
			my($GroupId, $ArtifactId, $Version, $Classifier, $Extension, $File) = (${$rhData}{groupId}, ${$rhData}{artifactId}, ${$rhData}{version}, ${$rhData}{classifier}, ${$rhData}{extension}, ${$rhData}{file});
			$Nexus{"g=$GroupId&a=$ArtifactId&v=$Version&c=$Classifier&e=$Extension&r=$Repository"} = $File;
		}
	}
	close(JS);
}