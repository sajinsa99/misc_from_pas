#!/usr/bin/perl -w

use LWP::UserAgent;
use Sys::Hostname;
use Data::Dumper;
use Time::Local;
use File::Path;
use Net::SMTP;
use XML::DOM;
use JSON;

use FindBin;
use lib ($FindBin::Bin);
$CURRENT_DIR = $FindBin::Bin;
$ENV{PROJECT} = 'documentation';
require Site;

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

die("ERROR: MY_DRIVE environment variable must be set") unless(exists($ENV{MY_DRIVE}));
die("ERROR: q_p_buildmode environment variable must be set") unless(exists($ENV{q_p_buildmode}));
die("ERROR: MY_BUILD_NAME environment variable must be set") unless(exists($ENV{MY_BUILD_NAME}));
die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});

$ENV{MY_IS_DELTA_COMPILATION} ||= 0;
$SRC_DIR = "$ENV{MY_DRIVE}:/$ENV{MY_BUILD_NAME}/src";
$OUTPUT_DIR = "$ENV{MY_DRIVE}:/$ENV{MY_BUILD_NAME}/win64_x64/release";
$BuildMode = $ENV{q_p_buildmode};
$Mode = grep({/=debug$/} @ARGV) ? 'debug':'release';

########
# Main #
########

open(TIMESTAMP, "$ENV{DITA_CONTAINER_DIR}/content/projects/deltafetch.timestamp") or warn("ERROR: cannot open '$ENV{DITA_CONTAINER_DIR}/content/projects/deltafetch.timestamp': $!"); 
while(<TIMESTAMP>) { last if(($CurrentSourceDate) = /gmtime=(\d+)/) }
close(TIMESTAMP);
if(($BuildMode ne 'releasedebug' or $Mode ne 'debug') and -f "$SRC_DIR/cms/content/projects/deltafetch.timestamp")
{
    my $PreviousSourceDate;
    open(TIMESTAMP, "$SRC_DIR/cms/content/projects/deltafetch.timestamp") or warn("ERROR: cannot open '$SRC_DIR/cms/content/projects/deltafetch.timestamp': $!"); 
    while(<TIMESTAMP>) { last if(($PreviousSourceDate) = /gmtime=(\d+)/) }
    close(TIMESTAMP);
    if($PreviousSourceDate == $CurrentSourceDate)
    {
        print("[INFO] No changes in '$ENV{DITA_CONTAINER_DIR}/content/projects/deltafetch.timestamp': nothing to do\n");
        open(DAT, ">$ENV{HTTP_DIR}/$ENV{MY_BUILD_NAME}/NothingToDo.dat") or die("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{MY_BUILD_NAME}/NothingToDo.dat': $!");
        print(DAT '@NothingToDo=(', time(), ", 'no changes in $ENV{DITA_CONTAINER_DIR}/content/projects/deltafetch.timestamp');");
        close(DAT);
        exit(0);
    }
}
if(-f "$ENV{IMPORT_DIR}/$ENV{MY_BUILD_NAME}/version.txt")
{
    open(VER, "$ENV{IMPORT_DIR}/$ENV{MY_BUILD_NAME}/version.txt") or die("ERROR: cannot open '$ENV{IMPORT_DIR}/$ENV{MY_BUILD_NAME}/version.txt': $!"); 
    chomp(my $BuildNumber = <VER>);
    close(VER);
    my $BuildRevision = sprintf("%s_%05d", $ENV{MY_BUILD_NAME}, $BuildNumber);
    if(-f "$ENV{HTTP_DIR}/$ENV{MY_BUILD_NAME}/$BuildRevision/$BuildRevision=win64_x64_release_status_1.dat")
    {
        my($codesourcedate, $requester);
        open(DAT, "$ENV{HTTP_DIR}/$ENV{MY_BUILD_NAME}/$BuildRevision/$BuildRevision=win64_x64_release_status_1.dat") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{MY_BUILD_NAME}/$BuildRevision/$BuildRevision=win64_x64_release_status_1.dat");
        { local $/; eval(<DAT>) }
        close(DAT);
        if($requester eq 'buildondemand' and $codesourcedate >= $CurrentSourceDate)
        {
            print("[INFO] The previous on demand build is more recent than the current source date: nothing to do\n");
            open(DAT, ">$ENV{HTTP_DIR}/$ENV{MY_BUILD_NAME}/NothingToDo.dat") or die("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{MY_BUILD_NAME}/NothingToDo.dat': $!");
            print(DAT '@NothingToDo=(', time(), ", 'The previous on demand build is more recent than the current source date');");
            close(DAT);
            exit(0);
        }
    }
}

