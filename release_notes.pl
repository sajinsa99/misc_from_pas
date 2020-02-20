##############################################################################
##### declare uses

## basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

use JSON qw( decode_json );
use Data::Dumper;
use DateTime;
use DateTime::TimeZone;
use HTTP::Tiny;
use Sort::Versions;
use Carp qw(cluck confess);
use File::Fetch;
use Getopt::Long;

## internal use
use sap_sm_jira;



#############################################################################
##### declare vars
#for script it self
use vars qw (
	$from_json
	$aiRef
	$aoRef
	$out_gen_dir
	$currentTime
	$released_version
	$remoteHost
	$remoteUser
	$remoteBranch
	$current_release_vector
	$flag_new_version_found
);


# date / time
use vars qw (
	$tz
	$dt
	$year
	$month
	$day
	$hour
	$minute
	$second
	$day_abbr
	$day_name
	$ymd
);

# pramaters / options
use vars qw (
	$opt_no_check_new_version
	$opt_no_update_jira
	$opt_no_mail
);



#############################################################################
##### declare functions
sub sap_main();
sub sap_init_vars();
sub sap_init_datetime();
sub sab_get_all_versions($);
sub sap_display_releases_notes_file_in_console($);
sub sap_get_releases_notes_for_version($);
sub sap_get_date_file_for_version($$$);
sub sap_check_if_new_version();
sub sap_generate_html();
sub sap_display_releases_notes_in_console();
sub sap_update_jiras();
sub sap_send_mail();
sub sap_get_current_release_vector();
sub sap_missed();
sub sap_get_jira_title_info($);



#############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
	"ncnv"    =>\$opt_no_check_new_version,
	"nuj"     =>\$opt_no_update_jira,
	"nm"      =>\$opt_no_mail,
);



#############################################################################
##### MAIN
sap_main();
exit 0;



#############################################################################
### internal functions
sub sap_main() {
	print "
START of $0
";

	sap_init_vars();
	sap_check_if_new_version();
	sap_display_releases_notes_in_console();
	sap_generate_html();
	if(open LIST , ">$out_gen_dir/list_jira.txt") {
		my $jira_list = join ',' , sort @LIST_JIRAS;
		print LIST "$released_version : $jira_list";
		close LIST;
	}
	if( $ENV{CALL_PERL_SCRIPTS} && ($ENV{CALL_PERL_SCRIPTS} =~ /^yes$/) ) {
		sap_update_jiras() unless($opt_no_update_jira);
		sap_send_mail()    unless($opt_no_mail);
	}
	else {
		if( $ENV{TESTS} && ($ENV{TESTS} =~ /^yes$/) ) {
			if( ! $ENV{CALL_PERL_SCRIPTS} ) {
				sap_update_jiras() unless($opt_no_update_jira);
				sap_send_mail()    unless($opt_no_mail);
			}
		}
	}

	print "
END of $0
";
}


sub sap_init_vars() {
	$File::Fetch::WARN = 0;
	my $json_text = do {
		open(my $json_fh,"<:encoding(UTF-8)","./release_notes.json")
			or confess "\n\nCan't open ./release_notes.json\": $!\n\n";
		local $/;
		<$json_fh>
	};
	my $json = JSON->new;
	$from_json = $json->decode($json_text);
	$aiRef = $from_json->{artifacts_input};
	$aoRef = $from_json->{artifacts_output};

	$out_gen_dir = "../gen";
	if( ! -e $out_gen_dir) {
		mkdir $out_gen_dir;
	}
	sap_init_datetime();
	# for remote
	$remoteHost   = "mo-60192cfe2.mo.sap.corp";
	$remoteUser   = "pblack";
	if( $ENV{TESTS} && ($ENV{TESTS} =~ /^yes$/) ) {
		$remoteBranch = "dev";
	}
	else {
		$remoteBranch = "master";
	}
	$flag_new_version_found = 0;
}


