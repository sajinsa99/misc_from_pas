#!/softs/perl/latest/bin/perl

##############################################################################
##############################################################################
##### declare uses
# ensure code quality
#use strict;
use warnings;
use diagnostics;
use Carp qw(cluck confess); # to use instead of (warn die)

# for the script itself
use JSON;
use Switch;
use File::Path;
use Data::Dumper;
use JSON::MaybeXS ();

# opt/parameters
use Getopt::Long;

# cutom perl modules
use sm_queries;
use sm_reports;
use sm_html;
use sm_velocity;



##############################################################################
##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
	"prj=s"      =>\$param_project,
	"site=s"     =>\$param_site,
	"X"          =>\$opt_debug,
	"fl"         =>\$opt_force_login,
	"member=s"   =>\$param_member,
	"request=s"  =>\$param_request,
	"nomail"     =>\$opt_No_Mail,
	"mail_alert" =>\$opt_MailAlert,
);



##############################################################################
##############################################################################
##### inits
$param_project ||= $ENV{SM_PROJECT} || "DTXMAKE";
$CouchDB_DB      = lc $param_project;
$param_site    ||= $ENV{SM_SITE}    || "LVL";



sm_inits();
$jira_Project_Members      = ($param_member) ? $param_member : $jira_Project_Members ;

# news
$output_new_jira_mail_file = "$REPORTS_SM_DIR/$param_project/$param_site/news.html";

# alerts
$output_html_alert_file  = "$REPORTS_SM_DIR/$param_project/$param_site/alerts.html";
@column_titles_alerts    = ("Jira ID" , "Status", "Fix Version(s)" , "Priority" , "Type" , "Epic Link" , "Component(s)" , "Summary" , "Assignee" , "Created" , "Reporter" , "WorkLog", "Story Points");

unless ( -e "$REPORTS_SM_DIR/$param_project/$param_site") {
	mkpath "$REPORTS_SM_DIR/$param_project/$param_site"
		or confess "\n\nERROR : cannot mkpath '$REPORTS_SM_DIR/$param_project/$param_site' : $!\n\n";
}



##############################################################################
##############################################################################
##### MAIN
sm_start_script();

sm_display_main_info();
if($param_request) {
	# 1 run queries
	mkpath "$LOG_SM_DIR/$param_project/$param_site" if ( ! -e "$LOG_SM_DIR/$param_project/$param_site" );
	my $queries_hRef = sm_get_available_queries($param_request);
	foreach my $this_query_hRef (  @{$queries_hRef->{projects}} ) {
		if($this_query_hRef->{project} =~ /$param_project/i) {
			foreach my $query (@{$this_query_hRef->{queries}}) {
				if($query->{label} =~ /$param_request/i) {
					my $cmd = "cd $BASE_SM_DIR/scripts ; perl -w sm_queries.pl -s=$param_site -p=$param_project -r=$param_request";
					$cmd   .= " -m=$param_member" if( $param_member && ($param_request !~ /^news$/i) );
					$cmd   .= " -X"               if($opt_debug);
					$cmd   .= " -fl"              if($opt_force_login);
					print "cmd : $cmd" if($opt_debug);
					system "$cmd >& $LOG_SM_DIR/$param_project/$param_site/$param_request.log";
					if( $opt_debug && ( -e "$LOG_SM_DIR/$param_project/$param_site/$param_request.log") ) {
						print "\n==========\n";
						system "cat $LOG_SM_DIR/$param_project/$param_site/$param_request.log";
						print "\n==========\n\n";
					}
					last;
				}
			}
			last;
		}
	}
	# 2 run specfic functions per query
	switch ($param_request) {
		case /^news$/i		{ sm_news();          }
		case /^alerts$/i	{ sm_alerts();        }
		case /^begin$/i	    { sm_sprint("begin"); }
		case /^end$/i	    { sm_sprint("end");   }
		case /^delta$/i	    { sm_velocity();      }
		else                { confess "ERROR : $param_request unknow" }
	}
}

sm_end_script();
