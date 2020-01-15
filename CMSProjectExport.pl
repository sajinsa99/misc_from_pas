#!/usr/bin/perl -w

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Sys::Hostname;
use File::Path;
use File::Copy;
use Net::SMTP;
use XML::DOM;

use FindBin;
use lib ($FindBin::Bin);
$ENV{PROJECT} = 'documentation';
require Site;

##############
# Parameters #
##############

$ENV{SMTP_SERVER} ||= "mail.sap.corp";
$SMTPFROM = $SMTPTO = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
$SMTPTO = 'jean.maqueda@sap.com';
$NumberOfEmails = 0;
$HOST = hostname();
#$SIG{__DIE__} = sub { SendMail(@_); die(@_) };
#$SIG{__WARN__} = sub { SendMail(@_); warn(@_) };

die("ERROR: SRC_DIR environment variable must be set") unless($SRC_DIR=$ENV{SRC_DIR});
die("ERROR: PACKAGES_DIR environment variable must be set") unless($PACKAGES_DIR=$ENV{PACKAGES_DIR});
die("ERROR: DROP_DIR environment variable must be set") unless($DROP_DIR=$ENV{DROP_DIR});
die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
die("ERROR: Context environment variable must be set") unless($CONTEXT=$ENV{Context});
die("ERROR: BUILD_NUMBER environment variable must be set") unless($BUILD_NUMBER=$ENV{BUILD_NUMBER});
die("ERROR: MY_DITA_PROJECT_ID environment variable must be set") unless($MY_DITA_PROJECT_ID=$ENV{MY_DITA_PROJECT_ID});
die("ERROR: BUILD_MODE environment variable must be set") unless($BUILD_MODE=$ENV{BUILD_MODE});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});

($CMS_DIR = "$SRC_DIR/cms") =~ s/\\/\//g;
$IsRollingBuild = exists($ENV{MY_PROJECTMAP});

########
# Main #
########

unless($BUILD_MODE eq 'release') { print("[INFO] no export on debug mode\n"); exit }

