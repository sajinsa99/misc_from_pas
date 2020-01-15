#!/usr/bin/perl

use Getopt::Long;
use Tie::IxHash;
use Net::SMTP;
use XML::DOM;
use File::Find;
use File::Copy;
use File::Path qw(mkpath);
#use P4;
    
use FindBin;
use lib ($FindBin::Bin, "$FindBin::Bin/site_perl");
use Site;

$SMTPFROM = $ENV{SMTPFROM} || 'julian.oprea@sap.com';
$SMTPTO = $ENV{SMTPTO};

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "mode=s"=>\$BUILD_MODE, "platform=s"=>\$Platform, "tag=s"=>\$BuildName);
Usage() if($Help);
unless($BuildName)  { print(STDERR "ERROR: -tag parameter is mandatory.\n"); Usage() };
$BUILD_MODE ||= "release";
$Platform   ||= "win32_x86";
if("debug"=~/^$BUILD_MODE/i) { $BUILD_MODE="debug" } elsif("release"=~/^$BUILD_MODE/i) { $BUILD_MODE="release" } elsif("releasedebug"=~/^$BUILD_MODE/i) { $BUILD_MODE="releasedebug" }
else { print(STDERR "ERROR: compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease|releasedebug]\n"); Usage() }

($Context, $BuildNumber) = $BuildName =~ /^(.+)_0*(\d+\.?\d*)$/;

$DROPDIR = "$ENV{DROP_DIR}/$Context/$BuildNumber/$Platform/$BUILD_MODE";
$HTTPDIR = "$ENV{HTTP_DIR}/$Context/$BuildName";

$HREFDROPLVL = "\\\\build-drops-lv.product.businessobjects.com\\dropzone\\$ENV{PROJECT}\\$Context\\$BuildNumber\\$Platform\\$BUILD_MODE";
$HREFDROPVCR = "\\\\build-drops-vc.product.businessobjects.com\\dropzoneV12\\$ENV{PROJECT}\\$Context\\$BuildNumber\\$Platform\\$BUILD_MODE";
$HREFDROPBLR = "\\\\blr-s-nsd001\\builds\\$ENV{PROJECT}\\$Context\\$BuildNumber\\$Platform\\$BUILD_MODE";
$HREFDROPWDF = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\$ENV{PROJECT}\\$Context\\$BuildNumber\\$Platform\\$BUILD_MODE";

if($ENV{SITE} eq "Bangalore") { $HREFCIS = "\\\\bgbuild-drops.pgdev.sap.corp\\cis" }
elsif($ENV{SITE} eq "Vancouver") { $HREFCIS = "\\\\build-drops-vc.pgdev.sap.corp\\tools\\preintegration\\cis" }
else { $HREFCIS = "\\\\build-drops-wdf.wdf.sap.corp\\preintegration\\CIS" } 
$HREFCIS .= "\\$Context\\$BuildName";

#$FromContext = "$DROPDIR/$BuildNumber/$Context.context.xml";
#$ToContext   = "$DROPDIR/".($BuildNumber-1)."/$Context.context.xml";

########
# Main #
########

#if($FromContext)
#{
#    my $CONTEXT = XML::DOM::Parser->new()->parsefile($FromContext);	
#    for my $COMPONENT (@{$CONTEXT->getElementsByTagName("fetch")})
#    {
#    	my($File, $Revision) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute("revision"));
#        $P4Diff2{$File} = [$Revision, ""];
#    }
#}
#if($ToContext)
#{
#    my $CONTEXT = XML::DOM::Parser->new()->parsefile($ToContext);	
#    for my $COMPONENT (@{$CONTEXT->getElementsByTagName("fetch")})
#    {
#    	my($File, $Revision) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute("revision"));
#        if(exists($P4Diff2{$File})) { ${$P4Diff2{$File}}[1] = $Revision }
#        else { $P4Diff2{$File} = ["", $Revision] }
#    }
#}

# New Versions
#my $p4 = new P4;
#$p4->ParseForms();
#$p4->Init() or die("ERROR: Failed to connect to Perforce Server: $!");

