#!/usr/bin/perl -w

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use LWP::Simple qw(getstore is_error);
use Sys::Hostname;
use Getopt::Long;
use Net::SMTP;
use XML::DOM;

use FindBin;
use lib ($FindBin::Bin);
$ENV{PW_DIR} ||= (($^O eq 'MSWin32') ? '\\\\build-drops-wdf\dropzone\documentation\.pegasus' : '/net/build-drops-wdf/dropzone/documentation/.pegasus');
require  Perforce;

$ENV{SMTP_SERVER} ||= "mail.sap.corp";
$SMTPFROM = $SMTPTO = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
$NumberOfEmails = 0;
$HOST = hostname();
$SIG{__DIE__} = sub { SendMail(@_); die(@_) };
$SIG{__WARN__} = sub { SendMail(@_); warn(@_) };

##############
# Parameters #
##############

die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});

GetOptions("help|?"=>\$Help, "client=s"=>\$CLIENT, "root=s"=>\$ROOTDIR);
Usage() if($Help);

$PLATFORM = ($^O eq "MSWin32") ? "windows" : "unix";
$ENV{P4USER} ||= (`p4 set P4USER`=~/^P4USER=(\w+)/, $1) || ($PLATFORM eq "windows" ? $ENV{USERNAME} : $ENV{USER});
$ENV{P4USER} =~ /^\s*.+\s*$/;
$ENV{HOME} ||= $PLATFORM eq "windows" ? "C:/cygwin/home/$ENV{P4USER}" : "/build/$ENV{P4USER}";
$CLIENT ||= "$ENV{P4USER}_$HOST";
$ROOTDIR ||= ($PLATFORM eq "windows") ? "C:\\" : $ENV{HOME};
$ENV{CBT_BRANCH} ||= '1.0/REL';
$ROOTDIR =~ s/[\/\\]$//;
$CURRENTDIR = $FindBin::Bin;
$DITA_OUTPUT_PROD = '\\\\build-drops-wdf\dropzone\documentation\dita_output_prod';
$CORE_BUILD_TOOLS = '\\\\build-drops-wdf\dropzone\Build_Tools\cbt';
# @Nexus = [platform, url, artifact, root, destination]
push(@Nexus, ['windows', 'http://nexus.wdf.sap.corp:8081/nexus/content/groups/build.milestones/com/sap/prd/access/credentials/com.sap.prd.access.credentials.dist.cli/2.8', 'com.sap.prd.access.credentials.dist.cli-2.8.zip', 'prodpassaccess-2.8', "$CURRENTDIR/prodpassaccess"]);
push(@Nexus, ['windows', 'http://nexus.wdf.sap.corp:8081/nexus/content/groups/build.milestones/com/sap/prd/commonrepo/artifactdeployer/com.sap.prd.commonrepo.artifactdeployer.dist.cli/0.16.3', 'com.sap.prd.commonrepo.artifactdeployer.dist.cli-0.16.3.zip', 'artifactdeployer-0.16.3', "$CURRENTDIR/artifactdeployer"]);
push(@Nexus, ['windows', 'http://nexus.wdf.sap.corp:8081/nexus/content/groups/build.milestones/com/sap/prd/commonrepo/artifactimporter/com.sap.prd.commonrepo.artifactimporter.dist.cli/0.6', 'com.sap.prd.commonrepo.artifactimporter.dist.cli-0.6.zip', 'artifactimporter-0.6', "$CURRENTDIR/artifactimporter"]);
push(@Nexus, ['windows', 'http://nexus.wdf.sap.corp:8081/nexus/content/repositories/build.milestones/com/sap/prd/codesign/mavenclient/com.sap.prd.codesign.mavenclient.dist.cli/0.3', 'com.sap.prd.codesign.mavenclient.dist.cli-0.3-dist.zip', 'mavenclient-0.3', "$CURRENTDIR/mavenclient"]);

########
# Main #
########

print("\nSTART of $0 (".scalar(localtime()).")\n\n");
print("###\nCurrent user is : $ENV{P4USER}\n###\n");

$CONTEXT = XML::DOM::Parser->new()->parsefile("$DITA_OUTPUT_PROD\\greatest.xml");  
($Version) = $CONTEXT->getElementsByTagName("version")->item(0)->getFirstChild()->getData() =~ /(\d+)$/;
$CONTEXT->dispose();
system("robocopy /MIR /NP /NFL /NDL /R:3 \"$DITA_OUTPUT_PROD\\$Version\\win64_x64\\release\\bin\" \"$CURRENTDIR\\bin\\dita_output_prod\"");
system("robocopy /MIR /NP /NFL /NDL /R:3 \"$CURRENTDIR\\bin\\dita_output_prod\\core.build.tools.docs\\buildconfigurator\" \"$CURRENTDIR\\buildconfigurator\"");
$CONTEXT = XML::DOM::Parser->new()->parsefile("$CORE_BUILD_TOOLS\\greatest.xml");  
($Version) = $CONTEXT->getElementsByTagName("version")->item(0)->getFirstChild()->getData() =~ /(\d+)$/;
$CONTEXT->dispose();
system("robocopy /MIR /NP /NFL /NDL /R:3 \"$CORE_BUILD_TOOLS\\$Version\\win64_x64\\release\\bin\\core.build.tools\" \"$CURRENTDIR\\bin\\core.build.tools\"");

