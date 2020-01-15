package sm_html;
##############################################################################
##############################################################################
##### declare uses
use strict;
use warnings;
use diagnostics;
use Carp qw(cluck confess); # to use instead of (warn die)

## custom perl modules
use sm_queries;

##############################################################################
##############################################################################
##### declare vars
use vars qw(
	@ISA
	@EXPORT
);



##############################################################################
##############################################################################
##### declare subs

sub sm_begin_html($$);
sub sm_start_html_table($$$$@);
sub sm_close_html_table($);
sub sm_close_html_section($);
sub sm_print_reports($$$);
sub sm_seconds_to_hms($);



##############################################################################
##############################################################################
##### export vars/functions
@ISA = qw(Exporter);
@EXPORT = qw (
	&sm_begin_html
	&sm_start_html_table
	&sm_close_html_table
	&sm_close_html_section
	&sm_print_reports
	&sm_seconds_to_hms
);

##############################################################################
##############################################################################
##### functions
sub sm_begin_html($$) {
	my ($file,$title) = @_;
	system "rm -f $file" if( -e "$file");
	if(open REPORT_HTML,">$file") {
		print "\ncreate $file\n";
		print REPORT_HTML '<!DOCTYPE HTML>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<title>',$title,'</title>
	<meta http-equiv="content-type" content="text/html; charset=UTF-8" />
	<link rel="icon" type="image/png" href="./images/SAP_icon.png" />
	<!--[if IE]><link rel="shortcut icon" type="image/x-icon" href="./images/SAP_icon.png"/><![endif]-->
	<link rel="stylesheet" type="text/css" href="./js/sortable/sortable.css"/>
	<script type="text/javascript" src="./js/jquery-1.11.0.min.js"></script>
	<script type="text/javascript" src="./js/highcharts.js"></script>
	<script type="text/javascript" src="./js/modules/data.js"></script>
	<script type="text/javascript" src="./js/modules/drilldown.js"></script>
	<script type="text/javascript" src="./js/modules/exporting.js"></script>
	<script type="text/javascript" src="./js/sortable/sortable.js"></script>
</head>
<body>
<br/>
<h1 align="center">',$title,'</h1>
<h3 align="center">',$display_Local_Day,'/',$display_Local_Month,'/',$Local_Year,'</h3>

<center>
	<h3><a name="TaktTransparency-CurrentTaktCountdown"></a>Current Takt (<font color="blue">'.$Current_Sprint.'</font>) Countdown</h3>
	<br/>
</center>
<br/>

<!-- start report -->
';
	close REPORT_HTML;
	}
}
sub sm_start_html_table($$$$@) {
	my ($file,$type,$sprint,$legend,@columnTitles) = @_;
	if(open REPORT_HTML,">>$file") {
		my $divID = "${type}_sprint_$sprint";
		print REPORT_HTML '
<fieldset style="border-style:solid;border-color:black;border-size:1px"><legend onclick="document.getElementById(\''.$divID.'\').style.display = (document.getElementById(\''.$divID.'\').style.display==\'none\') ? \'block\' : \'none\';" onmouseover="this.style.cursor=\'pointer\'" onmouseout="this.style.cursor=\'auto\'">'.$legend.'</legend>
<div id="'.$divID.'" style="display:none">
<br/>
<br/><table class="sortable" id="table_'.$divID.'" rules="all" style="border:1px solid black; margin-left:100px;" cellpadding="6">
		';
		print REPORT_HTML "\t<tr>";
		my $first_line = 0;
		foreach my $title (@columnTitles) {
			$first_line++;
			if($first_line == 1) {
				if($title =~ /update/i) {
					print REPORT_HTML "<th  class=\"unsortable\">$title</th>";
					$first_line = 0;
				} else {
				print REPORT_HTML "<th class=\"startsort\">$title</th>";
				}
			} else {
				print REPORT_HTML "<th>$title</th>";
			}
		}
		print REPORT_HTML "</tr>\n";
		close REPORT_HTML;
	}
}

sub sm_close_html_table($) {
	my ($file) = @_;
	if(open REPORT_HTML,">>$file") {
		print REPORT_HTML "</table><br/>\n";
		close REPORT_HTML;
	}
}

sub sm_close_html_section($) {
	my ($file) = @_;
	if(open REPORT_HTML,">>$file") {
		print REPORT_HTML "</div></fieldset><br/>\n";
		close REPORT_HTML;
	}
}