#for my $File (keys(%P4Diff2))
#{
#    my($FromRevision, $ToRevision) = @{$P4Diff2{$File}};
#    next if($FromRevision eq $ToRevision);
#
#    my @Diff2 = $p4->diff2("-q", "$File$FromRevision", "$File$ToRevision");   
#    foreach my $rhFile (@Diff2)
#    {
#		my $File = ref(${$rhFile}{depotFile}) eq "ARRAY" ? ${${$rhFile}{depotFile}}[0] : ${$rhFile}{depotFile};
#		my($FirstRevision, $LastRevision) = ref(${$rhFile}{rev})eq"ARRAY" ? (${${$rhFile}{rev}}[0],${${$rhFile}{rev}}[-1]):(0,1);
#        next if($FirstRevision eq $LastRevision);
#		foreach(my $Revision=$FirstRevision+1; $Revision<=$LastRevision; $Revision++)
#		{
#			my $rhFileLog = $p4->filelog("-m1", "$File\#$Revision");
#			die("ERROR: cannot filelog '$File\#$Revision': ", @{$p4->Errors()}) if($p4->ErrorCount());
#        	my $User = ${${$rhFileLog}{user}}[0];
#			#$NewFiles{$File}{$User} = undef;
#
#            unless(exists($Recipients{$User}))
#            {
#			    my $rhUser = $p4->user("-o", $User);
#			    die("ERROR: cannot user $User': ", @{$p4->Errors()}) if($p4->ErrorCount());
#			    $Recipients{$User} = ${$rhUser}{Email};
#			}
#		}
#    }
#}

if ($ENV{JLIN} eq "yes"){
	my $dropLogDir = "$ENV{DROP_DIR}/$ENV{context}/$ENV{build_number}/$ENV{PLATFORM}/release/logs/$ENV{HOSTNAME}";
	JlinLogsCopy($dropLogDir,"$HTTPDIR");
	JlinError($dropLogDir);
}

