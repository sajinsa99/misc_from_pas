#!/usr/bin/perl

use Getopt::Long;
use Tie::IxHash;
use Net::SMTP;
use XML::DOM;
#use P4;

use FindBin;
use lib ($FindBin::Bin, "$FindBin::Bin/site_perl");
use Site;

#$SMTPFROM = $ENV{SMTPFROM} || 'julian.oprea@sap.com';
$SMTPFROM = $ENV{SMTPFROM} || 'DL_011000358700001506162009E@exchange.sap.corp';
#$SMTPTO   = $ENV{SMTPTO};


##############
# Parameters #
##############

#Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "mode=s"=>\$BUILD_MODE, "platform=s"=>\$Platform, "tag=s"=>\$BuildName);
Usage() if($Help);

$BuildName  ||= $ENV{BUILD_NAME};
unless($BuildName)  { print(STDERR "ERROR: -tag parameter is mandatory.\n"); Usage() };

$BUILD_MODE ||= $ENV{BUILD_MODE} || "release";
$BUILD_MODE ||= "release";

$Platform   ||= $ENV{PLATFORM}   || "win32_x86";
my $Platform_current_build = $Platform ;

if("debug"=~/^$BUILD_MODE/i) { $BUILD_MODE="debug" } elsif("release"=~/^$BUILD_MODE/i) { $BUILD_MODE="release" } elsif("releasedebug"=~/^$BUILD_MODE/i) { $BUILD_MODE="releasedebug" }
else { print(STDERR "ERROR: compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease|releasedebug]\n"); Usage() }

($Context, $BuildNumber) = $BuildName =~ /^(.+)_0*(\d+\.?\d*)$/;
$HTTPDIR = "$ENV{HTTP_DIR}/$Context/$BuildName";

$HTTP_CIS = "http://cis_wdf.pgdev.sap.corp:1080/cgi-bin/CIS.pl";
$Project = $ENV{PROJECT};
$Site = $ENV{SITE};

my %HREFDROP;
my %HREFCIS;
my %SHORTNAMES;