sub sm_print_reports($$$) {
	my ($file,$missing_elem,$results) = @_ ;
	my @skipJira = ();
	if( ($missing_elem eq "no_ts") || ($missing_elem eq "no_sp") ) {
		my $nb_jira = 0;
		foreach my $full_jira (sort @$results) {
			my $this_json_file = "$OUTPUT_SM_DIR/$param_project/$param_site/issues/$full_jira";
			my $THIS_JIRA;
			sm_load_json_file($this_json_file,\$THIS_JIRA);
			my $skip_jira = 0 ;
			foreach my $comment (@{$THIS_JIRA->{'fields'}->{'comment'}->{'comments'}}) {
				if($comment->{'body'} =~ /no\s+need\s+to\s+log\s+work/i) {
					$skip_jira = 1 ;
					push @skipJira , $THIS_JIRA->{key} ;
					last;
				}
				if($comment->{'body'} =~ /no\s+story\s+point\s+needed/i) {
					$skip_jira = 1 ;
					push @skipJira , $THIS_JIRA->{key} ;
					last;
				}
			}
			next if ($skip_jira == 1);
			$nb_jira++;
		}
		my @columnTitles = ("Jira ID" , "Status", "Fix Version(s)" , "Priority" , "Type" , "Epic Link" , "Component(s)" , "Summary" , "Assignee" , "Created" , "Reporter" , "WorkLog" , "Story Points");
		my $legend    = "";
		my $id_table  = "";
		if($missing_elem eq "no_ts") {
			$legend   = "No Time Spent Logged";
			$id_table = "alerts_notTS";
		}
		if($missing_elem eq "no_sp") {
			$legend   = "No Story Points";
			$id_table = "alerts_notSP";
		}
		sm_start_html_table($file,$id_table,$Current_Sprint,"$legend ($nb_jira Jira(s)&nbsp;)",@columnTitles);
	}
	if(open REPORT_HTML,">>$file") {
		foreach my $full_jira (sort @$results) {
			next if ( grep /^$full_jira$/ , @skipJira );
			my $this_json_file = "$OUTPUT_SM_DIR/$param_project/$param_site/issues/$full_jira";
			my $THIS_JIRA;
			sm_load_json_file($this_json_file,\$THIS_JIRA);
			print REPORT_HTML "\t<tr>";
			print REPORT_HTML "<td><a href=\"$jira_Url/browse/$THIS_JIRA->{key}\">$THIS_JIRA->{key}</a></td>";
			print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'status'}->{'name'}</td>";
			my $fixVersions;
			foreach my $fixVersion (@{$THIS_JIRA->{'fields'}->{'fixVersions'}}) {
				$fixVersions .= "$fixVersion->{'name'} ";
			}
			$fixVersions = ($fixVersions) ? $fixVersions : "none";
			($fixVersions) =~ s-\s+$--;
			print REPORT_HTML "<td>$fixVersions</td>";
			if($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^Blocker$/i) {
				print REPORT_HTML "<td><font color=\"red\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
			}
			elsif ($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^critical$/i){
				print REPORT_HTML "<td><font color=\"#A52A2A\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
			}
			elsif ($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^major$/i){
				print REPORT_HTML "<td><font color=\"#FFA500\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
			}
			else {
				print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</td>";
			}
			print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}</td>";
			my $epicLinkTitle = ($THIS_JIRA->{'fields'}->{'customfield_15140'}) ? sm_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "na" ;
			if($epicLinkTitle eq "na") { # search in parent if parent
				$epicLinkTitle = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   ? sm_get_parent_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) : "na" ;
			}
			print REPORT_HTML "<td>$epicLinkTitle</td>";
			print REPORT_HTML "<td>";
			foreach my $component (@{$THIS_JIRA->{'fields'}->{'components'}}) {
				print REPORT_HTML "$component->{'name'} ";
			}
			print REPORT_HTML "</td>";
			print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'summary'}</td>";
			my $assigne = ($THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'}) ? $THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'} : "<font color=\"red\">Unassigned</font>";
			unless($assigne eq "no_assignee") {
				print REPORT_HTML "<td>$assigne</td>";
			}
			else {
				print REPORT_HTML "<td><font color=\"red\">Unassigned</font></td>";
			}
			my $displayCreated = $THIS_JIRA->{'fields'}->{'created'};
			($displayCreated) =~ s-T- -;
			($displayCreated) =~ s-\..+?$--;
			print REPORT_HTML "<td>$displayCreated</td>";
			print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'reporter'}->{'displayName'}</td>";
			my $totalTs = $THIS_JIRA->{'fields'}->{'timespent'};
			my $displayTimeSpent = ($totalTs  && ($totalTs>0)) ? sm_seconds_to_hms($totalTs) : "<font color=\"red\">0</font>";
			print REPORT_HTML "<td>$displayTimeSpent</td>";
			my $story_points = ($THIS_JIRA->{'fields'}->{'customfield_10013'}) ? $THIS_JIRA->{'fields'}->{'customfield_10013'} : "<font color=\"red\">0</font>" ;
			print REPORT_HTML "<td>$story_points</td>";
			
			print REPORT_HTML "</tr>\n";
		}
		sm_close_html_table($file);
		if(open REPORT_HTML,">>$file") {
			print REPORT_HTML "</div>\n";
			close REPORT_HTML;
		}
		sm_close_html_section($file);
	}
}

sub sm_seconds_to_hms($) {
    my ($totalsecondes) = @_;
    my $secondes = $totalsecondes % 60;
    my $minutes  = ($totalsecondes / 60) % 60;
    my $heures   = ($totalsecondes / (60 * 60));
    return sprintf "%02d:%02d:%02d",($heures, $minutes, $secondes);
}

##############################################################################
##############################################################################
##############################################################################
1;
