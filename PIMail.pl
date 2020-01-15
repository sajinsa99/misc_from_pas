#!/usr/bin/perl

use Getopt::Long;
use Net::SMTP;
use FindBin;
use lib ($FindBin::Bin);

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "context=s"=>\$Context, "number=s"=>\$BuildNumber, "project=s"=>\$Project);
Usage() if($Help);
unless($Context)     { print(STDERR "ERROR: -c.ontext parameter is mandatory.\n"); Usage() };
unless($BuildNumber) { print(STDERR "ERROR: -n.umber parameter is mandatory.\n"); Usage() };
unless($Project)     { print(STDERR "ERROR: -p.roject parameter is mandatory.\n"); Usage() };

die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
#$SMTPTO = $ENV{SMTPTO} || 'jean.maqueda@sap.com';
$SMTPTO = $ENV{SMTPTO} || 'jean.maqueda@sap.com;xiaohong.ding@sap.com;mei.tan@sap.com;bruno.fablet@sap.com;christophe.thiebaud@sap.com;louis.lecaroz@sap.com;julian.oprea@sap.com;youssef.bennani@sap.com;nathalie.magnier@sap.com;kitty.lam@sap.com;remy.andre@sap.com';
$OBJECT_MODEL = 32; 
if($^O eq "MSWin32")    { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64" : "win32_x86"  }
elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc"  }
elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64" : "aix_rs6000"  }
elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64" : "hpux_pa-risc" }
elsif($^O eq "linux")   { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64" : "linux_x86"  }

if(defined($Project)) { $ENV{PROJECT}=$Project; delete $ENV{DROP_DIR}; delete $ENV{IMPORT_DIR} } 
require Site;

########
# Main #
########

open(HTML, ">$TEMPDIR/PIMail$$.htm") or die("ERROR: cannot open '$TEMPDIR/PIMail$$.htm': $!");
print(HTML "<html xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:w=\"urn:schemas-microsoft-com:office:word\" xmlns:m=\"http://schemas.microsoft.com/office/2004/12/omml\" xmlns=\"http://www.w3.org/TR/REC-html40\">\n");
print(HTML "<head>\n");
print(HTML "<meta http-equiv=Content-Type content=\"text/html; charset=us-ascii\">\n");
print(HTML "<meta name=Generator content=\"Microsoft Word 12 (filtered medium)\">\n");
print(HTML "<style>\n");
print(HTML "<!--\n");
print(HTML "/* Font Definitions */\n");
print(HTML "\@font-face{font-family:Calibri;panose-1:2 15 5 2 2 2 4 3 2 4;}\n");
print(HTML "\@font-face{font-family:Verdana;panose-1:2 11 6 4 3 5 4 4 2 4;}\n");
print(HTML "/* Style Definitions */");
print(HTML "p.MsoNormal, li.MsoNormal, div.MsoNormal {margin:0in;margin-bottom:.0001pt;font-size:11.0pt;font-family:\"Calibri\",\"sans-serif\";}");
print(HTML "a:link, span.MsoHyperlink {mso-style-priority:99;color:blue;text-decoration:underline;}\n");
print(HTML "a:visited, span.MsoHyperlinkFollowed {mso-style-priority:99;color:purple;text-decoration:underline;}\n");
print(HTML "span.EmailStyle17 {mso-style-type:personal;font-family:\"Calibri\",\"sans-serif\";color:windowtext;}\n");
print(HTML "span.EmailStyle18 {mso-style-type:personal-reply;font-family:\"Calibri\",\"sans-serif\";color:#1F497D;}\n");
print(HTML ".MsoChpDefault {mso-style-type:export-only;font-size:10.0pt;}\n");
print(HTML "\@page Section1 {size:8.5in 11.0in;margin:1.0in 1.0in 1.0in 1.0in;}\n");
print(HTML "div.Section1 {page:Section1;}\n");
print(HTML "-->\n");
print(HTML "</style>\n");
print(HTML "<!--[if gte mso 9]><xml>\n");
print(HTML "<o:shapedefaults v:ext=\"edit\" spidmax=\"1026\" />\n");
print(HTML "</xml><![endif]--><!--[if gte mso 9]><xml>\n");
print(HTML "<o:shapelayout v:ext=\"edit\">\n");
print(HTML "<o:idmap v:ext=\"edit\" data=\"1\" />\n");
print(HTML "</o:shapelayout></xml><![endif]-->\n");
print(HTML "</head>\n");
print(HTML "<body lang=EN-US link=blue vlink=purple>\n");
print(HTML "<div class=Section1>\n");
print(HTML "<p class=MsoNormal><span style='font-size:10.0pt;font-family:\"Verdana\",\"sans-serif\";color:black'>*****This email has been sent from an unmonitored automatic mailbox.*****<o:p></o:p></span></p>\n");
print(HTML "<p class=MsoNormal><span style='font-size:10.0pt;font-family:\"Verdana\",\"sans-serif\";color:black'><o:p>&nbsp;</o:p></span></p>\n");
print(HTML "<p class=MsoNormal><span style='font-size:9.0pt;font-family:\"Arial\",\"sans-serif\"'>Hi everyone,<o:p></o:p></span></p>\n");
print(HTML "<p class=MsoNormal><span style='font-size:9.0pt;font-family:\"Arial\",\"sans-serif\"'><o:p>&nbsp;</o:p></span></p>\n");
print(HTML "<p class=MsoNormal><span style='font-size:9.0pt;font-family:\"Arial\",\"sans-serif\"'>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;The build <a href=\"http://lv-s-build01.product.businessobjects.com/cgi-bin/CISRedirect.pl?all=1&amp;area=&amp;tag=${Context}_$BuildNumber&amp;default=&amp;date=&amp;projects=&amp;streams=$Context\">${Context}_$BuildNumber</a> is the new greatest build for the platform $PLATFORM.<o:p></o:p></span></p>\n");
print(HTML "<p class=MsoNormal><span style='font-size:19.0pt;font-family:\"Arial\",\"sans-serif\"'><br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href=\"http://lv-s-build01.product.businessobjects.com/cgi-bin/CISRedirect.pl?all=1&amp;area=&amp;tag=${Context}_$BuildNumber&amp;default=&amp;date=&amp;projects=&amp;streams=$Context\">Click here</a> for the full status build.<br><br><o:p></o:p></span></p>\n");
print(HTML "<p class=MsoNormal><span style='font-size:9.0pt;font-family:\"Arial\",\"sans-serif\"'><o:p>&nbsp;</o:p></span></p>\n");
print(HTML "<p class=MsoNormal><span style='font-size:9.0pt;font-family:\"Arial\",\"sans-serif\"'>To import binaries<span style='color:#1F497D'> </span>without compilation use<span style='color:#1F497D'>: </span></span><span style='font-size:8.0pt;font-family:\"Courier New\";color:red'>$Context_<area name>/greatest.xml</span>\n");
print(HTML "<p class=MsoNormal><span style='font-size:9.0pt;font-family:\"Arial\",\"sans-serif\"'>For more information, look at the Aurora_assembling.ini<o:p></o:p></span></p>\n");
print(HTML "<p class=MsoNormal><span style='font-size:9.0pt;font-family:\"Arial\",\"sans-serif\"'><o:p>&nbsp;</o:p></span></p>\n");
print(HTML "<p class=MsoNormal><span style='font-size:9.0pt;font-family:\"Arial\",\"sans-serif\"'>Best regards<o:p></o:p></span></p>\n");
print(HTML "</div>\n");
print(HTML "</body>\n");
print(HTML "</html>\n");
close(HTML);

# Mail
$smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60);
$smtp->mail('PGEDCReleaseManagementTools@businessobjects.com');
$smtp->to(split('\s*;\s*', $SMTPTO));
$smtp->data();
$smtp->datasend("To: $SMTPTO\n");
$smtp->datasend("Subject: [$Context] new $PLATFORM greatest\n");
$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
open(HTML, "$TEMPDIR/PIMail$$.htm") or die ("ERROR: cannot open '$TEMPDIR/PIMail$$.htm': $!");
while(<HTML>) { $smtp->datasend($_) } 
close(HTML);
$smtp->dataend();
$smtp->quit();

unlink("$TEMPDIR/PIMail$$.htm") or die("ERROR: cannot unlink '$TEMPDIR/PIMail$$.htm': $!");

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : PIMail.pl [options]
   Example : PIMail.pl -h
             PIMail.pl -p=Aurora -c=PI_Aurora_tp.perl -n=00003

   [options]
   -help|?     argument displays helpful information about builtin commands.
   -c.ontext  specifies the context name.
   -n.umber   specifies the build number.
   -p.roject  specifies the project name.
USAGE

	exit;
}