$IsInitial = (-f "$SRC_DIR/cms/content/projects/$ENV{MY_BUILD_NAME}.project.mf.xml") ? 0 : 1;
my(@Project);
open(DAT, "$ENV{DITA_CONTAINER_DIR}/content/projects/$ENV{MY_BUILD_NAME}.dat") or die("ERROR: cannot open '$ENV{DITA_CONTAINER_DIR}/content/projects/$ENV{MY_BUILD_NAME}.dat': $!");
eval <DAT>;
close(DAT);
die("ERROR: no project found in '$ENV{DITA_CONTAINER_DIR}/content/projects/$ENV{MY_BUILD_NAME}.dat'") unless($Project[0]);
exit(0) if($BuildMode eq 'releasedebug' and $Mode eq 'debug' and (!-d $OUTPUT_DIR or -f "$SRC_DIR/cms/content/localization/en-US/$Project[0].empty"));
unlink("$SRC_DIR/cms/content/localization/en-US/$Project[0].empty") or warn("ERROR: cannot unlink '$SRC_DIR/cms/content/localization/en-US/$Project[0].empty': $!") if(-f "$SRC_DIR/cms/content/localization/en-US/$Project[0].empty");
system("perl $CURRENT_DIR/Build.pl @ARGV -q=MY_SRC_DIR_TO_DELETE: -q=MY_PROJECTMAP:$Project[0] -q=MY_FALLBACK_LANGUAGE:localization/$Project[2] -q=MY_IS_DELTA_COMPILATION:1 -q=MY_IS_INITIAL_BUILD=$IsInitial");

open(VER, "$ENV{IMPORT_DIR}/$ENV{MY_BUILD_NAME}/version.txt") or warn("ERROR: cannot open '$ENV{IMPORT_DIR}/$ENV{MY_BUILD_NAME}/version.txt': $!");
chomp($BuildNumber = <VER>);
close(VER);
$ua = LWP::UserAgent->new(ssl_opts =>{ verify_hostname=>0}, protocols_allowed=>['https']) or warn("ERROR: cannot create LWP agent: $!");
$Request = HTTP::Request->new('GET', sprintf("$ENV{CIS_HREF}/cgi-bin/DAMJSON.pl?stream=$ENV{MY_BUILD_NAME}&tag=$ENV{MY_BUILD_NAME}_%05d", $BuildNumber), ['Content-Type'=>'application/json;charset=UTF-8']);
$Response = $ua->request($Request);
if($Response->is_success())
{
    my $rhJSON;
    eval { $rhJSON = from_json($Response->decoded_content()) };
    if($@)
    {
        warn("ERROR: unexpected json response : $@");
        print($Response->content(), "\n");
    }
    else
    {
        $SourceDate = ${${$rhJSON}{infra}}{codesourcedate};
        foreach my $rhLang (@{${$rhJSON}{langs}})
        {
            foreach my $Mode (keys(%{${$rhLang}{build}}))
            {
                foreach $rhOutput (@{${${$rhLang}{build}}{$Mode}})
                {
                    next unless(exists(${${$rhOutput}{errors}}{FATAL}));
                    push(@Outputs, [${$rhOutput}{mapTitle}, ${$rhOutput}{documentLink}, ${$rhOutput}{type}, ${$rhLang}{lang}, ${${$rhOutput}{errors}}{FATAL}, $Mode, ${$rhOutput}{logOverview}, ${$rhOutput}{fullLogLink}]);
                }
            }
        }
    }
}
else
{
    warn("ERROR: unexpected HTTP response : ", $Response->status_line());
    print($Response->content(), "\n");
}
SendFatalErrorsMail() if(@Outputs);

