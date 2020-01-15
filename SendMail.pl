#!/usr/bin/perl

use Getopt::Long;
use Net::SMTP;

$SMTPTO = 'jmaqueda@businessobjects.com';

use FindBin;
use lib ($FindBin::Bin, "$FindBin::Bin/site_perl");
use Perforce;
use Site;

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "mode=s"=>\$BUILD_MODE, "platform=s"=>\$Platform, "recipients=s"=>\$Recipients, "tag=s"=>\$BuildName);
Usage() if($Help);
unless($BuildName)  { print(STDERR "ERROR: -tag parameter is mandatory.\n"); Usage() };
$BUILD_MODE ||= "release";
$Platform   ||= "win32_x86";
if("debug"=~/^$BUILD_MODE/i) { $BUILD_MODE="debug" } elsif("release"=~/^$BUILD_MODE/i) { $BUILD_MODE="release" }
else { print(STDERR "ERROR: compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease]\n"); Usage() }
($Context, $BuildNumber) = $BuildName =~ /^(.+)_(\d+)$/;
$HTTPDIR = "$ENV{HTTP_DIR}/$Context/$BuildName";

########
# Main #
########

# Output #
open(HTML, ">$HTTPDIR/Mail=${Platform}_$BUILD_MODE.htm") or die("ERROR: cannot open '$HTTPDIR/Mail=${Platform}_$BUILD_MODE.htm': $!");
print(HTML "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0 Transitional//EN\">
<HTML><HEAD><TITLE>Mail Lib Email</TITLE>
<META http-equiv=Content-Type content=\"text/html; charset=us-ascii\">
<BODY>
<DIV class=OutlookMessageHeader lang=en-us dir=ltr align=left>
<FONT face=verdana color=black size=2>*****This email has been sent from an unmonitored automatic mailbox.*****<BR><br>
<FONT face=verdana color=navy size=2>You are receiving this email because you checked code into the indicated context recently. Please verify that your code didn't break the build. <BR><BR>
For more information : <A href=\"http://lv-s-build01.product.businessobjects.com/cgi-bin/CIS.pl?tag=$BuildName&streams=$Context\">http://lv-s-build01.product.businessobjects.com/cgi-bin/CIS.pl</A> or <a href=\"http://pgbuildreporting.product.businessobjects.com/\">http://pgbuildreporting.product.businessobjects.com/</a></BODY></HTML>");

# Mail #
$SMTPTO = "$Recipients;$ENV{SMTPTO_ROLL}" if($ENV{SMTPTO_ROLL});
my $smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60);
$smtp->mail('PGEDCReleaseManagementTools@businessobjects.com');
$smtp->to(split('\s*;\s*', $SMTPTO));
$smtp->data();
$smtp->datasend("To: $SMTPTO\n");
$smtp->datasend("Subject: [$Context] build rev.$BuildNumber status - $Platform $BUILD_MODE\n");
$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
open(HTML, "$HTTPDIR/Mail=${Platform}_$BUILD_MODE.htm") or die ("ERROR: cannot open '$HTTPDIR/Mail=${Platform}_$BUILD_MODE.htm': $!");
while(<HTML>) { $smtp->datasend($_) } 
close(HTML);
$smtp->dataend();
$smtp->quit();

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : SendMail.pl [options]
   Example : SendMail.pl -h
             SendMail.pl -t=IW_PI_Roll_3 -m=release -p=win32_x86

   [options]
   -help|?       argument displays helpful information about builtin commands.
   -m.ode        debug or release, default is release.
   -p.latform    specifies the platform name, default is win32_x86.
   -t.ag         specifies the build name.
   -r.ecipients  specifies the e-mail recipients. Syntax is -r=reciptient;...
USAGE

	exit;
}
