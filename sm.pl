#!/softs/perl/latest/bin/perl

##############################################################################
##############################################################################
##### declare uses
# for clean perl
#use strict;
use warnings;
use diagnostics;
use Carp qw(cluck confess); # to use instead of (warn die)

use Data::Dumper;

use charnames ':full';

use File::stat;
use File::Path;
use File::Copy;
use Tie::Hash::Indexed;

# opt/parameters
use Getopt::Long;

# web
#use CGI 'param';
#use CGI qw(:standard);
#use JSON;

use Date::Calc(qw(Delta_DHMS));

# my uses
use sm;
use sm_graphs;



##############################################################################
##############################################################################
##### declare vars

use vars qw (
	$list_iNumbers
	$Warnings
	$url_report
	$port_report
	$currentDate
);

# for mail
use vars qw (
	$SMTPFROM
	$SMTPTO
);

# for options:parameters
use vars qw (
	$param_jkey
	$param_jvalue
	$opt_Force
);



##############################################################################
##############################################################################
##### declare subs
sub sap_sm_date_to_seconds($$);
sub sap_sm_seconds_to_hms($);
sub sap_sm_seconds_to_decimalhour($);
sub sap_sm_seconds_to_hours($);

#html
sub sap_sm_begin_html($$);
sub sap_sm_close_html($);
sub sap_sm_start_html_table($$$$@);
sub sap_sm_start_RTS_html_table($$$$$@);
sub sap_sm_start_RTS_html_table2($$$$$@);
sub sap_sm_close_html_table($);
sub sap_sm_write_stats_in_html($$);
sub sap_sm_close_html_section($);

#others
sub sap_sm_send_new_jiras_by_mail();
sub sap_sm_print_reports($$$);
sub sap_get_title_of_epicLink($);
sub sap_get_parent_title_of_epicLink($);
sub sap_is_bisextil($);



##############################################################################
##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
	"closed"    =>\$opt_Closed,
	"rts"       =>\$opt_RTS,
	"cs"        =>\$opt_CurrentSprint,
	"ws"        =>\$opt_WholeStatus,
	"nomail"    =>\$opt_No_mail,
	"epics"     =>\$opt_Epics,
	"takt=s"    =>\$param_Takt,
	"sp=s"      =>\$param_Takt,
	"tf=s"      =>\$param_TaktFrom,
	"spf=s"     =>\$param_TaktFrom,
	"tt=s"      =>\$param_TaktTo,
	"spt=s"     =>\$param_TaktTo,
	"warn"      =>\$Warnings,
	"refresh"   =>\$opt_RefreshData,
	"dl=s"      =>\$SMTPTO,
	"inumber=s" =>\$opt_JiraUser,
	"fl"        =>\$opt_ForceLogin,
	"prj=s"     =>\$param_JIRA_PRJ,
	"jira=s"    =>\$param_This_Jira,
	"key=s"     =>\$param_jkey,
	"value=s"   =>\$param_jvalue,
	"watchers"  =>\$opt_Watchers,
	"FORCE"     =>\$opt_Force,
);



##############################################################################
##############################################################################
##### inits

$currentTakt = ($param_Takt) ? $param_Takt : (keys %CurrentTakt)[0];
$list_iNumbers = join ',',keys %JiraINumbers;

$param_Takt     ||= $currentTakt ;
$param_TaktFrom ||= $currentTakt ;
$param_TaktTo   ||= $currentTakt ;
$param_JIRA_PRJ ||= "DTXMAKE"    ;


mkpath "$OUTPUTS_LOGS/$param_JIRA_PRJ"    unless( -e "$OUTPUTS_LOGS/$param_JIRA_PRJ"    );
mkpath "$OUTPUTS_JIRAS/$param_JIRA_PRJ"   unless( -e "$OUTPUTS_JIRAS/$param_JIRA_PRJ"   );
mkpath "$OUTPUTS_STO/$param_JIRA_PRJ"     unless( -e "$OUTPUTS_STO/$param_JIRA_PRJ"     );
mkpath "$OUTPUTS_CS/$param_JIRA_PRJ"      unless( -e "$OUTPUTS_CS/$param_JIRA_PRJ"      );
mkpath "$OUTPUTS_REPORTS/$param_JIRA_PRJ" unless( -e "$OUTPUTS_REPORTS/$param_JIRA_PRJ" );
mkpath "$OUTPUTS_NOTES/$param_JIRA_PRJ"   unless( -e "$OUTPUTS_NOTES/$param_JIRA_PRJ"   );

$url_report  = $ENV{SM_HTTP_SERVER} || "mo-60192cfe2.mo.sap.corp";
$port_report = $ENV{SM_HTTP_PORT}   || "8888";




##############################################################################
##############################################################################
##### MAIN

open STDERR,"> /dev/null" unless($Warnings);
#print header('application/json');

$currentDate  = $Local_Year.'-'.$display_Local_Month.'-'.$display_Local_Day;
if($param_This_Jira) {
	my @list_jiras;
	if( -e "$param_This_Jira") {
		if(open JIRA_LIST_FILE ,"$param_This_Jira") {
			while(<JIRA_LIST_FILE>) {
				chomp;
				my $line = $_ ;
				push @list_jiras , $line unless grep /^$line$/ , @list_jiras;
			}
			close JIRA_LIST_FILE;
		}
	}  else  {
		@list_jiras = split ',' , $param_This_Jira;
	}
	sap_sm_jira_wget_login();
	foreach my $jira (sort @list_jiras) {
		my $THIS_JIRA;
		if($opt_RefreshData) {
			system "rm -f $OUTPUTS_JIRAS/$param_JIRA_PRJ/$jira";
		}
		if( -e "$OUTPUTS_JIRAS/$param_JIRA_PRJ/$jira") {
			sap_sm_read_json_jira($jira,$param_JIRA_PRJ,\$THIS_JIRA) ;
		}  else  {
			sap_sm_wget_json_jira($jira,$param_JIRA_PRJ,\$THIS_JIRA);
		}
		if($param_jkey) {
			if($param_jkey eq "epic") {
				my $this_epic;
				if($THIS_JIRA->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i) {
					if($THIS_JIRA->{'fields'}->{'summary'} !~ /legacy/i) {
						$this_epic = "xMake Support" ;
					}  else  {
						$this_epic = "Legacy" ;
					}
				}  else  {
					$this_epic = ($THIS_JIRA->{'fields'}->{'customfield_15140'}) ? sap_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "na" ;
				}
				if($this_epic eq "na") { # search in parent if parent
					$this_epic = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   ? sap_get_parent_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) : "na" ;
				}
				if($param_jvalue) {
					if ($this_epic =~ /^$param_jvalue$/i) {
						print "$jira - epic : $this_epic\n";
					}
				}  else  {
					print "$jira - epic : $this_epic\n";
				}
			}
			if($param_jkey eq "status") {
				if($THIS_JIRA->{'fields'}->{'status'}->{'name'}) {
					if($param_jvalue) {
						if ($THIS_JIRA->{'fields'}->{'status'}->{'name'} =~ /^$param_jvalue$/i) {
							print "$jira - status : $THIS_JIRA->{'fields'}->{'status'}->{'name'}\n";
						}
					}  else  {
						print "$jira - status : $THIS_JIRA->{'fields'}->{'status'}->{'name'}\n";
					}
				}
			}
			if($param_jkey eq "type") {
				if($THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}) {
					if($param_jvalue) {
						if ($THIS_JIRA->{'fields'}->{'issuetype'}->{'name'} =~ /^$param_jvalue$/i) {
							print "$jira - type : $THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}\n";
						}
					}  else  {
						print "$jira - type : $THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}\n";
					}
				}
			}
			if($param_jkey eq "assignee") {
				#assignee
				my $assignee = ($THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'}) ? $THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'} : "Unassigned";
				print "$jira - assignee : $assignee\n";
			}
			if($param_jkey eq "sp") {
				my $story_points = ($THIS_JIRA->{'fields'}->{'customfield_10013'}) ? $THIS_JIRA->{'fields'}->{'customfield_10013'} : 0 ;
				print "$jira - story points : $story_points\n";
			}
		}  else  {
			if ( -e "$OUTPUTS_JIRAS/$param_JIRA_PRJ/$jira") {
				print "$jira\n";
					print "cat $OUTPUTS_JIRAS/$param_JIRA_PRJ/$jira\n\n";
					system "cat $OUTPUTS_JIRAS/$param_JIRA_PRJ/$jira";
				print "\n";
			}
		}
		undef $THIS_JIRA;
	}
	print "\n";
	exit 0;
}