sub sap_init_datetime() {
	# date / time
	#$tz = DateTime::TimeZone->new( name => 'Europe/Paris' );
	$dt = DateTime->now;
	$dt->set_time_zone( 'Europe/Paris' );

	$year   = $dt->year;
	$month  = $dt->month;          # 1-12
	$day    = $dt->day;            # 1-31

	$hour   = $dt->hour;           # 0-23
	$minute = $dt->minute;         # 0-59
	$second = $dt->second;         # 0-61 (leap seconds!)

	$hour   = "0$hour"    if ($hour     < 10);
	$minute = "0$minute"  if ($minute   < 10);
	$second = "0$second"  if ($second   < 10);

	$day_abbr = $dt->day_abbr;   # Mon, Tue, ...
	#$day_name = $dt->day_name;
	$ymd      = $dt->ymd;
}

sub sab_get_all_versions($) {
	my ($this_maven_metadata_url) = @_ ;
	my $response = HTTP::Tiny->new->get($this_maven_metadata_url);
	my @maven_metadata_xml;
	if ($response->{success}) {
		@maven_metadata_xml = split '\n' , $response->{content};
	}
	my @tmp;
	my $this_released_version;
	foreach my $line (@maven_metadata_xml) {
		if($line =~  /\<release\>(.+?)\<\/release\>/) {
			$this_released_version = $1;
		}
		if($line =~ /\<version\>(.+?)\<\/version\>/) {
			push @tmp , $1;
		}
	}
	my @tmp2 = sort versioncmp @tmp;
	return ($this_released_version,@tmp2);
}

sub sap_display_releases_notes_in_console() {
	for my $aiElement (@$aiRef) {
		if( $aiElement->{nexus} && $aiElement->{repository} && $aiElement->{groupID} && $aiElement->{artifactID} ) {
			# 1 get all version of artifats
			# list ofr version in maven-metadata.xml
			# 1.1 transform '.' by '/' in groupID for calculating maven-metadata url
			( my $groupID_url  = $aiElement->{groupID} ) =~ s-\.-\/-g;
			# 1.2 calculate maven-metadata url
			my $base_ai_url = "$aiElement->{nexus}/"
						 . "$aiElement->{repository}/"
						 . "$groupID_url/"
						 . "$aiElement->{artifactID}/"
						 ;
			my $meta_data_url = "$base_ai_url/maven-metadata.xml";
			my ($this_released_version,@all_versions) = sab_get_all_versions($meta_data_url);
			if(scalar @all_versions > 0) {
				print "artifact : $aiElement->{artifactID}\n";
				print "base_url : $base_ai_url\n";
				print "released version : $this_released_version\n";
				print "base version     : $aiElement->{oldest_version_supported}\n" if($aiElement->{oldest_version_supported});
				foreach my $version (reverse @all_versions) {
					my $url_release_notes_txt_file = "$base_ai_url/"
												   . "$version/"
												   . "$aiElement->{artifactID}"
												   . "-$version.txt"
												   ;
					print "\t$version\n";
					sap_display_releases_notes_file_in_console("$url_release_notes_txt_file");
					last if( $aiElement->{oldest_version_supported} eq "$version");
				}
				print "\n";
			}
		}
		else {
			print "\nERROR : one key value missing !\n";
			print "available keys:
* nexus
* repository
* groupID
* artifactID
oldest_version_supported
jira
note:
* mandatory key
			";
			exit 1;
		}
	}
}

