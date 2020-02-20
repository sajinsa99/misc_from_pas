package sap_sm_jira;
##############################################################################
##### declare uses

## basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

## other use
use Exporter;
use JSON qw( decode_json );
use Data::Dumper;
use DateTime;
use DateTime::TimeZone;
use HTTP::Tiny;
use Sort::Versions;
use Carp qw(cluck confess);
use File::Fetch;
use JIRA::REST;
use JIRA::Client::Automated;



#############################################################################
##### declare vars

# for the script itself
use vars qw (
	$comment
	@ISA
	@EXPORT
);

# options/parameters
use vars qw (
	$param_jira_list
	$param_released_version
);

# jira
use vars qw (
	$jira_Url
	$jira_User
	$jira_Password
	$jira_Connexion
	@LIST_JIRAS
);



#############################################################################
##### declare functions
sub sap_get_credentials();
sub sap_jira_login();
sub sap_set_comment();
sub sap_get_title_of_epicLink($);
sub sap_get_jira_title($);



##############################################################################
##############################################################################
##### init vars
# jira
$jira_Url = $ENV{JIRA_URL};
local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0 ;



@ISA    = qw(Exporter);
@EXPORT = qw (
	$comment
	$param_jira_list
	$param_released_version
	$jira_Connexion
	$jira_Url
	@LIST_JIRAS
	&sap_jira_login
	&sap_set_comment
	&sap_get_title_of_epicLink
	&sap_get_jira_title
);



#############################################################################
### internal functions
sub sap_get_credentials() {
	my $jira_Project       = $ENV{JIRA_PROJECT}       || "dtxmake";
	my $CREDENTIALS_SM_DIR = $ENV{CREDENTIALS_SM_DIR} || "$ENV{HOME}/.prodpassaccess" ;
	$jira_User       ||= `prodpassaccess --credentials-root $CREDENTIALS_SM_DIR get jira.$jira_Project user`;
	chomp $jira_User;
	$jira_Password   ||= `prodpassaccess --credentials-root $CREDENTIALS_SM_DIR get jira.$jira_Project password`;
	chomp $jira_Password;
}

sub sap_jira_login() {
	sap_get_credentials();
	$jira_Connexion = JIRA::Client::Automated->new($jira_Url, $jira_User, $jira_Password);
	unless($jira_Connexion) {
		print "ERROR : issue connecting to $jira_Url, as $jira_User\n";
		exit 1;
	}
	else {
		print "Connexion to $jira_Url, as $jira_User OK\n";
	}
}

sub sap_set_comment() {
	if(open TXT , "./template_comment.txt") {
		#$jira_Connexion->create_comment($jira_test, $comment);
		while(<TXT>) {
			chomp;
			next if(/^\#/);  # skip comment line started by '#'
			next unless($_); # skip empty line
			s-\$RELEASED\_VERSION-$param_released_version-gi;
			$comment = $_;
			last;
		}
		close TXT;
	}
}

sub sap_get_title_of_epicLink($) {
	my ($epicLink) = @_;
	my $title;
	if($epicLink) {
		my $issue = $jira_Connexion->get_issue($epicLink);
		if( ! ($issue->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i) ) {
			$title = $issue->{'fields'}->{'summary'};
		}
	}
	$title = ($title) ? $title : "(n/a)";
	return $title;
}

sub sap_get_jira_title($) {
	my ($this_jira) = @_;
	local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0 ;
	sap_jira_login();
	my $title;
	if($this_jira) {
		my $issue = $jira_Connexion->get_issue($this_jira);
		if( ! ($issue->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i) ) {
			$title = $issue->{'fields'}->{'summary'};
		}
	}
	$title = ($title) ? $title : " ";
	return $title;
}

1;
