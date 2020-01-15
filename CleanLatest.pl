#!/usr/bin/perl -w

use Date::Calc(qw(Today_and_Now Delta_DHMS Add_Delta_Days Add_Delta_DHMS));
use Sys::Hostname;
use Getopt::Long;
use File::Copy;
use File::Find;
use Net::SMTP;
use XML::DOM;
use JSON;

use FindBin;
use lib ($FindBin::Bin);
$ENV{PROJECT} = 'documentation';
$CURRENT_DIR = $FindBin::Bin;
system("p4 print -o $CURRENT_DIR/Site.pm //internal/core.build.tools/1.0/REL/export/shared/Site.pm");
require Site;

$ENV{SMTP_SERVER} ||= "mail.sap.corp";
$SMTPFROM = $SMTPTO = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
$SMTPTO = 'jean.maqueda@sap.com';
$NumberOfEmails = 0;
$HOST = hostname();
$SIG{__DIE__} = sub { SendMail(@_); die(@_) };
$SIG{__WARN__} = sub { SendMail(@_); warn(@_) };

##############
# Parameters #
##############

die("ERROR: MY_DITA_PROJECT_ID environment variable must be set") unless($ENV{MY_DITA_PROJECT_ID});
die("ERROR: DROP_DIR environment variable must be set") unless($ENV{DROP_DIR});
die("ERROR: SRC_DIR environment variable must be set") unless($ENV{SRC_DIR});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});
die("ERROR: BUILD_NAME environment variable must be set") unless($ENV{BUILD_NAME});
die("ERROR: BUILD_NUMBER environment variable must be set") unless($ENV{BUILD_NUMBER});
die("ERROR: BUILD_MODE environment variable must be set") unless($ENV{BUILD_MODE});
die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
$TEMP_DIR =~ s/[\\\/]\d+$//;

GetOptions("help|?"=>\$Help, "project=s"=>\@Projects);
Usage() if($Help);

########
# Main #
########

$ua = LWP::UserAgent->new() or warn("ERROR: cannot create LWP agent: $!");

unless($ENV{MY_PROJECTMAP})
{
    $PROJECT = XML::DOM::Parser->new()->parsefile("$ENV{SRC_DIR}/cms/content/projects/$ENV{MY_DITA_PROJECT_ID}.project");
    $FullPath = $PROJECT->getElementsByTagName('deliverable')->item(0)->getElementsByTagName('fullpath', 0)->item(0)->getFirstChild()->getData();
    $PROJECT->dispose();
    ($ENV{MY_PROJECTMAP}) = $FullPath =~ /([^\\\/]+)$/;
}
die("ERROR: cannot found the project map for the project '$ENV{MY_DITA_PROJECT_ID}'") unless($ENV{MY_PROJECTMAP});

$PMFrom = "$ENV{DROP_DIR}/$ENV{MY_DITA_PROJECT_ID}/".($ENV{BUILD_NUMBER}-1)."/contexts/allmodes/files/$ENV{MY_PROJECTMAP}";
$PMTo = "$ENV{SRC_DIR}/cms/content/localization/en-US/$ENV{MY_PROJECTMAP}";

unless(-d "$ENV{SRC_DIR}/cms/content/localization") { print(STDERR "ERROR: '$ENV{SRC_DIR}/cms/content/localization' not found.\n"); exit }
system("cd /d $CURRENT_DIR/buildconfigurator & buildconfigurator.bat --deleted --ixiaprojectid $ENV{MY_DITA_PROJECT_ID} --projectmap $PMTo --deletedFile $ENV{OUTPUT_DIR}/obj/ProjectMapTo.json");
copy("$ENV{OUTPUT_DIR}/obj/ProjectMapTo.json", "$ENV{HTTP_DIR}/$ENV{MY_DITA_PROJECT_ID}/$ENV{BUILD_NAME}/ProjectMap.json") or warn("ERROR: cannot copy '$ENV{OUTPUT_DIR}/obj/ProjectMapTo.json': $!");
eval {
    open(JSON, "$ENV{OUTPUT_DIR}/obj/ProjectMapTo.json") or die("ERROR: cannot open '$ENV{OUTPUT_DIR}/obj/ProjectMapTo.json': $!");
    { local $/; $rhProjectTo = ProjectMap(decode_json(<JSON>)) }
    close(JSON);
};
die("ERROR: cannot read JSON from '$PMTo': $@") if($@ or !$rhProjectTo);
if(-f $PMFrom)
{
    system("cd /d $CURRENT_DIR/buildconfigurator & buildconfigurator.bat --deleted  --ixiaprojectid $ENV{MY_DITA_PROJECT_ID} --projectmap $PMFrom --deletedFile $ENV{OUTPUT_DIR}/obj/ProjectMapFrom.json");
    eval {
        open(JSON, "$ENV{OUTPUT_DIR}/obj/ProjectMapFrom.json") or die("ERROR: cannot open '$ENV{OUTPUT_DIR}/obj/ProjectMapFrom.json': $!");
        { local $/; $rhProjectFrom = ProjectMap(decode_json(<JSON>)) }
        close(JSON);
    };
    die("ERROR: cannot read JSON from '$PMFrom': $@") if($@ or !$rhProjectFrom);
}