if($opt_RefreshData) {
	exit if($param_This_Jira);
	my $start = 0;
	my $takt_From_this_date;
	foreach my $thisTakt (keys %Takts) {
		$start = 1 if($param_TaktTo eq $thisTakt);
		if($start == 1) {
			$takt_From_this_date = $Takts{$thisTakt}{begin};
		}
		$start = 0 if($param_TaktFrom eq $thisTakt);
	}
	my $request = 'project = '.$param_JIRA_PRJ.' AND assignee in ('.$list_iNumbers
				.',EMPTY) AND ( resolutiondate >= '.$takt_From_this_date
				.' OR updatedDate >= '.$takt_From_this_date
				.' ) AND status not in (Open, "To Do") ORDER BY key DESC'
				;
	print "jql : $request\n" if($Warnings);
	my @results = sap_sm_jql($request);
	foreach my $issue (@results) {
		next if($issue->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
		push @all_jira_to_download , $issue->{key} unless grep /^$issue->{key}$/ , @all_jira_to_download;
	}
	if(open ALL_JIRA , ">$OUTPUTS_JIRAS/$param_JIRA_PRJ/all.txt") {
		foreach my $jira (@all_jira_to_download) {
			print ALL_JIRA "$jira_Url/rest/api/latest/issue/$jira\n";
		}
		close ALL_JIRA;
		system "cd $OUTPUTS_JIRAS/$param_JIRA_PRJ/ ; rm -f @all_jira_to_download";
		sap_sm_wget_multiples_json_jira($param_JIRA_PRJ,"$OUTPUTS_JIRAS/$param_JIRA_PRJ/all.txt");
	}
	exit 0;

}
# closed option,
if($opt_Closed) {
    my $start = 0;
    my $htmlFile = "$OUTPUTS_REPORTS/$param_JIRA_PRJ/closed";
    $htmlFile   .= "_$param_Takt"   if($param_Takt);
    $htmlFile   .= ".html";
    my $main_html_file = "$OUTPUTS_REPORTS/$param_JIRA_PRJ/closed.html";
    sap_sm_begin_html($htmlFile,"Closed Jira cases");
    my %StatsClosed;
    my %StatsClosedLabels;
    foreach my $thisTakt (keys %Takts) {
        $start = 1 if($param_TaktTo eq $thisTakt);
        if( $start == 1) {
            my $request = 'project = '.$param_JIRA_PRJ.' AND assignee in ('.$list_iNumbers
                        .',EMPTY) AND ( resolutiondate >= '.$Takts{$thisTakt}{begin}
                        .' ) AND ( resolutiondate <= '.$Takts{$thisTakt}{end}
                        .' ) ORDER BY key DESC'
                        ;
            print "jql : $request\n" if($Warnings);
            my @results = sap_sm_jql($request);
            next if($results[0] == 0);
            my $numberClosed = scalar @results;
            my $total_story_points = 0;
            my @columnTitles = ("JIRA","Type","Epic Link","Summary","Assignee","Story Point","Created during sprint $thisTakt","Created","Resolved","Worklog","Life");
            sap_sm_start_html_table($htmlFile,"closed",$thisTakt,"$thisTakt ( $Takts{$thisTakt}{begin} - $Takts{$thisTakt}{end})",@columnTitles);
            if(open REPORT_HTML,">>$htmlFile") {
                foreach my $THIS_JIRA (@results) {
                    next if($THIS_JIRA->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
                    next if($THIS_JIRA->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i);
                    $StatsClosed{$thisTakt}{total}++;
                    print REPORT_HTML "\t<tr>";
                    #jira id
                    print REPORT_HTML "<td><a href=\"$jira_Url/browse/$THIS_JIRA->{key}\">$THIS_JIRA->{key}</a></td>";
                    #type
                    print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}</td>";
                    #Epic link
                    my $epicLinkTitle = ($THIS_JIRA->{'fields'}->{'customfield_15140'}) ? sap_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "na" ;
                    if($epicLinkTitle eq "na") { # search in parent if parent
                        $epicLinkTitle = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   ? sap_get_parent_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) : "na" ;
                    }
                    print REPORT_HTML "<td>$epicLinkTitle</td>";
                    #summary
                    #print "SUMMARY : $thisTakt - $THIS_JIRA->{key} - $THIS_JIRA->{'fields'}->{'summary'}\n";
                    print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'summary'}</td>";
                    #assignee
                    my $assignee = ($THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'}) ? $THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'} : "<font color=\"red\">Unassigned</font>";
                   print REPORT_HTML "<td>$assignee</td>";
                    #story point
                    my $story_point = ($THIS_JIRA->{'fields'}->{'customfield_10013'}) ? $THIS_JIRA->{'fields'}->{'customfield_10013'} : 0;
                    print REPORT_HTML "<td>$story_point</td>";
                    $total_story_points += int ($story_point);
                    if($story_point == 0) {
                        $story_point = "<font color=\"red\">n/a</font>";
                    }
                    #created during the current takt (yes/no)
                    my ($YearJiraCreated,$MonthJiraCreated,$DayJiraCreated,$HoursJiraCreated,$MinutesJiraCreated,$SecondsJiraCreated)
                       = $THIS_JIRA->{'fields'}->{'created'}
                       =~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)\./;
                    my $JiraCreatedInSeconds
                       = sap_sm_date_to_seconds("$YearJiraCreated-$MonthJiraCreated-$DayJiraCreated","$HoursJiraCreated:$MinutesJiraCreated:$SecondsJiraCreated");
                    my $taktBeginSeconds = sap_sm_date_to_seconds($Takts{$thisTakt}{begin},"0:0:0");
                    my $taktEndSeconds   = sap_sm_date_to_seconds($Takts{$thisTakt}{end},"0:0:0");
                    if(($JiraCreatedInSeconds >= $taktBeginSeconds) && ($JiraCreatedInSeconds < $taktEndSeconds)) {
                        print REPORT_HTML "<td><font color=\"green\">yes</font></td>";
                        $StatsClosed{$thisTakt}{intakt}++;
                    }  else  {
                        print REPORT_HTML "<td>no</td>";
                    }
                    #created
                    my $displayCreated = $THIS_JIRA->{'fields'}->{'created'};
                    ($displayCreated) =~ s-T- -;
                    ($displayCreated) =~ s-\..+?$--;
                    print REPORT_HTML "<td>$displayCreated</td>";
                    #resolved
                    my $displayClosed = $THIS_JIRA->{'fields'}->{'resolutiondate'};
                    ($displayClosed) =~ s-T- -;
                    ($displayClosed) =~ s-\..+?$--;
                    print REPORT_HTML "<td>$displayClosed</td>";
                    #time spent
                    my $totalTs = $THIS_JIRA->{'fields'}->{'timespent'};
                    my $displayTimeSpent = ($totalTs && ($totalTs>0))
                                         ? sap_sm_seconds_to_hms($totalTs)
                                         : 0;
                    print REPORT_HTML "<td>$displayTimeSpent</td>";
                    #duration
                    my ($YearJiraClosed,$MonthJiraClosed,$DayJiraClosed,$HoursJiraClosed,$MinutesJiraClosed,$SecondsJiraClosed)
                       = $THIS_JIRA->{'fields'}->{'resolutiondate'}
                       =~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)\./;
                    my @lifeHMS
                       = Delta_DHMS($YearJiraCreated,$MonthJiraCreated,$DayJiraCreated,$HoursJiraCreated,$MinutesJiraCreated,$SecondsJiraCreated,$YearJiraClosed,$MonthJiraClosed,$DayJiraClosed,$HoursJiraClosed,$MinutesJiraClosed,$SecondsJiraClosed);
                    my $sLifeHMS = sprintf "%u d %u h %02u mn %02u s" , @lifeHMS;
                    print REPORT_HTML "<td>$sLifeHMS</td>";
                    print REPORT_HTML "</tr>\n";
                }
                close REPORT_HTML;
            }
            $StatsClosed{$thisTakt}{storypoint} = $total_story_points;
            my $closed_in_takt = ($StatsClosed{$thisTakt}{intakt}) ? $StatsClosed{$thisTakt}{intakt} : 0;
            my $closed_total   = ($StatsClosed{$thisTakt}{total})  ? $StatsClosed{$thisTakt}{total}  : 0;
            my $statToWrite = "<tr class=\"sortbottom\"><td colspan=\"11\">nb Jira created and closed : $closed_in_takt<br/>nb Jira closed : $closed_total<br/>nb total stoy points : $total_story_points</td></tr>";
            sap_sm_write_stats_in_html($htmlFile,$statToWrite);
            sap_sm_close_html_table($htmlFile);
            sap_sm_close_html_section($htmlFile);
        }
        $start = 0 if($param_TaktFrom eq $thisTakt);
    }
    ### charts
    if(open REPORT_HTML,">>$htmlFile") {
        print REPORT_HTML "\n<hr/><br/>\n";
        close(REPORT_HTML);
        #1st graph
        my $start = 0;
        my @labels;
        my %data1;
        foreach my $thisTakt (sort {$a <=> $b} keys %Takts) {
            $start = 1 if($param_TaktFrom eq $thisTakt);
            if($start == 1) {
                push @labels,$thisTakt;
                push @{$data1{'nb total closed per takt'}},$StatsClosed{$thisTakt}{total};
                push @{$data1{'opened and closed per takt'}},$StatsClosed{$thisTakt}{intakt};
            }
            $start = 0 if($param_TaktTo eq $thisTakt);
        }
        sap_sm_line_chart($param_JIRA_PRJ,"Closed",$htmlFile,"graphAllClosed","Evolution","nb Jira case(s)",\@labels,\%data1);
    }
    sap_sm_close_html($htmlFile);
    if(open REPORT_HTML,">>$htmlFile") {
        print REPORT_HTML "\n<hr/><br/>\n";
        close(REPORT_HTML);
        #2nd graph
        my $start = 0;
        my @labels;
        my %data1;
        foreach my $thisTakt (sort {$a <=> $b} keys %Takts) {
            $start = 1 if($param_TaktFrom eq $thisTakt);
            if($start == 1) {
                push @labels,$thisTakt;
                push @{$data1{'nb total story points per takt'}},$StatsClosed{$thisTakt}{storypoint};
            }
            $start = 0 if($param_TaktTo eq $thisTakt);
        }
        sap_sm_line_chart($param_JIRA_PRJ,"Story Points",$htmlFile,"graphAllClosed2","Evolution Story Points","nb story point",\@labels,\%data1);
    }
    sap_sm_close_html($htmlFile);
    copy $htmlFile , $main_html_file or confess "\nERROR : Copy failed $htmlFile to $main_html_file: $!";
    print "\ndone, see $htmlFile\nalso in : http://$url_report:$port_report/Reports/$param_JIRA_PRJ/closed.html\n";
}

