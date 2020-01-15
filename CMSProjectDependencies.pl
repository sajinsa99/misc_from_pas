#!/usr/bin/perl -w

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Sys::Hostname;
use File::Path;
use File::Copy;
use Net::SMTP;
use XML::DOM;
use JSON;

use FindBin;
use lib ($FindBin::Bin);
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

die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
die("ERROR: SRC_DIR environment variable must be set") unless($SRC_DIR=$ENV{SRC_DIR});
die("ERROR: IMPORT_DIR environment variable must be set") unless($IMPORT_DIR=$ENV{IMPORT_DIR});
die("ERROR: PACKAGES_DIR environment variable must be set") unless($PACKAGES_DIR=$ENV{PACKAGES_DIR});
die("ERROR: Context environment variable must be set") unless($CONTEXT=$ENV{Context});
die("ERROR: MY_DITA_PROJECT_ID environment variable must be set") unless($MY_DITA_PROJECT_ID=$ENV{MY_DITA_PROJECT_ID});
die("ERROR: BUILD_NUMBER environment variable must be set") unless($BUILD_NUMBER=$ENV{BUILD_NUMBER});
die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
($CURRENTDIR = $FindBin::Bin) =~ s/\//\\/g;
($CMS_DIR = "$SRC_DIR/cms") =~ s/\\/\//g;
$IsRollingBuild = exists($ENV{MY_PROJECTMAP});

########
# Main #
########

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

mkpath($PACKAGES_DIR) or warn("ERROR: cannot mkpath '$PACKAGES_DIR': $!") unless(-d $PACKAGES_DIR);
$ProjectMap = "$CMS_DIR/content/localization/en-US/$ProjectMap";
if(-f $ProjectMap) { ImportProjectMapDependencies($ProjectMap) }
else { die("ERROR: project map '$ProjectMap' not found") }
ImportMetadata($CONTEXT, $ProjectMap, 'latest');
if($IsRollingBuild and -d "$IMPORT_DIR/$CONTEXT/latest/packages")
{
    # copy package from latest except matadata sub-folder
    $Result = system("robocopy /E /XO /XX /NS /NC /NFL /NDL /NP /R:3 \"$IMPORT_DIR/$CONTEXT/latest/packages\" \"$IMPORT_DIR/$CONTEXT/$BUILD_NUMBER/packages\" /XD metadata") & 0xff;
    warn("ERROR: cannot robocopy '$IMPORT_DIR/$CONTEXT/latest/packages' to '$IMPORT_DIR/$CONTEXT/$BUILD_NUMBER/packages': $!") if($Result);
}

#############
# Functions #
#############

sub ImportProjectMapDependencies
{
    my($ProjectMap) = @_;
    return if(exists($ProjectMaps{$ProjectMap}));
    $ProjectMaps{$ProjectMap} = undef;

    system("$CURRENTDIR/buildconfigurator/buildconfigurator --projectDependencies true --projectDependenciesFile $TEMP_DIR/deps$$.json -p $ProjectMap");
    open(JSON, "$TEMP_DIR/deps$$.json") or die("ERROR: cannot open '$TEMP_DIR/deps$$.json': $!");
    { local $/; $raProjectDependencies = from_json(<JSON>) }
    close(JSON);
    unlink("$TEMP_DIR/deps$$.json") or warn("ERROR: cannot unlink '$TEMP_DIR/deps$$.json': $!");
    foreach my $rhDependencies (@{$raProjectDependencies})
    {
        unless(${$rhDependencies}{navtitle}) { warn("ERROR: tag 'navtitle' not found in '$ProjectMap'"); next }
        (my $Project = ${$rhDependencies}{navtitle}) =~ s/\.project$//;
        next if(exists($Dependencies{$Project}));
        $Dependencies{$Project} = undef;
        # start migration
        unless(-f "$IMPORT_DIR/$Project/latest/packages/$Project.project")
        {
            warn("WARNING: cannot found '$IMPORT_DIR/$Project/latest/packages/$Project.project'");
            if(-f "$IMPORT_DIR/$Project/latest.xml")
            {
                my $DOC = XML::DOM::Parser->new()->parsefile("$IMPORT_DIR/$Project/latest.xml");
                my($BuildNumber) = $DOC->getElementsByTagName('version')->item(0)->getFirstChild()->getData() =~ /(\d+)$/;
                $DOC->dispose();
                copy("$IMPORT_DIR/$Project/$BuildNumber/contexts/allmodes/files/$Project.project", "$IMPORT_DIR/$Project/latest/packages") or warn("ERROR: cannot copy '$IMPORT_DIR/$Project/$BuildNumber/contexts/allmodes/files/$Project.project': $!");
            } else { warn("ERROR: cannot found '$IMPORT_DIR/$Project/latest.xml'"); next }
        }
        # end migration
        unless(-f "$IMPORT_DIR/$Project/latest/packages/$Project.project") { warn("ERROR: cannot found '$IMPORT_DIR/$Project/latest/packages/$Project.project'"); next }
        my $ProjectMap = ProjectMapFromProject("$IMPORT_DIR/$Project/latest/packages/$Project.project");
        copy("$IMPORT_DIR/$Project/latest/packages/$ProjectMap", $PACKAGES_DIR) or warn("ERROR: cannot copy '$IMPORT_DIR/$Project/latest/packages/$ProjectMap': $!");
        ImportMetadata($Project, "$PACKAGES_DIR/$ProjectMap", 'latest');
        ImportProjectMapDependencies("$PACKAGES_DIR/$ProjectMap");
    }
}

