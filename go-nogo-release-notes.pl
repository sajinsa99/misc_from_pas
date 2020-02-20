#############################################################################
# gonogo-release-notes.pl

#############################################################################
##### declare uses

## ensure good code quality
use strict;
use warnings;
use diagnostics;
use Carp qw(cluck confess);

## for the script itself
use JSON;
use Sort::Versions;
## for calculating current dir
use FindBin;
use lib $FindBin::Bin;



#############################################################################
##### declare vars
# for the script itself
# url
use vars qw (
	$CURRENTDIR
	$xmake_gendir
	$xmake_jenkins_url
	$xmake_jenkins_job_folder
	$xmake_jenkins_job
	$xmake_jenkins_job_status
	$release_vector_metadata_url
	$release_notes_metadata_url
	$version_in_release_notes_url
);

# xmake credentials
use vars qw (
	$xmake_user_purpose
	$xmake_user_id
	$xmake_user_token
);

# misc
use vars qw (
	$version_in_job
	$version_in_nexus
	$version_in_release_notes
	$release_notes_version
);



#############################################################################
##### declare functions
sub cleans_downloaded_files();
sub get_credentials();
sub get_jenkins_job_status();
sub get_latest_release_vector_in_job();
sub get_latest_release_vector_in_nexus();
sub get_release_notes_version();
sub get_latest_release_vector_in_release_notes();



#############################################################################
##### inits
$CURRENTDIR                    = $FindBin::Bin;
$xmake_gendir                  = $ENV{XMAKE_GENDIR} || "$CURRENTDIR/gen";
cleans_downloaded_files();
$xmake_user_purpose            = "xmake-dev" ;
get_credentials();
$xmake_jenkins_url             = "https://$xmake_user_purpose.wdf.sap.corp:8443";
$xmake_jenkins_job_folder      = "xmake-ci";
$xmake_jenkins_job             = "xmake-ci-ci_workflows_release_vector-OD-linuxx86_64";
$release_vector_metadata_url   = "http://nexus.wdf.sap.corp:8081/nexus/content/repositories/deploy.milestones.xmake/com/sap/prd/xmake/release_vector/ci_workflows_release_vector/maven-metadata.xml";
$release_notes_metadata_url    = "http://nexus.wdf.sap.corp:8081/nexus/content/repositories/deploy.milestones/com/sap/prd/xmake/release_notes/maven-metadata.xml";
$release_notes_version         = get_release_notes_version();
$version_in_release_notes_url  = "http://nexus.wdf.sap.corp:8081/nexus/content/repositories/deploy.milestones/com/sap/prd/xmake/release_notes/$release_notes_version/release_notes-${release_notes_version}-released_version.txt";




#############################################################################
##### MAIN
print "\n";
chdir $xmake_gendir or confess "ERROR : cannot chdir into $xmake_gendir: $!\n";
$xmake_jenkins_job_status = get_jenkins_job_status();
if($xmake_jenkins_job_status == 0) { # no error
	$version_in_job            = get_latest_release_vector_in_job();
	$version_in_nexus          = get_latest_release_vector_in_nexus();
	if( $version_in_job ne $version_in_nexus) { # anomaly nothing to do
		print "\n\nERROR : the version deployed ($version_in_job) in latest job $xmake_jenkins_job, is different than the one found in nexus ($version_in_nexus)\n\n";
		cleans_downloaded_files();
		exit 1;
	}
	$version_in_release_notes  = get_latest_release_vector_in_release_notes();
	my $compare_version_status = versioncmp($version_in_release_notes, $version_in_job);
	print "\n\n====================\n";
	print "deployed version in the latest xmake jenkins job : $version_in_job\n";
	print "version found in nexus : $version_in_nexus\n";
	print "version detected in the latest release notes : $version_in_release_notes\n";
	print "====================\n\n";
	if($compare_version_status == 0 ) { # no change
		print "\t=> no change, nothing to do\n\n";
		cleans_downloaded_files();
		exit 1; # nothing to do
	}
	if($compare_version_status == -1 ) { # new version $version_in_job > $version_in_release_notes
		print "\t=> version updated from $version_in_release_notes to $version_in_job, go release notes\n\n";
		cleans_downloaded_files();
		exit 0; # then run release notes job
	}
	if($compare_version_status == 1 ) { # anomaly $version_in_release_notes > $version_in_job
		print "\t=> version downgraded from $version_in_job to $version_in_release_notes, nothing to do\n\n";
		cleans_downloaded_files();
		exit 1; # nothing to do
	}
}  else  { # if job status failed, nothing to do
	cleans_downloaded_files();
	print "nothing to do\n";
	exit 1; # nothing to do
}