# real time spent option
if($opt_RTS) {
    my $start = 0;
	# 1 collect all jiras at once
    my %TS;
    my %JiraLabels;
    my %Counts;
    my %StatsRTS;
    my %Jiras;
    tie %Jiras, 'Tie::Hash::Indexed';
    foreach my $thisTakt (keys %Takts) {
        $start = 1 if($param_TaktTo eq $thisTakt);
        # project = DTXMAKE AND 
        # assignee in (i051566, i051113, i050674, i050726, i050619, i051432, i051375, i079877, i050910, i051393, i079644, EMPTY) AND (resolutiondate >= 2019-01-21 OR status not in (Closed, Completed, Consumed, Resolved, Done, "Validate", Committed, Confirmed, Abandoned)) ORDER BY key ASC
        if( $start == 1 ) {
            my $request = 'project = '.$param_JIRA_PRJ.' AND assignee in ('.$list_iNumbers
                        .',EMPTY) AND ( (resolutiondate >= '.$Takts{$thisTakt}{begin}
                        .' ) OR (status not in (Closed, Completed, Consumed, Resolved, Done, "Validate", Committed, Confirmed, Abandoned))'
                        .') AND timespent is not EMPTY ORDER BY key ASC'
                        ;
            print "jql : $request\n" if($Warnings);
            my @results = sap_sm_jql($request);
            next if($results[0] == 0);
            my $numberJira = scalar @results;
            my $taktBeginSeconds = sap_sm_date_to_seconds($Takts{$thisTakt}{begin},"0:0:0");
            my $taktEndSeconds   = sap_sm_date_to_seconds($Takts{$thisTakt}{end},"0:0:0");
            foreach my $issue (@results) {
                next if($issue->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
                next if($issue->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i);
                my $THIS_JIRA;
                # required, due to @{$THIS_JIRA->{'fields'}->{'worklog'}->{'worklogs'} does not exist in return value by Jira::REST :(
                if( -e "$OUTPUTS_JIRAS/$param_JIRA_PRJ/$issue->{key}") {
                    sap_sm_read_json_jira($issue->{key},$param_JIRA_PRJ,\$THIS_JIRA) ;
                }  else  {
                	sap_sm_wget_json_jira($issue->{key},$param_JIRA_PRJ,\$THIS_JIRA) ;
                }
                unless($THIS_JIRA->{key}) {
                	sap_sm_wget_json_jira($issue->{key},$param_JIRA_PRJ,\$THIS_JIRA) ;
                }
                my ($id) = $issue->{key} =~ /^$param_JIRA_PRJ\-(\d+)$/i;
                next unless($THIS_JIRA);
                #epic
                my $this_epic;
                $this_epic = ($THIS_JIRA->{'fields'}->{'customfield_15140'})   ? sap_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "na" ;
                if($this_epic eq "na") { # search in parent if parent
                    $this_epic = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) ? sap_get_parent_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) : "na" ;
                }
                next if($this_epic =~ /^Legacy$/i);
                my ($YearJiraCreated,$MonthJiraCreated,$DayJiraCreated,$HoursJiraCreated,$MinutesJiraCreated,$SecondsJiraCreated)
                   = $THIS_JIRA->{'fields'}->{'created'}
                   =~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)\./;
                my $JiraCreatedInSeconds
                   = sap_sm_date_to_seconds("$YearJiraCreated-$MonthJiraCreated-$DayJiraCreated","$HoursJiraCreated:$MinutesJiraCreated;$SecondsJiraCreated");
                my $TSJira = 0;
                foreach my $ts (@{$THIS_JIRA->{'fields'}->{'worklog'}->{'worklogs'}}) {
                    my ($YearJTSCreated,$MonthTSCreated,$DayTSCreated,$HoursTSCreated,$MinutesTSCreated,$SecondsTSCreated)
                       = $ts->{'created'}
                       =~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)\./;
                    my $TSInSeconds
                       = sap_sm_date_to_seconds("$YearJTSCreated-$MonthTSCreated-$DayTSCreated","$HoursTSCreated:$MinutesTSCreated:$SecondsTSCreated");
                    if(($TSInSeconds >= $taktBeginSeconds) && ($TSInSeconds < $taktEndSeconds)) {
                        $TS{$thisTakt} = $TS{$thisTakt} + $ts->{'timeSpentSeconds'};
                        $TSJira = $TSJira + $ts->{'timeSpentSeconds'}
                    }
                }
                my $thisLabel = ($THIS_JIRA->{'fields'}->{'labels'}->[0]) ? $THIS_JIRA->{'fields'}->{'labels'}->[0] : "noLabel";
                $JiraLabels{$thisLabel}=1;
                $Jiras{$thisTakt}{$id}{$thisLabel}{type} = $THIS_JIRA->{'fields'}->{'issuetype'}->{'name'};
                #Epic link
                my $epicLinkTitle = ($THIS_JIRA->{'fields'}->{'customfield_15140'}) ? sap_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "na" ;
				if($epicLinkTitle eq "na") { # search in parent if parent
					$epicLinkTitle = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   ? sap_get_parent_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) : "na" ;
				}
                $Jiras{$thisTakt}{$id}{$thisLabel}{epicLink} = $epicLinkTitle;
                my $fixVersions;
                foreach my $fixVersion (@{$THIS_JIRA->{'fields'}->{'fixVersions'}}) {
                    $fixVersions .= "$fixVersion->{'name'} ";
                }
                ($fixVersions) =~ s-\s+$-- if($fixVersions);
                $Jiras{$thisTakt}{$id}{$thisLabel}{fixversion} = ($fixVersions) ? $fixVersions : "noFixVersion";
                $Jiras{$thisTakt}{$id}{$thisLabel}{summary}    = $THIS_JIRA->{'fields'}->{'summary'};
                $Jiras{$thisTakt}{$id}{$thisLabel}{status}     = $THIS_JIRA->{'fields'}->{'status'}->{'name'};
                $Jiras{$thisTakt}{$id}{$thisLabel}{worklog}    = $TSJira;
                $Jiras{$thisTakt}{$id}{$thisLabel}{created}    = $THIS_JIRA->{'fields'}->{'created'};
                if($Counts{$thisTakt}{worklog}) {
                    $Counts{$thisTakt}{worklog}                = $Counts{$thisTakt}{worklog}    + $TSJira;
                }  else  {
                    $Counts{$thisTakt}{worklog}                = $TSJira;
                }
                if($Counts{$thisTakt}{label}) {
                    $Counts{$thisTakt}{label}                  = $Counts{$thisTakt}{label}      + $TSJira;
                }  else  {
                    $Counts{$thisTakt}{label}                  = $TSJira;
                }
                #$Counts{$thisTakt}{$thisLabel}                 = $Counts{$thisTakt}{$thisLabel} + $TSJira;
            }
        }
        last if($param_TaktFrom eq $thisTakt);
    }
    my $htmlFile = "$OUTPUTS_REPORTS/$param_JIRA_PRJ/rts";
    $htmlFile   .= "_$param_Takt"   if($param_Takt);
    $htmlFile   .= ".html";
    sap_sm_begin_html($htmlFile,"Real Time Spent");
    my @columnTitles = ("JIRA","Type","Epic Link","Summary","FixVersion(s)","Status","Worklog","Created");
    my $DoneRegExp = qr/Closed|Completed|Consumed|Resolved|Done|Validate|Committed|Confirmed/ ;
    $start = 0;
    foreach my $thisTakt (keys %Takts) {
        $start = 1 if($param_TaktTo eq $thisTakt);
        next if ($start == 0);
        if( $start == 1) {
            #main report
            my $subTable = '<legend onclick="document.getElementById(\'main_'.$thisTakt.'\').style.display = (document.getElementById(\'main_'.$thisTakt.'\').style.display==\'none\') ? \'block\' : \'none\';" onmouseover="this.style.cursor=\'pointer\'" onmouseout="this.style.cursor=\'auto\'"><u>general report</u></legend>
<div id="main_'.$thisTakt.'" style="display:none">
';
            sap_sm_start_RTS_html_table($htmlFile,"rts",$thisTakt,"$thisTakt ( $Takts{$thisTakt}{begin} - $Takts{$thisTakt}{end})",$subTable,@columnTitles);
            if(open REPORT_HTML,">>$htmlFile") {
                my %Stats1;
                foreach my $JIRA (sort {$b <=> $a} keys %{$Jiras{$thisTakt}}) {
                    print REPORT_HTML "<tr>";
                        print REPORT_HTML "<td><a href=\"$jira_Url/browse/${param_JIRA_PRJ}-$JIRA\">${param_JIRA_PRJ}-$JIRA</a></td>";
                        $Stats1{totaljira}++;
                        foreach my $thisLabel (keys %{$Jiras{$thisTakt}{$JIRA}}) {
                            print REPORT_HTML "<td>$Jiras{$thisTakt}{$JIRA}{$thisLabel}{type}</td>";
                            print REPORT_HTML "<td>$Jiras{$thisTakt}{$JIRA}{$thisLabel}{epicLink}</td>";
                            print REPORT_HTML "<td>$Jiras{$thisTakt}{$JIRA}{$thisLabel}{summary}</td>";
                            print REPORT_HTML "<td>$Jiras{$thisTakt}{$JIRA}{$thisLabel}{fixversion}</td>";
                            if($Jiras{$thisTakt}{$JIRA}{$thisLabel}{status} =~ /^$DoneRegExp$/i) {
                                $Stats1{done}++ ;
                                print REPORT_HTML "<td><font color=\"green\">$Jiras{$thisTakt}{$JIRA}{$thisLabel}{status}</font></td>";
                            } else {
                                print REPORT_HTML "<td>$Jiras{$thisTakt}{$JIRA}{$thisLabel}{status}</td>";
                            }
                            my $displayWorkLog = ($Jiras{$thisTakt}{$JIRA}{$thisLabel}{worklog} && ($Jiras{$thisTakt}{$JIRA}{$thisLabel}{worklog}>0))
                                               ? sap_sm_seconds_to_hms($Jiras{$thisTakt}{$JIRA}{$thisLabel}{worklog}) : 0;
                            print REPORT_HTML "<td>$displayWorkLog</td>";
                            $Stats1{totalworklog} = $Stats1{totalworklog} + $Jiras{$thisTakt}{$JIRA}{$thisLabel}{worklog} ;
                            my ($YearJiraCreated,$MonthJiraCreated,$DayJiraCreated,$HoursJiraCreated,$MinutesJiraCreated,$SecondsJiraCreated)
                               = $Jiras{$thisTakt}{$JIRA}{$thisLabel}{created}
                               =~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)\./;
                            my $JiraCreatedInSeconds
                               = sap_sm_date_to_seconds("$YearJiraCreated-$MonthJiraCreated-$DayJiraCreated","$HoursJiraCreated:$MinutesJiraCreated;$SecondsJiraCreated");
                            my $taktBeginSeconds = sap_sm_date_to_seconds($Takts{$thisTakt}{begin},"0:0:0");
                            my $taktEndSeconds   = sap_sm_date_to_seconds($Takts{$thisTakt}{end},"0:0:0");
                            my $displayCreated = $Jiras{$thisTakt}{$JIRA}{$thisLabel}{created};
                            ($displayCreated) =~ s-T- -;
                            ($displayCreated) =~ s-\..+?$--;
                            if(($JiraCreatedInSeconds >= $taktBeginSeconds) && ($JiraCreatedInSeconds < $taktEndSeconds)) { #inside this takt
                                print REPORT_HTML "<td>$displayCreated</td>";
                            }  else  {
                                print REPORT_HTML "<td bgcolor=\"#C6C6C6\">$displayCreated</td>";
                            }
                        }
                    print REPORT_HTML "</tr>\n";
                }
                close REPORT_HTML;
                my $displayTotalWorkLog = ($Stats1{totalworklog} && ($Stats1{totalworklog}>0))
                                        ? sap_sm_seconds_to_hms($Stats1{totalworklog}) : 0;
                my $statToWrite = "<tr class=\"sortbottom\"><td  colspan=\"9\">Total Time Spent : $displayTotalWorkLog<br/>nb Jira : $Stats1{totaljira}<br/>nb completed : $Stats1{done}</td></tr>";
                sap_sm_write_stats_in_html($htmlFile,$statToWrite);
                sap_sm_close_html_table($htmlFile);
                if(open REPORT_HTML,">>$htmlFile") {
                    print REPORT_HTML "</div>\n";
                    close(REPORT_HTML);
                }
                $StatsRTS{$thisTakt}{rts} = int ( $Stats1{totalworklog} / 3600 ) ;
            }
            #close takt
            sap_sm_close_html_section($htmlFile);
        }
    	last if($param_TaktFrom eq $thisTakt);
    }

    ### charts
    if(open REPORT_HTML,">>$htmlFile") {
        print REPORT_HTML "\n<hr/><br/>\n";
        close(REPORT_HTML);
        #1st graph
        my $start = 0;
        my @labels;
        my %data1;
        foreach my $thisTakt (sort {$a <=> $b} keys %Takts) {
            $start = 1 if($param_TaktFrom eq $thisTakt);
            if($start == 1) {
                push @labels,$thisTakt;
                push @{$data1{'nb total hours spent per takt'}},$StatsRTS{$thisTakt}{rts};
            }
            $start = 0 if($param_TaktTo eq $thisTakt);
        }
        sap_sm_line_chart($param_JIRA_PRJ,"Real Time Spent",$htmlFile,"graphAllRTS","Evolution","nb hours spent",\@labels,\%data1);
    }
    sap_sm_close_html($htmlFile);
    system "cp -pf $htmlFile $OUTPUTS_REPORTS/$param_JIRA_PRJ/rts.html";
    print "\ndone, see $htmlFile\nalso in : http://$url_report:$port_report/Reports/$param_JIRA_PRJ/rts.html\n";
}