foreach my $LoIO (keys(%{$rhProjectTo}))
{
    foreach my $Language (keys(%{${$rhProjectTo}{$LoIO}}))
    {
        foreach my $Name (keys(%{${$rhProjectTo}{$LoIO}{$Language}}))
        {
            my($IsDeleted1, $rhChannel1) = @{${$rhProjectTo}{$LoIO}{$Language}{$Name}};
            my($IsDeleted2, $rhChannel2) = @{${$rhProjectFrom}{$LoIO}{$Language}{$Name}} if($rhProjectFrom and exists(${$rhProjectFrom}{$LoIO}) and exists(${$rhProjectFrom}{$LoIO}{$Language}) and exists(${$rhProjectFrom}{$LoIO}{$Language}{$Name}));
            CleanChannel($rhChannel1) if($IsDeleted1 and !$IsDeleted2);
        }
    }
}
foreach my $LoIO (keys(%{$rhProjectFrom}))
{
    foreach my $Language (keys(%{${$rhProjectFrom}{$LoIO}}))
    {
        foreach my $Name (keys(%{${$rhProjectFrom}{$LoIO}{$Language}}))
        {
            my($IsDeleted, $rhChannel) = @{${$rhProjectFrom}{$LoIO}{$Language}{$Name}};
            CleanChannel($rhChannel) if(!$IsDeleted and (!exists(${$rhProjectTo}{$LoIO}) or !exists(${$rhProjectTo}{$LoIO}{$Language}) or !exists(${$rhProjectTo}{$LoIO}{$Language}{$Name})));
        }
    }
}

##############################################################

unless(@Projects)
{
    opendir(PROJECTS, $ENV{IMPORT_DIR}) or die("ERROR: cannot opendir '$ENV{IMPORT_DIR}': $!");
    while(defined($Project = readdir(PROJECTS)))
    {
        next unless($Project=~/^[a-z0-9]{3}\d{13}$/i and -d "$ENV{IMPORT_DIR}/$Project/latest/packages");
        push(@Projects, $Project);
    }
    closedir(PROJECTS);
}

