#!/usr/bin/perl -w

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Sys::Hostname;

$ENV{SMTP_SERVER} ||= "mail.sap.corp";
$SMTPFROM = $SMTPTO = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
$SMTPTO = 'jean.maqueda@sap.com';
$NumberOfEmails = 0;
$HOST = hostname();
#$SIG{__DIE__} = sub { SendMail(@_); die(@_) };
#$SIG{__WARN__} = sub { SendMail(@_); warn(@_) };

##############
# Parameters #
##############

die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
die("ERROR: SRC_DIR environment variable must be set") unless($ENV{SRC_DIR});
die("ERROR: IMPORT_DIR environment variable must be set") unless($ENV{IMPORT_DIR});
die("ERROR: PACKAGES_DIR environment variable must be set") unless($ENV{PACKAGES_DIR});
die("ERROR: RC_BUILD_NAME environment variable must be set") unless($ENV{RC_BUILD_NAME});
die("ERROR: RC_BUILD_NUMBER environment variable must be set") unless($ENV{RC_BUILD_NUMBER});

########
# Main #
########

system("robocopy /MIR /NP /NFL /NDL /R:3 \"$ENV{IMPORT_DIR}/$ENV{RC_BUILD_NAME}/$ENV{RC_BUILD_NUMBER}/packages\" \"$ENV{PACKAGES_DIR}\"");
foreach my $Folder (qw(cms cms/content/authoring cms/content/localization/en-US cms/content/projects))
{
    system("robocopy /MIR /NP /NFL /NDL /R:3 \"$ENV{IMPORT_DIR}/$ENV{RC_BUILD_NAME}/$ENV{RC_BUILD_NUMBER}/contexts/allmodes/files\" \"$ENV{SRC_DIR}/$Folder\"");
}
if(-f "$ENV{PACKAGES_DIR}/metadata.zip")
{
    chdir($ENV{PACKAGES_DIR}) or warn("ERROR: cannot chdir '$ENV{PACKAGES_DIR}': $!");
    $Zip = Archive::Zip->new();
    warn("ERROR: cannot read 'metadata.zip': $!") unless($Zip->read("metadata.zip") == AZ_OK);
    warn("ERROR: cannot extracTree from 'metadata.zip': $!") unless($Zip->extractTree() == AZ_OK);
}

#############
# Functions #
#############

sub SendMail
{
    my @Messages = @_;

    return if($NumberOfEmails);
    $NumberOfEmails++;
    
    open(HTML, ">$TEMP_DIR/Mail$$.htm") or die("ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $!");
    print(HTML "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n");
    print(HTML "<html>\n");
    print(HTML "\t<head>\n");
    print(HTML "\t</head>\n");
    print(HTML "\t<body>\n");
    print(HTML "*****This email has been sent from an unmonitored automatic mailbox.*****<br/><br/>\n");
    print(HTML "Hi everyone,<br/><br/>\n");
    print(HTML "&nbsp;"x5, "We have the following error(s) in $0 on $HOST:<br/>\n");
    foreach (@Messages)
    {
        print(HTML "&nbsp;"x5, "$_<br/>\n");
    }
    print(HTML "<br/>Best regards\n");
    print(HTML "\t</body>\n");
    print(HTML "</html>\n");
    close(HTML);

    my $smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60) or warn("ERROR: SMTP connection impossible: $!");
    $smtp->mail($SMTPFROM);
    $smtp->to(split('\s*;\s*', $SMTPTO));
    $smtp->data();
    $smtp->datasend("To: $SMTPTO\n");
    my($Script) = $0 =~ /([^\/\\]+)$/; 
    $smtp->datasend("Subject: [$Script] Errors on $HOST\n");
    $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
    open(HTML, "$TEMP_DIR/Mail$$.htm") or warn("ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $!");
    while(<HTML>) { $smtp->datasend($_) } 
    close(HTML);
    $smtp->dataend();
    $smtp->quit();

    unlink("$TEMP_DIR/Mail$$.htm") or warn("ERROR: cannot unlink '$TEMP_DIR/Mail$$.htm': $!");
}