# current status option
if($opt_CurrentSprint) {
    my %Status;
    my $request;
    #project = DTXMAKE AND assignee in (i051566,i050910,i050726,i051113,i050906,i050619,i051393,i051312,i051375,i079644,i335126,i079877,i051356,i050674,EMPTY) AND ( (status not in (Closed, Completed, Consumed, Resolved, Done, "Validate", Committed, Confirmed))  OR (resolutiondate >= 2017-08-28)  ) ORDER BY status DESC, key DESC
    unless($opt_JiraUser) {
        $request = 'project = '.$param_JIRA_PRJ
                 . ' AND ((fixVersion = '.$currentTakt.') OR (Sprint = "Focus '.$currentTakt.'")) AND assignee in ('.$list_iNumbers.',EMPTY) AND ( (status not in (Closed, Completed, Consumed, Resolved, Done, "Validate", Committed, Confirmed)) OR (resolutiondate >= '.$Takts{$currentTakt}{begin}
                 .') ) ORDER BY status DESC, key DESC'
                 ;
    }  else  {
        if($opt_JiraUser =~ /^unassigned$/i) {
            $request = 'project = '.$param_JIRA_PRJ;
            $request .= ' AND ((fixVersion = '.$currentTakt.') OR (Sprint = "Focus '.$currentTakt.'")) AND (status not in (Closed,Completed,Consumed,Resolved,Done)) AND assignee = '.$opt_JiraUser
                     .' ORDER BY status ASC, key DESC'
                     ;
        }  else  {
            $request = 'project = '.$param_JIRA_PRJ.' AND ((fixVersion = '.$currentTakt.') OR (Sprint = "Focus '.$currentTakt.'")) AND (status not in (Closed,Completed,Consumed,Resolved,Done)) AND assignee = '.$opt_JiraUser
                     .' ORDER BY status ASC, key DESC'
                     ;
        }
    }
    print "jql : $request\n" if($Warnings);
    my @results = sap_sm_jql($request);
    if( (! @results) || ($results[0] == 0) ) {
        cluck "WARNING : no result found\n";
        exit 0;
    }
    my %counts_jira_for_chart;
    my %counts_ts_for_chart;
    foreach my $THIS_JIRA (@results) {
        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i);
        next if($THIS_JIRA->{'fields'}->{'status'}->{'name'} =~ /Abandoned/i);
        my $status   = $THIS_JIRA->{'fields'}->{'status'}->{'name'};
        my $priority = $THIS_JIRA->{'fields'}->{'priority'}->{'name'};
        $Status{$status}{nb}++;
        $Status{$status}{$priority} = 1;
        $Status{totalJira}++;
    }
    # put current list in a backuped files
    my $newFile = "${Local_Year}-${Local_Month}-$Local_Day";
    $newFile .= "_$opt_JiraUser" if($opt_JiraUser);
    open TODAY,">$OUTPUTS_CS/$param_JIRA_PRJ/$newFile.txt";
    foreach my $status (sort keys %Status) {
        next if($status eq "nb");
        next if($status eq "totalJira");
        print TODAY "[$status]\n";
        foreach my $priority (sort keys %{$Status{$status}}) {
            foreach my $THIS_JIRA (sort @results) {
		        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
		        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i);
		        next if($THIS_JIRA->{'fields'}->{'status'}->{'name'} =~ /Abandoned/i);
                next unless($THIS_JIRA->{'fields'}->{'status'}->{'name'}   eq $status);
                next unless($THIS_JIRA->{'fields'}->{'priority'}->{'name'} eq $priority);
                print TODAY "$THIS_JIRA->{key}\n";
            }
        }
        print TODAY "\n";
    }
    close TODAY;
    #get previous list
    my %previousFiles;
    if(opendir CS,"$OUTPUTS_CS/$param_JIRA_PRJ") {
        while(defined(my $file = readdir CS)) {
            next unless($file =~ /\.txt$/i); #skip non txt file
            next if( !($opt_JiraUser) && ($file =~ /\_.+?$/i));           #skip files _i*.txt
            next if(   $opt_JiraUser  && (!($file =~ /\_$opt_JiraUser\.txt$/i)));  #skip files without *_this_iNumber.txt
            my $timestemp = stat("$OUTPUTS_CS/$param_JIRA_PRJ/$file")->mtime;
            $previousFiles{$timestemp} = $file;
        }
        closedir CS;
    }
    my $previousFileCount = 1;
    my $previousFile;
    foreach my $timestemp (sort {$b <=> $a} (keys %previousFiles)) {
        if($previousFileCount == 2) {
            $previousFile = $previousFiles{$timestemp};
            last;
        }
        $previousFileCount++;
    }


    my %PreviousJiras;
    my %status_found;
    if($previousFile) {
        if(open PREVIOUS,"$OUTPUTS_CS/$param_JIRA_PRJ/$previousFile") {
            my $Section;
            
            while(<PREVIOUS>) {
                chomp;
                next unless($_);
                if(/\[(.+?)\]$/) {
                    $Section = $1;
                    next;
                }
                my $jira = $_;
                push @{$PreviousJiras{$Section}} , $jira;
                $status_found{$Section} = 1;
            }
            close PREVIOUS;
            #search status not found
            foreach my $status (sort keys %Status) {
                next if($status eq "nb");
                next if($status eq "totalJira");
                my $found = 0;
                foreach my $status2 (sort keys %status_found) {
                    if($status =~ /^$status2$/i) {
                        $found = 1;
                        last;
                    }
                }
                if($found == 0) {
                    push @{$PreviousJiras{$status}} , 0;
                }
            }
        }
    }

    #HTML
    my $htmlFile = "$OUTPUTS_REPORTS/$param_JIRA_PRJ/cs";
    $htmlFile   .= "_$opt_JiraUser" if($opt_JiraUser);
    $htmlFile   .= ".html";
    if($opt_JiraUser) {
        sap_sm_begin_html($htmlFile," Current status for the Sprint=Focus<br/>Version = $currentTakt ( $Takts{$currentTakt}{begin} -> $Takts{$currentTakt}{end})<br/><font color=\"blue\">$opt_JiraUser</font><br/>nb total Jira : $Status{totalJira}");
    }  else  {
        sap_sm_begin_html($htmlFile," Current status for the Sprint=Focus<br/>Version = $currentTakt ( $Takts{$currentTakt}{begin} -> $Takts{$currentTakt}{end})<br/>nb total Jira : $Status{totalJira}");
    }
    my @columnTitles = ("Update" , "Jira ID" , "Fix Version(s)" , "Priority" , "Type" , "Epic Link" , "Story Point", "Summary" , "Assignee" , "Created" , "Reporter" , "WorkLog");
    my $DoneRegExp = qr/Closed|Completed|Consumed|Resolved|Done|Validate|Committed|Confirmed/ ;
    #set level order for the sort in the table

    my %PriorityLevels;
    $PriorityLevels{'Trivial'}   = 0;
    $PriorityLevels{'Low'}       = 1;
    $PriorityLevels{'Medium'}    = 2;
    $PriorityLevels{'High'}      = 3;
    $PriorityLevels{'Very High'} = 4;


    foreach my $status (sort keys %Status) {
        next if($status eq "nb");
        next if($status eq "totalJira");
        sap_sm_start_html_table($htmlFile,"cs_$status",$currentTakt,"$status ($Status{$status}{nb})",@columnTitles);
        if(open REPORT_HTML,">>$htmlFile") {
            foreach my $PriorityLevel (sort {$b <=> $a} (values %PriorityLevels)) {
                foreach my $THIS_JIRA (sort @results) {
			        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
			        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i);
			        next if($THIS_JIRA->{'fields'}->{'status'}->{'name'} =~ /Abandoned/i);
                    next unless($THIS_JIRA->{'fields'}->{'status'}->{'name'}   eq $status);
                    my $tmpPriority = $THIS_JIRA->{'fields'}->{'priority'}->{'name'};
                    next if($PriorityLevels{$tmpPriority} ne $PriorityLevel);
                    $counts_jira_for_chart{status}{$status}++;
                    $counts_jira_for_chart{priority}{$PriorityLevel}++;

                    #search in previous status
                    my $notFoundInPrevious = 1;
                    if( @{$PreviousJiras{$status}} ) {
                        foreach my $previous (sort @{$PreviousJiras{$status}}) {
                            ($previous) =~ s-^\w+\---i;
                            next if($previous ==0);
                            if($previous eq $THIS_JIRA->{key}) {
                                $notFoundInPrevious = 1;
                                last;
                            }
                        }
                    }
                    if($notFoundInPrevious == 1) {
                        print REPORT_HTML "\t<tr>";
                        print REPORT_HTML "<td></td>";
                    }  else  {
                        print REPORT_HTML "\t<tr bgcolor=\"#98AFC7\">";
                        print REPORT_HTML "<td align=\"center\"><strong>+</strong></td>";
                    }
                    print REPORT_HTML "<td><a href=\"$jira_Url/browse/$THIS_JIRA->{key}\">$THIS_JIRA->{key}</a></td>";
                    my $fixVersions;
                    foreach my $fixVersion (@{$THIS_JIRA->{'fields'}->{'fixVersions'}}) {
                        $fixVersions .= "$fixVersion->{'name'} ";
                    }
                    $fixVersions = ($fixVersions) ? $fixVersions : "none";
                    ($fixVersions) =~ s-\s+$--;
                    print REPORT_HTML "<td>$fixVersions</td>";
                    $counts_jira_for_chart{fixVersion}{$fixVersions}++;
                    if($THIS_JIRA->{'fields'}->{'priority'}->{'name'}     =~ /^Blocker$/i) {
                        print REPORT_HTML "<td><font color=\"red\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
                    }  elsif ($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^critical$/i)  {
                        print REPORT_HTML "<td><font color=\"#A52A2A\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
                    }  elsif ($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^major$/i)  {
                        print REPORT_HTML "<td><font color=\"#FFA500\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
                    }  else  {
                        print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</td>";
                    }
                    print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}</td>";
                    my $epicLinkTitle = ($THIS_JIRA->{'fields'}->{'customfield_15140'}) ? sap_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "na" ;
					if($epicLinkTitle eq "na") { # search in parent if parent
						$epicLinkTitle = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   ? sap_get_parent_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) : "na" ;
					}
                    print REPORT_HTML "<td>$epicLinkTitle</td>";
                    my $story_point = ($THIS_JIRA->{'fields'}->{'customfield_10013'}) ? $THIS_JIRA->{'fields'}->{'customfield_10013'} : "<font color=\"red\">n/a</font>";
                    print REPORT_HTML "<td>$story_point</td>";
                    binmode(REPORT_HTML, ":utf8");
                    print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'summary'}</td>";
                    
                    if( $THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'} ) {
                        print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'}</td>";
                    }  else  {
                        print REPORT_HTML "<td><font color=\"red\">Unassigned</font></td>";
                    }
                    my $displayCreated = $THIS_JIRA->{'fields'}->{'created'};
                    ($displayCreated) =~ s-T- -;
                    ($displayCreated) =~ s-\..+?$--;
                    print REPORT_HTML "<td>$displayCreated</td>";
                    print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'reporter'}->{'displayName'}</td>";
                    my $reporter = $THIS_JIRA->{'fields'}->{'reporter'}->{'displayName'};
                    $counts_jira_for_chart{reporter}{$reporter}++;
                    my $totalTs = $THIS_JIRA->{'fields'}->{'timespent'};
                    my $displayTimeSpent = ($totalTs  && ($totalTs>0)) ? sap_sm_seconds_to_hms($totalTs) : 0;
                    if($totalTs) {
                        $counts_ts_for_chart{status}{$status}          += $totalTs;
                        $counts_ts_for_chart{priority}{$PriorityLevel} += $totalTs;
                        $counts_ts_for_chart{fixVersion}{$fixVersions} += $totalTs;
                        if($THIS_JIRA->{'fields'}->{'labels'}->[0]) {
                            my $label = $THIS_JIRA->{'fields'}->{'labels'}->[0];
                            $counts_ts_for_chart{label}{$label}        += $totalTs;
                        }  else  {
                            $counts_ts_for_chart{label}{"no label"}    += $totalTs;
                        }
                        $counts_ts_for_chart{reporter}{$reporter}      += $totalTs;
                    }
                    print REPORT_HTML "<td>$displayTimeSpent</td>";
                    print REPORT_HTML "</tr>\n";
                }
            }
                close REPORT_HTML;
            }
        sap_sm_close_html_table($htmlFile);
        if(open REPORT_HTML,">>$htmlFile") {
            print REPORT_HTML "</div>\n";
            close REPORT_HTML;
        }
        sap_sm_close_html_section($htmlFile);
    }

    # charts
    if(open REPORT_HTML,">>$htmlFile") {
        print REPORT_HTML "\n<hr/><br/>\n";
        print REPORT_HTML "<center><h1>graphs % nb jira(s) per </h1></center><br/>\n";
        close REPORT_HTML;
    }
    foreach my $key (qw(status priority fixVersion reporter)) {
            my %data;
            foreach my $value (keys %{$counts_jira_for_chart{$key}}) {
                $data{$value} = "$counts_jira_for_chart{$key}{$value},0";
            }
            sap_sm_pie_chart($param_JIRA_PRJ,"REPORT_HTML",$htmlFile,"pie_chart_cs_jira_$key","$key",\%data);
    }

    if(open REPORT_HTML,">>$htmlFile") {
        print REPORT_HTML "\n<br/><hr/><br/>\n";
        print REPORT_HTML "<center><h1>graphs % worklog per </h1></center><br/>\n";
        close REPORT_HTML;
    }
    foreach my $key (qw(status priority fixVersion reporter)) {
            my %data;
            foreach my $value (keys %{$counts_ts_for_chart{$key}}) {
                $data{$value} = "$counts_ts_for_chart{$key}{$value},0";
            }
            sap_sm_pie_chart($param_JIRA_PRJ,"REPORT_HTML",$htmlFile,"pie_chart_cs_ts_$key","$key",\%data);
    }
	sap_sm_close_html($htmlFile);
    my $url = ($opt_JiraUser) ? "http://$url_report:$port_report/Reports/$param_JIRA_PRJ/cs_$opt_JiraUser.html" : "http://$url_report:$port_report/Reports/$param_JIRA_PRJ/cs.html";
    print "\ndone, see $htmlFile\nalso in : $url\n";
}