foreach (@Nexus)
{
    my($Platform, $URL, $Artifact, $Root, $Destination) = @{$_};
    next unless($Platform eq $PLATFORM || $Platform=~/^all$/i);
    unlink("$CURRENTDIR/$Artifact") or warn("ERROR: cannot unlink '$CURRENTDIR/$Artifact': $!") if(-f "$CURRENTDIR/$Artifact");	
    my $rc = getstore("$URL/$Artifact", "$CURRENTDIR/$Artifact");
    `wget $URL/$Artifact` unless(-f "$CURRENTDIR/$Artifact");
    if(-f "$CURRENTDIR/$Artifact")
    {
        if($Artifact =~ /\.zip$/i)
        {
            my $Zip = Archive::Zip->new();
            warn("ERROR: cannot read '$CURRENTDIR/$Artifact': $!") unless($Zip->read("$CURRENTDIR/$Artifact") == AZ_OK);
            warn("ERROR: cannot extractTree '$Root': $!") unless($Zip->extractTree($Root, $Destination) == AZ_OK);
        } elsif($Artifact =~ /\.tar.gz$/) { warn("ERROR: format tar.gz not supported") }    
    } else { warn("ERROR: cannot getstore '$URL/$Artifact': $rc") }
}

$p4 = new Perforce;
$p4->Logon();
warn("ERROR: cannot perforce logon: ", @{$p4->Errors()}) if($p4->ErrorCount());
$p4->SetOptions("-z Bootstrap -c \"$CLIENT\"");
$rhClient = $p4->FetchClient($CLIENT);
die("ERROR: cannot fetch client '$CLIENT': ", @{$p4->Errors()}) if($p4->ErrorCount());
${$rhClient}{Options} = 'allwrite clobber nocompress unlocked nomodtime rmdir';
${$rhClient}{Root} = $ROOTDIR;
delete ${$rhClient}{View};
push(@{${$rhClient}{View}}, "//depot2/Main/Stable/Build/... //$CLIENT/Build/...");
push(@{${$rhClient}{View}}, "//internal/core.build.tools/$ENV{CBT_BRANCH}/... //$CLIENT/core.build.tools/...");
push(@{${$rhClient}{View}}, "//internal/cis/1.0/REL/cgi-bin/... //$CLIENT/cis/cgi-bin/...");
push(@{${$rhClient}{View}}, "+//product/cbt/1.0/REL/export/shared/contexts/*.ini //$CLIENT/core.build.tools/export/shared/contexts/*.ini");
push(@{${$rhClient}{View}}, "+//product/documentation/1.0/REL/export/shared/contexts/*.ini //$CLIENT/core.build.tools/export/shared/contexts/*.ini");
push(@{${$rhClient}{View}}, "-//internal/core.build.tools/$ENV{CBT_BRANCH}/ixiasoft_deltafetch052019/... //$CLIENT/core.build.tools/export/shared/ixiasoft_deltafetch052019/...");
$p4->SaveClient($rhClient);
die("ERROR: cannot save client '$CLIENT': ", @{$p4->Errors()}) if($p4->ErrorCount());
$p4->sync("-f");
die("ERROR: cannot sync '$CLIENT': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);

print("\n\nEND of $0 (".scalar(localtime()).")\n\n");
END { $p4->Final() if($p4) } 

#############
# Functions #
#############

sub SendMail {
    my @Messages = @_;

    return if($NumberOfEmails);
    $NumberOfEmails++;
    
    open(HTML, ">$TEMP_DIR/Mail$$.htm") or print(STDERR "ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $! at ", __FILE__, " line ", __LINE__, ".\n");
    print(HTML "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n");
    print(HTML "<html>\n");
    print(HTML "\t<head>\n");
    print(HTML "\t</head>\n");
    print(HTML "\t<body>\n");
    print(HTML "*****This email has been sent from an unmonitored automatic mailbox.*****<br/><br/>\n");
    print(HTML "Hi everyone,<br/><br/>\n");
    print(HTML "&nbsp;"x5, "We have the following error(s) in $0 on $HOST with $ENV{USERDOMAIN}\\$ENV{USERNAME} :<br/>\n");
    foreach (@Messages) {
        print(STDERR);
        print(HTML "&nbsp;"x5, "$_<br/>\n");
    }
    print(HTML "Stack Trace:<br/>\n");
    my $i = 0;
    while((my ($FileName, $Line, $Subroutine) = (caller($i++))[1..3])) {
        print(HTML "File \"$FileName\", line $Line, in $Subroutine.<br/>\n");
    }
    print(HTML "<br/>Best regards\n");
    print(HTML "\t</body>\n");
    print(HTML "</html>\n");
    close(HTML);

    my $smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60) or print(STDERR "ERROR: SMTP connection impossible: $! at ", __FILE__, " line ", __LINE__, ".\n");
    $smtp->mail($SMTPFROM);
    $smtp->to(split('\s*;\s*', $SMTPTO));
    $smtp->data();
    $smtp->datasend("To: $SMTPTO\n");
    my($Script) = $0 =~ /([^\/\\]+)$/; 
    $smtp->datasend("Subject: [$Script] Errors on $HOST\n");
    $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
    open(HTML, "$TEMP_DIR/Mail$$.htm") or print(STDERR "ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $! at ", __FILE__, " line ", __LINE__, ".\n");
    while(<HTML>) { $smtp->datasend($_) } 
    close(HTML);
    $smtp->dataend();
    $smtp->quit();

    unlink("$TEMP_DIR/Mail$$.htm") or print(STDERR "ERROR: cannot unlink '$TEMP_DIR/Mail$$.htm': $! at ", __FILE__, " line ", __LINE__, ".\n");
}

sub Usage
{
   print <<USAGE;
   Usage   : $0.pl -r
   Example : $0.pl -h
             $0.pl -r=C:\\My_Depot -c=My_Client

   [option]
   -help|?     argument displays helpful information about builtin commands.
   -r.oot      specifies the view relative directory, default is C:\ (windows) or \$HOME (unix)
   -c.lient    specifies the client spec name to be created, default is \$USER_\$HOST.
USAGE
    exit;
}
