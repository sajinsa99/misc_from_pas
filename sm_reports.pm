package sm_reports;
##############################################################################
##############################################################################
##### declare uses
## ensure code quality
use strict;
use warnings;
use diagnostics;
use Carp qw(cluck confess); # to use instead of (warn die)

## for the script itself
use charnames ':full';
use JSON;
use Exporter;
use File::Path;
use File::stat;
use Time::Local;
use Data::Dumper;
use File::Basename;
use Store::CouchDB;
use Sort::Versions;
use Tie::Hash::Indexed;
## for jira
use JIRA::REST;
use JIRA::Client::Automated;

## custom perl modules
use sm_queries;
use sm_html;



##############################################################################
##############################################################################
##### declare vars
use vars qw (
	$output_new_jira_mail_file
	$opt_No_Mail
	$opt_MailAlert
);

# for a	lerts
use vars qw (
	$output_html_alert_file
	@column_titles_alerts
);

##### declare vars
use vars qw(
	@ISA
	@EXPORT
);



##############################################################################
##############################################################################
##### declare subs
sub sm_get_list_jira_from_json_file($);
sub sm_send_new_jiras_by_mail();
sub sm_news();
sub sm_alerts();
sub sm_alerts_report($$$$);
sub sm_alerts_mail();



##############################################################################
##############################################################################
##### export vars/functions
@ISA = qw(Exporter);
@EXPORT = qw (
	$output_new_jira_mail_file
	$opt_No_Mail
	$opt_MailAlert
	$output_html_alert_file
	@column_titles_alerts
	&sm_get_list_jira_from_json_file
	&sm_send_new_jiras_by_mail
	&sm_news
	&sm_alerts
);



##############################################################################
##############################################################################
##### functions
sub sm_get_list_jira_from_json_file($) {
	my ($this_json_file) = @_;
	my @tmp_list_jira = ();
	my $json_text = do {
		open(my $json_fh,"<:encoding(UTF-8)",$this_json_file)
			or confess "\n\nCan't open \$this_json_file\": $!\n\n";
			local $/;
			<$json_fh>
	};
	my $this_json_data = decode_json($json_text);
	foreach my $this_jira ( @{${$this_json_data}{jiras}} ) {
		push @tmp_list_jira , "$this_jira->{key}" if(defined $this_jira->{key});
	}
	return @tmp_list_jira if( scalar @tmp_list_jira > 0 ) ;
}

#news
sub sm_send_new_jiras_by_mail() {
	use Net::SMTP;
	$ENV{SMTP_SERVER} ||="mail.sap.corp";
	my $SMTPFROM   ||= $ENV{SMTPFROM}  || "bruno.fablet\@sap.com";
	#my $SMTPTO     ||= $ENV{SMTPTO}        || "bruno.fablet\@sap.com ; julian.oprea\@sap.com";
	my $SMTPTO     ||= $ENV{SMTPTO}        || "bruno.fablet\@sap.com";
	if($SMTPTO) {
		use Date::Calc qw[Add_Delta_Days Today];
		my ($this_year, $this_month, $this_day) = Today();
		#human readable
		if($this_month < 10) {
			$this_month = "0$this_month";
		}
		if($this_day < 10) {
			$this_day = "0$this_day";
		}
		my ($thisMonth) = scalar localtime =~ /^\w+\s+(.+?)\s+\d+/;
		my $smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60) or confess "ERROR: SMTP connection impossible: $!";
		$smtp->mail($SMTPFROM);
		$smtp->to(split('\s*;\s*', $SMTPTO));
		$smtp->data();
		map({$smtp->datasend("To: $_\n")} split('\s*;\s*', $SMTPTO));
		my $Subject = "Subject: [$param_project] New Jira case(s) detected today, $this_day/$this_month/$this_year - sprint : $Current_Sprint";
		$smtp->datasend("$Subject\n");
		$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=${Current_Sprint}_news.html\n");
		open HTML, "$output_new_jira_mail_file" or confess "ERROR: cannot open '$output_new_jira_mail_file': $!";
			while(<HTML>) { $smtp->datasend($_) }
		close HTML;
		$smtp->dataend();
		$smtp->quit();
		print "mail sent to $SMTPTO\n";
	}
}

