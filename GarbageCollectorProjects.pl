#!/usr/bin/perl -w

use Date::Calc(qw(Today_and_Now Delta_DHMS Add_Delta_Days));
use Sys::Hostname;
use Getopt::Long;
use File::Path;
use Net::SMTP;

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
GetOptions("help|?"=>\$Help, "directory=s"=>\@Directories);
die("ERROR: the parameter -d is mandatory\n") unless(@Directories);
Usage() if($Help);

########
# Main #
########

@Start = Today_and_Now();
foreach my $Directory (@Directories)
{
    next unless(-d "$Directory\\todelete");
    system("del /s/f/q $Directory\\todelete > nul & rmdir $Directory\\todelete /s/q");
    system("rm -rf $Directory\\todelete") if(-d "$Directory\\todelete");
    warn("ERROR: cannot delete '$Directory\\todelete': $!") if(-d "$Directory\\todelete")
}
printf("Garbage collector took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

#############
# Functions #
#############

sub SendMail {
    my @Messages = @_;

    return if($NumberOfEmails);
    $NumberOfEmails++;
    
    open(HTML, ">$TEMP_DIR/Mail$$.htm") or warn("ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $! at ", __FILE__, " line ", __LINE__, ".\n");
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
    print(HTML "Stack Trace:<br/>\n");
    my $i = 0;
    while((my ($FileName, $Line, $Subroutine) = (caller($i++))[1..3])) {
        print(HTML "File \"$FileName\", line $Line, in $Subroutine.<br/>\n");
    }
    print(HTML "<br/>Best regards\n");
    print(HTML "\t</body>\n");
    print(HTML "</html>\n");
    close(HTML);

    my $smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60) or warn("ERROR: SMTP connection impossible: $! at ", __FILE__, " line ", __LINE__, ".\n");
    $smtp->mail($SMTPFROM);
    $smtp->to(split('\s*;\s*', $SMTPTO));
    $smtp->data();
    $smtp->datasend("To: $SMTPTO\n");
    $smtp->datasend("Subject: [$0] Errors on $HOST\n");
    $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
    open(HTML, "$TEMP_DIR/Mail$$.htm") or warn("ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $! at ", __FILE__, " line ", __LINE__, ".\n");
    while(<HTML>) { $smtp->datasend($_) } 
    close(HTML);
    $smtp->dataend();
    $smtp->quit();

    unlink("$TEMP_DIR/Mail$$.htm") or warn("ERROR: cannot unlink '$TEMP_DIR/Mail$$.htm': $! at ", __FILE__, " line ", __LINE__, ".\n");
}

sub Usage
{
   print <<USAGE;
   Usage   : $GarbageCollectorProjects.pl -d
   Example : $GarbageCollectorProjects.pl -h
             $GarbageCollectorProjects.pl -d=C:

   [option]
   -help|?     argument displays helpful information about builtin commands.
   -d.irectory specifies the one or more directory name.
USAGE
    exit;
}