sub sap_generate_html() {
	if(open HTML , ">$out_gen_dir/release_notes.html") {
		print "\nCreating $out_gen_dir/release_notes.html\n";
		my $start_time = "generated on $day_abbr, $ymd (yyyy-mm-dd)</br>at $hour:$minute:$second (Paris time)";
		unlink "$out_gen_dir/release_notes.txt" if ( -e "$out_gen_dir/release_notes.txt");
		print HTML '<!DOCTYPE html>
	<html>
	<head>
		<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
	    <meta http-equiv="cache-control" content="no-cache" />
	    <meta http-equiv="pragma" content="no-cache" />
		<title>Releases Notes xMake</title>
</head>
</br>
</br>
<div align="right">'.$start_time.'</div>
</br>
<h1><center>Release Notes</center></h1>
</br>
</br>
	';
		my $nbTitles = 0;
		for my $aiElement (@$aiRef) {
			if( $aiElement->{nexus} && $aiElement->{repository} && $aiElement->{groupID} && $aiElement->{artifactID} && $aiElement->{title} ) {
				$nbTitles++;
			}
		}
		if($nbTitles > 1) {
			print HTML '
</br>
';
			for my $aiElement (@$aiRef) {
				if( $aiElement->{nexus} && $aiElement->{repository} && $aiElement->{groupID} && $aiElement->{artifactID} && $aiElement->{title} ) {
					print HTML "<a href=\"#$aiElement->{title}\">$aiElement->{title}</a></br>\n";
				}
			}
			print HTML '
</br>
</br>
';
		}
		for my $aiElement (@$aiRef) {
			if( $aiElement->{nexus} && $aiElement->{repository} && $aiElement->{groupID} && $aiElement->{artifactID} ) {
				# 1 get all version of artifats
				# list ofr version in maven-metadata.xml
				# 1.1 transform '.' by '/' in groupID for calculating maven-metadata url
				( my $groupID_url  = $aiElement->{groupID} ) =~ s-\.-\/-g;
				# 1.2 calculate maven-metadata url
				my $base_ai_url = "$aiElement->{nexus}/"
							 . "$aiElement->{repository}/"
							 . "$groupID_url/"
							 . "$aiElement->{artifactID}"
							 ;
				my $meta_data_url = "$base_ai_url/maven-metadata.xml";
				my ($this_released_version,@all_versions) = sab_get_all_versions($meta_data_url);
				print HTML '
</br>
<a id="'.$aiElement->{title}.'"></a>
<fieldset><legend>&nbsp;&nbsp;<strong>'.$aiElement->{title}.'</strong>&nbsp;&nbsp;</legend>
</br>
<table rules="all" style="border:1px solid black; margin-left:100px;" cellpadding="6">
';
				if(scalar @all_versions > 0) {
					my $start = 0;
					foreach my $version (reverse @all_versions) {
						my $date_file = sap_get_date_file_for_version($aiElement->{artifactID},$version,"$base_ai_url/$version");
						my $url_release_notes_txt_file = "$base_ai_url/"
													   . "$version/"
													   . "$aiElement->{artifactID}"
													   . "-$version.txt"
													   ;
						if($version eq $this_released_version) {
							print HTML "<tr style=\"background-color: \#D3D3D3\"><td align=\"center\" release=\"$version\" id=\"$version\"><a href=\"$url_release_notes_txt_file\" target=_blank>$version</a> ($date_file)</td></tr>\n";
							$start = 1;
							$released_version = $this_released_version;
						}
						else {
							print HTML "<tr style=\"background-color: \#D3D3D3\"><td align=\"center\" id=\"$version\"><a href=\"$url_release_notes_txt_file\" target=_blank>$version</a> ($date_file)</td></tr>\n";
							$start = 0;
						}
						my $content = sap_get_releases_notes_for_version($url_release_notes_txt_file);
						my @lines = split '\n' , $content;
						print HTML "<tr><td><p>";
						my $changelog = 0;
						my $JIRAComp = $aiElement->{jira};
						foreach my $line (@lines) {
							chomp $line;
							next if($line =~ /Merge pull request/);
							next if($line =~ /Merge branch/);
							if($line =~ /^Change Log/i) {
								$changelog =  1;
								next;
							}
							next unless($changelog == 1);
							if($line =~ /$JIRAComp/i) {
								my $final_line = $line;
								(my $tmp_line = $line) =~ s-$JIRAComp\-\d+--gi;
								($tmp_line) =~ s/\s+//g;
								my $flag_missed_comment = 0;
								if( $tmp_line !~ /[\w+|\d+]/i) { # no alpha-numeric
									$flag_missed_comment = 1;
								}
								while($line =~ /($JIRAComp\-\d+)/gi) {
									my $jira = $1;
									my $jira_uppercase = uc $jira;
									if ($start == 1) {
										push @LIST_JIRAS , "$jira_uppercase" unless grep /^$jira_uppercase$/i , @LIST_JIRAS ;
									}
									# check if no description
									my $missed_comment = "";
									if($flag_missed_comment == 1) {
										$missed_comment = sap_get_jira_title_info($jira_uppercase);
										$missed_comment = " " . $missed_comment;
									}
									($final_line) =~ s-$jira-\<a href\=\"https\:\/\/sapjira\.wdf\.sap\.corp\/browse\/$jira_uppercase\"\ target\=\_blank\>$jira_uppercase\<\/a\>$missed_comment-gi;
								}
								print HTML "$final_line</br>\n" if ($changelog == 1);
							}
							else {
								next if( $line =~ /^\>/ ); # skip line starting by '>'
								print HTML "$line</br>\n" if ($changelog == 1);
							}
						}
						print HTML "</p></td></tr>\n";
						last if($aiElement->{oldest_version_supported} && ($version eq $aiElement->{oldest_version_supported}));
					}
				}
				print HTML '
</table>
<br/>
</fieldset>
';
				if(open TXT , ">>$out_gen_dir/release_notes.txt") {
						print TXT "$aiElement->{title} ($aiElement->{artifactID}) : $this_released_version\n";
					close TXT;
			}
		}
	}
	if($nbTitles > 1) {
		print HTML '
</br>
';
		for my $aiElement (@$aiRef) {
			if( $aiElement->{nexus} && $aiElement->{repository} && $aiElement->{groupID} && $aiElement->{artifactID} && $aiElement->{title} ) {
				print HTML "<a href=\"#$aiElement->{title}\">$aiElement->{title}</a></br>\n";
			}
		}
			print HTML '
</br>
</br>
';
	}
	print HTML '
<br/>
</body>
</html>
	';
		close HTML;
		print "\n$out_gen_dir/release_notes.html created\n";
	}
	system "touch $out_gen_dir/missed.txt";
}