# whole dtxmake status option
if($opt_WholeStatus) {
    my %Status;
    my $request;

    #project = DTXMAKE AND assignee in (i051566,i050910,i050726,i051113,i050906,i050619,i051393,i051312,i051375,i079644,i335126,i079877,i051356,i050674,EMPTY) AND ( (status not in (Closed, Completed, Consumed, Resolved, Done, "Validate", Committed, Confirmed))  OR (resolutiondate >= 2017-08-28)  ) ORDER BY status DESC, key DESC
    unless($opt_JiraUser) {
        $request = 'project = '.$param_JIRA_PRJ;
        if($fixVersions{exclude}) {
                $request .= ' AND fixVersion not in ('.$fixVersions{exclude}.')';
        }
        $request .= ' AND assignee in ('.$list_iNumbers.',EMPTY) AND ( (status not in (Closed, Completed, Consumed, Resolved, Done, "Validate", Committed, Confirmed)) OR (resolutiondate >= '.$Takts{$currentTakt}{begin}
                 .') ) ORDER BY status DESC, key DESC'
                 ;
    }  else  {
        if($opt_JiraUser =~ /^unassigned$/i) {
            $request = 'project = '.$param_JIRA_PRJ;
            $request .= ' AND (status not in (Closed,Completed,Consumed,Resolved,Done)) AND assignee = '.$opt_JiraUser
                     .' ORDER BY status ASC, key DESC'
                     ;
        }  else  {
            $request = 'project = '.$param_JIRA_PRJ.' AND (status not in (Closed,Completed,Consumed,Resolved,Done)) AND assignee = '.$opt_JiraUser
                     .' ORDER BY status ASC, key DESC'
                     ;
        }
    }
    print "jql : $request\n" if($Warnings);
    my @results = sap_sm_jql($request);
    if( (! @results) || ($results[0] == 0) ) {
        cluck "WARNING : no result found\n";
        exit 0;
    }
    my %counts_jira_for_chart;
    my %counts_ts_for_chart;
    foreach my $THIS_JIRA (@results) {
        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i);
        my $status   = $THIS_JIRA->{'fields'}->{'status'}->{'name'};
        my $priority = $THIS_JIRA->{'fields'}->{'priority'}->{'name'};
        $Status{$status}{nb}++;
        $Status{$status}{$priority} = 1;
        $Status{totalJira}++;
    }
    # put current list in a backuped files
    my $newFile = "${Local_Year}-${Local_Month}-$Local_Day";
    $newFile .= "_$opt_JiraUser" if($opt_JiraUser);
    open TODAY,">$OUTPUTS_CS/$param_JIRA_PRJ/$newFile.txt";
    foreach my $status (sort keys %Status) {
        next if($status eq "nb");
        next if($status eq "totalJira");
        print TODAY "[$status]\n";
        foreach my $priority (sort keys %{$Status{$status}}) {
            foreach my $THIS_JIRA (sort @results) {
		        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
		        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i);
                next unless($THIS_JIRA->{'fields'}->{'status'}->{'name'}   eq $status);
                next unless($THIS_JIRA->{'fields'}->{'priority'}->{'name'} eq $priority);
                print TODAY "$THIS_JIRA->{key}\n";
            }
        }
        print TODAY "\n";
    }
    close TODAY;
    #get previous list
    my %previousFiles;
    if(opendir CS,"$OUTPUTS_CS/$param_JIRA_PRJ") {
        while(defined(my $file = readdir CS)) {
            next unless($file =~ /\.txt$/i); #skip non txt file
            next if( !($opt_JiraUser) && ($file =~ /\_.+?$/i));           #skip files _i*.txt
            next if(   $opt_JiraUser  && (!($file =~ /\_$opt_JiraUser\.txt$/i)));  #skip files without *_this_iNumber.txt
            my $timestemp = stat("$OUTPUTS_CS/$param_JIRA_PRJ/$file")->mtime;
            $previousFiles{$timestemp} = $file;
        }
        closedir CS;
    }
    my $previousFileCount = 1;
    my $previousFile;
    foreach my $timestemp (sort {$b <=> $a} (keys %previousFiles)) {
        if($previousFileCount == 2) {
            $previousFile = $previousFiles{$timestemp};
            last;
        }
        $previousFileCount++;
    }


    my %PreviousJiras;
    my %status_found;
    if($previousFile) {
        if(open PREVIOUS,"$OUTPUTS_CS/$param_JIRA_PRJ/$previousFile") {
            my $Section;
            
            while(<PREVIOUS>) {
                chomp;
                next unless($_);
                if(/\[(.+?)\]$/) {
                    $Section = $1;
                    next;
                }
                my $jira = $_;
                push @{$PreviousJiras{$Section}} , $jira;
                $status_found{$Section} = 1;
            }
            close PREVIOUS;
            #search status not found
            foreach my $status (sort keys %Status) {
                next if($status eq "nb");
                next if($status eq "totalJira");
                my $found = 0;
                foreach my $status2 (sort keys %status_found) {
                    if($status =~ /^$status2$/i) {
                        $found = 1;
                        last;
                    }
                }
                if($found == 0) {
                    push @{$PreviousJiras{$status}} , 0;
                }
            }
        }
    }

    #HTML
    my $htmlFile = "$OUTPUTS_REPORTS/$param_JIRA_PRJ/cs";
    $htmlFile   .= "_$opt_JiraUser" if($opt_JiraUser);
    $htmlFile   .= ".html";
    if($opt_JiraUser) {
        sap_sm_begin_html($htmlFile," Current status $currentTakt ( $Takts{$currentTakt}{begin} -> $Takts{$currentTakt}{end})<br/><font color=\"blue\">$opt_JiraUser</font><br/>nb total Jira : $Status{totalJira}");
    }  else  {
        sap_sm_begin_html($htmlFile," Current status $currentTakt ( $Takts{$currentTakt}{begin} -> $Takts{$currentTakt}{end})<br/>nb total Jira : $Status{totalJira}");
    }
    my @columnTitles = ("Update" , "Jira ID" , "Fix Version(s)" , "Priority" , "Type" , "Epic Link" , "Story Point", "Summary" , "Assignee" , "Created" , "Reporter" , "WorkLog");
    my $DoneRegExp = qr/Closed|Completed|Consumed|Resolved|Done|Validate|Committed|Confirmed/ ;
    #set level order for the sort in the table

    my %PriorityLevels;
    $PriorityLevels{'Trivial'}   = 0;
    $PriorityLevels{'Low'}       = 1;
    $PriorityLevels{'Medium'}    = 2;
    $PriorityLevels{'High'}      = 3;
    $PriorityLevels{'Very High'} = 4;

    foreach my $status (sort keys %Status) {
        next if($status eq "nb");
        next if($status eq "totalJira");
        sap_sm_start_html_table($htmlFile,"cs_$status",$currentTakt,"$status ($Status{$status}{nb})",@columnTitles);
        if(open REPORT_HTML,">>$htmlFile") {
            foreach my $PriorityLevel (sort {$b <=> $a} (values %PriorityLevels)) {
                foreach my $THIS_JIRA (sort @results) {
			        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
			        next if($THIS_JIRA->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i);
                    next unless($THIS_JIRA->{'fields'}->{'status'}->{'name'}   eq $status);
                    my $tmpPriority = $THIS_JIRA->{'fields'}->{'priority'}->{'name'};
                    next if($PriorityLevels{$tmpPriority} ne $PriorityLevel);
                    $counts_jira_for_chart{status}{$status}++;
                    $counts_jira_for_chart{priority}{$PriorityLevel}++;

                    #search in previous status
                    my $notFoundInPrevious = 1;
                    if( @{$PreviousJiras{$status}} ) {
                        foreach my $previous (sort @{$PreviousJiras{$status}}) {
                            ($previous) =~ s-^\w+\---i;
                            next if($previous ==0);
                            if($previous eq $THIS_JIRA->{key}) {
                                $notFoundInPrevious = 1;
                                last;
                            }
                        }
                    }
                    if($notFoundInPrevious == 1) {
                        print REPORT_HTML "\t<tr>";
                        print REPORT_HTML "<td></td>";
                    }  else  {
                        print REPORT_HTML "\t<tr bgcolor=\"#98AFC7\">";
                        print REPORT_HTML "<td align=\"center\"><strong>+</strong></td>";
                    }
                    print REPORT_HTML "<td><a href=\"$jira_Url/browse/$THIS_JIRA->{key}\">$THIS_JIRA->{key}</a></td>";
                    my $fixVersions;
                    foreach my $fixVersion (@{$THIS_JIRA->{'fields'}->{'fixVersions'}}) {
                        $fixVersions .= "$fixVersion->{'name'} ";
                    }
                    $fixVersions = ($fixVersions) ? $fixVersions : "none";
                    ($fixVersions) =~ s-\s+$--;
                    print REPORT_HTML "<td>$fixVersions</td>";
                    $counts_jira_for_chart{fixVersion}{$fixVersions}++;
                    if($THIS_JIRA->{'fields'}->{'priority'}->{'name'}     =~ /^Blocker$/i) {
                        print REPORT_HTML "<td><font color=\"red\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
                    }  elsif ($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^critical$/i)  {
                        print REPORT_HTML "<td><font color=\"#A52A2A\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
                    }  elsif ($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^major$/i)  {
                        print REPORT_HTML "<td><font color=\"#FFA500\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
                    }  else  {
                        print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</td>";
                    }
                    print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}</td>";
                    my $epicLinkTitle = ($THIS_JIRA->{'fields'}->{'customfield_15140'}) ? sap_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "na" ;
					if($epicLinkTitle eq "na") { # search in parent if parent
						$epicLinkTitle = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   ? sap_get_parent_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) : "na" ;
					}
                    print REPORT_HTML "<td>$epicLinkTitle</td>";
                    my $story_point = ($THIS_JIRA->{'fields'}->{'customfield_10013'}) ? $THIS_JIRA->{'fields'}->{'customfield_10013'} : "<font color=\"red\">n/a</font>";
                    print REPORT_HTML "<td>$story_point</td>";
                    binmode(REPORT_HTML, ":utf8");
                    print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'summary'}</td>";
                    
                    if( $THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'} ) {
                        print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'}</td>";
                    }  else  {
                        print REPORT_HTML "<td><font color=\"red\">Unassigned</font></td>";
                    }
                    my $displayCreated = $THIS_JIRA->{'fields'}->{'created'};
                    ($displayCreated) =~ s-T- -;
                    ($displayCreated) =~ s-\..+?$--;
                    print REPORT_HTML "<td>$displayCreated</td>";
                    print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'reporter'}->{'displayName'}</td>";
                    my $reporter = $THIS_JIRA->{'fields'}->{'reporter'}->{'displayName'};
                    $counts_jira_for_chart{reporter}{$reporter}++;
                    my $totalTs = $THIS_JIRA->{'fields'}->{'timespent'};
                    my $displayTimeSpent = ($totalTs  && ($totalTs>0)) ? sap_sm_seconds_to_hms($totalTs) : 0;
                    if($totalTs) {
                        $counts_ts_for_chart{status}{$status}          += $totalTs;
                        $counts_ts_for_chart{priority}{$PriorityLevel} += $totalTs;
                        $counts_ts_for_chart{fixVersion}{$fixVersions} += $totalTs;
                        if($THIS_JIRA->{'fields'}->{'labels'}->[0]) {
                            my $label = $THIS_JIRA->{'fields'}->{'labels'}->[0];
                            $counts_ts_for_chart{label}{$label}        += $totalTs;
                        }  else  {
                            $counts_ts_for_chart{label}{"no label"}    += $totalTs;
                        }
                        $counts_ts_for_chart{reporter}{$reporter}      += $totalTs;
                    }
                    print REPORT_HTML "<td>$displayTimeSpent</td>";
                    print REPORT_HTML "</tr>\n";
                }
            }
                close REPORT_HTML;
            }
        sap_sm_close_html_table($htmlFile);
        if(open REPORT_HTML,">>$htmlFile") {
            print REPORT_HTML "</div>\n";
            close REPORT_HTML;
        }
        sap_sm_close_html_section($htmlFile);
    }

    # charts
    if(open REPORT_HTML,">>$htmlFile") {
        print REPORT_HTML "\n<hr/><br/>\n";
        print REPORT_HTML "<center><h1>graphs % nb jira(s) per </h1></center><br/>\n";
        close REPORT_HTML;
    }
    foreach my $key (qw(status priority fixVersion reporter)) {
            my %data;
            foreach my $value (keys %{$counts_jira_for_chart{$key}}) {
                $data{$value} = "$counts_jira_for_chart{$key}{$value},0";
            }
            sap_sm_pie_chart($param_JIRA_PRJ,"REPORT_HTML",$htmlFile,"pie_chart_cs_jira_$key","$key",\%data);
    }

    if(open REPORT_HTML,">>$htmlFile") {
        print REPORT_HTML "\n<br/><hr/><br/>\n";
        print REPORT_HTML "<center><h1>graphs % worklog per </h1></center><br/>\n";
        close REPORT_HTML;
    }
    foreach my $key (qw(status priority fixVersion reporter)) {
            my %data;
            foreach my $value (keys %{$counts_ts_for_chart{$key}}) {
                $data{$value} = "$counts_ts_for_chart{$key}{$value},0";
            }
            sap_sm_pie_chart($param_JIRA_PRJ,"REPORT_HTML",$htmlFile,"pie_chart_cs_ts_$key","$key",\%data);
    }
	sap_sm_close_html($htmlFile);
    my $url = ($opt_JiraUser) ? "http://$url_report:$port_report/Reports/$param_JIRA_PRJ/cs_$opt_JiraUser.html" : "http://$url_report:$port_report/Reports/$param_JIRA_PRJ/cs.html";
    print "\ndone, see $htmlFile\nalso in : $url\n";
}

