##############################################################################
##### declare uses

## basics to ensure good quality and get good messages in runtime.
## basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

use DateTime;
use DateTime::TimeZone;
use HTTP::Tiny;
use Sort::Versions;
use Carp qw(cluck confess);
use File::Fetch;
use Net::SMTP;
use JSON qw( decode_json );
use Data::Dumper;
use Getopt::Long;

## internal use
use sap_sm_jira;


#############################################################################
##### declare vars
#for script it self
use vars qw (
	$out_gen_dir
	$htmlFile
	$Warnings
);

# for mail
use vars qw (
	$SMTP_SERVER
	$smtp
	$mail_From
	$mail_To
	$mail_Cc
	$mail_Bcc
	$mail_Subject
);

#############################################################################
##### declare functions
sub sap_main();
sub sap_get_mail_infos();
sub sap_write_mail();
sub sap_send_mail();



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
	"rv=s"       =>\$param_released_version,
	"warn"       =>\$Warnings,
);



#############################################################################
##### init var
# jira
local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0 ;
$out_gen_dir = $ENV{XMAKE_GENDIR} || "../gen";
if( ! -e $out_gen_dir) {
	mkdir $out_gen_dir;
}
$htmlFile = "$out_gen_dir/Mail.html";



#############################################################################
##### MAIN
sap_main();
exit 0;




#############################################################################
### internal functions
sub sap_main() {
	open STDERR,"> /dev/null" unless($Warnings);
	print "

START of $0

";

	sap_get_mail_infos();
	sap_write_mail();
	sap_send_mail();

	print "

END of $0

";
	close STDERR unless($Warnings);
}

sub sap_get_mail_infos() {
	if (open INFO , "./mail_missed_infos.txt") {
		while(<INFO>) {
			chomp;
			next if(/^\#/);  # skip comment line started by '#'
			next unless($_); # skip empty line
			if(/^SMTP_SERVER:\s+(.+?)$/) {
				$SMTP_SERVER = $1;
			}
			if(/^From:\s+(.+?)$/) {
				$mail_From = $1;
			}
			if(/^To:\s+(.+?)$/) {
				$mail_To = $1;
			}
			if(/^Cc:\s+(.+?)$/) {
				$mail_Cc = $1;
			}
			if(/^Bcc:\s+(.+?)$/) {
				$mail_Bcc = $1;
			}
			if(/^Subject:\s+(.+?)$/) {
				($mail_Subject = $1 )  =~ s-\$RELEASED\_VERSION-$param_released_version-gi;
			}
		}
		close INFO;
	}
	if( $ENV{TESTS} && ($ENV{TESTS} =~ /^yes$/) ) {
		$mail_To = "bruno.fablet\@sap.com";
		undef $mail_Bcc if($mail_Bcc);
		undef $mail_Cc  if($mail_Cc);
	}
}

sub sap_write_mail () {
	unlink $htmlFile if( -e $htmlFile );
	if (open HTML , ">$htmlFile") {
		if (open TEMPLATE , "./mail_missed_template.html") {
			while(<TEMPLATE>) {
				chomp;
				s-\$RELEASED_VERSION-$param_released_version-g if(/\$RELEASED_VERSION/);
				print HTML $_,"\n";
			}
			close TEMPLATE;
		}
		close HTML ;
	}
}

sub sap_send_mail() {
	print "From: $mail_From\n";
	print "To: $mail_To\n";
	print "Cc: $mail_Cc\n"   if($mail_Cc);
	print "Bcc: $mail_Bcc\n" if($mail_Bcc);
	print "Subject: $mail_Subject\n";

	my $jira_User       ||= `prodpassaccess get jira user`;
	chomp $jira_User;
	my $jira_Password   ||= `prodpassaccess get jira password`;
	chomp $jira_Password;

	if( $ENV{TESTS} && ($ENV{TESTS} =~ /^yes$/) ) {    # test mode
		$smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>90, Debug=>1,);
		print "ici 1: ",$smtp->message();
		print $smtp->domain,"\n";
		print $smtp->banner(),"\n";
		$smtp->hello($smtp->domain);
		print "ici 2: ",$smtp->message();
		$smtp->auth($jira_User, $jira_Password);
		print "ici 3: ",$smtp->message();
		$smtp->mail($mail_From);
		print "ici 4: ",$smtp->message();
		$smtp->auth($jira_User, $jira_Password);
		print "ici 3.1: ",$smtp->message();
		$smtp->to(split '\s*;\s*'  , $mail_To);
		#$smtp->cc(split  '\s*;\s*' , $mail_Cc)  if($mail_Cc);
		#$smtp->bcc(split '\s*;\s*' , $mail_Bcc) if($mail_Bcc);
		print "ici 5: ",$smtp->message();
		$smtp->data();
		print "ici 6: ",$smtp->message();
		$smtp->datasend("To: $mail_To\n");
		$smtp->datasend("Cc: $mail_Cc\n")  if($mail_Cc);
		print "ici 7: ",$smtp->message();
		$smtp->datasend("Subject: $mail_Subject\n");
		print "ici 8: ",$smtp->message();
		$smtp->datasend("Importance: High\n");
		print "ici 8.1: ",$smtp->message();
		$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.html\n");
		print "ici 9: ",$smtp->message();
		open HTML, "$htmlFile"  or confess "\n\nERROR: cannot open '$htmlFile': $!\n\n";
			while(<HTML>) { $smtp->datasend($_) }
		close HTML;
		print "ici 10: ",$smtp->message();
		$smtp->dataend();
		print "ici 11: ",$smtp->message();
		$smtp->quit();
	}
	else { ## prod mode
		$smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>90, Debug=>1,);
		$smtp->hello($smtp->domain);
		$smtp->mail($mail_From);
		$smtp->auth($jira_User, $jira_Password);
		$smtp->to(split  '\s*;\s*' , $mail_To);
		$smtp->cc(split  '\s*;\s*' , $mail_Cc)  if($mail_Cc);
		$smtp->bcc(split '\s*;\s*' , $mail_Bcc) if($mail_Bcc);
		$smtp->data();
		$smtp->datasend("To: $mail_To\n");
		$smtp->datasend("Cc: $mail_Cc\n")       if($mail_Cc);
		$smtp->datasend("Subject: $mail_Subject\n");
		$smtp->datasend("Importance: High\n");
		$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.html\n");
		open HTML, "$htmlFile"  or confess "\n\nERROR: cannot open '$htmlFile': $!\n\n";
			while(<HTML>) { $smtp->datasend($_) }
		close HTML;
		$smtp->dataend();
		$smtp->quit();
	}
	print "\nMail Release Notes version '$param_released_version' MISSED sent\n";
}