sub sap_display_releases_notes_file_in_console($) {
	my ($this_url_release_note) = @_ ;
	my $details = sap_get_releases_notes_for_version($this_url_release_note);
	my $changelog = 0;
	my @lines = split '\n' , $details;
	my $JIRAComp;
	for my $aiElement (@$aiRef) {
		$JIRAComp = $aiElement->{jira};
	}
	foreach my $line (@lines) {
		chomp $line;
		next if($line =~ /Merge pull request/);
		if($line =~ /^Change Log/i) {
			$changelog =  1;
			next;
		}
		next if( ($line =~ /^\>/) && !($line =~ /${JIRAComp}/i) ); # skip line starting by '>' but without jira component
		print "$line\n" if($changelog == 1);
	}
	print "\n";
}

sub sap_get_releases_notes_for_version($) {
	my ($this_url_release_note2) = @_ ;
	my $content;
	my $response = HTTP::Tiny->new->get($this_url_release_note2);
	if ($response->{success}) {
		$content = $response->{content};
	}
	return "$content";
}

sub sap_get_date_file_for_version($$$) {
	my ($pattern,$this_version,$url_release_note) = @_ ;
	#my $url_release_note = "http://nexus.wdf.sap.corp:8081/nexus/content/repositories"
	#					 . "/$repository"
	#					 . "/com/sap/prd/xmake/release_vector/ci_workflows_release_vector"
	#					 . "/$this_version/";
	my $content;
	my $response = HTTP::Tiny->new->get($url_release_note);
	if ($response->{success}) {
		$content = $response->{content};
	}
	my @lines = split '\n' , $content;
	my $found = 0;
	my $date;
	for my $line (@lines) {
		if($line =~ /$pattern-$this_version.txt\"\>/) {
			$found = 1;
			next;
		}
		if(($found == 1) && ($line =~ /\<td\>(.+?)\<\/td\>/)) {
			$date = $1;
			last;
		}
	}
	return $date;
}

