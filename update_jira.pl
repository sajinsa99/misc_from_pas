##############################################################################
##### declare uses

## basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

## other use
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

# for the script itself
use vars qw (
	$comment
);

# options/parameters
use vars qw (
	$param_jira_list
	$param_released_version
);



#############################################################################
##### declare functions
sub sap_main();
sub sap_manage_jira();
sub sap_tests();



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "jl=s"       =>\$param_jira_list,
    "rv=s"       =>\$param_released_version,
);



#############################################################################
##### init var
# jira
local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0 ;
@LIST_JIRAS = split ',' ,  $param_jira_list;



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

	sap_jira_login();
	sap_set_comment();
	if( $ENV{TESTS} && ($ENV{TESTS} =~ /^yes$/) ) {
		sap_tests();
	}
	else {
		sap_manage_jira();
	}

	print "

END of $0

";
}

sub sap_tests() {
	print "\n\t$param_released_version\n";
	print "comment: $comment\n\n";
	if( $ENV{TESTS} && ($ENV{TESTS} =~ /^yes$/) ) {
		print "\n\tTEST mode : jira status won't be updated\n";
	}
	foreach my $jira_case (sort @LIST_JIRAS) {
		eval {
			my $issue  = $jira_Connexion->get_issue($jira_case);
			my $status = $issue->{'fields'}->{'status'}->{'name'};
			print "> $jira_case\n";
			print "\tadd comment";
			#$jira_Connexion->create_comment($jira_case, $comment);
			if($status =~ /In\s+Waiting\s+for\s+IT/i) {
				print " -> Set to Completed";
				#$jira_Connexion->close_issue($jira_case);
				print " -> Set to Consumed\n";
				#$jira_Connexion->transition_issue($jira_case, "Consumed");
			}
			else {
				if($status !~ /^Closed|Completed|Consumed|Resolved|Done|Abandoned$/i) {
					print " , inconsistent state of $jira_case ($status)\n";
				}
				else {
					print "\n";
				}
			}
		};
	}
	print "\n";
}

sub sap_manage_jira() {
	print "\n\t$param_released_version\n";
	print "comment: $comment\n\n";
	foreach my $jira_case (sort @LIST_JIRAS) {
		eval {
			my $issue  = $jira_Connexion->get_issue($jira_case);
			my $status = $issue->{'fields'}->{'status'}->{'name'};
			print "> $jira_case\n";
			print "\tadd comment";
			$jira_Connexion->create_comment($jira_case, $comment);
			if($status =~ /In\s+Waiting\s+for\s+IT/i) {
				print " -> Set to Completed";
				$jira_Connexion->close_issue($jira_case);
				print " -> Set to Consumed\n";
				$jira_Connexion->transition_issue($jira_case, "Consumed");
			}
			else {
				if($status !~ /^Closed|Completed|Consumed|Resolved|Done|Abandoned$/i) {
					print " , inconsistent state of $jira_case ($status)\n";
				}
				else {
					print "\n";
				}
			}
		};
	}
	print "\n";
}