#############
# Functions #
#############

sub SendFatalErrorsMail
{
    my($DocBase) = $ENV{MY_TEXTML} =~ /\/(.+)$/;
    return unless($DocBase eq 'dita');

    my $ProjectTitle;
    eval
    {
        my $PROJECT = XML::DOM::Parser->new()->parsefile("$ENV{DITA_CONTAINER_DIR}/content/projects/$ENV{MY_BUILD_NAME}.project");
        $ProjectTitle = $PROJECT->getElementsByTagName('title')->item(0)->getFirstChild()->getData();
        $PROJECT->dispose();
    };
    warn("ERROR: cannot parsefile the project '$ENV{DITA_CONTAINER_DIR}/content/projects/$ENV{MY_BUILD_NAME}.project': $@") if($@);

    my @DocLeads;
    eval
    {
        my $CUSTOMPROPERTIES = XML::DOM::Parser->new()->parsefile("$ENV{DITA_CONTAINER_DIR}/content/projects/$ENV{MY_BUILD_NAME}.customproperties");
        for my $ASSIGNMENT (@{$CUSTOMPROPERTIES->getElementsByTagName('assignment')})
        {
            next unless($ASSIGNMENT->getAttribute('role') eq 'Doc Lead');
            for my $ASSIGNEDTO (@{$ASSIGNMENT->getElementsByTagName('assignedTo')})
            {
                push(@DocLeads, $ASSIGNEDTO->getFirstChild()->getData());
            }
        }
        $CUSTOMPROPERTIES->dispose();
    };
    warn("ERROR: cannot parsefile the project '$ENV{DITA_CONTAINER_DIR}/content/projects/$ENV{MY_BUILD_NAME}.customproperties': $@") if($@);
    my $DocLeads = join(';', map({ /\[([^\]]+)\]/; $1 } @DocLeads));
    $DocLeads =~ s/pBlack\@sap.com;//g;
    unless($DocLeads) { warn("ERROR: the project '$ProjectTitle' ($ENV{MY_BUILD_NAME}) doesn't contain doc leads"); return }

    $DocLeads .= ';stephane.albucher@sap.com'; # DEBUG

    open(HTML, ">$TEMP_DIR/Mail$$.htm") or die("ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $!");
    print(HTML "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n");
    print(HTML "<html>\n");
    print(HTML "\t<head>\n");
    print(HTML "\t\t<meta http-equiv=\"content-type\" content=\"text/html; charset=UTF-8\"/>\n");
    print(HTML "\t\t<title>Build Unit History</title>\n");
    print(HTML "\t\t<style type='text/css'>\n");
    print(HTML "\t\t\tbody { background:white }\n");
    print(HTML "\t\t\t.n0110 {border-right:solid black 1px;border-bottom:solid black 1px;padding-left:0.1cm;padding-right:0.1cm}\n");
    print(HTML "\t\t\t.n0111 {border-right:solid black 1px;border-bottom:solid black 1px;border-left:solid black 1px;padding-left:0.1cm;padding-right:0.1cm}\n");
    print(HTML "\t\t\t.b1111 {text-align:center;border:solid black 1px;color:black;background:#BDD3EF;font-weight:bold;padding-left:0.1cm;padding-right:0.1cm}\n");
    print(HTML "\t\t\t.b1110 {text-align:center;border-right:solid black 1px;border-top:solid black 1px;border-right:solid black 1px;border-bottom:solid black 1px;color:black;background:#BDD3EF;font-weight:bold;padding-left:0.1cm;padding-right:0.1cm}\n");
    print(HTML "\t\t</style>\n");
    print(HTML "\t</head>\n");
    print(HTML "\t<body>\n");
    print(HTML "*****This email has been sent from an unmonitored automatic mailbox.*****<br/><br/>\n");
    print(HTML "Hi everyone,<br/><br/>\n");
    print(HTML "&nbsp;"x5, "We have the following fatal error(s) building the project '$ProjectTitle' ($ENV{MY_BUILD_NAME}) Build Revision : $BuildNumber, Source Date : ", FormatDate($SourceDate), " :<br/><br/>\n");
    print(HTML "Please follow the <a href='https://jam4.sapjam.com/wiki/show/cOTRqd5UGxeMyf1qgRvdIW'>support process</a> would you need further info or help.<br/>\n");
    print(HTML "\t\t<table border='0' cellpadding='0' cellspacing='0'>\n");
    print(HTML "\t\t\t<tr>\n");
    print(HTML "\t\t\t\t<td class='b1111'>Output Title</td>\n");
    print(HTML "\t\t\t\t<td class='b1110'>Output File Name</td>\n");
    print(HTML "\t\t\t\t<td class='b1110'>Type</td>\n");
    print(HTML "\t\t\t\t<td class='b1110'>Language</td>\n");
    print(HTML "\t\t\t\t<td class='b1110'>Fatals</td>\n");
    print(HTML "\t\t\t\t<td class='b1110'>Mode</td>\n");
    print(HTML "\t\t\t</tr>\n");
    foreach my $raOutput (@Outputs)
    { 
        print(HTML "\t\t\t<tr>\n");
        print(HTML "\t\t\t\t<td class='n0111'>${$raOutput}[0]</td>\n");
        my($FileName) = ${$raOutput}[1] =~ /([^\\\/]+)$/;
        print(HTML "\t\t\t\t<td class='n0110'>$FileName</td>\n");
        print(HTML "\t\t\t\t<td class='n0111'>${$raOutput}[2]</td>\n");
        print(HTML "\t\t\t\t<td class='n0111'>${$raOutput}[3]</td>\n");
        print(HTML "\t\t\t\t<td class='n0111'><a href='$ENV{CIS_HREF}/cgi-bin/loganalyser.pl?summarylog=${$raOutput}[6]&amp;fulllog=${$raOutput}[7]'>${$raOutput}[4]</a></td>\n");
        print(HTML "\t\t\t\t<td class='n0111'>", ${$raOutput}[5] eq 'release' ? 'production' : 'draft', "</td>\n");
        print(HTML "\t\t\t</tr>\n");
    }
    print(HTML "\t\t</table>\n");
    print(HTML "<br/>Best regards\n");
    print(HTML "\t</body>\n");
    print(HTML "</html>\n");
    close(HTML);

    my $smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60) or warn("ERROR: SMTP connection impossible: $!");
    $smtp->mail($SMTPFROM);
    $smtp->to(split('\s*;\s*', $DocLeads));
    $smtp->data();
    $smtp->datasend("To: $DocLeads\n");
    $smtp->datasend("Subject: Fatal error(s) building '$ProjectTitle' ($ENV{MY_BUILD_NAME})\n");
    $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
    open(HTML, "$TEMP_DIR/Mail$$.htm") or warn("ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $!");
    while(<HTML>) { $smtp->datasend($_) } 
    close(HTML);
    $smtp->dataend();
    $smtp->quit();

    unlink("$TEMP_DIR/Mail$$.htm") or warn("ERROR: cannot unlink '$TEMP_DIR/Mail$$.htm': $!");
}

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
    print(HTML "&nbsp;"x5, "We have the following error(s) in $0 building $ENV{BUILD_NAME} on $HOST:<br/>\n");
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

sub FormatDate
{
    my($Time) = @_;
    my($ss, $mn, $hh, $dd, $mm, $yy, $wd, $yd, $isdst) = localtime($Time);
    return sprintf("%04u/%02u/%02u %02u:%02u:%02u", $yy+1900, $mm+1, $dd, $hh, $mn, $ss);
}