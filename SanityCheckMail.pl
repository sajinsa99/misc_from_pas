#!/usr/bin/perl -w

use Net::SMTP;

##############
# Parameters #
##############

die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});
die("ERROR: BUILD_NAME environment variable must be set") unless($ENV{BUILD_NAME});
die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/[\\\/]\d+$//;
$SMTPFROM = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
$CIS_HREF = $ENV{CIS_HREF} || 'http://cis_wdf.pgdev.sap.corp:1080';
$ENV{SMTP_SERVER} ||= "mail.sap.corp";
($Stream) = $ENV{BUILD_NAME} =~ /^(.+)_\d+$/;

########
# Main #
########

our($SapValidateProjectContainers, $DocbaseValidate);
foreach my $BuildUnit (qw(SapValidateProjectContainers DocbaseValidate))
{
    ${$BuildUnit} = 0;
    open(TXT, "$ENV{OUTPUT_DIR}/logs/Build/$BuildUnit.summary.txt") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/Build/$BuildUnit.summary.txt': $!");
    while(<TXT>)
    {
        ${$BuildUnit}++ if(/^\[ERROR\s+\@\d+\]/);
    }
    close(TXT);
}
SendMail('DL_525E83D6DF15DB5741002C7A@exchange.sap.corp') if($SapValidateProjectContainers);
SendMail('DL_522F903BFD84A01F490040AE@exchange.sap.corp') if($DocbaseValidate);

#############
# Functions #
#############

sub SendMail
{
    my($SMTPTO) = @_;
    
    open(HTML, ">$TEMPDIR/Mail$$.htm") or die("ERROR: cannot open '$TEMPDIR/Mail$$.htm': $!");
	print(HTML "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n");
    print(HTML "<html>\n");
    print(HTML "\t<body>\n");
    print(HTML "*****This email has been sent from an unmonitored automatic mailbox.*****<br/><br/>\n");
    print(HTML "Hi everyone,<br/><br/>\n");
    print(HTML "&nbsp;"x5, "We have error(s) in $ENV{BUILD_NAME} build<br/>\n");
    print(HTML "&nbsp;"x5, "Click here <a href='$CIS_HREF/cgi-bin/BuildErrors.pl?tag=$ENV{BUILD_NAME}&stream=$Stream&mode=release&platform=win64_x64&phase=build'>$ENV{BUILD_NAME}</a> for more details.<br/>\n");
    print(HTML "<br/>Best regards\n");
    print(HTML "\t</body>\n");
    print(HTML "</html>\n");
    close(HTML);

    my $smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60) or warn("ERROR: SMTP connection impossible: $!");
    $smtp->mail($SMTPFROM);
    $smtp->to(split('\s*;\s*', $SMTPTO));
    $smtp->data();
    $smtp->datasend("To: $SMTPTO\n");
    $smtp->datasend("Subject: Errors on $ENV{BUILD_NAME}\n");
    $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
    open(HTML, "$TEMPDIR/Mail$$.htm") or die ("ERROR: cannot open '$TEMPDIR/Mail$$.htm': $!");
    while(<HTML>) { $smtp->datasend($_) } 
    close(HTML);
    $smtp->dataend();
    $smtp->quit();

    unlink("$TEMPDIR/Mail$$.htm") or die("ERROR: cannot unlink '$TEMPDIR/Mail$$.htm': $!");
}