tie my %areas, "Tie::IxHash";
opendir(LOGS, $HTTPDIR) or die("ERROR: cannot open '$HTTPDIR': $!");
while(defined($File = readdir(LOGS)))
{
   	next unless(my($Platform, $Target, $Phase) = $File =~ /$BuildName=(.+)_(.+?)_(.+?)_\d+.dat/);
	next if($Phase eq "host");
	if ($Phase eq "jlin"){
		open(DAT, "$HTTPDIR/$File") or die("ERROR: cannot open '$HTTPDIR/$File': $!");
		eval <DAT>;
		close(DAT);
		next unless(defined($JlinErrors[0]));
		push(@{$Errors{"$Platform"}{"$Target"}{"Summary"}}, $JlinErrors[0]);
		foreach my $raLogs (@JlinErrors[1..$#JlinErrors])
		{
			map({$Recipients{${$_}[0]} = ${$_}[1]} @{$Areas{"$Area"}}) if(exists($Areas{"$Area"}));
			my($Errors, $Area, $BUs) = @{$raLogs};
			push(@{$Errors{"$Platform"}{"$Target"}{"$Phase"}{"Area"}}, [$Errors, $Area]);
			foreach my $BU (@$BUs[0..scalar(@$BUs)])
			{
				my($BUErrors, $BUName) = @{$BU};
				push(@{$Errors{"$Platform"}{"$Target"}{"$Phase"}{"$Area"}}, [$BUErrors, $BUName]);
			}
		}
		
	}else{
		open(DAT, "$HTTPDIR/$File") or die("ERROR: cannot open '$HTTPDIR/$File': $!");
		eval <DAT>;
		close(DAT);
		next unless(defined($Errors[0]));
		foreach my $raLogs (@Errors[1..$#Errors])
		{
			map({$Recipients{${$_}[0]} = ${$_}[1]} @{$Areas{"$Area"}}) if(exists($Areas{"$Area"}));
			my($Errors, $Log, $Txt, $Area, $Start, $Stop) = @{$raLogs};
			push(@{$Errors{"$Platform"}{"$Target"}{"$Phase"}{"$Area"}}, [$Errors, $Log, $Txt, $Start, $Stop]);
			$areas{"$Area"} = undef;
		}
	}
}
close(LOGS);

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
 p.MsoNormal, li.MsoNormal, div.MsoNormal
	{margin:0in;
	margin-bottom:.0001pt;
	font-size:12.0pt;
	font-family:"Times New Roman";}
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

<p class=MsoNormal><font size=1 color=black face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:black\'>Hi all,<o:p></o:p></span></font></p>

<p class=MsoNormal><font size=1 color=black face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:black\'><o:p>&nbsp;</o:p></span></font></p>

<p class=MsoNormal><font size=1 color=black face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:black\'><o:p>&nbsp;</o:p></span></font></p>

<table class=MsoNormalTable border=0 cellspacing=0 cellpadding=0
 bgcolor="#404040" style=\'background:#404040;border-collapse:collapse\'>
 <tr>
  <td width=779 valign=top style=\'width:604.6pt;border:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><b><font size=3 color=white face=Verdana><span
  style=\'font-size:12.0pt;font-family:Verdana;color:white;font-weight:bold\'>Highlights</span></font></b><font
  size=1 color=white face=Verdana><span style=\'font-size:8.0pt;font-family:
  Verdana;color:white\'><o:p></o:p></span></font></p>
  </td>
 </tr>
</table>

<p class=MsoNormal><font size=1 color=black face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:black\'><o:p>&nbsp;</o:p></span></font></p>

<p class=MsoNormal><font size=1 color=black face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:black\'><o:p>&nbsp;</o:p></span></font></p>

<table class=MsoNormalTable border=0 cellspacing=0 cellpadding=0
 bgcolor="#404040" style=\'background:#404040;border-collapse:collapse\'>
 <tr>
  <td width=779 valign=top style=\'width:604.6pt;border:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><b><font size=3 color=white face=Verdana><span
  style=\'font-size:12.0pt;font-family:Verdana;color:white;font-weight:bold\'>Useful
  links</span></font></b><font size=1 color=white face=Verdana><span
  style=\'font-size:8.0pt;font-family:Verdana;color:white\'><o:p></o:p></span></font></p>
  </td>
 </tr>
</table>

<p class=MsoNormal><font size=1 color=black face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:black\'><o:p>&nbsp;</o:p></span></font></p>

<table class=MsoNormalTable border=0 cellspacing=0 cellpadding=0
 style=\'margin-left:-.8pt;border-collapse:collapse\'>
 <tr>
  <td width=76 valign=top style=\'width:57.3pt;border:solid silver 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><font size=1 color=black face=Verdana><span
  style=\'font-size:8.0pt;font-family:Verdana;color:black\'>Dashboard</span></font><font
  size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'><o:p></o:p></span></font></p>
  </td>
  <td width=716 valign=top style=\'width:537.1pt;border:solid silver 1.0pt;
  border-left:none;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal style=\'margin-left:.25in;text-indent:-.25in;mso-list:l0 level1 lfo1\'><font face="Verdana" size="1"><![if !supportLists]><font
  size=1 color=blue face=Arial><span style=\'mso-list:Ignore\'>-<span
  style=\'font:7.0pt "Times New Roman"\'>
  </span></span></font><![endif]></u></span></p>
  <p class=MsoNormal style=\'margin-left:.25in;text-indent:-.25in;mso-list:l0 level1 lfo1\'><font face="Verdana" size="1"><![if !supportLists]><font
  size=1 color=blue face=Arial><span style=\'mso-list:Ignore\'>-<span
  style=\'font:7.0pt "Times New Roman"\'>
  </span></span></font><![endif]><span dir=LTR><u><font size=1
  color=blue face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana;
  color:blue\'><a href="https://builddashboard.pgdev.sap.corp"
  title="https://builddashboard.pgdev.sap.corp>https://builddashboard.pgdev.sap.corp</a></span></font></u></span><font
  size=1 color=blue face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana;
  color:blue\'><o:p></o:p></span></font>&nbsp;<font color=#000000>[Torch]</font></font></p>
  </td>
 </tr>
 <tr>
  <td width=76 valign=top style=\'width:57.3pt;border:solid silver 1.0pt;
  border-top:none;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  font-family:Verdana\'>Dropzone<o:p></o:p></span></font></p>
  </td>
  <td width=692 valign=top style=\'width:519.1pt;border-top:none;border-left:
  none;border-bottom:solid silver 1.0pt;border-right:solid silver 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal style=\'margin-left:.25in;text-indent:-.25in;mso-list:l0 level1 lfo3\'><![if !supportLists]><font
  size=1 color=blue face=Arial><span style=\'font-size:8.0pt;font-family:Arial;
  color:blue\'><span style=\'mso-list:Ignore\'>-<font size=1 face="Times New Roman"><span
  style=\'font:7.0pt "Times New Roman"\'>
  </span></font></span></span></font><![endif]><span dir=LTR><font size=1
  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>From <font
  color=blue><span style=\'color:blue\'><a
  href="file:///',"$HREFDROPLVL\\bin",'"
  title="file:',"$HREFDROPLVL\\bin",'">LVL</a>
  / </span></font>From <font
  color=blue><span style=\'color:blue\'><a
  href="file:///',"$HREFDROPVCR\\bin",'"
  title="file:',"$HREFDROPVCR\\bin",'">VCR</a>
  / </span></font>From <font
  color=blue><span style=\'color:blue\'><a
  href="file:///',"$HREFDROPWDF\\bin",'"
  title="file:',"$HREFDROPWDF\\bin",'">WDF</a>
  / </span></font>From <font color=blue><span style=\'color:blue\'><a
  href="file:///',"$HREFDROPBLR\\bin",'"
  title="file:',"$HREFDROPBLR\\bin",'">BLR</a><o:p></o:p></span></font></span></font></span></p>
  </td>
 </tr>
 <tr>
  <td width=76 valign=top style=\'width:57.3pt;border:solid silver 1.0pt;
  border-top:none;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  font-family:Verdana\'>Packages<o:p></o:p></span></font></p>
  </td>
  <td width=692 valign=top style=\'width:519.1pt;border-top:none;border-left:
  none;border-bottom:solid silver 1.0pt;border-right:solid silver 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal style=\'margin-left:.25in;text-indent:-.25in;mso-list:l0 level1 lfo3\'><![if !supportLists]><font
  size=1 color=blue face=Arial><span style=\'font-size:8.0pt;font-family:Arial;
  color:blue\'><span style=\'mso-list:Ignore\'>-<font size=1 face="Times New Roman"><span
  style=\'font:7.0pt "Times New Roman"\'>
  </span></font></span></span></font><![endif]><span dir=LTR><font size=1
  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>From <font
  color=blue><span style=\'color:blue\'><a
  href="file:///',"$HREFDROPLVL\\packages",'"
  title="file:',"$HREFDROPLVL\\packages",'">LVL</a>
  / </span></font>From <font
  color=blue><span style=\'color:blue\'><a
  href="file:///',"$HREFDROPVCR\\packages",'"
  title="file:',"$HREFDROPVCR\\packages",'">VCR</a>
  / </span></font>From <font
  color=blue><span style=\'color:blue\'><a
  href="file:///',"$HREFDROPWDF\\packages",'"
  title="file:',"$HREFDROPWDF\\packages",'">WDF</a>
  / </span></font>From <font 
  color=blue><span style=\'color:blue\'><a
  href="file:///',"$HREFDROPBLR\\packages",'"
  title="file:',"$HREFDROPBLR\\packages",'">BLR</a>
  <o:p></o:p></span></font></span></font></span></p>
  </td>
 </tr>
</table>

<p class=MsoNormal><font size=1 color=black face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:black\'><o:p>&nbsp;</o:p></span></font></p>

<p class=MsoNormal><font size=1 color=black face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:black\'><o:p>&nbsp;</o:p></span></font></p>

<table class=MsoNormalTable border=0 cellspacing=0 cellpadding=0
 bgcolor="#404040" style=\'background:#404040;border-collapse:collapse\'>
 <tr>
  <td width=779 valign=top style=\'width:627.6pt;border:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><b><font size=3 color=white face=Verdana><span
  style=\'font-size:12.0pt;font-family:Verdana;color:white;font-weight:bold\'>Compilation</span></font></b><font
  size=1 color=white face=Verdana><span style=\'font-size:8.0pt;font-family:
  Verdana;color:white\'><o:p></o:p></span></font></p>
  </td>
 </tr>
</table>

<p class=MsoNormal><font size=1 face=Verdana><span style=\'font-size:8.0pt;
font-family:Verdana\'><o:p>&nbsp;</o:p></span></font></p>

<table class=MsoNormalTable border=0 cellspacing=0 cellpadding=0
 style=\'border-collapse:collapse\'>
 <tr>
  <td width=121 valign=top bgcolor="#E0E0E0" style=\'width:90.4pt;border:solid silver 1.0pt;
  background:#E0E0E0;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><b><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  font-family:Verdana;font-weight:bold\'>Area<o:p></o:p></span></font></b></p>
  </td>
  <td width=59 valign=top bgcolor="#E0E0E0" style=\'width:43.9pt;border:solid silver 1.0pt;
  border-left:none;background:#E0E0E0;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal align=center style=\'text-align:center\'><b><font size=1
  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>#err<o:p></o:p></span></font></b></p>
  </td>
  <td width=132 valign=top bgcolor="#E0E0E0" style=\'width:99.3pt;border:solid silver 1.0pt;
  border-left:none;background:#E0E0E0;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal align=center style=\'text-align:center\'><b><font size=1
  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>Logs with errors<br>
  - per build units -<o:p></o:p></span></font></b></p>
  </td>
  <td width=457 valign=top bgcolor="#E0E0E0" style=\'width:343.1pt;border:solid silver 1.0pt;
  border-left:none;background:#E0E0E0;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal align=center style=\'text-align:center\'><b><font size=1
  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>Comments / Issues / Follow-up<o:p></o:p></span></font></b></p>
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
  <td width=121 valign=top style=\'width:90.4pt;border:solid silver 1.0pt;
  border-top:none;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><b><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  font-family:Verdana;font-weight:bold\'>',$Area,'</span></font></b><font size=1
  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'><o:p></o:p></span></font></p>
  </td>
  <td width=59 valign=top bgcolor=',$Errors?"red":"lime",' style=\'width:43.9pt;border-top:none;
  border-left:none;border-bottom:solid silver 1.0pt;border-right:solid silver 1.0pt;
  background:',$Errors?"red":"lime",';padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal align=center style=\'text-align:center\'><b><font size=1
  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>',$Errors,'</span></font></b><font size=1 face=Verdana><span style=\'font-size:
  8.0pt;font-family:Verdana\'><o:p></o:p></span></font></p>
  </td>
    <td width=132 valign=top style=\'width:99.3pt;border-top:none;border-left:
  none;border-bottom:solid silver 1.0pt;border-right:solid silver 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>');

  if($Errors)
  {
  	foreach my $Log (@Logs)
	{
		my($File) = $Log =~ /[\\\/](.+?)=/;
		print(HTML '<p class=MsoNormal><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  		font-family:Verdana\'><a
	    href="file:///',"$HREFCIS/$Log",'">',$File,'</a><o:p></o:p></span></font></p>');
	}
  }

print(HTML '</td>
  <td width=457 valign=top style=\'width:343.1pt;border-top:none;border-left:
  none;border-bottom:solid silver 1.0pt;border-right:solid silver 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  font-family:Verdana\'><o:p>',"&nbsp;",'</o:p></span></font></p>
  </td>
 </tr>');
}

if (($ENV{JLIN} eq "yes")&&($Errors{"$Platform"}{"$BUILD_MODE"}{"Summary"}[0] ne "")){

print(HTML '<tr>
  <td width=121 valign=top style=\'width:90.4pt;border:solid silver 1.0pt;
  border-top:none;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><b><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  font-family:Verdana;font-weight:bold\'>',jlin,'</span></font></b><font size=1
  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'><o:p></o:p></span></font></p>
  </td>
  <td width=59 valign=top bgcolor=',$Errors{"$Platform"}{"$BUILD_MODE"}{"Summary"}[0]?"red":"lime",' style=\'width:43.9pt;border-top:none;
  border-left:none;border-bottom:solid silver 1.0pt;border-right:solid silver 1.0pt;
  background:',$Errors{"$Platform"}{"$BUILD_MODE"}{"Summary"}[0]?"red":"lime",';padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal align=center style=\'text-align:center\'><b><font size=1
  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>',$Errors{"$Platform"}{"$BUILD_MODE"}{"Summary"}[0],'</span></font></b><font size=1 face=Verdana><span style=\'font-size:
  8.0pt;font-family:Verdana\'><o:p></o:p></span></font></p>
  </td>
    <td width=132 valign=top style=\'width:99.3pt;border-top:none;border-left:
  none;border-bottom:solid silver 1.0pt;border-right:solid silver 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'><span></span></td>
  <td width=132 valign=top style=\'width:99.3pt;border-top:none;border-left:
  none;border-bottom:solid silver 1.0pt;border-right:solid silver 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'><span></span></td>
  </tr>');

print(HTML '
</table><br/>');
print(HTML '
<table class=MsoNormalTable border=0 cellspacing=0 cellpadding=0
 style=\'border-collapse:collapse\'>
 <tr>
  <td width=121 valign=top bgcolor="#E0E0E0" style=\'width:90.4pt;border:solid silver 1.0pt;
  background:#E0E0E0;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><b><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  font-family:Verdana;font-weight:bold\'>Jlin<o:p></o:p></span></font></b></p>
  </td>
  <td width=59 valign=top bgcolor="#E0E0E0" style=\'width:43.9pt;border:solid silver 1.0pt;
  border-left:none;background:#E0E0E0;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal align=center style=\'text-align:center\'><b><font size=1
  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
  bold\'>#err<o:p></o:p></span></font></b></p>
  </td><td width=121 valign=top bgcolor="#E0E0E0" style=\'width:90.4pt;border:solid silver 1.0pt;
  background:#E0E0E0;padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><b><font size=1 face=Verdana><span style=\'font-size:8.0pt;
  font-family:Verdana;font-weight:bold\'>Summary<o:p></o:p></span></font></b></p>
  </td>
 </tr>');
	foreach my $areaArray(@{$Errors{"$Platform"}{"$BUILD_MODE"}{"jlin"}{"Area"}})
	{
		my $areaErr;
		my $area;
		($areaErr, $area) = @{$areaArray};
		my $areaSummary = $HREFCIS . "\\jlin\\$area\\JLin\\reports\\logs\\summary.html";
		
		print(HTML '
			<tr class="jlinarea">
				  <td width=121 valign=top style=\'width:90.4pt;border:solid silver 1.0pt;border-top:none;padding:0in 5.4pt 0in 5.4pt\'>
						<p class=MsoNormal>
						<b>
							<font size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:bold\'>
							',$area,'
							</font>
						</b>
						</p>
				  </td>
				  <td width=59 valign=top bgcolor=',$areaErr?"red":"lime",' style=\'width:43.9pt;border-top:none;
					  border-left:none;border-bottom:solid silver 1.0pt;border-right:solid silver 1.0pt;
					  background:',$areaErr?"red":"lime",';padding:0in 5.4pt 0in 5.4pt\'>
					  <p class=MsoNormal align=center style=\'text-align:center\'><b><font size=1
					  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana;font-weight:
					  bold\'>',$areaErr,'</span></font></b><font size=1 face=Verdana><span style=\'font-size:
					  8.0pt;font-family:Verdana\'><o:p></o:p></span></font></p>
					  </td>
				  
				  <td width=121 valign=top style=\'width:90.4pt;border:solid silver 1.0pt;
				  border-top:none;padding:0in 5.4pt 0in 5.4pt\'>
				  <p class=MsoNormal><b><font size=1 face=Verdana><span style=\'font-size:8.0pt;
				  font-family:Verdana;font-weight:bold\'><a href=',$areaSummary,'>Summary</a></span></font></b><font size=1
				  face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'><o:p></o:p></span></font></p>
				  </td>
			</tr>

		');
	} 
print(HTML '
</table>');

}else{
	print(HTML '
	</table><br/>');
}

print(HTML '
<p class=MsoNormal><font size=1 color=black face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:black\'><o:p>&nbsp;</o:p></span></font></p>
<p class=MsoNormal><font size=1 color=black face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:black\'><o:p>&nbsp;</o:p></span></font></p>

<table class=MsoNormalTable border=0 cellspacing=0 cellpadding=0
 bgcolor="#404040" style=\'background:#404040;border-collapse:collapse\'>
 <tr>
  <td width=779 valign=top style=\'width:604.6pt;border:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt\'>
  <p class=MsoNormal><b><font size=3 color=white face=Verdana><span
  style=\'font-size:12.0pt;font-family:Verdana;color:white;font-weight:bold\'>BOE
  Smoke Tests</span></font></b><font size=1 color=white face=Verdana><span
  style=\'font-size:8.0pt;font-family:Verdana;color:white\'><o:p></o:p></span></font></p>
  </td>
 </tr>
</table>

<p class=MsoNormal><font size=1 face=Verdana><span style=\'font-size:8.0pt;
font-family:Verdana\'><o:p>&nbsp;</o:p></span></font></p>

<p class=MsoNormal><font size=1 face=Verdana><span style=\'font-size:8.0pt;
font-family:Verdana\'><o:p>&nbsp;</o:p></span></font></p>

<p class=MsoNormal><b><font size=1 color=navy face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:navy;font-weight:bold\'>Smoke test configuration<o:p></o:p></span></font></b></p>

<p class=MsoNormal><b><font size=1 color=navy face=Verdana><span
style=\'font-size:8.0pt;font-family:Verdana;color:navy;font-weight:bold\'><o:p>&nbsp;</o:p></span></font></b></p>

<table class=MsoNormalTable border=0 cellspacing=0 cellpadding=0
 style=\'border-collapse:collapse\'>
 <tr height=17 style=\'height:12.7pt\'>
  <td width=191 height=17 valign=top style=\'width:143.6pt;border:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt;height:12.7pt\'>
  <p class=MsoNormal style=\'mso-margin-top-alt:auto;mso-margin-bottom-alt:auto\'><font
  size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>Language<o:p></o:p></span></font></p>
  </td>
  <td width=588 height=17 valign=top style=\'width:441.0pt;border:solid #999999 1.0pt;
  border-left:none;padding:0in 5.4pt 0in 5.4pt;height:12.7pt\'>
  <p class=MsoNormal style=\'mso-margin-top-alt:auto;mso-margin-bottom-alt:auto\'><font
  size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>English<o:p></o:p></span></font></p>
  </td>
 </tr>');
 print(HTML '
 <tr height=17 style=\'height:12.7pt\'>
  <td width=191 height=17 valign=top style=\'width:143.6pt;border:solid #999999 1.0pt;
  border-top:none;padding:0in 5.4pt 0in 5.4pt;height:12.7pt\'>
  <p class=MsoNormal style=\'mso-margin-top-alt:auto;mso-margin-bottom-alt:auto\'><font
  size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>Server/Client
  OS Version<o:p></o:p></span></font></p>
  </td>
  <td width=588 height=17 valign=top style=\'width:441.0pt;border-top:none;
  border-left:none;border-bottom:solid #999999 1.0pt;border-right:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt;height:12.7pt\'>
  <p class=MsoNormal style=\'mso-margin-top-alt:auto;mso-margin-bottom-alt:auto\'><font
  size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>Windows
  2003 <ST1:CITY style="BACKGROUND-POSITION: left bottom; BACKGROUND-IMAGE: url(res://ietag.dll/#34/#1001); BACKGROUND-REPEAT: repeat-x" u2:st="on"><ST1:PLACE style="BACKGROUND-POSITION: left bottom; BACKGROUND-IMAGE: url(res://ietag.dll/#34/#1001); BACKGROUND-REPEAT: repeat-x" u2:st="on"><st1:place
  w:st="on"><st1:City
   style="BACKGROUND-POSITION: left bottom; BACKGROUND-IMAGE: url(res://ietag.dll/#34/#1001); BACKGROUND-REPEAT: repeat-x"
   tabIndex="0" w:st="on">Server Enterprise</st1:City></st1:place> SP2<o:p></o:p></span></font></p>
  </td>
 </tr>
 <tr height=17 style=\'height:12.7pt\'>
  <td width=191 height=17 valign=top style=\'width:143.6pt;border:solid #999999 1.0pt;
  border-top:none;padding:0in 5.4pt 0in 5.4pt;height:12.7pt\'>
  <p class=MsoNormal style=\'mso-margin-top-alt:auto;mso-margin-bottom-alt:auto\'><font
  size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>Browser<o:p></o:p></span></font></p>
  </td>
  <td width=588 height=17 valign=top style=\'width:441.0pt;border-top:none;
  border-left:none;border-bottom:solid #999999 1.0pt;border-right:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt;height:12.7pt\'>
  <p class=MsoNormal style=\'mso-margin-top-alt:auto;mso-margin-bottom-alt:auto\'><font
  size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>IE 7
  <o:p></o:p></span></font></p>
  </td>
 </tr>
 ') if($Platform eq "win32_x86");
print(HTML '
 <tr height=17 style=\'height:12.7pt\'>
  <td width=191 height=17 valign=top style=\'width:143.6pt;border:solid #999999 1.0pt;
  border-top:none;padding:0in 5.4pt 0in 5.4pt;height:12.7pt\'>
  <p class=MsoNormal style=\'mso-margin-top-alt:auto;mso-margin-bottom-alt:auto\'><font
  size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>CMS<o:p></o:p></span></font></p>
  </td>
  <td width=588 height=17 valign=top style=\'width:441.0pt;border-top:none;
  border-left:none;border-bottom:solid #999999 1.0pt;border-right:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt;height:12.7pt\'>
  <p class=MsoNormal style=\'mso-margin-top-alt:auto;mso-margin-bottom-alt:auto\'><font
  size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>MySQL<o:p></o:p></span></font></p>
  </td>
 </tr>
 <tr height=17 style=\'height:12.7pt\'>
  <td width=191 height=17 valign=top style=\'width:143.6pt;border:solid #999999 1.0pt;
  border-top:none;padding:0in 5.4pt 0in 5.4pt;height:12.7pt\'>
  <p class=MsoNormal style=\'mso-margin-top-alt:auto;mso-margin-bottom-alt:auto\'><font
  size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>Web App
  Server<o:p></o:p></span></font></p>
  </td>
  <td width=588 height=17 valign=top style=\'width:441.0pt;border-top:none;
  border-left:none;border-bottom:solid #999999 1.0pt;border-right:solid #999999 1.0pt;
  padding:0in 5.4pt 0in 5.4pt;height:12.7pt\'>
  <p class=MsoNormal style=\'mso-margin-top-alt:auto;mso-margin-bottom-alt:auto\'><font
  size=1 face=Verdana><span style=\'font-size:8.0pt;font-family:Verdana\'>Tomcat
  (for Java Infoview)<o:p></o:p></span></font></p>
  </td>
 </tr>
</table>

<p class=MsoNormal><font size=1 face=Verdana><span style=\'font-size:8.0pt;
font-family:Verdana\'><o:p>&nbsp;</o:p></span></font></p>

<p class=MsoNormal><font size=1 face=Verdana><span style=\'font-size:8.0pt;
font-family:Verdana\'>RM Operations team<o:p></o:p></span></font></p>

<p class=MsoNormal><font size=1 face=Arial><span style=\'font-size:9.0pt;
font-family:Arial\'><o:p>&nbsp;</o:p></span></font></p>

</div>

</body>

</html>
');
close(HTML);

# Mail
$SMTPTO = join(";", $SMTPTO,$ENV{SMTPTO_RECIPIENTS_WHEN_ERRORS}) if($ENV{SMTPTO_RECIPIENTS_WHEN_ERRORS} and $Errors); 
if(SMTPTO)
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

sub JlinError{
		my($dropLogDir) = @_;
        my @jlinArea;
        opendir(DIR, "$dropLogDir/Build") or warn("ERROR: cannot opendir '$dropLogDir/Build': $!");
		while(defined($File = readdir(DIR)))
        {
            next unless(my($Area) = $File =~ /jlinreport.log/);
            my($jlinArea, $jlinComponent, $Errors) = (0, 0);
            if(open(SUM, "$dropLogDir/Build/jlinreport.log"))
            {
				
				my @jlinAreaComponents = ();
				my $jlinAreaErrors = 0;
                while(<SUM>)
                {
					my($line) = $_;
                    if((!($line =~ /.*=.*/)&&!($line =~ /.*:.*/)&&($line =~ /[\S]+/)&&!($line eq ""))||(eof)){ 
						$newjlinArea = $line;
						if (((scalar @jlinAreaComponents) != 0)){
							
							$jlinArea = substr $jlinArea, 0,-1;
							my $jlinAreaString = "[$jlinAreaErrors, \"$jlinArea\", [";
							my $jlinAreaComponentsCounter;
							foreach $jlinAreaComponents (@jlinAreaComponents){
								if (++$jlinAreaComponentsCounter == scalar(@jlinAreaComponents)){
									$jlinAreaString .= "$jlinAreaComponents";
								}else{
									$jlinAreaString .= "$jlinAreaComponents ,";
								}
							}
							$jlinAreaString .= "]]";
							push(@jlinArea, $jlinAreaString);
							@jlinAreaComponents = ();
							$jlinArea = $newjlinArea;
							$Errors +=$jlinAreaErrors;
							$jlinAreaErrors=0;
						}else{
							$jlinArea = $line;
						}
					}
                    elsif((!($line =~ /.*=.*/)&&($line =~ /.*:.*/))){ 
						my $errorCountIndex = index($line, ':');
						$jlinComponent = substr $line, 1,$errorCountIndex-1;
						$jlinComponentErrors = substr $line, $errorCountIndex+1, -1;
						$jlinAreaErrors += $jlinComponentErrors;
						push(@jlinAreaComponents, "[$jlinComponentErrors, \"$jlinComponent\"]");
					}
                }
                close(SUM);
				
				open (jlinDat, ">$HTTPDIR/$BuildName=$ENV{PLATFORM}_$ENV{BUILD_MODE}_jlin_1.dat"); 
				
				print jlinDat "\@JlinErrors =($Errors,";
				my $jlinDatCounter;
				foreach $jlinString (@jlinArea){
					if (++$jlinDatCounter == scalar(@jlinArea)){
						print jlinDat "$jlinString";
					}else{
						print jlinDat "$jlinString,";
					}
				}
				print jlinDat ");";
				close (jlinDat); 				
            }
            else { warn("ERROR: cannot open '$dropLogDir/Build/jlinreport.log': $!") }
        }
        closedir(DIR);
    }  
	
sub JlinLogsCopy{
	my($dir, $target) = @_;
	my $pattern = '.';
	
		if (!(-e "$target/jlin/Build")){
				mkpath("$target/jlin/Build");
		}
	
	copy("$dir/Build/jlinreport.log","$target/jlin/Build/jlinreport.log");
	
	#opendir(DropDir, $dir) or die("ERROR: cannot open '$HTTPDIR': $!");
	JlinLogsCopy2($dir, "$target/jlin");
}

sub JlinLogsCopy2{
	my ($dir, $target) = @_;
	my $DropDir;
	if (!(-e "$target")){
			mkpath("$target");
	}

	opendir($DropDir, $dir) or die("ERROR: cannot open '$HTTPDIR': $!");
	while(defined(my $File = readdir($DropDir))){
		if (-d "$dir/$File"){
			if (("$File" ne  ".") && ("$File" ne  "..") && ("$File" ne  "Build")){
					JlinLogsCopy2("$dir/$File","$target/$File");
			}
		}else{
			copy("$dir/$File","$target/$File");
		}
	}
	closedir $DropDir;
}

sub Usage
{
   print <<USAGE;
   Usage   : JLinMail.pl [options]
   Example : JLinMail.pl -h
             JLinMail.pl -t=Main_PI_39 -m=release -p=win32_x86

   [options]
   -help|?     argument displays helpful information about builtin commands.
   -m.ode      debug, release or releasedebug, default is release.
   -p.latform  specifies the platform name, default is win32_x86.
   -t.ag       specifies the build name.
USAGE

	exit;
}