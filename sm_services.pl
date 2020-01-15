#!/softs/perl/latest/bin/perl

##############################################################################
##############################################################################
##### declare uses
# ensure quality
#use strict;
use warnings;
use diagnostics;
use Carp qw(cluck confess); # to use instead of (warn die)

# for the script itself
use Data::Dumper;
use JSON;
use JSON::MaybeXS ();
use Switch;


# opt/parameters
use Getopt::Long;

# personal uses
use sm_queries;



##############################################################################
##############################################################################
##### declare vars
## Options/Parameters
# options
use vars qw (
	$opt_List_Watchers
	$opt_Add_Watcher
	$opt_Remove_Watcher
	$param_watchers
	$param_jira_users
);



##############################################################################
##############################################################################
##### declare subs
sub sm_get_jiras_of_jira_user();
sub sm_action_watcher($);
sub sm_list_watchers();



##############################################################################
##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
	"prj=s"       =>\$param_project,
	"site=s"      =>\$param_site,
	"X"           =>\$opt_debug,
	"fl"          =>\$opt_force_login,
	"watchers=s"  =>\$param_watchers,
	"users=s"     =>\$param_jira_users,
	"jira=s"      =>\$param_this_jira,
	"A"           =>\$opt_Add_Watcher,
	"R"           =>\$opt_Remove_Watcher,
	"L"           =>\$opt_List_Watchers,
);



##############################################################################
##############################################################################
##### inits
$param_project ||= $ENV{SM_PROJECT} || "DTXMAKE";
$CouchDB_DB      = lc $param_project;
$param_site    ||= $ENV{SM_SITE}    || "LVL";



sm_inits();
$jira_Project_Members = ($param_jira_users) ? $param_jira_users : $jira_Project_Members ;



##############################################################################
##############################################################################
##### MAIN
sm_start_script();

sm_display_main_info();

print "\n\tWatchers Option\n";
print   "\t===============\n";

if($opt_Add_Watcher or $opt_Remove_Watcher) {
	unless($param_watchers) {
		confess "\nERROR : a watcher user id is missing, it is mandatory\n\n";
	}
}

if($opt_List_Watchers)  {
	sm_list_watchers();
}
if($opt_Add_Watcher)    {
	sm_action_watcher("add");
}
if($opt_Remove_Watcher) {
	sm_action_watcher("remove");
}

sm_end_script();



##############################################################################
##############################################################################
##### functions

sub sm_get_jiras_of_jira_user() {
	my $request = 'project = '.$param_project.' AND status in (Open, "To Do", "In Progress", "In Waiting", "In Waiting for IT", Blocked) AND assignee = '.$param_jira_users.' AND Sprint = "Focus '.$Current_Sprint.'" ORDER BY key DESC';
	my @results = sm_jql($request);
	my @tmp_list_jira;
	foreach my $issue (@results) {
		next if($issue->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
		next if($issue->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i);
		if ($issue->{key}) {
			push @tmp_list_jira , $issue->{key} ;
		}
	}
	return @tmp_list_jira if( scalar @tmp_list_jira > 0);
}

sub sm_action_watcher($) {
	my ($action) = @_   ;
	my @list_jiras = () ;
	unless($param_this_jira) {
		if($param_jira_users) {
			@list_jiras = sm_get_jiras_of_jira_user
		} else {
			confess "\nERROR : a Jira, or a list of Jira is missing, or a jira user is missing, jira list of jira member is mandatory\n\n";
		}
		
	} else {
		@list_jiras   = split ',' , $param_this_jira ;
	}

	#if add
	print "add watcher(s) per Jira\n"    if($action eq "add");
	sm_jira_perl_login_method2()         if($action eq "add");
	#if remove
	print "remove watcher(s) per Jira\n" if($action eq "remove");
	sm_jira_perl_login_method3()         if($action eq "remove");

	foreach my $this_jira (@list_jiras) {
		my @list_watchers = split ',' , $param_watchers ;
		foreach my $this_watcher (@list_watchers) {
			#if add
			print "add $this_watcher as watcher, for $jira_Url/browse/$this_jira\n" if($action eq "add");
			$jira_Connexion_method2->add_issue_watchers($this_jira, $this_watcher)  if($action eq "add");
			#if remove
			print "remove watcher $this_watcher for $jira_Url/browse/$this_jira\n"  if($action eq "remove");
			$jira_Connexion_method3->unwatch_issue($this_jira, $this_watcher)       if($action eq "remove");
		}
	}
}

sub sm_list_watchers() {
	if($param_this_jira) {
		print "List per Jira\n";
		$param_this_jira = uc $param_this_jira ;
		my @list_jiras   = split ',' , $param_this_jira ;
		sm_jira_perl_login_method2();
		foreach my $this_jira (@list_jiras) {
			print "\n----$this_jira----\n";
			print "url : $jira_Url/browse/$this_jira\n";
			print "watcher(s):\n";
			my $watchers = $jira_Connexion_method2->get_issue_watchers($this_jira,1);
			my $found_watchers = 0;
			foreach my $array_watchers (@{$watchers}) {
				print "\t$array_watchers->{'displayName'}\n";
				$found_watchers++;
			}
			if( $found_watchers == 0 ) {
				print "\tno watcher found\n";
			}
			print "\n";
		}
	}
	else {
		if($param_watchers) {
			print "List per Member\n";
			my @list_watchers = split ',' , $param_watchers ;
			foreach my $this_jira_user (@list_watchers) {
				# 1 get Jira user info
				my $displayName = "";
				my $request1 = "project = $param_project AND assignee = $this_jira_user ORDER BY key ASC";
				my @results1 = sm_jql($request1);
				foreach my $issue (@results1) {
					$displayName = $issue->{'fields'}->{'assignee'}->{'displayName'};
					last;
				}
				# 2 get watchers
				my $request2 = 'project = '.$param_project.' AND status in (Open, "To Do", "In Progress", "In Waiting", "In Waiting for IT", Blocked) AND assignee = '.$this_jira_user.' AND Sprint = "Focus '.$Current_Sprint.'" ORDER BY key DESC';
				my @results2 = sm_jql($request2);
				print "\n";
				if($displayName) {
					print "$displayName";
				}
				else {
					print "$param_watchers";
				}
				print " - Sprint = \"Focus $Current_Sprint\"\n";
				sm_jira_perl_login_method2();
				foreach my $issue (@results2) {
					next if($issue->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
					next if($issue->{'fields'}->{'summary'} =~ /Misc\s+Support\s+Activities/i);
					print "\t$issue->{key} - $issue->{'fields'}->{'summary'} - $issue->{'fields'}->{'status'}->{'name'}\n";
					print "\turl : $jira_Url/browse/$issue->{key}\n";
					my $watchers = $jira_Connexion_method2->get_issue_watchers($issue->{key},1);
					#print Dumper $watchers;
					my $found_watchers = 0;
					foreach my $array_watchers (@{$watchers}) {
						print "\t\t$array_watchers->{'displayName'}\n";
						$found_watchers++;
					}
					if($found_watchers == 0) {
						print "\t\tno watcher found\n";
					}
					print "\n";
				}
			}
		}
	}
	print "\n";
}
