use warnings;
use diagnostics;

use JIRA::REST;
use JIRA::Client::Automated;


## internal use
use sap_sm_jira;

local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0 ;
sap_jira_login();

if($jira_Connexion) {
        print "\n\nConnexion successfully\n";
        my $jira_key = $ARGV[0] || "DTXMAKE-2046";
        my $issue = $jira_Connexion->get_issue($jira_key);
        my $title = $issue->{'fields'}->{'summary'};
        print "$jira_key : $title\n\n";
        exit 0;
}  else  {
        print "ERROR : not connected to Jira server\n";
        exit 1;
}