foreach my $Project (@Projects)
{
    my @Start = Today_and_Now();
    print("clean $Project...\n");

    unless(chdir("$ENV{IMPORT_DIR}/$Project/latest/packages")) { warn("ERROR: cannot chdir '$ENV{IMPORT_DIR}/$Project/latest/packages': $!"); next }
    my @ProjectMaps = <*.ditamap>;
    if($#ProjectMaps) { warn("WARNING: not unique ditamap ($ENV{MY_PROJECTMAP}) file in $ENV{IMPORT_DIR}/$Project/latest/packages"); next }
    my @CMSProjects = <*.project>;
    if($#CMSProjects) { warn("ERROR: not unique project file in $ENV{IMPORT_DIR}/$Project/latest/packages"); next }
    warn("WARNING: metadata.zip not found in '$ENV{IMPORT_DIR}/$Project/latest/packages' : zip metadata folder! ") unless(-f 'metadata.zip');
    warn("WARNING: metadata folder found in '$ENV{IMPORT_DIR}/$Project/latest/packages' : zip metadata folder ! ") if(-d 'metadata');

    my $ProjectId = $Project;
    unless(-f "$ENV{IMPORT_DIR}/$Project/latest/packages/$ProjectId.project")
    {
        opendir(PACKAGES, "$ENV{IMPORT_DIR}/$Project/latest/packages") or warn("ERROR: cannot opendir '$ENV{IMPORT_DIR}/$Project/latest/packages': $!");
        while(defined(my $File = readdir(PACKAGES))) { last if(($ProjectId) = $File =~ /^(.+)\.project$/) }
        closedir(PACKAGES);
    }
    my $ProjectMap;
    eval
    {
        my $PROJECT = XML::DOM::Parser->new()->parsefile("$ENV{IMPORT_DIR}/$Project/latest/packages/$ProjectId.project");
        ($ProjectMap) = $PROJECT->getElementsByTagName('deliverable')->item(0)->getElementsByTagName('fullpath', 0)->item(0)->getFirstChild()->getData() =~ /([^\/]+\.ditamap)$/;
        $PROJECT->dispose();
    };
    if($@) { warn("ERROR: cannot parse '$ENV{IMPORT_DIR}/$Project/latest/packages/$ProjectId.project': $@"); next }
    unless($ProjectMap) { warn("ERROR: project map not found in '$ENV{IMPORT_DIR}/$Project/latest/packages/$ProjectId.project'") ; next }
    %Deliverables = ParseProjectMap("$ENV{IMPORT_DIR}/$Project/latest/packages/$ProjectMap", $Project);
    unless(%Deliverables) { warn("ERROR: no deliverables found in '$ENV{IMPORT_DIR}/$Project/latest/packages/$ProjectMap'"); next }
    find(\&Clean, "$ENV{IMPORT_DIR}/$Project/latest/packages");

    printf("\t\tclean $Project/latest folder took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);
}

#############
# Functions #
#############

sub ProjectMap 
{
    my($rhJSON) = @_;
    return undef unless($rhJSON);
    
    my %ProjectMap;
    foreach my $LoIO (keys(%{$rhJSON}))
    {
        my $rhDeliverables = ${$rhJSON}{$LoIO}{deliverables};
        for my $Language (keys(%{$rhDeliverables}))
        {
            my $rhChannels = ${$rhDeliverables}{$Language}{channels};
            foreach my $Name (keys(%{$rhChannels}))
            {
                my $rhChannel = ${$rhChannels}{$Name};
                my $IsDeleted = (${$rhJSON}{$LoIO}{status} eq 'deleted' or ${$rhDeliverables}{$Language}{status} eq 'deleted' or ${$rhChannel}{status} eq 'deleted') ? 1 : 0;
                $ProjectMap{$LoIO}{$Language}{$Name} = [$IsDeleted, $rhChannel];
            }
        }
    }
    return \%ProjectMap;
}

sub CleanChannel
{
    my($rhChannel) = @_;

    if(${$rhChannel}{type} eq 'uacp')
    {
        (my $URL = ${$rhChannel}{uacp_url}) =~s/\/upload_secure$//;
        my $Language = ${$rhChannel}{uacp_locale};
        my $Version = ${$rhChannel}{uacp_version_id};
        (my $LoIO = ${$rhChannel}{uacp_output_id}) =~ s/^loio//;
        my $State = $ENV{BUILD_MODE} eq 'release' ? 'DRAFT' : 'TEST';
        $URL .= "/deliverable\?state=$State&loio=$LoIO&version=$Version&language=$Language";
        #$ua->proxy(['http', 'https'] => $PROXY);
        print("HTTP delete $URL\n");
        my $Request = HTTP::Request->new(DELETE => $URL);
        #$Request->authorization_basic($ENV{DPS_USER}, $ENV{DPS_PASSWORD}) if($ENV{DPS_USER} && $ENV{DPS_PASSWORD});
        $Request->header('Authorization' => "Basic YWRtaW46NjY0MlQkNGg0LkM3aUFwbw==");
        
        my $Response = $ua->request($Request);
        unless($Response->is_success())
        {
            warn("ERROR: unexpected HTTP response of '$URL': ", $Response->status_line());
            print($Response->content(), "\n");
        }
    }
    elsif(${$rhChannel}{type} eq 'dropzone')
    {
        my $Path = ${$rhChannel}{path};
        print("unlink $ENV{DROP_DIR}/$Path\n");
        unlink("$ENV{DROP_DIR}/$Path") or warn("ERROR: cannot unlink '$ENV{DROP_DIR}/$Path': $!") if(-e "$ENV{DROP_DIR}/$Path");
    }
}

sub ParseProjectMap
{
    my($ProjectMap, $Project) = @_;

    my %Deliverables;
    eval
    {
        $DOC = XML::DOM::Parser->new()->parsefile($ProjectMap);
        for my $OUTPUT (@{$DOC->getElementsByTagName('output')})
        {
            (my $TransType = $OUTPUT->getAttribute('transtype')) =~ s/\./00/g;
            for my $DELIVERABLE (@{$OUTPUT->getElementsByTagName('deliverable')})
            {
                my($FileName, $Language, $BuildMode) = ($DELIVERABLE->getAttribute('filename'), $DELIVERABLE->getAttribute('lang'), , $DELIVERABLE->getAttribute('buildMode'));
                $BuildMode = $BuildMode eq 'draft' ? 'debug' : 'release';
                next unless($TransType and $Language and $FileName and $BuildMode eq $ENV{BUILD_MODE});
                print(STDERR "WARNING: deliverable '$ENV{IMPORT_DIR}/$Project/latest/packages/$TransType/$Language/$BuildMode/$FileName' not found.\n") unless(-f "$ENV{IMPORT_DIR}/$Project/latest/packages/$TransType/$Language/$BuildMode/$FileName");
                $Deliverables{"$TransType/$Language/$BuildMode/$FileName"} = undef;
            }
        }
        $DOC->dispose();
    };
    if($@) { warn("ERROR: cannot parse '$ProjectMap': $@"); %Deliverables = () }
    return %Deliverables;
}

sub Clean
{
    return unless($File::Find::dir =~ /\/[a-z]{2}-[A-Z]{2}\/$ENV{BUILD_MODE}$/); 

    my($File) = $File::Find::name =~ /\/([^\/]+\/[^\/]+\/[^\/]+\/[^\/]+)$/;
    if(-d $File::Find::name)
    {
        if(-d "$File::Find::name/plugins")
        {
            my(%Plugins, @Files);
            opendir(PLUGIN, "$File::Find::name/plugins") or die("ERROR: cannot opendir '$File::Find::name/plugins': $!");
            while(defined($JAR = readdir(PLUGIN)))
            {
                next unless((my($Name, $Version) = $JAR =~ /^(.+)\.(\d+)\.jar$/));
                push(@Files, [$Name, $Version]);
                if(exists($Plugins{$Name})) { $Plugins{$Name} = $Version if($Version>$Plugins{$Name}) }
                else { $Plugins{$Name} = $Version }
            }
            closedir(PLUGIN);  
            foreach my $raFile (@Files)
            {
                if(${$raFile}[1] != $Plugins{${$raFile}[0]})
                {
                    print("\tunlink $File::Find::name/plugins/${$raFile}[0].${$raFile}[1].jar\n");
                    unlink("$File::Find::name/plugins/${$raFile}[0].${$raFile}[1].jar") or warn("WARNING: cannot unlink '$File::Find::name/plugins/${$raFile}[0].${$raFile}[1].jar': $!");
                }
            }
        }
    }
    else
    {
        return if(exists($Deliverables{$File}));
        print("\tunlink $File::Find::name\n");
        unlink("$File::Find::name") or warn("WARNING: cannot unlink '$File::Find::name': $!");
    }
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
    print(HTML "&nbsp;"x5, "We have the following error(s) in $0 building $ENV{BUILD_NAME} on $HOST:<br/>\n");
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

    unlink("$TEMP_DIR/Mail$$.htm") or print(STDERR "ERROR: cannot unlink '$TEMP_DIR/Mail$$.htm': $! at ", __FILE__, " line ", __LINE__, ".\n");
}

sub Usage
{
   print <<USAGE;
   Usage   : CleanLatest.pl -p
   Example : CleanLatest.pl -h
             CleanLatest.pl -p=rxy1513190357741

   [option]
   -help|?      argument displays helpful information about builtin commands.
   -p.roject    specifies one or more project names. Default is all projects.
USAGE
    exit;
}