sub sm_news() {
	my $json_file_today = "$OUTPUT_SM_DIR/$param_project/$param_site/status/${Current_Sprint}_news_today.json";
	my @list_jira_today;
	my @list_jira_in_sprint;
	if( -e "$json_file_today" ) {
		@list_jira_today = sm_get_list_jira_from_json_file($json_file_today);
		if( scalar @list_jira_today > 0 ) {
			my $json_file_in_sprint = "$OUTPUT_SM_DIR/$param_project/$param_site/status/${Current_Sprint}_news_in_sprint.json";
			if( -e "$json_file_in_sprint") {
				@list_jira_in_sprint = sm_get_list_jira_from_json_file($json_file_in_sprint);
			} else {
				print "WARNING : '$json_file_in_sprint' does not exist.\n";
			}
		}
	} else {
		print "WARNING : '$json_file_today' does not exist.\n";
	}
	if( scalar @list_jira_today > 0 ) {
		if(open MAIL , ">$output_new_jira_mail_file") {
			print "\nnew jira case detected, preparing mail\n";
			print MAIL '
<html xmlns:o="urn:schemas-microsoft-com:office:office"
xmlns:w="urn:schemas-microsoft-com:office:word"
xmlns:x="urn:schemas-microsoft-com:office:excel"
xmlns:m="http://schemas.microsoft.com/office/2004/12/omml"
xmlns="http://www.w3.org/TR/REC-html40">

<head>
<meta http-equiv=Content-Type content="text/html; charset=windows-1252">
<meta name=ProgId content=Word.Document>
<meta name=Generator content="Microsoft Word 12">
<meta name=Originator content="Microsoft Word 12">
<link rel=File-List href="email_files/filelist.xml">
<link rel=Edit-Time-Data href="email_files/editdata.mso">

<body lang=FR link=blue vlink=purple style=\'tab-interval:35.4pt\'>
';
			print MAIL "
Hi,<br/><br/>
Please find jira case(s) created since the beginning of the sprint $Current_Sprint ($Current_Sprint_begin) :<br/><br/>
<table class=\"sortable\" id=\"jiraTable_news\"rules=\"all\" style=\"border:1px solid black;\" cellpadding=\"10\">
";
			print MAIL "
	<tr>
		<th class=\"startsort\">Jira</th>
		<th>Summary</th>
		<th>Priority</th>
		<th>Version</th>
		<th>Story Point</th>
		<th>Epic Link</th>
		<th>Sprint</th>
		<th>Reporter</th>
		<th>Created</th>
		<th>Type</th>
		<th>Assignee</th>
		<th>Status</th>
	</tr>
";
			my $nb_new_jira = 0;
			my $nb_new_jira_today = 0;
			# wget optim
			sm_wget_all_jira(\@list_jira_in_sprint,"list_jira_in_sprint");
			print "\n" if($opt_debug);
			foreach my $this_issue (@list_jira_in_sprint) {
				my $this_json_file = "$OUTPUT_SM_DIR/$param_project/$param_site/issues/$this_issue";
				print "$this_issue - $this_json_file\n" if($opt_debug);
				if( ! -e "$this_json_file" ) {
					sm_wget_json_jira($this_issue);
				} else { # if exist but with size 0
					my $file_size = stat("$this_json_file")->size;
					if($file_size == 0) {
						sm_wget_json_jira($this_issue);
					}
				}
				my $THIS_JIRA;
				sm_load_json_file("$this_json_file",\$THIS_JIRA);
				next if($THIS_JIRA->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
				next if($THIS_JIRA->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i);
				print "$this_issue\n" if($opt_debug);
				$nb_new_jira++;
				my ($id) = $THIS_JIRA->{key} =~ /$param_project\-(\d+)$/i;
				my $displayCreated = $THIS_JIRA->{'fields'}->{'created'};
				($displayCreated) =~ s-T- -;
				($displayCreated) =~ s-\..+?$--;
				if($displayCreated =~ /${Local_Year}-${display_Local_Month}-$display_Local_Day/) {
					print MAIL '    <tr bgcolor="#DFF2FF">';
					$nb_new_jira_today++;
				} else {
					print MAIL "    <tr>";
				}
				# Jira key
				binmode(MAIL, ":utf8");
				print MAIL "<td><a href=\"$jira_Url/browse/$THIS_JIRA->{key}\" target=\"_BLANK\">$THIS_JIRA->{key}</a></td>";
				# summary
				print MAIL "<td>$THIS_JIRA->{'fields'}->{'summary'}</td>";
				# priority
				print MAIL "<td>$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</td>";
				# version
				my $fixVersions;
				foreach my $fixVersion (@{$THIS_JIRA->{'fields'}->{'fixVersions'}}) {
					$fixVersions .= "$fixVersion->{'name'} , ";
				}
				if($fixVersions) {
					($fixVersions) =~ s-\s+$--;
					($fixVersions) =~ s-\,$--;
					($fixVersions) =~ s-\s+$--;
					print MAIL "<td>$fixVersions</td>";
				} else {
					print MAIL "<td><font color=\"red\">no Version</font></td>";
				}
				# story point
				my $story_points = ($THIS_JIRA->{'fields'}->{'customfield_10013'}) ? $THIS_JIRA->{'fields'}->{'customfield_10013'} : 0 ;
				print MAIL "<td>$story_points</td>";
				# epic link
				my $epicLink;
				my $skipThatEpic = 0;
				my $epicLinkTitle = ($THIS_JIRA->{'fields'}->{'customfield_15140'})  ? sm_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "" ;
				if($epicLinkTitle =~ /^\s+$/i) { # search in parent if parent
					$epicLinkTitle = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   ? sm_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   : "" ;
				}
				if( ! defined $epicLinkTitle ) {
					print MAIL "<td>&nbsp;</td>";
				} else {
					if( defined $THIS_JIRA->{'fields'}->{'customfield_15140'} ) {
						print MAIL "<td><a href=\"$jira_Url/browse/$THIS_JIRA->{'fields'}->{'customfield_15140'}\" target=\"_BLANK\">$epicLinkTitle</a></td>";
					} else {
						print MAIL "<td>&nbsp;</td>";
					}
				}
				# sprint
				if($THIS_JIRA->{'fields'}->{'customfield_12740'}->[0]) {
					my ($sprint) = $THIS_JIRA->{'fields'}->{'customfield_12740'}->[0] =~ /\,name\=(.+?)\,/ ;
					print MAIL "<td>$sprint</td>";
				} else {
					print MAIL "<td>&nbsp;</td>";
				}
				# reporter
				print MAIL "<td>$THIS_JIRA->{'fields'}->{'reporter'}->{'displayName'}</td>";
				# created date
				print MAIL "<td>$displayCreated</td>";
				# type
				print MAIL "<td>$THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}</td>";
				# assignee
				my $assignee = ( $THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'} ) ?  $THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'} :"Unassigned" ;
				print MAIL "<td>$assignee</td>";
				print MAIL "<td>$THIS_JIRA->{'fields'}->{'status'}->{'name'}</td>";
				print MAIL "</tr>\n";
			}
			print MAIL "</table><br/>\n";
			print MAIL "nb jira case(s) created today : $nb_new_jira_today<br/>\n";
			print MAIL "nb jira case(s) created since the beginning of $Current_Sprint : $nb_new_jira<br/>\n";
			print MAIL '
<br/>
<br/>
Best Regards,<br/>
Bruno<br/>
<br/>
note:<br/>
The item(s) in blue high-lighted above in the table, is/are the newest jira case(s) created.<br/>
</body>
</html>
';
			close MAIL;
		}
		print "mail created, see $output_new_jira_mail_file\n";
		sm_send_new_jiras_by_mail() unless($opt_No_Mail);
	} else {
		my $this_date = $display_Local_Day . "/" . $display_Local_Month . "/" . $Local_Year;
		print "no new jira created on $this_date\n\n";
	}
}

#alerts
sub sm_alerts() {
	print "start sm_alerts : $output_html_alert_file\n" if($opt_debug);
	sm_begin_html($output_html_alert_file,"Alerts");

	### no assigned
	sm_alerts_report("Assignee","alerts_no_assignee","No Assignee","no_assignee");

	### no worklog
	sm_alerts_report("Worklog","alerts_no_worklog","No Worklog","no_worklog");

	### no fix version
	sm_alerts_report("fixVersion","alerts_no_fixVersion","No Fix Version","no_fv");

	### no epic link attached
	sm_alerts_report("Epic","alerts_no_epic","No Epic","no_epic");

	# no story points
	sm_alerts_report("StoryPoints","alerts_no_storypoints","No Story Points","no_sp");
	#my $url_Alert = "http://$url_report:$port_report/Reports/$param_project/alerts.html";
	#print "\ndone, see $output_html_alert_file\nalso in : $url_Alert\n";

	sm_alerts_mail();
	print "end sm_alerts\n" if($opt_debug);
}

sub sm_alerts_report($$$$) {
	my ($suffix_json_file,$id1,$prefix_title,$id2) = @_ ;
	my $json_file = "$OUTPUT_SM_DIR/$param_project/$param_site/status/${Current_Sprint}_alerts_no_$suffix_json_file";
	if($param_member) {
		$json_file .= "_$param_member";
	}
	$json_file .= ".json";
	print "sm_alerts_report : $suffix_json_file,$id1,$prefix_title,$id2 => $json_file\n" if($opt_debug);
	my @list_jira = ();
	if( -e "$json_file" ) {
		@list_jira = sm_get_list_jira_from_json_file($json_file);
		if( scalar @list_jira > 0 ) {
			my $nb_issues = scalar @list_jira;
			sm_wget_all_jira(\@list_jira,"alerts_$id2");
			if( ($id2 ne "no_ts") && ($id2 ne "no_sp") ) {
				sm_start_html_table($output_html_alert_file,$id1,$Current_Sprint,"$prefix_title ($nb_issues Jira(s)&nbsp;)",@column_titles_alerts);
			}
			sm_print_reports($output_html_alert_file,$id2,\@list_jira);
		}
	}
}

sub sm_alerts_mail() {
	my $mailDir = "$OUTPUT_SM_DIR/$param_project/$param_site/mails";
	if ( ! -e "$mailDir" ) {
		mkpath "$mailDir";
	}
	my %iNumberToAlert;
	my @markersINumbers  = qw(Worklog fixVersion Epic StoryPoints);
	foreach my $marker (@markersINumbers) {
		my $json_file = "$OUTPUT_SM_DIR/$param_project/$param_site/status/${Current_Sprint}_alerts_no_$marker" ;
		if($param_member) {
			$json_file .= "_$param_member";
		}
		$json_file .= ".json";
		if( -e "$json_file" ) {
			my @list_jira = sm_get_list_jira_from_json_file($json_file);
			if( scalar @list_jira > 0 ) {
				my $nb_issues = scalar @list_jira;
				#sm_wget_all_jira(\@list_jira,"alerts_$id2");
				foreach my $this_issue (sort @list_jira) {
					my $this_json_file = "$OUTPUT_SM_DIR/$param_project/$param_site/issues/$this_issue";
					my $THIS_JIRA;
					sm_load_json_file("$this_json_file",\$THIS_JIRA);
					my $assigneeKey = ( $THIS_JIRA->{'fields'}->{'assignee'}->{'key'} ) ?  $THIS_JIRA->{'fields'}->{'assignee'}->{'key'} :"Unassigned" ;
					if($assigneeKey =~ /^Unassigned$/i) {
						$iNumberToAlert{$assigneeKey}{email}       = 'bruno.fablet@sap.com' ;
						$iNumberToAlert{$assigneeKey}{firstName}   = "Bruno" ;
					}  else  {
						$iNumberToAlert{$assigneeKey}{email}       = ( $THIS_JIRA->{'fields'}->{'assignee'}->{'emailAddress'} ) ?  $THIS_JIRA->{'fields'}->{'assignee'}->{'emailAddress'} : 'bruno.fablet@sap.com' ;
						($iNumberToAlert{$assigneeKey}{firstName}) = $THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'}      =~ /\,\s+(.+?)$/i ;
					}
					push @{${$iNumberToAlert{$assigneeKey}{$marker}}} , $this_issue ;
				}
			}
		}
	}
	my $found_iNumber = 0;
	foreach my $iNumber (sort keys %iNumberToAlert) {
		next if($param_member && $param_member !~ /^$iNumber$/i);
		print "$iNumber\n";
		$found_iNumber++;
		my $mailFile = "$mailDir/alert_mail_$iNumber.html";
		if( -e "$mailFile") {
			system "rm -f \"$mailFile\"";
		}
		open HTML, ">$mailFile" or die "ERROR: cannot create '$mailFile': $!";
		print HTML "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n";
		print HTML "<html>\n";
		print HTML "<body><br/>\n";		
		print HTML "Hi $iNumberToAlert{$iNumber}{firstName},<br/><br/>\n";
		print HTML "The scrum scripts detected that some information are missing.<br/><br/>\n";
		foreach my $marker (sort keys %{$iNumberToAlert{$iNumber}}) {
			next if($marker =~ /^email$/i);
			next if($marker =~ /^firstName$/i);
			print "\tno $marker\n";
			my $nb_jiras = scalar @{${$iNumberToAlert{$iNumber}{$marker}}} ;
			print HTML "
<fieldset style=\"border-style:solid;border-color:black;border-size:1px\"><legend>No $marker ($nb_jiras Jira(s)&nbsp;)</legend>
<div id=\"alerts_no_$marker\" style=\"display:block\">
<br/>
<table class=\"sortable\" id=\"table_alerts_no_$marker\" rules=\"all\" style=\"border:1px solid black; margin-left:100px;\" cellpadding=\"6\">
<tr><th class=\"startsort\">Jira ID</th><th>Status</th><th>Fix Version(s)</th><th>Priority</th><th>Type</th><th>Epic Link</th><th>Component(s)</th><th>Summary</th><th>Assignee</th><th>Created</th><th>Reporter</th><th>WorkLog</th><th>Story Points</th></tr>";
			foreach my $this_issue (sort @{${$iNumberToAlert{$iNumber}{$marker}}} ) {
				print "\t\t$this_issue\n";
				my $this_json_file = "$OUTPUT_SM_DIR/$param_project/$param_site/issues/$this_issue";
				my $THIS_JIRA;
				sm_load_json_file("$this_json_file",\$THIS_JIRA);
				print HTML "\t<tr>";
				print HTML "<td><a href=\"$jira_Url/browse/$THIS_JIRA->{key}\">$THIS_JIRA->{key}</a></td>";
				print HTML "<td>$THIS_JIRA->{'fields'}->{'status'}->{'name'}</td>";
				my $fixVersions;
				foreach my $fixVersion (@{$THIS_JIRA->{'fields'}->{'fixVersions'}}) {
					$fixVersions .= "$fixVersion->{'name'} ";
				}
				$fixVersions = ($fixVersions) ? $fixVersions : "none";
				($fixVersions) =~ s-\s+$--;
				print HTML "<td>$fixVersions</td>";
				if($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^Blocker$/i) {
					print HTML "<td><font color=\"red\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
				}
				elsif ($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^critical$/i){
					print HTML "<td><font color=\"#A52A2A\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
				}
				elsif ($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^major$/i){
					print HTML "<td><font color=\"#FFA500\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
				}
				else {
					print HTML "<td>$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</td>";
				}
				print HTML "<td>$THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}</td>";
				my $epicLinkTitle = ($THIS_JIRA->{'fields'}->{'customfield_15140'}) ? sm_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "na" ;
				if($epicLinkTitle eq "na") { # search in parent if parent
					$epicLinkTitle = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   ? sm_get_parent_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) : "na" ;
				}
				print HTML "<td>$epicLinkTitle</td>";
				print HTML "<td>";
				foreach my $component (@{$THIS_JIRA->{'fields'}->{'components'}}) {
					print HTML "$component->{'name'} ";
				}
				print HTML "</td>";
				print HTML "<td>$THIS_JIRA->{'fields'}->{'summary'}</td>";
				my $assigne  = ($THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'})  ? $THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'} : "<font color=\"red\">Unassigned</font>";
				unless($assigne eq "no_assignee") {
					print HTML "<td>$assigne</td>";
				}
				else {
					print HTML "<td><font color=\"red\">Unassigned</font></td>";
				}
				my $displayCreated = $THIS_JIRA->{'fields'}->{'created'};
				($displayCreated) =~ s-T- -;
				($displayCreated) =~ s-\..+?$--;
				print HTML "<td>$displayCreated</td>";
				print HTML "<td>$THIS_JIRA->{'fields'}->{'reporter'}->{'displayName'}</td>";
				my $totalTs = $THIS_JIRA->{'fields'}->{'timespent'};
				my $displayTimeSpent = ($totalTs  && ($totalTs>0)) ? sm_seconds_to_hms($totalTs) : "<font color=\"red\">0</font>";
				print HTML "<td>$displayTimeSpent</td>";
				my $story_points = ($THIS_JIRA->{'fields'}->{'customfield_10013'}) ? $THIS_JIRA->{'fields'}->{'customfield_10013'} : "<font color=\"red\">0</font>" ;
				print HTML "<td>$story_points</td>";

				print HTML "</tr>\n";
				print HTML "</table><br/>\n";
			}
			print HTML "<br/></div></fieldset><br/>\n";
		}
		print HTML "\n<br/><br/>Please fill the empty field(s).<br/>\n";
		print HTML "If you really don't need to log time, or no need any story point, for any reason, please add as comment (copy-paste) :<br/>";
		print HTML "no need to log work<br/>\n";
		print HTML "no story point needed<br/>\n";
		print HTML "<br/><br/>Best Regards,<br/>\n";
		print HTML "</body>\n</html>\n";
		close HTML;
		if($opt_MailAlert) {
			#$iNumberToAlert{$assigneeKey}{email}
			my $SMTP_SERVER     = $ENV{SM_SMTP_SERVER}             || "mail.sap.corp";
			my $SCRIPT_SMTPTO   = $iNumberToAlert{$iNumber}{email} || 'bruno.fablet@sap.com';
			$SCRIPT_SMTPTO      = 'bruno.fablet@sap.com' if($opt_debug);
			my $SCRIPT_SMTPFROM = 'bruno.fablet@sap.com';
			my $SCRIPT_SMTPCC   = 'bruno.fablet@sap.com ; julian.oprea@sap.com';
			my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>60) or die "ERROR : SMTP connection impossible : $!";
			print "sending mail for $SCRIPT_SMTPTO\n";
			$smtp->mail($SCRIPT_SMTPFROM);
			$smtp->to(split('\s*;\s*', $SCRIPT_SMTPTO));
			$smtp->cc(split('\s*;\s*', $SCRIPT_SMTPCC)) unless($opt_debug);
			$smtp->data();
			$smtp->datasend("To: $SCRIPT_SMTPTO\n");
			$smtp->datasend("Cc: $SCRIPT_SMTPCC\n") unless($opt_debug);
			my($Script) = $0 =~ /([^\/\\]+)$/;
			$smtp->datasend("Subject: [DTXMAKE] [SCRUM] action required for $iNumberToAlert{$iNumber}{firstName}\n");
			$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
			open HTML, "$mailFile"  or warn "WARNING : cannot open '$mailFile' : $!";
			while(<HTML>) { $smtp->datasend($_) } 
			close(HTML);
			$smtp->dataend();
			$smtp->quit();
		}
		system "rm -f \"$mailFile\" >& /dev/null || true";
	}
	if($found_iNumber == 0) {
		if($param_member) {
			print "\nCongratulations, no alert found for $param_member.\n\n";
		}  else  {
			print "\nCongratulations, no alert found for the team.\n\n";
		}
		
	}
}

##############################################################################
##############################################################################
##############################################################################
1;