sub sap_check_if_new_version() {
	#return if( $ENV{TESTS} && ($ENV{TESTS} =~ /^yes$/) );
	#get nb elem for calculate the nb of new version for each elem
	
	sap_get_current_release_vector();
	# ICI for TESTS
	#$current_release_vector = "1.3.3";
	
	my $nbElem = 0;
	for my $aiElement (@$aiRef) {
		if( $aiElement->{nexus} && $aiElement->{repository} && $aiElement->{groupID} && $aiElement->{artifactID} ) {
			$nbElem++;
		}
	}
	my $nbElemRel = 0;

	# create hash to skip parsing aiRef all the time
	my %thisaoArtifact;
	for my $aoElement (@$aoRef) {
		if( $aoElement->{nexus} && $aoElement->{repository} && $aoElement->{groupID} && $aoElement->{artifactID} ) {
			$thisaoArtifact{nexus}      = $aoElement->{nexus};
			$thisaoArtifact{repository} = $aoElement->{repository};
			$thisaoArtifact{groupID}    = $aoElement->{groupID};
			$thisaoArtifact{artifactID} = $aoElement->{artifactID};
			$nbElemRel++;
		}
	}
	( my $groupID_url  = $thisaoArtifact{groupID} ) =~ s-\.-\/-g;
	# get metadat
	my $base_ao_url = "$thisaoArtifact{nexus}"
				. "/$thisaoArtifact{repository}"
				. "/$groupID_url"
				. "/$thisaoArtifact{artifactID}"
				;
	if( $ENV{TESTS} && ($ENV{TESTS} =~ /^yes$/) ) {
		#($base_ao_url) =~ s-nexus\.wdf\.sap\.corp\:8081-nexustest\.wdf\.sap\.corp\:9091-;
	}
	my $rn_maven_metadata_url = "$base_ao_url/maven-metadata.xml";

	# get released version of tis artifact
	my $response = HTTP::Tiny->new->get($rn_maven_metadata_url);
	my @tmp;
	if ($response->{success}) {
		@tmp = split '\n' , $response->{content};
	}
	my $rn_released_version;
	foreach my $line (@tmp) {
		chomp $line;
		if($line =~ /\<release\>(.+?)\<\/release\>/) {
			$rn_released_version = $1;
			last;
		}
	}
	# fetch file infor containing rleased versions
	# http://nexus.wdf.sap.corp:8081/nexus/content/repositories/deploy.milestones/com/sap/prd/xmake/release_notes/1.0-201704117223107/release_notes-1.0-201704117223107-released_version.txt
	my $artifactID = $thisaoArtifact{artifactID};
	my $file = "${artifactID}-${rn_released_version}-released_version.txt";
	my $url_file = "$base_ao_url/$rn_released_version/$file";
	unlink "$out_gen_dir/$file" if ( -e "$out_gen_dir/$file" );
	my $ff = File::Fetch->new(uri => "$url_file");
	my $where = $ff->fetch( to => "$out_gen_dir" ) or die $ff->error;
	# get infos from downloaded file
	my %Elems;
	if( -e "$out_gen_dir/$file" ) {
		if (open TXT , "$out_gen_dir/$file") {
			while(<TXT>) {
				chomp;
				if(/^(.+?)\s+\((.+?)\)\s+\:\s+(.+?)$/) {
					my $artifactID = $2;
					$Elems{$artifactID}{title}                 = $1;
					$Elems{$artifactID}{released_version}      = $3;
				}
			}
			close TXT;
			my $newVersions = 0;
			my @released_elems;
			for my $aiElement (@$aiRef) {
				if( $aiElement->{nexus} && $aiElement->{repository} && $aiElement->{groupID} && $aiElement->{artifactID} ) {
					foreach my $artifactID_rel (keys %Elems) {
						if( ($artifactID_rel eq $aiElement->{artifactID}) && ($Elems{$artifactID_rel}{title} eq $aiElement->{title}) ) {
							( my $groupID_url  = $aiElement->{groupID} ) =~ s-\.-\/-g;
							# 1.2 calculate maven-metadata url
							my $base_ai_url = "$aiElement->{nexus}/"
										 . "$aiElement->{repository}/"
										 . "$groupID_url/"
										 . "$aiElement->{artifactID}"
										 ;
							my $meta_data_url = "$base_ai_url/maven-metadata.xml";
							my ($this_released_version,@all_versions) = sab_get_all_versions($meta_data_url);
							push @released_elems , $this_released_version unless grep /^$this_released_version$/ , @released_elems ;
							if($Elems{$artifactID_rel}{released_version} ne $this_released_version) {
								$newVersions++;
							}
							else {
								print "\nWARNING : for $Elems{$artifactID_rel}{title}, in release notes, version $Elems{$artifactID_rel}{released_version}, the latest version '$this_released_version' is still the released version,\nno new version found since last time\n";
							}
						}
					}
				}
			}
			if(($newVersions == 0) && ($nbElem <= $nbElemRel)) { # no new version detected for any element
				if($current_release_vector && !(grep /^$current_release_vector$/ , @released_elems) ) {
					sap_missed();
				}
				else {
					print "\nERROR : no new version found, nothing to do, end of $0\n";
					exit 1 unless($opt_no_check_new_version);
				}
			}
			else {
				$flag_new_version_found = 1;
			}
		}
	}
}