if($opt_Epics) {
	my %Epics_Sprint;
	my %Epics_Name;
	my %Epics_Name_counts;
	my %All_Epics;
	my $htmlFile = "$OUTPUTS_REPORTS/$param_JIRA_PRJ/epics.html";
	my $List_Epics_RegExp = qr/KSR|CI\&E|Quality\s+of\s+Service|xMake\s+Support/ ;
	sap_sm_begin_html($htmlFile,"Epics");
	my $start = 0;
	foreach my $thisTakt (keys %Takts) {
		$start = 1 if($param_TaktTo eq $thisTakt);
		if( $start == 1) {
			my $request;
			if($param_Takt && ($param_Takt eq $thisTakt)) {
				$request = 'project = '.$param_JIRA_PRJ.' AND assignee in ('.$list_iNumbers
						.',EMPTY) AND Sprint = "'.$thisTakt
						. '" AND status not in (Open, "To Do") ORDER BY key DESC'
						;
			}  else  {
				$request = 'project = '.$param_JIRA_PRJ.' AND assignee in ('.$list_iNumbers
						.',EMPTY) AND ( ( resolutiondate >= '.$Takts{$thisTakt}{begin}
						.'  AND  resolutiondate <= '.$Takts{$thisTakt}{end}
						.' ) OR ( (updatedDate >= '.$Takts{$thisTakt}{begin}
						.' AND updatedDate < '.$Takts{$thisTakt}{end}
						.' ) AND timespent is not EMPTY ) ) ORDER BY key DESC'
						;
			}
			print "jql : $request\n" if($Warnings);
			my @results = sap_sm_jql($request);
			next if($results[0] == 0);
			# for stats
			my $taktBeginSeconds = sap_sm_date_to_seconds($Takts{$thisTakt}{begin},"0:0:0");
			my $taktEndSeconds   = sap_sm_date_to_seconds($Takts{$thisTakt}{end},"0:0:0");
			my $nbTotal_Jira = 0;
			my @columnTitles = ("JIRA","Type","Epic Link","Summary","Status","Assignee","Story Point","Created during sprint $thisTakt","Created","Resolved","Worklog","Life");
			sap_sm_start_html_table($htmlFile,"epic",$thisTakt,"$thisTakt ( $Takts{$thisTakt}{begin} - $Takts{$thisTakt}{end})",@columnTitles);
			if(open REPORT_HTML,">>$htmlFile") {
				foreach my $issue (@results) {
					next if($issue->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
					my $THIS_JIRA;
					# required, due to @{$THIS_JIRA->{'fields'}->{'worklog'}->{'worklogs'} does not exist in return value by Jira::REST :(
					if( -e "$OUTPUTS_JIRAS/$param_JIRA_PRJ/$issue->{key}") {
						sap_sm_read_json_jira($issue->{key},$param_JIRA_PRJ,\$THIS_JIRA) ;
					}  else  {
						sap_sm_wget_json_jira($issue->{key},$param_JIRA_PRJ,\$THIS_JIRA) ;
					}
					unless($THIS_JIRA->{key}) {
						sap_sm_wget_json_jira($issue->{key},$param_JIRA_PRJ,\$THIS_JIRA) ;
					}
					#epic
					my $this_epic;
					if($THIS_JIRA->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i) {
						if($THIS_JIRA->{'fields'}->{'summary'} !~ /legacy/i) {
							$this_epic = "xMake Support" ;
						}  else  {
							$this_epic = "Legacy" ;
						}
					}  else  {
						$this_epic = ($THIS_JIRA->{'fields'}->{'customfield_15140'}) ? sap_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "na" ;
					}
					if($this_epic eq "na") { # search in parent if parent
						$this_epic = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   ? sap_get_parent_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) : "na" ;
					}
					next if($this_epic =~ /^Legacy$/i);
					if($this_epic !~ /^$List_Epics_RegExp$/i) {
						$this_epic = "PM";
					}
					# worklog in this sprint
					my $TSJira = 0;
					foreach my $ts (@{$THIS_JIRA->{'fields'}->{'worklog'}->{'worklogs'}}) {
						my ($YearJTSCreated,$MonthTSCreated,$DayTSCreated,$HoursTSCreated,$MinutesTSCreated,$SecondsTSCreated)
							= $ts->{'created'}
							=~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)\./;
						my $TSInSeconds
							= sap_sm_date_to_seconds("$YearJTSCreated-$MonthTSCreated-$DayTSCreated","$HoursTSCreated:$MinutesTSCreated:$SecondsTSCreated");
						if(($TSInSeconds >= $taktBeginSeconds) && ($TSInSeconds < $taktEndSeconds)) {
							$TSJira = $TSJira + $ts->{'timeSpentSeconds'}
						}
					}
					unless($param_Takt && ($param_Takt eq $thisTakt)) { # not current takt
						next if( ($TSJira == 0) && ! ($THIS_JIRA->{'fields'}->{'resolutiondate'}) ); # no workload and not closed
					}
					$nbTotal_Jira++;
					$Epics_Sprint{$thisTakt}{$this_epic}{nb}++;
					$Epics_Name{$this_epic}{$thisTakt}{nb}++;
					$Epics_Name_counts{nb}{$this_epic}++;
					# story points
					$story_points = ($THIS_JIRA->{'fields'}->{'customfield_10013'}) ? $THIS_JIRA->{'fields'}->{'customfield_10013'} : 0 ;
					$Epics_Sprint{$thisTakt}{$this_epic}{sp} = ( $Epics_Sprint{$thisTakt}{$this_epic}{sp} ) ? $Epics_Sprint{$thisTakt}{$this_epic}{sp} + $story_points : $story_points;
					$Epics_Name{$this_epic}{$thisTakt}{sp}   = ( $Epics_Name{$this_epic}{$thisTakt}{sp} )   ? $Epics_Name{$this_epic}{$thisTakt}{sp}   + $story_points : $story_points;
					$Epics_Name_counts{sp}{$this_epic}       = ( $Epics_Name_counts{sp}{$this_epic} )       ? $Epics_Name_counts{sp}{$this_epic}       + $story_points : $story_points;

					$Epics_Sprint{$thisTakt}{$this_epic}{ts} = ( $Epics_Sprint{$thisTakt}{$this_epic}{ts} ) ? $Epics_Sprint{$thisTakt}{$this_epic}{ts} + $TSJira : $TSJira;
					$Epics_Name{$this_epic}{$thisTakt}{ts}   = ( $Epics_Name{$this_epic}{$thisTakt}{ts} )   ? $Epics_Name{$this_epic}{$thisTakt}{ts}   + $TSJira : $TSJira;
					$Epics_Name_counts{ts}{$this_epic}       = ( $Epics_Name_counts{ts}{$this_epic} )       ? $Epics_Name_counts{ts}{$this_epic}       + $TSJira : $TSJira;
					# write html
					print REPORT_HTML "\t<tr>";
					#jira id
					print REPORT_HTML "<td><a href=\"$jira_Url/browse/$THIS_JIRA->{key}\">$THIS_JIRA->{key}</a></td>";
					#type
					print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}</td>";
					#Epic link
					print REPORT_HTML "<td>$this_epic</td>";
					#summary
					#print "SUMMARY : $thisTakt - $THIS_JIRA->{key} - $THIS_JIRA->{'fields'}->{'summary'}\n";
					binmode(REPORT_HTML, ":utf8");
					print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'summary'}</td>";
					#status
					#print "SUMMARY : $thisTakt - $THIS_JIRA->{key} - $THIS_JIRA->{'fields'}->{'summary'}\n";
					print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'status'}->{'name'}</td>";
					#assignee
					my $assignee = ($THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'}) ? $THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'} : "<font color=\"red\">Unassigned</font>";
					print REPORT_HTML "<td>$assignee</td>";
					#story point
					print REPORT_HTML "<td>$story_points</td>";
					#created during the current takt (yes/no)
					my ($YearJiraCreated,$MonthJiraCreated,$DayJiraCreated,$HoursJiraCreated,$MinutesJiraCreated,$SecondsJiraCreated)
						= $THIS_JIRA->{'fields'}->{'created'}
						=~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)\./;
					my $JiraCreatedInSeconds
						= sap_sm_date_to_seconds("$YearJiraCreated-$MonthJiraCreated-$DayJiraCreated","$HoursJiraCreated:$MinutesJiraCreated:$SecondsJiraCreated");
					my $taktBeginSeconds = sap_sm_date_to_seconds($Takts{$thisTakt}{begin},"0:0:0");
					my $taktEndSeconds   = sap_sm_date_to_seconds($Takts{$thisTakt}{end},"0:0:0");
					if(($JiraCreatedInSeconds >= $taktBeginSeconds) && ($JiraCreatedInSeconds < $taktEndSeconds)) {
						print REPORT_HTML "<td><font color=\"green\">yes</font></td>";
					}  else  {
						print REPORT_HTML "<td>no</td>";
					}
					#created
					my $displayCreated = $THIS_JIRA->{'fields'}->{'created'};
					($displayCreated) =~ s-T- -;
					($displayCreated) =~ s-\..+?$--;
					print REPORT_HTML "<td>$displayCreated</td>";
					#resolved
					my $displayClosed = " ";
					if($THIS_JIRA->{'fields'}->{'resolutiondate'}) {
						$displayClosed = $THIS_JIRA->{'fields'}->{'resolutiondate'};
						($displayClosed) =~ s-T- -;
						($displayClosed) =~ s-\..+?$--;
					}
					print REPORT_HTML "<td>$displayClosed</td>";
					#time spent
					my $displayTimeSpent = ($TSJira > 0) ? sap_sm_seconds_to_hms($TSJira) : "0";
					print REPORT_HTML "<td>$displayTimeSpent</td>";
					#duration
					my ($YearJiraClosed,$MonthJiraClosed,$DayJiraClosed,$HoursJiraClosed,$MinutesJiraClosed,$SecondsJiraClosed);
					my @lifeHMS;
					my $sLifeHMS = " ";
					if($THIS_JIRA->{'fields'}->{'resolutiondate'}) {
						($YearJiraClosed,$MonthJiraClosed,$DayJiraClosed,$HoursJiraClosed,$MinutesJiraClosed,$SecondsJiraClosed)
							= $THIS_JIRA->{'fields'}->{'resolutiondate'}
							=~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)\./;
						@lifeHMS
							= Delta_DHMS($YearJiraCreated,$MonthJiraCreated,$DayJiraCreated,$HoursJiraCreated,$MinutesJiraCreated,$SecondsJiraCreated,$YearJiraClosed,$MonthJiraClosed,$DayJiraClosed,$HoursJiraClosed,$MinutesJiraClosed,$SecondsJiraClosed);
						$sLifeHMS = sprintf "%u d %u h %02u mn %02u s" , @lifeHMS;
					}
					print REPORT_HTML "<td>$sLifeHMS</td>";
					print REPORT_HTML "</tr>\n";
					push @{$All_Epics{$this_epic}} , $THIS_JIRA->{key} unless grep /^$THIS_JIRA->{key}$/ , @{$All_Epics{$this_epic}};
					undef $THIS_JIRA;
				}
				my $statToWrite = "<tr class=\"sortbottom\"><td colspan=\"12\">nb total jira: $nbTotal_Jira<br/>\n";
				foreach my $epic_name (sort keys %Epics_Name) {
					if( $Epics_Name{$epic_name}{$thisTakt}{nb} || $Epics_Name{$epic_name}{$thisTakt}{sp} || $Epics_Name{$epic_name}{$thisTakt}{ts} ) {
						 my $displayTimeSpent = ($Epics_Name{$epic_name}{$thisTakt}{ts}  && ($Epics_Name{$epic_name}{$thisTakt}{ts}>0)) ? sap_sm_seconds_to_hms($Epics_Name{$epic_name}{$thisTakt}{ts}) : "0";
						 $statToWrite .= "<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<font color=\"#0000CD\">$epic_name</font><br/>
nb total jira : $Epics_Name{$epic_name}{$thisTakt}{nb}<br/>
nb total story points : $Epics_Name{$epic_name}{$thisTakt}{sp}<br/>
nb worklog for : $displayTimeSpent<br/>";
					}
				}
				$statToWrite .= "</td></tr>\n";
				sap_sm_write_stats_in_html($htmlFile,$statToWrite);
				sap_sm_close_html_table($htmlFile);
				sap_sm_close_html_section($htmlFile);
			}
		}
		$start = 0 if($param_TaktFrom eq $thisTakt);
	}
	# per epic name
	if(open REPORT_HTML,">>$htmlFile") {
		print REPORT_HTML "\n<hr/><br/>\n";
		print REPORT_HTML "<center><h1>per epic names</h1></center><br/>\n";
		close REPORT_HTML;
	}
	my @columnTitles = ("JIRA","Type","Epic Link","Summary","Status","Assignee","Story Point", "Created","Resolved","Worklog");
	foreach my $this_epic (keys %All_Epics) {
		my $this_epic_id = $this_epic;
		($this_epic_id) =~ s-\'-\_-g;
		my $legend = $this_epic_id;
		($this_epic_id) =~ s-\s+-\_-g;
		my $nb_jira = 0;
		sap_sm_start_html_table($htmlFile,"epic2",$this_epic_id,$legend,@columnTitles);
		foreach my $jira ( @{$All_Epics{$this_epic}} ) {
			my $THIS_JIRA;
			# required, due to @{$THIS_JIRA->{'fields'}->{'worklog'}->{'worklogs'} does not exist in return value by Jira::REST :(
			if( -e "$OUTPUTS_JIRAS/$param_JIRA_PRJ/$jira") {
				sap_sm_read_json_jira($jira,$param_JIRA_PRJ,\$THIS_JIRA) ;
			}  else  {
				sap_sm_wget_json_jira($jira,$param_JIRA_PRJ,\$THIS_JIRA) ;
			}
			$nb_jira++;
			#epic
			my $this_epic;
			if($THIS_JIRA->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i) {
				if($THIS_JIRA->{'fields'}->{'summary'} !~ /legacy/i) {
					$this_epic = "xMake Support" ;
				}  else  {
					$this_epic = "Legacy" ;
				}
			}  else  {
				$this_epic = ($THIS_JIRA->{'fields'}->{'customfield_15140'}) ? sap_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "na" ;
			}
			if($this_epic eq "na") { # search in parent if parent
				$this_epic = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   ? sap_get_parent_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) : "na" ;
			}
			next if($this_epic =~ /^Legacy$/i);
			# write html
			if(open REPORT_HTML,">>$htmlFile") {
				print REPORT_HTML "\t<tr>";
				#jira id
				print REPORT_HTML "<td><a href=\"$jira_Url/browse/$THIS_JIRA->{key}\">$THIS_JIRA->{key}</a></td>";
				#type
				print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}</td>";
				#Epic link
				print REPORT_HTML "<td>$this_epic</td>";
				#summary
				#print "SUMMARY : $thisTakt - $THIS_JIRA->{key} - $THIS_JIRA->{'fields'}->{'summary'}\n";
				binmode(REPORT_HTML, ":utf8");
				print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'summary'}</td>";
				#status
				#print "SUMMARY : $thisTakt - $THIS_JIRA->{key} - $THIS_JIRA->{'fields'}->{'summary'}\n";
				print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'status'}->{'name'}</td>";
				#assignee
				my $assignee = ($THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'}) ? $THIS_JIRA->{'fields'}->{'assignee'}->{'displayName'} : "<font color=\"red\">Unassigned</font>";
				print REPORT_HTML "<td>$assignee</td>";
				#story point
				print REPORT_HTML "<td>$story_points</td>";
				#created
				my $displayCreated = $THIS_JIRA->{'fields'}->{'created'};
				($displayCreated) =~ s-T- -;
				($displayCreated) =~ s-\..+?$--;
				print REPORT_HTML "<td>$displayCreated</td>";
				#resolved
				my $displayClosed = " ";
				if($THIS_JIRA->{'fields'}->{'resolutiondate'}) {
					$displayClosed = $THIS_JIRA->{'fields'}->{'resolutiondate'};
					($displayClosed) =~ s-T- -;
					($displayClosed) =~ s-\..+?$--;
				}
				print REPORT_HTML "<td>$displayClosed</td>";
				#time spent
				my $totalTs = $THIS_JIRA->{'fields'}->{'timespent'};
				my $displayTimeSpent = ($totalTs  && ($totalTs>0)) ? sap_sm_seconds_to_hms($totalTs) : 0;
				print REPORT_HTML "<td>$displayTimeSpent</td>";
				print REPORT_HTML "</tr>\n";
			}
			undef $THIS_JIRA;
		}
		my $statToWrite = "<tr class=\"sortbottom\"><td colspan=\"12\">nb total jira: $nb_jira<br/>\n";
		$statToWrite .= "</td></tr>\n";
		sap_sm_write_stats_in_html($htmlFile,$statToWrite);
		sap_sm_close_html_table($htmlFile);
		sap_sm_close_html_section($htmlFile);
	}

	# charts
	if(open REPORT_HTML,">>$htmlFile") {
		print REPORT_HTML "\n<hr/><br/>\n";
		print REPORT_HTML "<center><h1>graphs in % per </h1></center><br/>\n";
		close REPORT_HTML;
	}
	foreach my $key (qw(nb sp ts)) {
		my $subtitle = $key;
		if ($key eq "nb") {
			$subtitle = "nb Jira";
		}
		if ($key eq "sp") {
			$subtitle = "Story Points";
		}
		if ($key eq "ts") {
			$subtitle = "Worklog";
		}
		my %data;
		foreach my $epic (keys %{$Epics_Name_counts{$key}}) {
			my $epic2 = $epic;
			($epic2) =~ s-\'-\\\'-g;
			$data{$epic2} = "$Epics_Name_counts{$key}{$epic},0";
		}
		sap_sm_pie_chart($param_JIRA_PRJ,"REPORT_HTML",$htmlFile,"pie_chart_epic_$key","$subtitle",\%data);
	}
	sap_sm_close_html($htmlFile);
	print "\ndone, see $htmlFile\nalso in : http://$url_report:$port_report/Reports/$param_JIRA_PRJ/epics.html\n";
}

