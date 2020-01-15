#!/usr/bin/perl -w

use Sys::Hostname;
use Net::SMTP;

use FindBin;
use lib ($FindBin::Bin);

die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});

$ENV{SMTP_SERVER} ||= "mail.sap.corp";
$SMTPFROM = $SMTPTO = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
$SMTPTO = 'jean.maqueda@sap.com';
$NumberOfEmails = 0;
$HOST = hostname();
$SIG{__DIE__} = sub { SendMail(@_); die(@_) };
$SIG{__WARN__} = sub { SendMail(@_); warn(@_) };

$CURRENT_DIR = $FindBin::Bin;
$ENV{PW_DIR} ||= '\\\\build-drops-wdf\dropzone\documentation\.pegasus';
$ENV{PRODPASSACCESS_DIR} ||= "$CURRENT_DIR/prodpassaccess";
$CREDENTIAL = "$ENV{PW_DIR}/.credentials.properties";
$MASTER = "$ENV{PW_DIR}/.master.xml";

open(CRED, $CREDENTIAL) or warn("ERROR: cannot open '$CREDENTIAL': $!");
while(<CRED>)
{
    next unless(my($Purpose) = /^\s*(.+)\.user\s*=/);
    next unless($Purpose eq 'PUBLISH');
    $ENV{"${Purpose}_USER"} ||= `$ENV{PRODPASSACCESS_DIR}/bin/prodpassaccess --credentials-file $CREDENTIAL --master-file $MASTER get $Purpose user`; chomp($ENV{"${Purpose}_USER"});
    $ENV{"${Purpose}_PASSWORD"} ||= `$ENV{PRODPASSACCESS_DIR}/bin/prodpassaccess --credentials-file $CREDENTIAL --master-file $MASTER get $Purpose password`; chomp($ENV{"${Purpose}_PASSWORD"});
}
close(CRED);

require Perforce;
$p4 = new Perforce;
$raClients = $p4->clients("-E *_$HOST");
warn("ERROR: cannot 'p4 clients -E *_$HOST' : ", @{$p4->Errors()}) if($p4->ErrorCount());
foreach (@{$raClients}) {
    next unless(my($P4Client) = /^Client\s+(.*?_$HOST)/);
    if($P4Client =~ /_pub_$HOST$/) {
        $p4->SetOptions(" -c $P4Client -u $ENV{PUBLISH_USER}");
        $p4->SetPassword($ENV{PUBLISH_PASSWORD});
    } else { $p4->SetOptions(" -c $P4Client") }
    my $raOpened = $p4->opened("-C $P4Client");
    warn("ERROR: cannot opened: @{$p4->Errors()}") if($p4->ErrorCount() and ${$p4->Errors()}[0]!~/File\(s\) not opened anywhere\.$/);
    foreach (@{$raOpened}) {
        next unless(my($File) = /^(.+?)#\d+\s+-\s+/);
        my $raRevert = $p4->revert("\"$File\"");
        warn("ERROR: cannot revert '$File': ", @{$p4->Errors()}) if($p4->ErrorCount());
        print("@{$raRevert}\n");
    }
    my $raChanges = $p4->changes("-c $P4Client -s pending");
    warn("ERROR: cannot changes -c $P4Client: @{$p4->Errors()}") if($p4->ErrorCount());
    foreach (@{$raChanges}) {
        next unless(my($Change) = /^Change\s+(\d+)\s+on/);
        my $raResults = $p4->change("-d $Change");
        warn("ERROR: cannot change -d $Change: @{$p4->Errors()}") if($p4->ErrorCount());
        print(@{$raResults});
    }
    if($P4Client =~ /_pub_$HOST$/) {
        my $raResults = $p4->client("-d $P4Client");
        warn("ERROR: cannot 'p4 client -d $P4Client' : ", @{$p4->Errors()}) if($p4->ErrorCount());
        print(@{$raResults});
    }
}
END { $p4->Final() }

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
    foreach (@Messages) { print(HTML "&nbsp;"x5, "$_<br/>\n") }
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