sub sap_update_jiras() {
	if( $released_version && ( scalar @LIST_JIRAS > 0) ) {
		my $jira_list = join ',' , sort @LIST_JIRAS;
		my $parameters = "-rv=$released_version -jl=$jira_list";
		print  "\ncall : perl update_jira.pl $parameters\n";
		system "perl -w update_jira.pl $parameters";
	}
	else {
		print "\nWARNING : no jira to update\n";
	}
}

sub sap_send_mail() {
	if( $released_version && ($flag_new_version_found == 1) ) {
		my $parameters = "-rv=$released_version";
		if ( scalar @LIST_JIRAS > 0 ) {
			my $jira_list = join ',' , sort @LIST_JIRAS;
			$parameters .= " -jl=$jira_list";
		}
		my $cmd = "perl -w mail.pl $parameters";
		print  "\ncall : perl mail.pl $parameters\n";
		system "$cmd";
	}
	else {
		print "\nWARNING : no mail to send\n\n";
	}
}

sub sap_get_current_release_vector() {
	if( $ENV{XMAKE_PROJECTDIR} ) { # if run by xmake
		my $XMAKE_PROJECTDIR = $ENV{XMAKE_PROJECTDIR} || "../";
		if( -e "$XMAKE_PROJECTDIR/.xmake/release_vector_metadata.json") {
			$File::Fetch::WARN = 0;
			my $json_text = do {
				open(my $json_fh,"<:encoding(UTF-8)","$XMAKE_PROJECTDIR/.xmake/release_vector_metadata.json")
					or confess "\n\nCan't open $XMAKE_PROJECTDIR/.xmake/release_vector_metadata.json\": $!\n\n";
				local $/;
				<$json_fh>
			};
			my $json = JSON->new;
			$from_json = $json->decode($json_text);
			$current_release_vector = $from_json->{release_vector}; # the one used inside the job
		}
	}
}