#############################################################################
### internal functions
sub cleans_downloaded_files() {
	system "rm -f $xmake_gendir/release_notes_maven-metadata.xml";
	system "rm -f $xmake_gendir/result.json";
	system "rm -f $xmake_gendir/consoleText";
	system "rm -f $xmake_gendir/released_version.txt";
}

sub get_credentials() {
	my $CREDENTIALS_SM_DIR = $ENV{CREDENTIALS_SM_DIR} || "$ENV{HOME}/.prodpassaccess" ;
	$xmake_user_id      = `prodpassaccess --credentials-root $CREDENTIALS_SM_DIR get $xmake_user_purpose user`;
	chomp $xmake_user_id;
	$xmake_user_token   = `prodpassaccess --credentials-root $CREDENTIALS_SM_DIR get $xmake_user_purpose password`;
	chomp $xmake_user_token;
}

sub get_release_notes_version() {
	system "wget --no-cookies --no-check-certificate $release_notes_metadata_url -O $xmake_gendir/release_notes_maven-metadata.xml > /dev/null 2>&1";
	(my $this_released_version) = `cat $xmake_gendir/release_notes_maven-metadata.xml  | grep -i release | grep -vi artifactid` =~ /\<release\>(.+?)\<\/release\>/i;
	return $this_released_version;
}

sub get_jenkins_job_status() {
	system "curl --fail --silent -u $xmake_user_id:$xmake_user_token $xmake_jenkins_url/job/$xmake_jenkins_job_folder/job/$xmake_jenkins_job/lastBuild/api/json > $xmake_gendir/result.json 2>&1";
	my $json_text = do {
		open(my $json_fh,"<:encoding(UTF-8)","$xmake_gendir/result.json")
			or confess "\n\nCan't open \./result.json\": $!\n\n";
		local $/;
		<$json_fh>
	};
	my $json = JSON->new;
	my $results_hRef = $json->decode($json_text);
	my $this_status = 0; # 0 passed, 1 failed
	print "url : $results_hRef->{url}\n";
	if($results_hRef->{result} !~ /^SUCCESS$/i) {
		print "\nERROR : latest build ($results_hRef->{id}) failed - $results_hRef->{result} !\n\n";
		$this_status = 1;
	}  else  {
		print "latest build $xmake_jenkins_job ($results_hRef->{id}) passed.\n";
		$this_status = 0;
	}
	return $this_status;
}

sub get_latest_release_vector_in_job() {
	system "curl --fail -u $xmake_user_id:$xmake_user_token $xmake_jenkins_url/job/$xmake_jenkins_job_folder/job/$xmake_jenkins_job/lastBuild/consoleText > $xmake_gendir/consoleText 2>&1";
	my $this_deployed_version;
	($this_deployed_version) = `grep \"deployed version\" $xmake_gendir/consoleText` =~ /deployed\s+version\:\s+(.+?)$/i;
	return $this_deployed_version;
}

sub get_latest_release_vector_in_nexus() {
	system "wget --no-cookies --no-check-certificate $release_vector_metadata_url -O $xmake_gendir/release_vector_maven-metadata.xml > /dev/null 2>&1";
	(my $this_released_version) = `cat $xmake_gendir/release_vector_maven-metadata.xml  | grep -i release | grep -vi artifactid` =~ /\<release\>(.+?)\<\/release\>/i;
	return $this_released_version;
}
#

sub get_latest_release_vector_in_release_notes() {
	system "wget --no-cookies --no-check-certificate $version_in_release_notes_url -O $xmake_gendir/released_version.txt > /dev/null 2>&1";
	my $this_released_version;
	($this_released_version) = `cat $xmake_gendir/released_version.txt` =~ /\s+\:\s+(.+?)$/i;
	return $this_released_version;
}