close STDERR  unless($Warnings);
exit;

##############################################################################
##############################################################################
##### my functions
sub sap_sm_date_to_seconds($$) {
    my ($Date2,$Time2) = @_;
    my ($hour,$min,$sec) = $Time2 =~ /^(\d+)\:(\d+)\:(\d+)$/;
    my ($Year,$Month,$Day) = $Date2 =~ /^(\d+)\-(\d+)\-(\d+)$/;
    $Month = $Month - 1;
    #print "$Date,$Time => $sec,$min,$hour,$Day,$Month,$Year\n";
    my @temps = ($sec,$min,$hour,$Day,$Month,$Year);
    use Time::Local;
    return timelocal(@temps);
}

sub sap_sm_seconds_to_hms($) {
    my ($totalsecondes) = @_;
    my $secondes = $totalsecondes % 60;
    my $minutes  = ($totalsecondes / 60) % 60;
    my $heures   = ($totalsecondes / (60 * 60));
    return sprintf "%02d:%02d:%02d",($heures, $minutes, $secondes);
}

sub sap_sm_seconds_to_decimalhour($) {
	my ($totalsecondes) = @_;
    my $secondes = $totalsecondes % 60;
    my $minutes  = ($totalsecondes / 60) % 60;
    my $heures   = ($totalsecondes / (60 * 60));
    my $dec_sec  =  $secondes / 3600;
    my $dec_min  =  $minutes  / 60;
    my $hour_dec = $heures + $dec_min + $dec_sec;
    $hour_dec = sprintf ("%0.2f", $hour_dec);
}

sub sap_sm_seconds_to_hours($) {
    my ($totalsecondes) = @_;
    my $hours = $totalsecondes / 3600;
    return sprintf "%.2f", $hours;
}