sub sap_missed() {

	# 1 check if missed already detected
	my %thisaoArtifact;
	# 1.1 get the last missed if exist
	# 1.1.1 calcul url path of rtifact missed
	for my $aoElement (@$aoRef) {
		if( $aoElement->{nexus} && $aoElement->{repository} && $aoElement->{groupID} && $aoElement->{artifactID} ) {
			$thisaoArtifact{nexus}      = $aoElement->{nexus};
			$thisaoArtifact{repository} = $aoElement->{repository};
			$thisaoArtifact{groupID}    = $aoElement->{groupID};
			$thisaoArtifact{artifactID} = "missed";
		}
	}
	( my $groupID_url  = $thisaoArtifact{groupID} ) =~ s-\.-\/-g;
	my $base_ao_url = "$thisaoArtifact{nexus}"
				. "/$thisaoArtifact{repository}"
				. "/$groupID_url"
				. "/$thisaoArtifact{artifactID}"
				;
	if( $ENV{TESTS} && ($ENV{TESTS} =~ /^yes$/) ) {
		($base_ao_url) =~ s-nexus\.wdf\.sap\.corp\:8081-nexustest\.wdf\.sap\.corp\:9091-;
	}
	my $rn_maven_metadata_url = "$base_ao_url/maven-metadata.xml";
	# 1.1.2 get metadat
	my $flag = 0;
	eval {
		my $response = HTTP::Tiny->new->get($rn_maven_metadata_url);
		if ($response->{success}) {
			my @tmp = split '\n' , $response->{content};
			my $rn_missed;
			foreach my $line (@tmp) {
				chomp $line;
				if($line =~ /\<release\>(.+?)\<\/release\>/) {
					$rn_missed = $1;
					last;
				}
			}
			# 1.2 read the content
			if($rn_missed) {
				my $artifactID = $thisaoArtifact{artifactID};
				my $file = "${artifactID}-${rn_missed}.txt";
				my $url_file = "$base_ao_url/$rn_missed/$file";
				unlink "$out_gen_dir/$file" if ( -e "$out_gen_dir/$file" );
				my $ff = File::Fetch->new(uri => "$url_file");
				my $where = $ff->fetch( to => "$out_gen_dir" );
				# 2.3 compare
				if( -e "$out_gen_dir/$file") {
					my $last_missed = `cat $out_gen_dir/$file`;
					chomp $last_missed;
					if ($last_missed && ($last_missed ne $current_release_vector) ) {
						$flag = 1;
					}
					else {
						print "ERROR : $current_release_vector (=$last_missed) already detected, no mail to send\n";
						exit 1;
					}
				}
				else {
					$flag = 1; # no file fetch, maybe never artfact 'missed' never released
				}
			}
			else { # 'missed' never released
				$flag = 1;
			}
		}
		else { # 'missed' never released
			$flag = 1;
		}
	};
	if($flag == 1) { # new issue create export
		my $artifactID = $thisaoArtifact{artifactID};
		my $file = "${artifactID}.txt";
		unlink "$out_gen_dir/$file" if ( -e "$out_gen_dir/$file" );
		# create artifact
		system "echo $current_release_vector > $out_gen_dir/$file";
		system "touch $out_gen_dir/release_notes.html";
		system "touch $out_gen_dir/release_notes.txt";
		sap_mail_missed();
	}
	else {
		print "ERROR : $current_release_vector already detected, no mail to send\n";
		exit 1;
	}
}


sub sap_mail_missed() {
	print  "\ncall : perl mail_missed.pl -rv=$current_release_vector\n";
	my $cmd       = "perl -w mail_missed.pl -rv=$current_release_vector";
	system "$cmd";
	exit 0;
}

sub sap_get_jira_title_info($) {
	my ($this_jira) = @_;
	use sap_sm_jira;
	my $title = sap_get_jira_title($this_jira);
	return $title;
}