if($IsRollingBuild)
{
    our(@Project);
    open(DAT, "$ENV{DITA_CONTAINER_DIR}/content/projects/$MY_DITA_PROJECT_ID.dat") or warn("ERROR: cannot open '$ENV{DITA_CONTAINER_DIR}/content/projects/$MY_DITA_PROJECT_ID.dat': $!");
    eval <DAT>;
    close(DAT);
    ($ProjectMap) = $Project[0] =~ /([^\\\/]+\.ditamap)$/;
}
# for compatibility
else { $ProjectMap = ProjectMapFromProject(<$CMS_DIR/content/projects/*.project>) }
# end compatibility

$ProjectMap = "$CMS_DIR/content/localization/en-US/$ProjectMap";
$PROJECTMAP = XML::DOM::Parser->new()->parsefile($ProjectMap);
$LoIO = $PROJECTMAP->getElementsByTagName('project-map')->item(0)->getAttribute('id');
$PROJECTMAP->dispose();
ExportMetadata($CONTEXT, 'latest', "${LoIO}_");
ExportMetadata($CONTEXT, $BUILD_NUMBER, "${LoIO}_.*[\\\/]metadata\.xml\$");
copy($ProjectMap, "$DROP_DIR/$CONTEXT/latest/packages") or warn("ERROR: cannot copy '$ProjectMap': $!");
copy("$CMS_DIR/content/projects/$MY_DITA_PROJECT_ID.project", "$DROP_DIR/$CONTEXT/latest/packages") or warn("ERROR: cannot copy '$CMS_DIR/content/projects/$MY_DITA_PROJECT_ID.project': $!");

$ToPath = "$ENV{OUTPUT_DIR}/obj/packages";
rmtree("$ToPath/collection") or warn("ERROR: cannot rmtree '$ToPath/collection' : $!") if(-d "$ToPath/collection");
rmtree("$ToPath/metadata") or warn("ERROR: cannot rmtree '$ToPath/metadata' : $!") if(-d "$ToPath/metadata");
mkpath($ToPath) or warn("ERROR: cannot mkpath '$ToPath': $!") unless(-d $ToPath);
rename("$PACKAGES_DIR/collection", "$ToPath/collection") or warn("ERROR: cannot rename '$PACKAGES_DIR/collection': $!") if(-d "$PACKAGES_DIR/collection");
rename("$PACKAGES_DIR/metadata", "$ToPath/metadata") or warn("ERROR: cannot rename '$PACKAGES_DIR/metadata': $!") if(-d "$PACKAGES_DIR/metadata");

system("robocopy /E /NS /NC /NFL /NDL /NP /R:3 \"$PACKAGES_DIR\" \"$DROP_DIR/$CONTEXT/$BUILD_NUMBER/packages\" /XF *.ditamap /XF *.project");
copy("$DROP_DIR/$CONTEXT/latest/packages/metadata.zip", $TEMP_DIR) or warn("ERROR: cannot copy '$DROP_DIR/$CONTEXT/latest/packages/metadata.zip': $!");
system("robocopy /E /XO /NS /NC /NFL /NDL /NP /R:3 \"$DROP_DIR/$CONTEXT/$BUILD_NUMBER/packages\" \"$DROP_DIR/$CONTEXT/latest/packages\" /XF *.ditamap /XF *.project");
copy("$TEMP_DIR/metadata.zip", "$DROP_DIR/$CONTEXT/latest/packages") or warn("ERROR: cannot copy '$TEMP_DIR/metadata.zip': $!");

#############
# Functions #
#############

sub ProjectMapFromProject
{
    my($CMSProject) = @_;

    my $PROJECT = XML::DOM::Parser->new()->parsefile($CMSProject);
    my($ProjectMap) = $PROJECT->getElementsByTagName('deliverable')->item(0)->getElementsByTagName('fullpath', 0)->item(0)->getFirstChild()->getData() =~ /([^\\\/]+\.ditamap)$/;
    $PROJECT->dispose();
    return $ProjectMap;
}

sub ExportMetadata {
    my($Project, $Version, $Pattern) = @_;

    my $Zip = Archive::Zip->new();
    warn("ERROR: cannot addTreeMatching '$PACKAGES_DIR/metadata': $!") unless($Zip->addTreeMatching("$PACKAGES_DIR/metadata", 'metadata', $Pattern)==AZ_OK);
    warn("ERROR: cannot writeToFileNamed '$TEMP_DIR/metadata.zip': $!") unless($Zip->writeToFileNamed("$TEMP_DIR/metadata.zip")==AZ_OK);
    mkpath("$DROP_DIR/$Project/$Version/packages") or warn("ERROR: cannot mkpath '$DROP_DIR/$Project/$Version/packages': $!") unless(-d "$DROP_DIR/$Project/$Version/packages");
    copy("$TEMP_DIR/metadata.zip", "$DROP_DIR/$Project/$Version/packages/metadata.zip") or warn("ERROR: cannot copy '$TEMP_DIR/metadata.zip' to '$DROP_DIR/$Project/$Version/packages/metadata.zip' : $!");
    unlink("$TEMP_DIR/metadata.zip") or warn("ERROR: cannot unlink '$TEMP_DIR/metadata.zip': $!");
}

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
    print(HTML "&nbsp;"x5, "We have the following error(s) in $0 on $HOST:<br/>\n");
    foreach (@Messages) {
        print(HTML "&nbsp;"x5, "$_<br/>\n");
    }
    my $i = 0;
    print(HTML "<br/>Stack Trace:<br/>\n");
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

    unlink("$TEMP_DIR/Mail$$.htm") or print(STDERR "ERROR: cannot unlink '$TEMP_DIR/Mail$$.htm': $! at ", __FILE__, " line ", __LINE__, ".\n");;
}