#html
sub sap_sm_begin_html($$) {
    my ($file,$title) = @_;
    sap_sm_force_rm("$file") if( -e "$file");
    if(open REPORT_HTML,">$file") {
    	print "\ncreate $file\n";
        my ($Local_Sec,$Local_Min,$Local_Hour,$Local_Day,$Local_Month,$Local_Year,$wday,$yday,$isdst) = localtime time;
        $Local_Year  = $Local_Year  + 1900;
        $Local_Month = $Local_Month + 1;
        $Local_Month     = "0$Local_Month"    if ($Local_Month < 10);
        $Local_Day       = "0$Local_Day"      if ($Local_Day   < 10);
        $Local_Hour      = "0$Local_Hour"     if ($Local_Hour  < 10);
        $Local_Min       = "0$Local_Min"      if ($Local_Min   < 10);
        $Local_Sec       = "0$Local_Sec"      if ($Local_Sec   < 10);
        #print REPORT_HTML '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
        my ($end_takt_year,$end_takt_month,$end_takt_day) = split '-',$Takts{$currentTakt}{end};
        print REPORT_HTML '<!DOCTYPE HTML>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <title>',$title,'</title>
    <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
    <link rel="icon" type="image/png" href="./images/SAP_icon.png" />
    <!--[if IE]><link rel="shortcut icon" type="image/x-icon" href="./images/SAP_icon.png"/><![endif]-->
    <link rel="stylesheet" type="text/css" href="./js/sortable/sortable.css"/>
    <script type="text/javascript" src="./js/jquery/dist/jquery.min.js"></script>
    <script type="text/javascript" src="./js/highcharts/highcharts.js"></script>
    <script type="text/javascript" src="./js/highcharts/modules/exporting.js"></script>
    <script type="text/javascript" src="./js/modules/data.js"></script>
    <script type="text/javascript" src="./js/modules/drilldown.js"></script>
    <script type="text/javascript" src="./js/modules/exporting.js"></script>
    <script type="text/javascript" src="./js/sortable/sortable.js"></script>
</head>
<body>
<br/>
<h1 align="center">',$title,'</h1>
<h3 align="center">',$Local_Day,'/',$Local_Month,'/',$Local_Year,'</h3>

<center>
    <h3><a name="TaktTransparency-CurrentTaktCountdown"></a>Current Takt (<font color="blue">'.$currentTakt.'</font>) Countdown</h3>
    <br/>
</center>
<br/>

<!-- start report -->
';
    close REPORT_HTML;
    }
}

sub sap_sm_close_html($) {
    my ($file) = @_;
    if(open REPORT_HTML,">>$file") {
        print REPORT_HTML '
<br/>
</body>
</html>
';
        close REPORT_HTML;
    }
}

sub sap_sm_start_html_table($$$$@) {
    my ($file,$type,$takt,$legend,@columnTitles) = @_;
    if(open REPORT_HTML,">>$file") {
        my $divID = "${type}_takt_$takt";
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
                }  else  {
                    print REPORT_HTML "<th class=\"startsort\">$title</th>";
                }
            }  else  {
                print REPORT_HTML "<th>$title</th>";
            }
        }
        print REPORT_HTML "</tr>\n";
        close REPORT_HTML;
    }
}

sub sap_sm_start_RTS_html_table($$$$$@) {
    my ($file,$type,$takt,$legend,$subSection,@columnTitles) = @_;
    if(open REPORT_HTML,">>$file") {
        my $divID = "${type}_takt_$takt";
        print REPORT_HTML '
<fieldset style="border-style:solid;border-color:black;border-size:1px"><legend onclick="document.getElementById(\''.$divID.'\').style.display = (document.getElementById(\''.$divID.'\').style.display==\'none\') ? \'block\' : \'none\';" onmouseover="this.style.cursor=\'pointer\'" onmouseout="this.style.cursor=\'auto\'">'.$legend.'</legend>
<div id="'.$divID.'" style="display:none">
<br/>
'.$subSection.'
<table class="sortable" id="table_'.$divID.'" rules="all" style="border:1px solid black; margin-left:100px;" cellpadding="6">
';
        print REPORT_HTML "\t<tr>";
        my $first_line = 0;
        foreach my $title (@columnTitles) {
            $first_line++;
            if($first_line == 1) {
                if($title =~ /update/i) {
                    print REPORT_HTML "<th class=\"unsortable\">$title</th>";
                    $first_line = 0;
                }  else  {
                    print REPORT_HTML "<th class=\"startsort\">$title</th>";
                }
            }  else  {
                print REPORT_HTML "<th>$title</th>";
            }
        }
        print REPORT_HTML "</tr>\n";
        close REPORT_HTML;
    }
}

sub sap_sm_start_RTS_html_table2($$$$$@) {
    my ($file,$type,$takt,$legend,$subSection,@columnTitles) = @_;
    if(open REPORT_HTML,">>$file") {
        my $divID = "${type}_takt_$takt";
        print REPORT_HTML '
'.$subSection.'
<table class="sortable" id="table_rts_'.$divID.'" rules="all" style="border:1px solid black; margin-left:100px;" cellpadding="6">
';
        print REPORT_HTML "\t<tr>";
        my $first_line = 0;
        foreach my $title (@columnTitles) {
            $first_line++;
            if($first_line == 1) {
                if($title =~ /update/i) {
                    print REPORT_HTML "<th class=\"unsortable\">$title</th>";
                    $first_line = 0;
                }  else  {
                    print REPORT_HTML "<th class=\"startsort\">$title</th>";
                }
            }  else  {
                print REPORT_HTML "<th>$title</th>";
            }
        }
        print REPORT_HTML "</tr>\n";
        close REPORT_HTML;
    }
}


sub sap_sm_close_html_table($) {
    my ($file) = @_;
    if(open REPORT_HTML,">>$file") {
        print REPORT_HTML "</table><br/>\n";
        close REPORT_HTML;
    }
}

sub sap_sm_write_stats_in_html($$) {
    my ($file,$elem) = @_;
    if(open REPORT_HTML,">>$file") {
        print REPORT_HTML "$elem\n";
        close REPORT_HTML;
    }
}

sub sap_sm_close_html_section($) {
    my ($file) = @_;
    if(open REPORT_HTML,">>$file") {
        print REPORT_HTML "</div></fieldset><br/>\n";
        close REPORT_HTML;
    }
}

sub sap_sm_send_new_jiras_by_mail() {
	use Net::SMTP;
	$ENV{SMTP_SERVER} ||="mail.sap.corp";
	$SMTPFROM   ||= $ENV{SMTPFROM}  || "bruno.fablet\@sap.com";
	$SMTPTO     ||= $ENV{SMTPTO}        || "bruno.fablet\@sap.com ; julian.oprea\@sap.com";
	#$SMTPTO        ||= $ENV{SMTPTO};
	if($SMTPTO) {
		use Date::Calc qw[Add_Delta_Days Today];
		my ($this_year, $this_month, $this_day) = Today();
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
		my $Subject = "Subject: [$param_JIRA_PRJ] New Jira case(s) detected today, $this_day/$this_month/$this_year";
		$smtp->datasend("$Subject\n");
		$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=njc.html\n");
		open HTML, "$OUTPUTS_REPORTS/$param_JIRA_PRJ/njc.html" or confess "ERROR: cannot open '$OUTPUTS_REPORTS/$param_JIRA_PRJ/njc.html': $!";
		    while(<HTML>) { $smtp->datasend($_) }
		close HTML;
		$smtp->dataend();
		$smtp->quit();
		print "mail sent to $SMTPTO\n";
	}
}

sub sap_sm_print_reports($$$) {
    my ($file,$missing_elem,$results) = @_ ;
    my @skipJira = ();
    if(($missing_elem eq "no_ts") || ($missing_elem eq "no_sp")){
        my $nb_jira = 0;
        foreach my $THIS_JIRA (sort @$results) {
            my $full_jira;
            sap_sm_wget_json_jira($THIS_JIRA->{key},$param_JIRA_PRJ,\$full_jira);
            my $skip_jira = 0 ;
            foreach my $comment (@{$full_jira->{'fields'}->{'comment'}->{'comments'}}) {
                if($comment->{'body'} =~ /no\s+need\s+to\s+log\s+work/i) {
                    $skip_jira = 1 ;
                    push @skipJira , $THIS_JIRA->{key} ;
                    last;
                }
            }
            next if ($skip_jira == 1);
            $nb_jira++;
        }
        my @columnTitles = ("Jira ID" , "Status", "Fix Version(s)" , "Priority" , "Type" , "Epic Link" , "Component(s)" , "Summary" , "Assignee" , "Created" , "Reporter" , "WorkLog" , "Story Points");
        my $htmlFile  = "$OUTPUTS_REPORTS/$param_JIRA_PRJ/alerts.html";
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
        sap_sm_start_html_table($htmlFile,$id_table,$currentTakt,"$legend ($nb_jira Jira(s)&nbsp;)",@columnTitles);
    }
    if(open REPORT_HTML,">>$file") {
        foreach my $THIS_JIRA (sort @$results) {
            my $full_jira;
            next if ( grep /^$THIS_JIRA->{key}$/ , @skipJira );
            sap_sm_read_json_jira($THIS_JIRA->{key},$param_JIRA_PRJ,\$full_jira);
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
            }  elsif ($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^critical$/i)  {
                print REPORT_HTML "<td><font color=\"#A52A2A\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
            }  elsif ($THIS_JIRA->{'fields'}->{'priority'}->{'name'} =~ /^major$/i)  {
                print REPORT_HTML "<td><font color=\"#FFA500\">$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</font></td>";
            }  else  {
                print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'priority'}->{'name'}</td>";
            }
            print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'issuetype'}->{'name'}</td>";
            my $epicLinkTitle = ($THIS_JIRA->{'fields'}->{'customfield_15140'}) ? sap_get_title_of_epicLink($THIS_JIRA->{'fields'}->{'customfield_15140'}) : "na" ;
			if($epicLinkTitle eq "na") { # search in parent if parent
				$epicLinkTitle = ($THIS_JIRA->{'fields'}->{'parent'}->{'key'})   ? sap_get_parent_title_of_epicLink($THIS_JIRA->{'fields'}->{'parent'}->{'key'}) : "na" ;
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
            }  else  {
                print REPORT_HTML "<td><font color=\"red\">Unassigned</font></td>";
            }
            my $displayCreated = $THIS_JIRA->{'fields'}->{'created'};
            ($displayCreated) =~ s-T- -;
            ($displayCreated) =~ s-\..+?$--;
            print REPORT_HTML "<td>$displayCreated</td>";
            print REPORT_HTML "<td>$THIS_JIRA->{'fields'}->{'reporter'}->{'displayName'}</td>";
            my $totalTs = $THIS_JIRA->{'fields'}->{'timespent'};
            my $displayTimeSpent = ($totalTs  && ($totalTs>0)) ? sap_sm_seconds_to_hms($totalTs) : "<font color=\"red\">0</font>";
            print REPORT_HTML "<td>$displayTimeSpent</td>";
            my $story_points = ($THIS_JIRA->{'fields'}->{'customfield_10013'}) ? $THIS_JIRA->{'fields'}->{'customfield_10013'} : 0 ;
            print REPORT_HTML "<td>$story_points</td>";
            
            print REPORT_HTML "</tr>\n";
        }
        sap_sm_close_html_table($file);
        if(open REPORT_HTML,">>$file") {
            print REPORT_HTML "</div>\n";
            close REPORT_HTML;
        }
        sap_sm_close_html_section($file);
    }
}

sub sap_get_parent_title_of_epicLink($) {
	my ($jira) = @_;
	my $label;
	my $request = "key = $jira";
	my @results = sap_sm_jql($request);
	foreach my $THIS_sub_JIRA (@results) {
		if($THIS_sub_JIRA->{'fields'}->{'customfield_15140'}) {
			$label = sap_get_title_of_epicLink($THIS_sub_JIRA->{'fields'}->{'customfield_15140'}) ;
			last;
		}
	}
	return $label if($label);
}

sub sap_get_title_of_epicLink($) {
    my ($epicLink) = @_;
    my $title;
    if($epicLink) {
        my $request = "key = $epicLink";
        my @results = sap_sm_jql($request);
        foreach my $THIS_sub_JIRA (@results) {
            next if($THIS_sub_JIRA->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
            $title = $THIS_sub_JIRA->{'fields'}->{'customfield_15141'};
            last;
        }
    }
    return $title if($title);
}

sub sap_is_bisextil($) {
	my ($year) = @_ ;
	return ( (($year & 3) == 0) && (($year % 100 != 0) || ($year % 400 == 0)) );
}