sub ProjectMapFromProject
{
    my($CMSProject) = @_;

    my $PROJECT = XML::DOM::Parser->new()->parsefile($CMSProject);
    my($ProjectMap) = $PROJECT->getElementsByTagName('deliverable')->item(0)->getElementsByTagName('fullpath', 0)->item(0)->getFirstChild()->getData() =~ /([^\\\/]+\.ditamap)$/;
    $PROJECT->dispose();
    return $ProjectMap;
}

sub ImportMetadata
{
    my($Project, $ProjectMap, $Version) = @_;
    
    # start migration
    unless (-f "$IMPORT_DIR/$Project/$Version/packages/metadata.zip") {
        my $PROJECTMAP = XML::DOM::Parser->new()->parsefile($ProjectMap);
        my $LoIO = $PROJECTMAP->getElementsByTagName('project-map')->item(0)->getAttribute('id');
        $PROJECTMAP->dispose();
        my $Zip = Archive::Zip->new();
        warn("ERROR: cannot addTreeMatching '$IMPORT_DIR/$Project/$Version/packages/metadata': $!") unless($Zip->addTreeMatching("$IMPORT_DIR/$Project/$Version/packages/metadata", 'metadata', "${LoIO}_")==AZ_OK);
        warn("ERROR: cannot writeToFileNamed '$TEMP_DIR/metadata.zip': $!") unless($Zip->writeToFileNamed("$TEMP_DIR/metadata.zip")==AZ_OK);
        copy("$TEMP_DIR/metadata.zip", "$IMPORT_DIR/$Project/$Version/packages/metadata.zip") or warn("ERROR: cannot copy '$TEMP_DIR/metadata.zip': $!");
        unlink("$TEMP_DIR/metadata.zip") or warn("ERROR: cannot unlink '$TEMP_DIR/metadata.zip': $!");
    }
    # end migration
    
    chdir($PACKAGES_DIR) or warn("ERROR: cannot chdir '$PACKAGES_DIR': $!");
    $Zip = Archive::Zip->new();
    warn("ERROR: cannot read '$IMPORT_DIR/$Project/$Version/packages/metadata.zip': $!") unless($Zip->read("$IMPORT_DIR/$Project/$Version/packages/metadata.zip") == AZ_OK);
    warn("ERROR: cannot extracTree from '$IMPORT_DIR/$Project/$Version/packages/metadata.zip': $!") unless($Zip->extractTree() == AZ_OK);
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

    unlink("$TEMP_DIR/Mail$$.htm") or print(STDERR "ERROR: cannot unlink '$TEMP_DIR/Mail$$.htm': $! at ", __FILE__, " line ", __LINE__, ".\n");
}