#build table for mail
foreach my $thisSite (qw(Levallois Vancouver Bangalore Walldorf)) {
	$SHORTNAMES{$thisSite} = "LVL" if($thisSite eq "Levallois");
	$SHORTNAMES{$thisSite} = "VCR" if($thisSite eq "Vancouver");
	$SHORTNAMES{$thisSite} = "BLR" if($thisSite eq "Bangalore");
	$SHORTNAMES{$thisSite} = "WDF" if($thisSite eq "Walldorf");
	if(open(SITE,"Site.pm")) {
		while(<SITE>) {
			chomp;
			next if(/^\#/);
			#CIS path
			if(/^\$VARS2\{$thisSite\}\{win32_x86\}?\s*\{HTTP_DIR\}\s+\=\s+\"(.+?)\"/i) {
				my $path = "$1\\$Context\\$BuildName";
				($path) =~ s-\\\\-\\-g;
				($path) =~ s-\\-\/-g;
				if(($^O eq "MSWin32")) {
					if( -e "$path") {
						$HREFCIS{$thisSite} = $path;
					}
				} else { #if unix, no check
					$HREFCIS{$thisSite} = $path;
				}
			}
			if(/^\$VARS2\{$thisSite\}\{Unix\}?\s*\{HTTP_DIR\}\s+\=\s+\"(.+?)\"/i) {
				my $path = "$1/$Context/$BuildName";
				if($^O ne "MSWin32") {
					if( -e "$path") {
						($path) =~ s-^\/net\/-\/-i; # transfor m to windows
						$HREFCIS{$thisSite} ||= $path;
					}
				} # no else, no need unix path for mail
			}
			# DROPZONE path
			if(/^\$VARS3\{$thisSite\}\{win32_x86\}\{$Project\}\{IMPORT_DIR\}\s+\=\s+\"(.+?)\"/i) {
				my $path = "$1\\\\$Context\\\\$BuildNumber\\\\$Platform\\\\$BUILD_MODE";
				($path) =~ s-\\\\-\\-g;
				($path) =~ s-\\-\/-g;
				if(($^O eq "MSWin32")) {
					if( -e "$path") {
						$HREFDROP{$thisSite} = $path;
					}
				} else { #if unix, no check
					$HREFDROP{$thisSite} = $path;
				}
			}
			if(/^\$VARS3\{$thisSite\}\{Unix\}?\s*\{$Project\}\{IMPORT_DIR\}\s+\=\s+\"(.+?)\"/i) {
				my $path = "$1/$Context/$BuildNumber/$Platform/$BUILD_MODE";
				if($^O ne "MSWin32") {
					$HREFDROP{$thisSite} = $path if( -e "$path");
				} # no else, no need unix path for mail
			}
		}
		close(SITE);
	}
}



########
# Main #
########

tie my %areas, "Tie::IxHash";
opendir(LOGS, $HTTPDIR) or die("ERROR: cannot open '$HTTPDIR': $!");
$Errors = 0;
my $nb_errors_current_build = 0 ;
while(defined($File = readdir(LOGS)))
{
   	next unless(my($Platform, $Target, $Phase) = $File =~ /$BuildName=(.+)_(.+?)_(.+?)_\d+.dat/);
   
	next if($Phase eq "host");
	open(DAT, "$HTTPDIR/$File") or die("ERROR: cannot open '$HTTPDIR/$File': $!");
	eval <DAT>;
	close(DAT);
	next unless(defined($Errors[0]));
	$Errors += $Errors[0];
	if ($Phase ne "infra" and  $Platform eq $Platform_current_build)
	{
		$nb_errors_current_build += $Errors[0];
	}
	foreach my $raLogs (@Errors[1..$#Errors])
	{

		map({$Recipients{${$_}[0]} = ${$_}[1]} @{$Areas{"$Area"}}) if(exists($Areas{"$Area"}));
		my($Errors, $Log, $Txt, $Area, $Start, $Stop) = @{$raLogs};
		push(@{$Errors{"$Platform"}{"$Target"}{"$Phase"}{"$Area"}}, [$Errors, $Log, $Txt, $Start, $Stop]);
		$areas{"$Area"} = undef;
	}
}
close(LOGS);

if (lc($ENV{MAIL_ON_ERRORS_ONLY}) eq 'true'){
	MailOnErrorsOnly();
}

# HTML
open(HTML, ">$HTTPDIR/Mail=${Platform}_$BUILD_MODE.htm") or die("ERROR: cannot open '$HTTPDIR/Mail=${Platform}_$BUILD_MODE.htm': $!");
print(HTML '
<html xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns:p="urn:schemas-microsoft-com:office:powerpoint" xmlns:dt="uuid:C2F41010-65B3-11d1-A29F-00AA00C14882" xmlns:oa="urn:schemas-microsoft-com:office:activation" xmlns:html="http://www.w3.org/TR/REC-html40" xmlns:D="DAV:" xmlns:st1="urn:schemas-microsoft-com:office:smarttags" xmlns="http://www.w3.org/TR/REC-html40">

<head>
<meta http-equiv=Content-Type content="text/html; charset=iso-8859-1">
<meta name=Generator content="Microsoft Word 11 (filtered medium)">
<o:SmartTagType namespaceuri="urn:schemas-microsoft-com:office:smarttags"
 name="City" downloadurl="http://www.5iamas-microsoft-com:office:smarttags"/>
<o:SmartTagType namespaceuri="urn:schemas-microsoft-com:office:smarttags"
 name="place" downloadurl="http://www.5iantlavalamp.com/"/>
<!--[if !mso]>
<style>
st1\:*{behavior:url(#default#ieooui) }
</style>
<![endif]-->
<style>
<!--
 /* Font Definitions */
 @font-face
	{font-family:Wingdings;
	panose-1:5 0 0 0 0 0 0 0 0 0;}
@font-face
	{font-family:Batang;
	panose-1:2 3 6 0 0 1 1 1 1 1;}
@font-face
	{font-family:"\@Batang";
	panose-1:2 3 6 0 0 1 1 1 1 1;}
@font-face
	{font-family:Verdana;
	panose-1:2 11 6 4 3 5 4 4 2 4;}
 /* Style Definitions */
 p
	{margin:0in;
	margin-bottom:.0001pt;
	font-size:12.0pt;
	font-family:"Times New Roman";}
.spanStyle{
  font-size:8.0pt;
  font-family:Verdana;
}
.smokeTestTd{
  width:143.6pt;
  border:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt;
  height:12.7pt
}
.smokeTestTdCol2{
  width:441.0pt;
  border-top:none;
  border-left:none;
  border-bottom:solid #999999 1.0pt;
  border-right:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt;
  height:12.7pt
}
.pStyle{
  margin-left:.25in;
  text-indent:-.25in;
  mso-list:l0 level1 lfo1
}
.tdCol1{
  width:90.4pt;
  border:solid silver 1.0pt;
  padding:0in 5.4pt 0in 5.4pt
  }
.tdCol2{
	width:43.9pt;
  border:solid silver 1.0pt;
  border-left:none;
  border-bottom:solid silver 1.0pt;
  border-right:solid silver 1.0pt;
  padding:0in 5.4pt 0in 5.4pt
 }
.tdCol3{
  width:99.3pt;
  border:solid silver 1.0pt;
  border-left:none;
  padding:0in 5.4pt 0in 5.4pt
  }
.tdCol4{
  width:343.1pt;
  border:solid silver 1.0pt;
  border-left:none;
  padding:0in 5.4pt 0in 5.4pt
 
}
a:link, span.MsoHyperlink
	{color:blue;
	text-decoration:underline;}
a:visited, span.MsoHyperlinkFollowed
	{color:purple;
	text-decoration:underline;}
span.EmailStyle17
	{mso-style-type:personal-compose;
	font-family:Arial;
	color:windowtext;
	font-weight:normal;
	font-style:normal;
	text-decoration:none none;}
@page Section1
	{size:8.5in 11.0in;
	margin:1.0in 1.25in 1.0in 1.25in;}
div.Section1
	{page:Section1;}
 /* List Definitions */
 @list l0
	{mso-list-id:31150187;
	mso-list-type:hybrid;
	mso-list-template-ids:-684040698 -1619512052 67698691 67698693 67698689 67698691 67698693 67698689 67698691 67698693;}
@list l0:level1
	{mso-level-start-at:0;
	mso-level-number-format:bullet;
	mso-level-text:-;
	mso-level-tab-stop:.25in;
	mso-level-number-position:left;
	margin-left:.25in;
	text-indent:-.25in;
	font-family:Arial;
	mso-fareast-font-family:Batang;}
@list l0:level2
	{mso-level-number-format:bullet;
	mso-level-text:o;
	mso-level-tab-stop:.75in;
	mso-level-number-position:left;
	margin-left:.75in;
	text-indent:-.25in;
	font-family:"Courier New";}
@list l0:level3
	{mso-level-tab-stop:1.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l0:level4
	{mso-level-tab-stop:2.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l0:level5
	{mso-level-tab-stop:2.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l0:level6
	{mso-level-tab-stop:3.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l0:level7
	{mso-level-tab-stop:3.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l0:level8
	{mso-level-tab-stop:4.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l0:level9
	{mso-level-tab-stop:4.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l1
	{mso-list-id:306205170;
	mso-list-type:hybrid;
	mso-list-template-ids:-1674931514 1730581374 67698691 67698693 67698689 67698691 67698693 67698689 67698691 67698693;}
@list l1:level1
	{mso-level-start-at:64;
	mso-level-number-format:bullet;
	mso-level-text:\F0A7;
	mso-level-tab-stop:.25in;
	mso-level-number-position:left;
	margin-left:.25in;
	text-indent:-.25in;
	mso-ansi-font-size:8.0pt;
	font-family:Wingdings;
	mso-fareast-font-family:Batang;
	mso-ansi-font-weight:normal;}
@list l1:level2
	{mso-level-tab-stop:1.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l1:level3
	{mso-level-tab-stop:1.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l1:level4
	{mso-level-tab-stop:2.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l1:level5
	{mso-level-tab-stop:2.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l1:level6
	{mso-level-tab-stop:3.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l1:level7
	{mso-level-tab-stop:3.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l1:level8
	{mso-level-tab-stop:4.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l1:level9
	{mso-level-tab-stop:4.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l2
	{mso-list-id:316303367;
	mso-list-type:hybrid;
	mso-list-template-ids:-1844835148 -1619512052 67698691 67698693 67698689 67698691 67698693 67698689 67698691 67698693;}
@list l2:level1
	{mso-level-start-at:0;
	mso-level-number-format:bullet;
	mso-level-text:-;
	mso-level-tab-stop:.25in;
	mso-level-number-position:left;
	margin-left:.25in;
	text-indent:-.25in;
	font-family:Arial;
	mso-fareast-font-family:Batang;}
@list l2:level2
	{mso-level-number-format:bullet;
	mso-level-text:o;
	mso-level-tab-stop:.75in;
	mso-level-number-position:left;
	margin-left:.75in;
	text-indent:-.25in;
	font-family:"Courier New";}
@list l2:level3
	{mso-level-tab-stop:1.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l2:level4
	{mso-level-tab-stop:2.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l2:level5
	{mso-level-tab-stop:2.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l2:level6
	{mso-level-tab-stop:3.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l2:level7
	{mso-level-tab-stop:3.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l2:level8
	{mso-level-tab-stop:4.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l2:level9
	{mso-level-tab-stop:4.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l3
	{mso-list-id:737479438;
	mso-list-type:hybrid;
	mso-list-template-ids:-321491296 1730581374 67698691 67698693 67698689 67698691 67698693 67698689 67698691 67698693;}
@list l3:level1
	{mso-level-start-at:64;
	mso-level-number-format:bullet;
	mso-level-text:\F0A7;
	mso-level-tab-stop:.25in;
	mso-level-number-position:left;
	margin-left:.25in;
	text-indent:-.25in;
	mso-ansi-font-size:8.0pt;
	font-family:Wingdings;
	mso-fareast-font-family:Batang;
	mso-ansi-font-weight:normal;}
@list l3:level2
	{mso-level-tab-stop:1.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l3:level3
	{mso-level-tab-stop:1.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l3:level4
	{mso-level-tab-stop:2.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l3:level5
	{mso-level-tab-stop:2.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l3:level6
	{mso-level-tab-stop:3.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l3:level7
	{mso-level-tab-stop:3.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l3:level8
	{mso-level-tab-stop:4.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l3:level9
	{mso-level-tab-stop:4.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l4
	{mso-list-id:1077752419;
	mso-list-type:hybrid;
	mso-list-template-ids:1896090450 1730581374 67698691 67698693 67698689 67698691 67698693 67698689 67698691 67698693;}
@list l4:level1
	{mso-level-start-at:64;
	mso-level-number-format:bullet;
	mso-level-text:\F0A7;
	mso-level-tab-stop:.25in;
	mso-level-number-position:left;
	margin-left:.25in;
	text-indent:-.25in;
	mso-ansi-font-size:8.0pt;
	font-family:Wingdings;
	mso-fareast-font-family:Batang;
	mso-ansi-font-weight:normal;}
@list l4:level2
	{mso-level-tab-stop:1.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l4:level3
	{mso-level-tab-stop:1.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l4:level4
	{mso-level-tab-stop:2.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l4:level5
	{mso-level-tab-stop:2.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l4:level6
	{mso-level-tab-stop:3.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l4:level7
	{mso-level-tab-stop:3.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l4:level8
	{mso-level-tab-stop:4.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l4:level9
	{mso-level-tab-stop:4.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l5
	{mso-list-id:1417049004;
	mso-list-type:hybrid;
	mso-list-template-ids:1743151242 1730581374 67698691 67698693 67698689 67698691 67698693 67698689 67698691 67698693;}
@list l5:level1
	{mso-level-start-at:64;
	mso-level-number-format:bullet;
	mso-level-text:\F0A7;
	mso-level-tab-stop:.25in;
	mso-level-number-position:left;
	margin-left:.25in;
	text-indent:-.25in;
	mso-ansi-font-size:8.0pt;
	font-family:Wingdings;
	mso-fareast-font-family:Batang;
	mso-ansi-font-weight:normal;}
@list l5:level2
	{mso-level-tab-stop:1.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l5:level3
	{mso-level-tab-stop:1.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l5:level4
	{mso-level-tab-stop:2.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l5:level5
	{mso-level-tab-stop:2.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l5:level6
	{mso-level-tab-stop:3.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l5:level7
	{mso-level-tab-stop:3.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l5:level8
	{mso-level-tab-stop:4.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l5:level9
	{mso-level-tab-stop:4.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l6
	{mso-list-id:1431781083;
	mso-list-type:hybrid;
	mso-list-template-ids:-1800215044 1380595462 67698713 67698715 67698703 67698713 67698715 67698703 67698713 67698715;}
@list l6:level1
	{mso-level-tab-stop:36.75pt;
	mso-level-number-position:left;
	margin-left:36.75pt;
	text-indent:-18.75pt;
	color:windowtext;
	mso-ansi-font-weight:normal;}
@list l6:level2
	{mso-level-number-format:alpha-lower;
	mso-level-tab-stop:1.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l6:level3
	{mso-level-number-format:roman-lower;
	mso-level-tab-stop:3.25in;
	mso-level-number-position:right;
	margin-left:3.25in;
	text-indent:-9.0pt;}
@list l6:level4
	{mso-level-tab-stop:2.0in;
	mso-level-number-position:left;
	text-indent:-.25in;
	color:windowtext;
	mso-ansi-font-weight:normal;}
@list l6:level5
	{mso-level-tab-stop:2.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l6:level6
	{mso-level-tab-stop:3.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l6:level7
	{mso-level-tab-stop:3.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l6:level8
	{mso-level-tab-stop:4.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l6:level9
	{mso-level-tab-stop:4.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l7
	{mso-list-id:1439835640;
	mso-list-type:hybrid;
	mso-list-template-ids:-1563007944 1730581374 67698691 67698693 67698689 67698691 67698693 67698689 67698691 67698693;}
@list l7:level1
	{mso-level-start-at:64;
	mso-level-number-format:bullet;
	mso-level-text:\F0A7;
	mso-level-tab-stop:.25in;
	mso-level-number-position:left;
	margin-left:.25in;
	text-indent:-.25in;
	mso-ansi-font-size:8.0pt;
	font-family:Wingdings;
	mso-fareast-font-family:Batang;
	mso-ansi-font-weight:normal;}
@list l7:level2
	{mso-level-tab-stop:1.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l7:level3
	{mso-level-tab-stop:1.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l7:level4
	{mso-level-tab-stop:2.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l7:level5
	{mso-level-tab-stop:2.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l7:level6
	{mso-level-tab-stop:3.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l7:level7
	{mso-level-tab-stop:3.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l7:level8
	{mso-level-tab-stop:4.0in;
	mso-level-number-position:left;
	text-indent:-.25in;}
@list l7:level9
	{mso-level-tab-stop:4.5in;
	mso-level-number-position:left;
	text-indent:-.25in;}
ol
	{margin-bottom:0in;}
ul
	{margin-bottom:0in;}
-->
</style>

</head>

<body lang=EN-US link=blue vlink=purple>

<div class=Section1>

<p><span
class=spanStyle>Hi all,<o:p></o:p></span></p>

<p><span
class=spanStyle><o:p>&nbsp;</o:p></span></p>

<p><span
class=spanStyle><o:p>&nbsp;</o:p></span></p>

<table class=MsoNormalTable style=\'background:#404040;border-collapse:collapse\'>
 <tr>
  <td width=779 valign=top style=\'width:604.6pt;border:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p><b><font size=3 color=white face=Verdana><span
  style=\'font-size:12.0pt;font-family:Verdana;color:white;font-weight:bold\'>Useful
  links</span></b><span
  style=\'font-size:8.0pt;font-family:Verdana;color:white\'><o:p></o:p></span></p>
  </td>
 </tr>
</table>

<p><span
class=spanStyle><o:p>&nbsp;</o:p></span></p>

<table class=MsoNormalTable
 style=\'margin-left:-.8pt;border-collapse:collapse\'>
 <tr>
  <td style=\'width:57.3pt;border:solid silver 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p><span
  class=spanStyle>Dashboard</span><o:p></o:p></span></p>
  </td>
  <td style=\'width:537.1pt;border:solid silver 1.0pt;
  border-left:none;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=pStyle><font face="Verdana" size="1"><![if !supportLists]><font
  size=1 color=blue face=Arial><span style=\'mso-list:Ignore\'><span
  style=\'font:7.0pt "Times New Roman"\'>
  </span></span><![endif]></u></span></p>
  <p class=pStyle><![if !supportLists]><font
  size=1 color=blue face=Arial><span style=\'mso-list:Ignore\'><span style=\'font-size:8.0pt;font-family:Verdana\'>-</span><span
  style=\'font:7.0pt "Times New Roman"\'>
  </span></span><![endif]><span dir=LTR><u><span style=\'font-size:8.0pt;font-family:Verdana;
  color:blue\'></span></u></span><font
  size=1 color=blue face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana;
  color:blue\'><o:p></o:p></span>&nbsp;<font color=#000000><a href="',$HTTP_CIS,'/#',$Context,'|Cis Build Dashboard">CIS</a></p>
  </td>
 </tr>
 ');
 my $flagBin = 0;
 my $flagPkg = 0;
 #check if table to do
  foreach my $thisSite (sort(keys(%HREFDROP))) {
	my $pathBin = "$HREFDROP{$thisSite}/bin";
	my $pathPkg = "$HREFDROP{$thisSite}/packages";
 	if( -e "$pathBin") {
		$flagBin = 1;
	}
	if( -e "$pathPkg") {
		$flagPkg = 1;
	}
 }
 ###bin
 if($flagBin == 1) {
 print(HTML '
 <tr>
  <td width=76 valign=top style=\'width:57.3pt;border:solid silver 1.0pt;
  border-top:none;padding:0in 5.4pt 0in 5.4pt\'>
  <p><span class=spanStyle>Binaries<o:p></o:p></span></p>
  </td>
  <td width=692 valign=top style=\'width:519.1pt;border-top:none;border-left:none;border-bottom:solid silver 1.0pt;border-right:solid silver 1.0pt; padding:0in 5.4pt 0in 5.4pt\'> <p style=\'margin-left:.25in;text-indent:-.25in;mso-list:l0 level1 lfo3\'><![if !supportLists]><font size=1 color=blue face=Arial>
  <span style=\'font-size:8.0pt;font-family:Arial; color:blue\'><span style=\'mso-list:Ignore\'><span style=\'font:7.0pt "Times New Roman"\'></span></span></span><![endif]><span dir=LTR><span style=\'font-size:8.0pt;font-family:Verdana\'>-');
  my $line = "";
  foreach my $thisSite (sort(keys(%HREFDROP))) {
  		my $path = "$HREFDROP{$thisSite}/bin";
  		if( -e "$path") {
	  		($path) =~ s-^\/net-\/-i;
			($path) =~ s-\\-\/-g;
			my $path2 = $path;
			($path2) =~ s-\/-\\-g;
			$line .="           From <font  color=blue><span style=\'color:blue\'><a href=\"file:///$path\",\"title=\"file:\"$path\",\">$SHORTNAMES{$thisSite}</a> / </span>";
		}
	}
  ($line) =~ s-\s+\/\s+\<\/span\>$-<\/span\>-;
  print(HTML $line);
  print(HTML '  <o:p></o:p></span></span></span></p>
  </td>
 </tr>
 ');
}

###packages
 if($flagPkg == 1) {
 print(HTML '
 <tr>
  <td width=76 valign=top style=\'width:57.3pt;border:solid silver 1.0pt;
  border-top:none;padding:0in 5.4pt 0in 5.4pt\'>
  <p><span class=spanStyle>Packages<o:p></o:p></span></p>
  </td>
  <td width=692 valign=top style=\'width:519.1pt;border-top:none;border-left:none;border-bottom:solid silver 1.0pt;border-right:solid silver 1.0pt; padding:0in 5.4pt 0in 5.4pt\'> <p style=\'margin-left:.25in;text-indent:-.25in;mso-list:l0 level1 lfo3\'><![if !supportLists]><font size=1 color=blue face=Arial>
  <span style=\'font-size:8.0pt;font-family:Arial; color:blue\'><span style=\'mso-list:Ignore\'><span style=\'font:7.0pt "Times New Roman"\'></span></span></span><![endif]><span dir=LTR><span style=\'font-size:8.0pt;font-family:Verdana\'>-');
  my $line = "";
  foreach my $thisSite (sort(keys(%HREFDROP))) {
  		my $path = "$HREFDROP{$thisSite}/packages";
  		if( -e "$path") {
	  		($path) =~ s-^\/net-\/-i;
			($path) =~ s-\\-\/-g;
			my $path2 = $path;
			($path2) =~ s-\/-\\-g;
			$line .="           From <font  color=blue><span style=\'color:blue\'><a href=\"file:///$path\",\"title=\"file:\"$path\",\">$SHORTNAMES{$thisSite}</a> / </span>";
		}
	}
  ($line) =~ s-\s+\/\s+\<\/span\>$-<\/span\>-;
  print(HTML $line);
  print(HTML '  <o:p></o:p></span></span></span></p>
  </td>
 </tr>
 ');
}

	print(HTML '
</table>

<p><span
class=spanStyle><o:p>&nbsp;</o:p></span></p>

<p><span
class=spanStyle><o:p>&nbsp;</o:p></span></p>

<table class=MsoNormalTable style=\'background:#404040;border-collapse:collapse\'>
 <tr>
  <td width=779 valign=top style=\'width:627.6pt;border:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p><b><font size=3 color=white face=Verdana><span
  style=\'font-size:12.0pt;font-family:Verdana;color:white;font-weight:bold\'>Compilation</span></b><font
  size=1 color=white face=Verdana><span style=\'font-size:8.0pt;font-family:
  Verdana;color:white\'><o:p></o:p></span></p>
  </td>
 </tr>
</table>

<p><span class=spanStyle><o:p>&nbsp;</o:p></span></p>

<table class=MsoNormalTable border=0 cellspacing=0 cellpadding=0
 style=\'border-collapse:collapse\'>
 <tr>
  <td class=tdCol1 valign=top bgcolor="#E0E0E0">
  <p><b><span style=\'font-size:8.0pt;
  font-family:Verdana;font-weight:bold\'>Area<o:p></o:p></span></b></p>
  </td>
  <td class=tdCol2 valign=top bgcolor="#E0E0E0">
  <p align=center style=\'text-align:center\'><b>
  <span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>#err<o:p></o:p></span></b></p>
  </td>
  <td class=tdCol3 valign=top bgcolor="#E0E0E0">
  <p align=center style=\'text-align:center\'><b><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>Logs with errors<br>
  - per build units -<o:p></o:p></span></b></p>
  </td>
  <td class=tdCol4 valign=top bgcolor="#E0E0E0">
  <p align=center style=\'text-align:center\'><b><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>Comments / Issues / Follow-up<o:p></o:p></span></b></p>
  </td>
 </tr>');
foreach my $Area (keys(%areas))
{
	next unless(exists($Errors{"$Platform"}{"$BUILD_MODE"}{build}{"$Area"}));
	my $Errors = 0;
	my @Logs;
	foreach (@{$Errors{"$Platform"}{"$BUILD_MODE"}{build}{"$Area"}})
	{
		my($Err, $Log, $Txt, $Start, $Stop) = @{$_};
		$Errors += $Err;
		push(@Logs, $Log) if($Err);
	}
	
 print(HTML '<tr>
  <td class=tdCol1 width=121 valign=top >
  <p><b><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  font-family:Verdana;font-weight:bold\'>',$Area,'</span></b>
  <span class=spanStyle><o:p></o:p></span></p>
  </td>
  <td class=tdCol2 valign=top bgcolor=',$Errors?"red":"lime",'>
  <p align=center style=\'text-align:center\'><b><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>',$Errors,'</span></b><span class=spanStyle><o:p></o:p></span></p>
  </td>
    <td class=tdCol3 valign=top>');

  if($Errors)
  {
  	foreach my $Log (@Logs)
	{
		my($File) = $Log =~ /[\\\/](.+?)=/;
		print(HTML '<p><span style=\'font-size:8.0pt;
  		font-family:Verdana\'><a
	    href="file:///',"$HREFCIS{$Site}/$Log",'">',$File,'</a><o:p></o:p></span></p>');
	}
  }

print(HTML '</td>
  <td class=tdCol4 valign=top>
  <p><span class=spanStyle><o:p>',"&nbsp;",'</o:p></span></p>
  </td>
 </tr>');
} 




print(HTML '
</table>


');

##debut isa

	print(HTML '

<p><span
class=spanStyle><o:p>&nbsp;</o:p></span></p>

<p><span
class=spanStyle><o:p>&nbsp;</o:p></span></p>

<table class=MsoNormalTable style=\'background:#404040;border-collapse:collapse\'>
 <tr>
  <td width=779 valign=top style=\'width:627.6pt;border:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p><b><font size=3 color=white face=Verdana><span
  style=\'font-size:12.0pt;font-family:Verdana;color:white;font-weight:bold\'>Setup</span></b><font
  size=1 color=white face=Verdana><span style=\'font-size:8.0pt;font-family:
  Verdana;color:white\'><o:p></o:p></span></p>
  </td>
 </tr>
</table>

<p><span class=spanStyle><o:p>&nbsp;</o:p></span></p>

<table class=MsoNormalTable border=0 cellspacing=0 cellpadding=0
 style=\'border-collapse:collapse\'>
 <tr>
  <td class=tdCol1 valign=top bgcolor="#E0E0E0">
  <p><b><span style=\'font-size:8.0pt;
  font-family:Verdana;font-weight:bold\'>Area<o:p></o:p></span></b></p>
  </td>
  <td class=tdCol2 valign=top bgcolor="#E0E0E0">
  <p align=center style=\'text-align:center\'><b>
  <span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>#err<o:p></o:p></span></b></p>
  </td>
  <td class=tdCol3 valign=top bgcolor="#E0E0E0">
  <p align=center style=\'text-align:center\'><b><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>Logs with errors<br>
  - per build units -<o:p></o:p></span></b></p>
  </td>
  <td class=tdCol4 valign=top bgcolor="#E0E0E0">
  <p align=center style=\'text-align:center\'><b><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>Comments / Issues / Follow-up<o:p></o:p></span></b></p>
  </td>
 </tr>');
foreach my $Area (keys(%areas))
{
	next unless(exists($Errors{"$Platform"}{"$BUILD_MODE"}{setup}{"$Area"}));
	my $Errors = 0;
	my @Logs;
	foreach (@{$Errors{"$Platform"}{"$BUILD_MODE"}{setup}{"$Area"}})
	{
		my($Err, $Log, $Txt, $Start, $Stop) = @{$_};
		$Errors += $Err;
		push(@Logs, $Log) if($Err);
	}
	
 print(HTML '<tr>
  <td class=tdCol1 width=121 valign=top >
  <p><b><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  font-family:Verdana;font-weight:bold\'>',$Area,'</span></b>
  <span class=spanStyle><o:p></o:p></span></p>
  </td>
  <td class=tdCol2 valign=top bgcolor=',$Errors?"red":"lime",'>
  <p align=center style=\'text-align:center\'><b><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>',$Errors,'</span></b><span class=spanStyle><o:p></o:p></span></p>
  </td>
    <td class=tdCol3 valign=top>');

  if($Errors)
  {
  	foreach my $Log (@Logs)
	{
		my($File) = $Log =~ /[\\\/](.+?)=/;
		print(HTML '<p><span style=\'font-size:8.0pt;
  		font-family:Verdana\'><a
	    href="file:///',"$HREFCIS{$Site}/$Log",'">',$File,'</a><o:p></o:p></span></p>');
	}
  }

print(HTML '</td>
  <td class=tdCol4 valign=top>
  <p><span class=spanStyle><o:p>',"&nbsp;",'</o:p></span></p>
  </td>
 </tr>');
} 


	print(HTML '
</table>

<p><span
class=spanStyle><o:p>&nbsp;</o:p></span></p>
');

##2eme tableau


##fin isa





#check if smt done
my $datFile = "$HREFCIS{$Site}/$BuildName=${Platform}_${BUILD_MODE}_smoke_1.dat";
($datFile) =~ s-\\\\-\\-g;
($datFile) =~ s-\\-\/-g;
if( -e "$datFile") {
	
##debut isa
	print(HTML '


<p><span
class=spanStyle><o:p>&nbsp;</o:p></span></p>

<table class=MsoNormalTable style=\'background:#404040;border-collapse:collapse\'>
 <tr>
  <td width=779 valign=top style=\'width:627.6pt;border:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p><b><font size=3 color=white face=Verdana><span
  style=\'font-size:12.0pt;font-family:Verdana;color:white;font-weight:bold\'>Smoke</span></b><font
  size=1 color=white face=Verdana><span style=\'font-size:8.0pt;font-family:
  Verdana;color:white\'><o:p></o:p></span></p>
  </td>
 </tr>
</table>

<p><span class=spanStyle><o:p>&nbsp;</o:p></span></p>

<table class=MsoNormalTable border=0 cellspacing=0 cellpadding=0
 style=\'border-collapse:collapse\'>
 <tr>
  <td class=tdCol1 valign=top bgcolor="#E0E0E0">
  <p><b><span style=\'font-size:8.0pt;
  font-family:Verdana;font-weight:bold\'>Area<o:p></o:p></span></b></p>
  </td>
  <td class=tdCol2 valign=top bgcolor="#E0E0E0">
  <p align=center style=\'text-align:center\'><b>
  <span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>#err<o:p></o:p></span></b></p>
  </td>
  <td class=tdCol3 valign=top bgcolor="#E0E0E0">
  <p align=center style=\'text-align:center\'><b><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>Logs with errors<br>
  - per build units -<o:p></o:p></span></b></p>
  </td>
  <td class=tdCol4 valign=top bgcolor="#E0E0E0">
  <p align=center style=\'text-align:center\'><b><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>Comments / Issues / Follow-up<o:p></o:p></span></b></p>
  </td>
 </tr>');
foreach my $Area (keys(%areas))
{
	next unless(exists($Errors{"$Platform"}{"$BUILD_MODE"}{smoke}{"$Area"}));
	my $Errors = 0;
	my @Logs;
	foreach (@{$Errors{"$Platform"}{"$BUILD_MODE"}{smoke}{"$Area"}})
	{
		my($Err, $Log, $Txt, $Start, $Stop) = @{$_};
		$Errors += $Err;
		push(@Logs, $Log) if($Err);
	}
	
 print(HTML '<tr>
  <td class=tdCol1 width=121 valign=top >
  <p><b><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  font-family:Verdana;font-weight:bold\'>',$Area,'</span></b>
  <span class=spanStyle><o:p></o:p></span></p>
  </td>
  <td class=tdCol2 valign=top bgcolor=',$Errors?"red":"lime",'>
  <p align=center style=\'text-align:center\'><b><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>',$Errors,'</span></b><span class=spanStyle><o:p></o:p></span></p>
  </td>
    <td class=tdCol3 valign=top>');

  if($Errors)
  {
  	foreach my $Log (@Logs)
	{
		my($File) = $Log =~ /[\\\/](.+?)=/;
		print(HTML '<p><span style=\'font-size:8.0pt;
  		font-family:Verdana\'><a
	    href="file:///',"$HREFCIS{$Site}/$Log",'">',$File,'</a><o:p></o:p></span></p>');
	}
  }

print(HTML '</td>
  <td class=tdCol4 valign=top>
  <p><span class=spanStyle><o:p>',"&nbsp;",'</o:p></span></p>
  </td>
 </tr>');
} 

print(HTML '
</table>

<p><span
class=spanStyle><o:p>&nbsp;</o:p></span></p>
<p><span
class=spanStyle><o:p>&nbsp;</o:p></span></p>
');
}	
##fin isa	
	

print(HTML '
<p><span class=spanStyle><o:p>&nbsp;</o:p></span></p>

<p><span class=spanStyle>Build OPS Team<o:p></o:p></span></p>

<p><span style=\'font-size:9.0pt;
font-family:Arial\'><o:p>&nbsp;</o:p></span></p>

</div>

</body>

</html>
');
close(HTML);

if($ENV{JENKINS_CI_NATIVE_GIT}) {
	$JENKINS_DIR		= $ENV{JENKINS_DIR}		|| "c:/jenkins" ;
	$JENKINS_JOB		= $ENV{JENKINS_JOBS}	|| "$Context" ;
	if(open(VERSION,"$JENKINS_DIR/jobs/$JENKINS_JOB/nextBuildNumber")) {
		while(<VERSION>) {
			chomp;
			$JENKINS_BUILD_VERSION = int($_);
			last;
		}
		close(VERSION);
	}
	$JENKINS_BUILD_VERSION ||=2;
	$JENKINS_BUILD_VERSION = $JENKINS_BUILD_VERSION - 1;
	&MailOnErrorsOnly();
	$SMTPTO = "DL_011000358700001506162009E@exchange.sap.corp";
	if( -e "$JENKINS_DIR/jobs/$JENKINS_JOB/builds/$JENKINS_BUILD_VERSION/changelog.xml") {
		if(open(CHANGELOG,"$JENKINS_DIR/jobs/$JENKINS_JOB/builds/$JENKINS_BUILD_VERSION/changelog.xml")) {
			while(<CHANGELOG>) {
				chomp($_);
				if(/^committer\s+/i) {
					($SMTPTO) = $_ =~ /\s+\<(.+?)\>\s+/i;
					last;
				}
			}
			close(CHANGELOG);
			$SMTPTO .= ";DL_011000358700001506162009E\@exchange.sap.corp";
		} else {
			$SMTPTO = "'DL_011000358700001506162009E\@exchange.sap.corp'";
		}
	} else {
		$SMTPTO = "'DL_011000358700001506162009E\@exchange.sap.corp'";
	}
	$SMTPTO .= ($SMTPTO?';':'').$ENV{SMTPTO_RECIPIENTS_WHEN_ERRORS} if($ENV{SMTPTO_RECIPIENTS_WHEN_ERRORS});
}

# Mail

$SMTPTO .= ($SMTPTO?';':'').$ENV{SMTPTO_RECIPIENTS_WHEN_ERRORS} if($ENV{SMTPTO_RECIPIENTS_WHEN_ERRORS} and $nb_errors_current_build); 
if($SMTPTO)
{
    $smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60) or die("ERROR: SMTP connection impossible: $!");
    $smtp->mail($SMTPFROM);
    $smtp->to(split('\s*;\s*', $SMTPTO));
    $smtp->data();
    map({$smtp->datasend("To: $_\n")} split('\s*;\s*', $SMTPTO));
    $smtp->datasend("Subject: [$Context] status build rev.$BuildNumber - $Platform $BUILD_MODE\n");
    $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
    open(HTML, "$HTTPDIR/Mail=${Platform}_$BUILD_MODE.htm") or die ("ERROR: cannot open '$HTTPDIR/Mail=${Platform}_$BUILD_MODE.htm': $!");
    while(<HTML>) { $smtp->datasend($_) } 
    close(HTML);
    $smtp->dataend();
    $smtp->quit();
}

#############
# Functions #
#############

# this subroutine checks whether or not there are build errors, if there is none, we don't send a email.
sub MailOnErrorsOnly
{

	foreach my $Area (keys(%areas))
	{
		next unless(exists($Errors{"$Platform"}{"$BUILD_MODE"}{build}{"$Area"}));
		my $Errors = 0;
		my @Logs;
		foreach (@{$Errors{"$Platform"}{"$BUILD_MODE"}{build}{"$Area"}})
		{
			my($Err, $Log, $Txt, $Start, $Stop) = @{$_};
			if ($Err > 0){
				return; # if error is found, continue and send the email.
			}
		}
	}
	print "\nno compile error detected\n";
	exit; # if no errors is found, just stop the script and no emails sent.
}

sub Usage
{
   print <<USAGE;
   Usage   : Mail.pl [options]
   Example : Mail.pl -h
             Mail.pl -t=Main_PI_39 -m=release -p=win32_x86

   [options]
   -help|?     argument displays helpful information about builtin commands.
   -m.ode      debug, release or releasedebug, default is release.
   -p.latform  specifies the platform name, default is win32_x86.
   -t.ag       specifies the build name.
USAGE

	exit;
}
