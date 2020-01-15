#!/usr/bin/perl -w

use Date::Calc(qw(Today_and_Now Delta_DHMS Add_Delta_Days Add_Delta_DHMS));
use HTTP::Request::Common(qw(POST));
use XML::DOM::XPath;
use LWP::UserAgent;
use Sys::Hostname;
use File::Compare;
use Data::Dumper;
use Win32::File;
use File::Copy;
use File::Path;
use File::Find;
use Net::SMTP;
use XML::DOM;
use FindBin;
use Encode; 
use JSON;

use lib($FindBin::Bin);
$CURRENT_DIR = $FindBin::Bin;
$ENV{PROJECT} = 'documentation';
require Site;

$|++;

$ENV{SMTP_SERVER} ||= "mail.sap.corp";
$SMTPFROM = $SMTPTO = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
$SMTPTO = 'jean.maqueda@sap.com';
$NumberOfEmails = 0;
$HOST = hostname();
#$SIG{__DIE__} = sub { SendMail(@_); die(@_) };
#$SIG{__WARN__} = sub { SendMail(@_); warn(@_) };

die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
$RAR = '"C:/Program Files/WinRAR/Rar.exe"';
$UNRAR = '"C:/Program Files/WinRAR/UnRAR.exe"';
$UNZIP = 'C:\cygwin\bin\unzip.exe';

##############
# Parameters #
##############

die("ERROR: SRC_DIR environment variable must be set") unless($SRC_DIR=$ENV{SRC_DIR});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});
die('ERROR: MY_DITA_PROJECT_ID environment variable must be set') unless($Project = $ENV{MY_DITA_PROJECT_ID});
die("ERROR: DROP_DIR environment variable must be set") unless($DROP_DIR=$ENV{DROP_DIR});
die("ERROR: HTTP_DIR environment variable must be set") unless($ENV{HTTP_DIR});
die('ERROR: BUILD_NAME environment variable must be set') unless(exists($ENV{BUILD_NAME}));
die('ERROR: PLATFORM environment variable must be set') unless(exists($ENV{PLATFORM}));
die('ERROR: BUILD_MODE environment variable must be set') unless(exists($ENV{BUILD_MODE}));
die('ERROR: MY_BUILD_REQUESTER environment variable must be set') unless(exists($ENV{MY_BUILD_REQUESTER}));
die('ERROR: BUILD_NUMBER environment variable must be set') unless(exists($ENV{BUILD_NUMBER}));
die('ERROR: Context environment variable must be set') unless(exists($ENV{Context}));
$LOCALIZATION_DIR = "$ENV{SRC_DIR}/cms/content/localization";
$BI_READER_DIR = "$DROP_DIR/BI-Reader";
$BI_DATA_DIR = "$DROP_DIR/BI-DATA-Exchange";
$BOM_READER_DIR = "$DROP_DIR/BOM-Reader";
$BOM_DATA_DIR = "$DROP_DIR/BOM-DATA-Exchange";
$PFDB_DIR = "$DROP_DIR/PFDB-Delivery";
$BackupDone = "$ENV{DITA_CONTAINER_DIR}\\content\\projects\\deltafetch.timestamp";
$TO_MANIFEST = "$ENV{OUTPUT_DIR}/$Project.project.mf.xml";
$FROM_MANIFEST = "$ENV{SRC_DIR}/cms/content/projects/$Project.project.mf.xml";
$Data::Dumper::Indent = 0;

copy("$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.project.mf.xml", $TO_MANIFEST) or warn("ERROR: cannot copy '$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.project.mf.xml': $!") if(-f "$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.project.mf.xml");

########
# Main #
########

$IsIxiasoftFetch = (exists($ENV{MY_PROJECTMAP}) and !exists($ENV{MY_CONFIG_DIR}))? 0 : 1;

if(exists($ENV{MY_PROJECTMAP}))
{
    open(TIMESTAMP, "$ENV{DITA_CONTAINER_DIR}/content/projects/deltafetch.timestamp") or warn("ERROR: cannot open '$ENV{DITA_CONTAINER_DIR}/content/projects/deltafetch.timestamp': $!"); 
    while(<TIMESTAMP>) { last if(($CodeSourceDate) = /gmtime=(\d+)/) }
    close(TIMESTAMP);
    
} else { $CodeSourceDate = time() }
open(DAT, ">$ENV{HTTP_DIR}/$ENV{Context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=$ENV{PLATFORM}_$ENV{BUILD_MODE}_status_1.dat") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{Context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=$ENV{PLATFORM}_$ENV{BUILD_MODE}_status_1.dat': $!");
print(DAT "\$codesourcedate=$CodeSourceDate;\n");
print(DAT "\$requester='$ENV{MY_BUILD_REQUESTER}';\n");
close(DAT);

mkpath("$ENV{OUTPUT_DIR}/bin/contexts") or warn("ERROR: cannot mkpath '$ENV{OUTPUT_DIR}/bin/contexts': $!") unless(-d "$ENV{OUTPUT_DIR}/bin/contexts");

my (%SecondaryFiles, %FallbackFiles);
open(DAT0, ">$ENV{OUTPUT_DIR}/logs/Build/CMSProjectFetch.dat") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/Build/CMSProjectFetch.dat': $!");
if($IsIxiasoftFetch)
{
    print(DAT0 Data::Dumper->Dump([["full fetch from $ENV{MY_TEXTML}", '']], ["*FetchMode"]));
    die("ERROR: MY_FETCH_JAVA_HOME environment variable must be set") unless(exists($ENV{MY_FETCH_JAVA_HOME}));
    die("ERROR: MY_FULL_TEXTML environment variable must be set") unless(exists($ENV{MY_FULL_TEXTML}));
    die("ERROR: MY_DITA_PROJECT environment variable must be set") unless(exists($ENV{MY_DITA_PROJECT}));
    if(exists($ENV{MY_CONFIG_DIR})) { FullFetch() }
    else {
        rmtree("$SRC_DIR/cms") or warn("ERROR: cannot rmtree '$SRC_DIR/cms': $!") if(-d "$SRC_DIR/cms");
        system("set JAVA_HOME=$ENV{MY_FETCH_JAVA_HOME} & $ENV{MY_FETCH_JAVA_HOME}/bin/java -Xmx33096m -XX:MaxPermSize=512m -Djacorb.log.default.verbosity=0 -Dcom.sun.CORBA.transport.ORBTCPReadTimeouts=2:120000:1000:7 -Djava.security.krb5.conf=$CURRENT_DIR/ixiasoft-42/conf/krb5.ini -Djava.security.auth.login.config=$CURRENT_DIR/ixiasoft-42/conf/login.conf -classpath $CURRENT_DIR/ixiasoft-42/libs/fetcher.jar;$CURRENT_DIR/ixiasoft-42/libs/sap-common.jar;$CURRENT_DIR/ixiasoft-42/libs/sap.packager.jar;$CURRENT_DIR/ixiasoft-42/libs/com.ixiasoft.outputgenerator.packager.jar;$CURRENT_DIR/ixiasoft-42/libs/ixiasoft-utils.jar;$CURRENT_DIR/ixiasoft-42/libs/outputgeneratorcorba.jar;$CURRENT_DIR/ixiasoft-42/libs/apache-log4j-1.2.17/log4j-1.2.17.jar;$CURRENT_DIR/ixiasoft-42/libs/commons-cli-1.2/commons-cli-1.2.jar;$CURRENT_DIR/ixiasoft-42/libs/commons-collections4-4.0/commons-collections4-4.0.jar;$CURRENT_DIR/ixiasoft-42/libs/commons-compress-1.7/commons-compress-1.7.jar;$CURRENT_DIR/ixiasoft-42/libs/textml-4.3.4162/jacorb.jar;$CURRENT_DIR/ixiasoft-42/libs/textml-4.3.4162/slf4j-api-1.5.6.jar;$CURRENT_DIR/ixiasoft-42/libs/textml-4.3.4162/slf4j-jdk14-1.5.6.jar;$CURRENT_DIR/ixiasoft-42/libs/textml-4.3.4162/textmlserver.jar;$CURRENT_DIR/ixiasoft-42/libs/textml-4.3.4162/textmlservercorba.jar;$CURRENT_DIR/ixiasoft-42/libs/textml-4.3.4162/textmlservercorbaInterfaces.jar;$CURRENT_DIR/ixiasoft-42/libs/xalan-j_2_7_1/xercesImpl.jar;$CURRENT_DIR/ixiasoft-42/libs/xalan-j_2_7_1/serializer.jar;$CURRENT_DIR/ixiasoft-42/libs/xalan-j_2_7_1/xml-apis.jar;$CURRENT_DIR/ixiasoft-42/libs/xalan-j_2_7_1/xalan.jar;$CURRENT_DIR/ixiasoft-42/libs/xerces-2_11_0/resolver.jar;$CURRENT_DIR/ixiasoft-42/conf com.ixiasoft.outputgenerator.fetcher.Fetch -u $ENV{MY_FULL_TEXTML} -p $ENV{MY_DITA_PROJECT} -d \"$ENV{SRC_DIR}/cms\" -l \"$ENV{OUTPUT_DIR}/logs/build/CMSmanifest.xml\"");
        my $rsNewFiles = sub {
            return unless(my($Language, $FileName) = $File::Find::name =~ /([a-z]{2}-[A-Z]{2})[\\\/]([^\\\/]+\.(?:xml|ditamap))$/);
            $NewFiles{"$Language/$FileName"} = $Manifest{"$Language/$FileName"} = [undef, undef];
        };
        find($rsNewFiles, $LOCALIZATION_DIR);
        ($NewIsDataMergeEnabled, $NewIsFeatureEnabled, $ProductAreaCode, $BuildRelease, $Scope, $UseCase, $CDMode) = ProjectMapSettings();
        print("==== Post treatment...\n");
        my @Start = Today_and_Now();
        Features($ProductAreaCode, $BuildRelease, $Scope, $UseCase, $CDMode) if($NewIsFeatureEnabled);
        PostTreatment($NewIsDataMergeEnabled, $NewIsFeatureEnabled, 0);
        close(DAT0);
        printf("Post treatment took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);
    }
    my $PROJECT = XML::DOM::Parser->new()->parsefile("$ENV{SRC_DIR}/cms/content/projects/$ENV{MY_DITA_PROJECT_ID}.project");
    my($ProjectMap) = $PROJECT->getElementsByTagName('deliverable')->item(0)->getElementsByTagName('fullpath', 0)->item(0)->getFirstChild()->getData() =~ /([^\\\/]+\.ditamap)$/;
    $PROJECT->dispose();
    mkpath("$ENV{OUTPUT_DIR}/bin/contexts") or warn("ERROR: cannot mkpath '$ENV{OUTPUT_DIR}/bin/contexts': $!") unless(-d "$ENV{OUTPUT_DIR}/bin/contexts");
    if(exists($ENV{MY_CONFIG_DIR})) {
        (my $Source = $ENV{MY_CONFIG_DIR}) =~ s/\//\\/g;
        (my $Destination = "$ENV{OUTPUT_DIR}/bin/contexts") =~ s/\//\\/g;
        $Result = system("robocopy /MIR /NP /NFL /NDL /R:3 \"$Source\" \"$Destination\"");
        $Result &= 0xff;
        warn("ERROR: cannot copy from '$Source' to '$Destination': $!") if($Result);
    } else {
        copy("$ENV{SRC_DIR}/cms/content/projects/$ENV{MY_DITA_PROJECT_ID}.project", "$ENV{OUTPUT_DIR}/bin/contexts") or warn("ERROR: cannot copy '$ENV{SRC_DIR}/cms/content/projects/$ENV{MY_DITA_PROJECT_ID}.project': $!");
        copy("$LOCALIZATION_DIR/en-US/$ProjectMap", "$ENV{OUTPUT_DIR}/bin/contexts") or warn("ERROR: cannot copy '$LOCALIZATION_DIR/en-US/$ProjectMap': $!");
    }

    open(DAT, ">$ENV{SRC_DIR}/cms/content/projects/RefFiles.dat") or warn("ERROR: cannot open '$ENV{SRC_DIR}/cms/content/projects/RefFiles.dat': $!");
    print(DAT Data::Dumper->Dump([\%RefFiles], ["*RefFiles"]));
    close(DAT);
    print("THE FETCH IS FINISHED.\n");
    exit(0);
}

@Start = Today_and_Now();
open(DAT, "$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.dat") or die("ERROR: cannot open '$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.dat': $!");
eval <DAT>;
close(DAT);
($ProjectMap, $FallbackLanguage, $raLanguages, $raContainers) = @Project[0,2..4];
unlink("$ENV{SRC_DIR}/cms/TempFolder/fetched_files.txt") or warn("ERROR: cannot unlink '$ENV{SRC_DIR}/cms/TempFolder/fetched_files.txt': $!") if(-f "$ENV{SRC_DIR}/cms/TempFolder/fetched_files.txt");

if(-e $FROM_MANIFEST)
{
    my @Start = Today_and_Now();
    print("INCREMENTAL FETCH\n");
    print(DAT0 Data::Dumper->Dump([['delta fetch from the container store', '']], ["*FetchMode"]));
    copy("$LOCALIZATION_DIR/en-US/$ProjectMap", "$LOCALIZATION_DIR/en-US/$ProjectMap.previous") or warn("ERROR: cannot copy '$LOCALIZATION_DIR/en-US/$ProjectMap': $!");
    copy($BackupDone, "$ENV{SRC_DIR}/cms/content/projects/deltafetch.timestamp") or warn("ERROR: cannot copy '$BackupDone': $!");
    copy($BackupDone, "$ENV{HTTP_DIR}/$ENV{Context}/$ENV{BUILD_NAME}") or warn("ERROR: cannot copy '$BackupDone': $!");
    $IsFullFetch = 0;

    my($IsFeatureEnabled, $IsDataMergeEnabled, %Features);
    open(DAT, "$ENV{SRC_DIR}/cms/content/projects/RefFiles.dat") or warn("ERROR: cannot open '$ENV{SRC_DIR}/cms/content/projects/RefFiles.dat': $!");
    eval <DAT>;
    close(DAT);
    print("==== Fetch from Container Store...\n");
    foreach my $Language (@{$raLanguages})
    {
        unlink("$LOCALIZATION_DIR/$Language") or warn("ERROR: cannot unlink '$LOCALIZATION_DIR/$Language': $!") if(-f "$LOCALIZATION_DIR/$Language");
        next if($Language eq $FallbackLanguage or -d "$LOCALIZATION_DIR/$Language");
        mkpath("$LOCALIZATION_DIR/$Language") or warn("ERROR: cannot mkpath '$LOCALIZATION_DIR/$Language': $!");
        unless(-e "$TEMP_DIR/$$.rar")
        {
            chdir("$LOCALIZATION_DIR/$FallbackLanguage") or warn("ERROR: cannot chdir '$LOCALIZATION_DIR/$FallbackLanguage': $!");
            system("$RAR a -r -inul -m0 $TEMP_DIR/$$.rar *.*");
        }
        chdir("$LOCALIZATION_DIR/$Language") or warn("ERROR: cannot chdir '$LOCALIZATION_DIR/$Language': $!");
        system("$UNRAR e -r -o- -inul $TEMP_DIR/$$.rar");
    }
    unlink("$TEMP_DIR/$$.rar") or warn("ERROR: cannot unlink '$TEMP_DIR/$$.rar': $!") if(-e "$TEMP_DIR/$$.rar");
    my $MANIFEST = XML::DOM::Parser->new()->parsefile($FROM_MANIFEST);
    for my $REFERENCE (@{$MANIFEST->getElementsByTagName('reference')})
    {
        my($FullPath, $Revision, $Language, $Name, $Type, $Container) = split(';', $REFERENCE->getFirstChild()->getData());
        $FromFiles{$FullPath} = [$Revision, $Language, $Name, $Type, $Container];
    }
    $MANIFEST->dispose();
    $MANIFEST = XML::DOM::Parser->new()->parsefile($TO_MANIFEST);
    for my $REFERENCE (@{$MANIFEST->getElementsByTagName('reference')})
    {
        my($FullPath, $Revision, $Language, $Name, $Type, $Container) = split(';', $REFERENCE->getFirstChild()->getData());
        ($Name) = $FullPath =~ /([^\/]*)\.ditamap$/ if($Type eq 'project-map' and $Language eq 'en-US');
        my($Extension) = $FullPath =~ /([^.]+)$/;
        $Manifest{"$Language/$Name.$Extension"} = [$FullPath, $Type];
        next if(exists($FromFiles{$FullPath}) and $Revision eq ${$FromFiles{$FullPath}}[0] and ($Type ne 'project-map' or $Language ne 'en-US'));
        next if($Type eq 'project-map' and $Language eq 'en-US' and compare("$ENV{DITA_CONTAINER_DIR}/content/localization/$Language/$Container/$Name.$Extension", "$LOCALIZATION_DIR/$Language/$Name.$Extension")==0);
        $NewFiles{"$Language/$Name.$Extension"} = [$FullPath, $Type];
        my @Extensions = ($Extension, 'properties');
        push(@Extensions, qw(zip indexedcontent)) if($Extension eq 'image');
        map({print("\tcopy $ENV{DITA_CONTAINER_DIR}/content/localization/$Language/$Container/$Name.$_\n"); copy("$ENV{DITA_CONTAINER_DIR}/content/localization/$Language/$Container/$Name.$_", "$LOCALIZATION_DIR/$Language") or warn("ERROR: cannot copy '$ENV{DITA_CONTAINER_DIR}/content/localization/$Language/$Container/$Name.$_': $!") } @Extensions);
    }
    $MANIFEST->dispose();
    map({ copy("$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.$_", "$ENV{SRC_DIR}/cms/content/projects") or warn("ERROR: cannot copy '$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.$_': $!") } (qw(project customproperties properties project.mf.xml)));
    copy("$ENV{SRC_DIR}/cms/content/projects/$Project.project.mf.xml", "$SRC_DIR/cms") or warn("ERROR: cannot copy '$ENV{SRC_DIR}/cms/content/projects/$Project.project.mf.xml': $!");
    printf("Fetch took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

    print("==== Check manifest...\n");
    @Start = Today_and_Now();
    CheckManifest();
    printf("CheckManifest took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

    print("==== Complete fallback language folder ($FallbackLanguage) with other authoring languages...\n");
    @Start = Today_and_Now();
    $MANIFEST = XML::DOM::Parser->new()->parsefile($TO_MANIFEST);
    for my $REFERENCE (@{$MANIFEST->getElementsByTagName('reference')})
    {
        my($FullPath, $Revision, $Language, $Name, $Type, $Container) = split(';', $REFERENCE->getFirstChild()->getData());
        ($Name) = $FullPath =~ /([^\/]*)\.ditamap$/ if($Type eq 'project-map');
        my($Extension) = $FullPath =~ /([^.]+)$/;
        next unless($FullPath=~/\/authoring\// and $Language ne $FallbackLanguage and ((exists($NewFiles{"$Language/$Name.$Extension"}) and !exists($Manifest{"$FallbackLanguage/$Name.$Extension"})) or !(-f "$LOCALIZATION_DIR/$FallbackLanguage/$Name.$Extension")));
        my @Extensions = ($Extension, 'properties');
        push(@Extensions, qw(zip indexedcontent)) if($Extension eq 'image');
        map({ print("\tcopy $LOCALIZATION_DIR/$Language/$Name.$_\n"); copy("$LOCALIZATION_DIR/$Language/$Name.$_", "$LOCALIZATION_DIR/$FallbackLanguage") or warn("ERROR: cannot copy '$LOCALIZATION_DIR/$Language/$Name.$_': $!") } @Extensions);
        $NewFiles{"$FallbackLanguage/$Name.$Extension"} = [$FullPath, $Type];
    }
    $MANIFEST->dispose();
    printf("Complement of fallback language ($FallbackLanguage) took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

    print("==== Post treatment...\n");
    @Start = Today_and_Now();
    ($NewIsDataMergeEnabled, $NewIsFeatureEnabled, $ProductAreaCode, $BuildRelease, $Scope, $UseCase, $CDMode) = ProjectMapSettings();
    foreach my $File (keys(%RefFiles))   # fallback primary loio
    {
        foreach my $Ref (keys(%{$RefFiles{$File}}))
        {
            next unless(exists($NewFiles{$Ref}) and ${$RefFiles{$File}}{$Ref} eq 'localization');
            next unless(my($FileName) = $Ref =~ /^$FallbackLanguage\/(.+)$/);
            foreach my $Lg (@{$raLanguages})
            {   
                FallbackFile($Lg, $FileName) if($Lg ne $FallbackLanguage and !exists($Manifest{"$Lg/$FileName"}));
            }
        }
    }
    foreach my $File (keys(%NewFiles))   # fallback copy-to
    {
        next unless(my($FileName) = $File =~ /^$FallbackLanguage\/(.+\.ditamap)$/);
        my $DOCUMENT = XML::DOM::Parser->new()->parsefile("$LOCALIZATION_DIR/$File", ProtocolEncoding=>'UTF-8');
        for my $TOPICREF (@{$DOCUMENT->getElementsByTagName('topicref')})
        {
            next unless($TOPICREF->getAttribute('copy-to'));
            foreach my $Lg (@{$raLanguages})
            {
                FallbackFile($Lg, $FileName) if($Lg ne $FallbackLanguage and !exists($Manifest{"$Lg/$FileName"}));
            }
            last;
        }
        $DOCUMENT->dispose();
    }
    %NewFeatures = Features($ProductAreaCode, $BuildRelease, $Scope, $UseCase, $CDMode) if($NewIsFeatureEnabled);
    foreach my $File (keys(%RefFiles))
    {
        next if(exists($NewFiles{$File}));
        my($Language) = $File =~ /^(.+?)\//;
        foreach my $Ref (keys(%{$RefFiles{$File}}))
        {
            if(${$RefFiles{$File}}{$Ref} eq 'localization') { next unless(exists($NewFiles{$Ref})) }
            elsif(${$RefFiles{$File}}{$Ref} eq 'feature') { next unless($NewIsFeatureEnabled != $IsFeatureEnabled or exists($Features{$Ref}) <=> exists($NewFeatures{$Ref})) }
            elsif(${$RefFiles{$File}}{$Ref} eq 'fragment') {
                unless(-f "$BI_DATA_DIR/output/$Ref") { warn("ERROR: '$BI_DATA_DIR/output/$Ref' not found (source: $File) "); next }
                next unless($NewIsDataMergeEnabled != $IsDataMergeEnabled or ($NewIsDataMergeEnabled and compare("$ENV{SRC_DIR}/cms/cache/$Ref", "$BI_DATA_DIR/output/$Ref")!=0));
            }
            elsif(${$RefFiles{$File}}{$Ref} eq 'bom') {
                my($RefName) = $Ref =~ /([^\\\/]+)$/;
                unless(-f $Ref) { warn("ERROR: '$Ref' not found"); next }
                next unless($NewIsDataMergeEnabled != $IsDataMergeEnabled or ($NewIsDataMergeEnabled and compare("$ENV{SRC_DIR}/cms/cache/bom/$RefName", $Ref)!=0));
            }
            copy("$ENV{SRC_DIR}/cms/cache/$File", "$LOCALIZATION_DIR/$Language") or warn("ERROR: cannot copy '$ENV{SRC_DIR}/cms/cache/$File': $!") if(-f "$ENV{SRC_DIR}/cms/cache/$File");
            $NewFiles{$File} = $Manifest{$File};
        }
    }
    PostTreatment($NewIsDataMergeEnabled, $NewIsFeatureEnabled, 1);
    printf("Post treatment took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

    print("==== Complete language folders with the fallback language ($FallbackLanguage)...\n");
    @Start = Today_and_Now();
    for my $File (keys(%NewFiles))
    {
        my($Language, $Name, $Extension) = $File =~ /([a-z]{2}-[A-Z]{2})\/(.+)\.(.+)$/;
        next unless($Language eq $FallbackLanguage);
        my($FullPath, $Type) = @{$NewFiles{$File}};
        ($Name) = $FullPath =~ /([^\/]*)\.ditamap$/ if($Type eq 'project-map' and $Language eq 'en-US');
        foreach my $Lg (@{$raLanguages})
        {
            next unless($Lg ne $FallbackLanguage and !exists($Manifest{"$Lg/$Name.$Extension"}) and !exists($NewFiles{"$Lg/$Name.$Extension"}));
            my @Extensions = ($Extension, 'properties');
            push(@Extensions, qw(zip indexedcontent)) if($Extension eq 'image');
            push(@Extensions, qw(customproperties)) if($Type eq 'project-map');
            map({ print("\tcopy $LOCALIZATION_DIR/$FallbackLanguage/$Name.$_\n"); copy("$LOCALIZATION_DIR/$FallbackLanguage/$Name.$_", "$LOCALIZATION_DIR/$Lg") or warn("ERROR: cannot copy '$LOCALIZATION_DIR/$Language/$Name.$_': $!") } @Extensions);
            $NewFiles{"$Lg/$Name.$Extension"} = $FallbackFiles{"$Lg/$Name.$Extension"} = [$FullPath, $Type];
        }
    }
    printf("Fallback language took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

    mkpath("$ENV{SRC_DIR}/cms/TempFolder") or warn("ERROR: cannot mkpath '$ENV{SRC_DIR}/cms/TempFolder': $!") unless(-d "$ENV{SRC_DIR}/cms/TempFolder");
    open(TXT, ">$ENV{SRC_DIR}/cms/TempFolder/fetched_files.txt") or warn("ERROR: cannot open '$ENV{SRC_DIR}/cms/TempFolder/fetched_files.txt': $!");
    map({print(TXT "$_\n")} keys(%NewFiles));
    close(TXT);
} else { FullFetch() }

copy("$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.dat", "$ENV{SRC_DIR}/cms/content/projects") or warn("ERROR: cannot copy '$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.dat': $!") if($ENV{MY_IS_DELTA_COMPILATION});
open(DAT, ">$ENV{SRC_DIR}/cms/content/projects/RefFiles.dat") or warn("ERROR: cannot open '$ENV{SRC_DIR}/cms/content/projects/RefFiles.dat': $!");
print(DAT Data::Dumper->Dump([\%RefFiles], ["*RefFiles"]));
print(DAT Data::Dumper->Dump([\%NewFeatures], ["*Features"]));
print(DAT Data::Dumper->Dump([$NewIsFeatureEnabled], ["*IsFeatureEnabled"]));
print(DAT Data::Dumper->Dump([$NewIsDataMergeEnabled], ["*IsDataMergeEnabled"]));
close(DAT);

open(TSV, "$ENV{DITA_CONTAINER_DIR}/content/projects/AllConflictContainers.tsv") or warn("ERROR: cannot open '$ENV{DITA_CONTAINER_DIR}/content/projects/AllConflictContainers.tsv': $!");
<TSV>;
while(<TSV>)
{
    my($ProjectName, $ProjectFilename, $RootContainerFilename, $RootContainerTitle, $RootContainerVersion, $ConflictingLoIO, @ConflictingContainers) = split('\t');
    $ProjectFilename =~ s/\.project$//;
    next unless($ProjectFilename eq $Project);
    warn("ERROR: [FETP001E][ERROR] [sapLevel:ERROR] several versions of container '", (split(',', $ConflictingContainers[0]))[1], "' have been retrieved: ", join(',', map({/([^,]+)\]$/; "'$1'"} @ConflictingContainers))); 
}
close(TSV);

copy("$ENV{SRC_DIR}/cms/content/projects/$ENV{MY_DITA_PROJECT_ID}.project", "$ENV{OUTPUT_DIR}/bin/contexts") or warn("ERROR: cannot copy '$ENV{SRC_DIR}/cms/content/projects/$ENV{MY_DITA_PROJECT_ID}.project': $!");
copy("$LOCALIZATION_DIR/en-US/$ProjectMap", "$ENV{OUTPUT_DIR}/bin/contexts") or warn("ERROR: cannot copy '$LOCALIZATION_DIR/en-US/$ProjectMap': $!");

print("THE FETCH IS FINISHED.\n");
printf("Total took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

#############
# Functions #
#############

sub FullFetch {
    my @Start = Today_and_Now();
    print("FULL FETCH\n");

    rmtree("$SRC_DIR/cms") or warn("ERROR: cannot rmtree '$SRC_DIR/cms': $!") if(-d "$SRC_DIR/cms");
    print(DAT0 Data::Dumper->Dump([['full fetch from the container store', 'cms folder missing']], ["*FetchMode"]));
    warn("ERROR: '$UNZIP' not found on '$HOST'") unless(-f $UNZIP);
    $IsFullFetch = 1;

    if(exists($ENV{MY_CONFIG_DIR})) {
        print("==== Fetch from Manifest...\n");
        system("set JAVA_HOME=$ENV{MY_FETCH_JAVA_HOME} & $ENV{MY_FETCH_JAVA_HOME}/bin/java -Xms512m -Xmx4384m -Djava.security.krb5.conf=$CURRENT_DIR/ixiasoft_deltafetch052019/conf/krb5.ini -Djava.security.auth.login.config=$CURRENT_DIR/ixiasoft_deltafetch052019/conf/login.conf -classpath $CURRENT_DIR/ixiasoft_deltafetch052019/conf;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/cmsdeltafetch.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/ixiasoft-utils.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/sap-common.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/apache-log4j-1.2.17/log4j-1.2.17.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/commons-cli-1.2/commons-cli-1.2.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/commons-collections4-4.0/commons-collections4-4.0.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/commons-compress-1.7/commons-compress-1.7.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/textml-4.3.4162/textmlserver.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/textml-4.3.4162/textmlservercorba.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/textml-4.3.4162/textmlservercorbaInterfaces.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/textml-4.3.4162/jacorb.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/textml-4.3.4162/slf4j-api-1.5.6.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/textml-4.3.4162/slf4j-jdk14-1.5.6.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/xerces-2_11_0/resolver.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/xerces-2_11_0/xml-apis.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/xerces-2_11_0/xercesImpl.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/xerces-2_11_0/serializer.jar;$CURRENT_DIR/ixiasoft_deltafetch052019/libs/xalan-j_2_7_1/xalan.jar com.ixiasoft.service.cmsFullFetch.BuildFromManifestRunner -u $ENV{MY_FULL_TEXTML} -o global.corp.sap -p $ENV{MY_CONFIG_DIR}/$ENV{MY_DITA_PROJECT_ID}.project.mf.xml -s \"$ENV{OUTPUT_DIR}/logs/build\" -w \"$ENV{SRC_DIR}/cms/content\" -b 5000 -c false");
        mkpath("$ENV{SRC_DIR}/cms/content/projects") or warn("ERROR: cannot mkpath '$ENV{SRC_DIR}/cms/content/projects': $!") unless(-d "$ENV{SRC_DIR}/cms/content/projects");
        copy("$ENV{MY_CONFIG_DIR}/$ENV{MY_DITA_PROJECT_ID}.project", "$ENV{SRC_DIR}/cms/content/projects") or warn("ERROR: cannot copy '$ENV{MY_CONFIG_DIR}/$ENV{MY_DITA_PROJECT_ID}.project': $!");
        copy("$ENV{MY_CONFIG_DIR}/$Project.project.mf.xml", "$ENV{SRC_DIR}/cms/content/projects") or warn("ERROR: cannot copy '$ENV{MY_CONFIG_DIR}/$ENV{MY_DITA_PROJECT_ID}.project': $!");
        ($NewIsDataMergeEnabled, $NewIsFeatureEnabled, $ProductAreaCode, $BuildRelease, $Scope, $UseCase, $CDMode) = ProjectMapSettings();
        copy("$ENV{MY_CONFIG_DIR}/$ProjectMap", "$LOCALIZATION_DIR/en-US") or warn("ERROR: cannot copy '$ENV{MY_CONFIG_DIR}/$ProjectMap': $!");
        opendir(LG, $LOCALIZATION_DIR) or warn("ERROR: cannot opendir '$LOCALIZATION_DIR': $!");
        while(defined(my $Language = readdir(LG))) {
            next unless($Language =~ /^[a-z]{2}-[A-Z]{2}$/);
            push(@{$raLanguages}, $Language)
        }
        closedir(LG);
    } else {
        print("==== Fetch from Container Store...\n");
        foreach my $Language (sort(@{$raLanguages}))
        {
            foreach my $Container (@{$raContainers})
            {
                next unless(-d "$ENV{DITA_CONTAINER_DIR}/zip/localization/$Language/$Container");
                mkpath("$LOCALIZATION_DIR/$Language") or die("ERROR: cannot mkpath '$LOCALIZATION_DIR/$Language': $!") unless(-d "$LOCALIZATION_DIR/$Language");
                print("\tunzip $ENV{DITA_CONTAINER_DIR}/zip/localization/$Language/$Container/$Container.zip\n");
                system("$UNZIP -o -q $ENV{DITA_CONTAINER_DIR}/zip/localization/$Language/$Container/$Container.zip -d $LOCALIZATION_DIR/$Language");
            }
        }
        mkpath("$ENV{SRC_DIR}/cms/content/projects") or warn("ERROR: cannot mkpath '$ENV{SRC_DIR}/cms/content/projects': $!") unless(-d "$ENV{SRC_DIR}/cms/content/projects");
        map({ copy("$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.$_", "$ENV{SRC_DIR}/cms/content/projects") or warn("ERROR: cannot copy '$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.$_': $!") } (qw(project customproperties properties project.mf.xml)));
        ($NewIsDataMergeEnabled, $NewIsFeatureEnabled, $ProductAreaCode, $BuildRelease, $Scope, $UseCase, $CDMode) = ProjectMapSettings();
    }
    copy("$ENV{SRC_DIR}/cms/content/projects/$Project.project.mf.xml", "$SRC_DIR/cms") or warn("ERROR: cannot copy '$ENV{SRC_DIR}/cms/content/projects/$Project.project.mf.xml': $!");
    copy($BackupDone, "$ENV{SRC_DIR}/cms/content/projects/deltafetch.timestamp") or warn("ERROR: cannot copy '$BackupDone': $!");
    copy($BackupDone, "$ENV{HTTP_DIR}/$ENV{Context}/$ENV{BUILD_NAME}") or warn("ERROR: cannot copy '$BackupDone': $!");
    my $MANIFEST = XML::DOM::Parser->new()->parsefile("$ENV{SRC_DIR}/cms/content/projects/$Project.project.mf.xml");
    for my $REFERENCE (@{$MANIFEST->getElementsByTagName('reference')})
    {
        my($FullPath, $Revision, $Language, $Name, $Type, $Container) = split(';', $REFERENCE->getFirstChild()->getData());
        next if($FullPath =~ /\/authoring\//);
        my($Extension) = $FullPath =~ /([^.]+)$/;
        $NewFiles{"$Language/$Name.$Extension"} = $Manifest{"$Language/$Name.$Extension"} = [$FullPath, $Type];
    }
    printf("Fetch took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

    print("==== Check manifest...\n");
    @Start = Today_and_Now();
    CheckManifest();
    printf("CheckManifest took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

    print("==== Complete fallback language folder ($FallbackLanguage) with other authoring languages...\n");
    @Start = Today_and_Now();
    for my $REFERENCE (@{$MANIFEST->getElementsByTagName('reference')})
    {
        my($FullPath, $Revision, $Language, $Name, $Type, $Container) = split(';', $REFERENCE->getFirstChild()->getData());
        next unless($FullPath =~ /\/authoring\// and $Language ne $FallbackLanguage);
        ($Name) = $FullPath =~ /([^\/]*)\.ditamap$/ if($Type eq 'project-map' and $Language eq 'en-US');
        my($Extension) = $FullPath =~ /([^.]+)$/;
        unless(-f "$LOCALIZATION_DIR/$FallbackLanguage/$Name.$Extension")
        {
            my @Extensions = ($Extension, 'properties');
            push(@Extensions, qw(zip indexedcontent)) if($Extension eq 'image');
            map({copy("$LOCALIZATION_DIR/$Language/$Name.$_", "$LOCALIZATION_DIR/$FallbackLanguage") or warn("ERROR: cannot copy '$LOCALIZATION_DIR/$Language/$Name.$_': $!") } @Extensions);
            $NewFiles{"$FallbackLanguage/$Name.$Extension"} = [$FullPath, $Type];
        }
    }
    $MANIFEST->dispose();
    printf("Complement of fallback language ($FallbackLanguage) took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

    print("==== Post treatment...\n");
    @Start = Today_and_Now();
    Features($ProductAreaCode, $BuildRelease, $Scope, $UseCase, $CDMode) if($NewIsFeatureEnabled);
    PostTreatment($NewIsDataMergeEnabled, $NewIsFeatureEnabled, 1);
    printf("Post treatment took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

    print("==== Complete language folders with the fallback language ($FallbackLanguage)...\n");
    @Start = Today_and_Now();
    if(@{$raLanguages} > 1)
    {
        chdir("$LOCALIZATION_DIR/$FallbackLanguage") or warn("ERROR: cannot chdir '$LOCALIZATION_DIR/$FallbackLanguage': $!");
        system("$RAR a -r -inul -m0 $TEMP_DIR/$$.rar *.*");  
        foreach my $Language (@{$raLanguages})
        {
            next unless($Language ne $FallbackLanguage);
            mkpath("$LOCALIZATION_DIR/$Language") or warn("ERROR: cannot mkpath '$LOCALIZATION_DIR/$Language': $!") unless(-e "$LOCALIZATION_DIR/$Language");
            chdir("$LOCALIZATION_DIR/$Language") or warn("ERROR: cannot chdir '$LOCALIZATION_DIR/$Language': $!");
            system("$UNRAR e -r -o- -inul $TEMP_DIR/$$.rar");
        }
        unlink("$TEMP_DIR/$$.rar") or warn("ERROR: cannot unlink '$TEMP_DIR/$$.rar': $!");
    }
    printf("Fallback language took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);
}

sub CheckManifest
{
    return if(exists($ENV{MY_CONFIG_DIR}));

    my(%DirFiles, %Files);
    (my $LocalisationDir = $LOCALIZATION_DIR) =~ s/\\/\//g;
    open(DIR, "cmd /c dir /s/b/a \"$LOCALIZATION_DIR\" |") or die("ERROR: cannot execute 'dir': $!");
    while(<DIR>)
    {
        chomp;
        s/\\/\//g;
        s/^$LocalisationDir\///;
        $DirFiles{$_} = undef;
    }
    close(DIR);
    my $MANIFEST = XML::DOM::Parser->new()->parsefile($TO_MANIFEST);
    for my $REFERENCE (@{$MANIFEST->getElementsByTagName('reference')})
    {
        my($FullPath, $Revision, $Language, $Name, $Type, $Container) = split(';', $REFERENCE->getFirstChild()->getData());
        next if(($FullPath =~ /\/authoring\//) or ($Type eq 'project-map' and $Language ne 'en-US'));
        ($Name) = $FullPath =~ /([^\/]*)\.ditamap$/ if($Type eq 'project-map');
        my($Extension) = $FullPath =~ /([^.]+)$/;
        next if(exists($Files{"$Language/$Name.$Extension"}));
        $Files{"$Language/$Name.$Extension"} = undef;
        my @Extensions = ($Extension, 'properties');
        push(@Extensions, qw(zip indexedcontent)) if($Extension eq 'image');
        push(@Extensions, qw(customproperties)) if($Type eq 'project-map');
        foreach my $Ext (@Extensions)
        {
            #next if(-f "$LOCALIZATION_DIR/$Language/$Name.$Ext");
            next if(exists($DirFiles{"$Language/$Name.$Ext"}));
            $NewFiles{"$Language/$Name.$Extension"} = [$FullPath, $Type];
            map({ print("\tcopy '$ENV{DITA_CONTAINER_DIR}/content/localization/$Language/$Container/$Name.$_' due of missing file\n"); copy("$ENV{DITA_CONTAINER_DIR}/content/localization/$Language/$Container/$Name.$_", "$LOCALIZATION_DIR/$Language") or warn("ERROR: cannot copy '$ENV{DITA_CONTAINER_DIR}/content/localization/$Language/$Container/$Name.$_': $!") } @Extensions);
        }
        my($Rev, $PhIO);
        open(PROP, '<:raw:encoding(UTF-16BE):crlf', "$LOCALIZATION_DIR/$Language/$Name.properties") or warn("ERROR: cannot open '$LOCALIZATION_DIR/$Language/$Name.properties': $!");
        {
            local $/;
            ($PhIO, $Rev) = <PROP> =~ /<name>(.+)<\/name>.*\n.*<version>(.*)<\/version>/m;
        }
        close(PROP);
        next if($Rev==$Revision and $FullPath=~/$PhIO$/);
        map({ print("\tcopy $ENV{DITA_CONTAINER_DIR}/content/localization/$Language/$Container/$Name.$_ due of wrong revision (rev. $Rev to $Revision)\n"); copy("$ENV{DITA_CONTAINER_DIR}/content/localization/$Language/$Container/$Name.$_", "$LOCALIZATION_DIR/$Language") or warn("ERROR: cannot copy '$ENV{DITA_CONTAINER_DIR}/content/localization/$Language/$Container/$Name.$_': $!") } @Extensions);
        $NewFiles{"$Language/$Name.$Extension"} = [$FullPath, $Type];
    }
    $MANIFEST->dispose();
}

sub ProjectMapSettings
{
    my($IsDataMergeEnabled, $IsFeatureEnabled) = (1, 0);
    my($ProductAreaCode, $BuildRelease, $Scope, $UseCase, $CDMode);

    if(exists($ENV{MY_PROJECTMAP})) { $ProjectMap = $ENV{MY_PROJECTMAP} }
    else
    {
        eval
        {
            my $PROJECT = XML::DOM::Parser->new()->parsefile("$ENV{SRC_DIR}/cms/content/projects/$Project.project");
            ($ProjectMap) = $PROJECT->getElementsByTagName('deliverable')->item(0)->getElementsByTagName('fullpath', 0)->item(0)->getFirstChild()->getData() =~ /([^\\\/]+\.ditamap)$/;
            $PROJECT->dispose();
        };
        warn("ERROR: cannot parsefile the project '$ENV{SRC_DIR}/cms/content/projects/$Project.project': $@") if($@);
    }
    eval
    {
        $PROJECTMAP = XML::DOM::Parser->new()->parsefile("$ENV{SRC_DIR}/cms/content/localization/en-US/$ProjectMap");
        $FallbackLanguage = $PROJECTMAP->getDocumentElement()->getAttribute('fallbacklanguage');
        for my $SETTINGS (@{$PROJECTMAP->getElementsByTagName('settings')})
        {
            for my $OUTPUTMETA (@{$SETTINGS->getElementsByTagName('outputmeta')})
            {
                for my $PARAM (@{$OUTPUTMETA->getElementsByTagName('param')})
                {
                    my($Name, $Value) = ($PARAM->getAttribute('name'), $PARAM->getAttribute('value'));
                    if($Name eq 'dm_enabled' and $Value eq 'yes') { $IsDataMergeEnabled = 1 }
                    elsif($Name eq 'ft_enabled' and $Value eq 'yes') { $IsFeatureEnabled = 1 }
                    elsif($Name eq 'ft_product_area_code' or $Name eq 'ft_productAreaCode') { $ProductAreaCode = $Value }
                    elsif($Name eq 'ft_planned_release' or $Name eq 'ft_buildRelease') { $BuildRelease = $Value }
                    elsif($Name eq 'ft_scope') { $Scope = $Value }
                    elsif($Name eq 'ft_useCase') { $UseCase = $Value }
                    elsif($Name eq 'ft_cdMode') { $CDMode = $Value }
                }
            }
        }
        $PROJECTMAP->dispose();
    };
    warn("ERROR: cannot parsefile the project map '$ENV{SRC_DIR}/cms/content/localization/en-US/$ProjectMap': $@") if($@);
    $IsDataMergeEnabled = 1;

    if($IsFeatureEnabled and !$ProductAreaCode) {
        warn("ERROR: ft_productAreaCode not found in the project map '$ENV{SRC_DIR}/cms/content/localization/en-US/$ProjectMap'");
        $IsFeatureEnabled = 0;
    }
    return ($IsDataMergeEnabled, $IsFeatureEnabled, $ProductAreaCode, $BuildRelease, $Scope, $UseCase, $CDMode);
}

sub Features
{
    my($ProductAreaCode, $BuildRelease, $Scope, $UseCase, $CDMode) = @_;
    $ProductAreaCode ||= '';
    $BuildRelease ||= '';
    $Scope ||= '';
    $UseCase ||= '';
    $CDMode ||= '';
    unlink("$ENV{SRC_DIR}/documentation/export/feature.ditaval") or warn("ERROR: cannot unlink '$ENV{SRC_DIR}/documentation/export/feature.ditaval': $!") if(-f "$ENV{SRC_DIR}/documentation/export/feature.ditaval");
    my(%Features, $Action);

    if(exists($ENV{MY_CONFIG_DIR})) {
        copy("$ENV{MY_CONFIG_DIR}/feature.ditaval", "$ENV{SRC_DIR}/documentation/export") or warn("ERROR: cannot copy '$ENV{MY_CONFIG_DIR}/feature.ditaval': $!") if(-f "$ENV{MY_CONFIG_DIR}/feature.ditaval");
        mkpath("$ENV{OUTPUT_DIR}/bin/contexts") or warn("ERROR: cannot mkpath '$ENV{OUTPUT_DIR}/bin/contexts': $!") unless(-d "$ENV{OUTPUT_DIR}/bin/contexts");
        copy("$ENV{SRC_DIR}/documentation/export/feature.ditaval", "$ENV{OUTPUT_DIR}/bin/contexts") or warn("ERROR: cannot copy '$ENV{SRC_DIR}/documentation/export/feature.ditaval': $!");
        return(%Features);
    }

    my $URL = 'https://v0636-iflmap.avtsbhf.eu1.hana.ondemand.com/http/buildserver2fr';
    my $ua = LWP::UserAgent->new() or warn("ERROR: cannot create LWP agent: $!");
    my $Request = HTTP::Request->new('GET', $URL, ['Content-Type'=>'application/json;charset=UTF-8']);
    $Request->authorization_basic($ENV{CPI_USER}, $ENV{CPI_PASSWORD});
    $Request->content("{\"buildRelease\":\"$BuildRelease\",\"productAreaCode\":\"$ProductAreaCode\",\"scope\":\"$Scope\",\"useCase\":\"$UseCase\",\"cdMode\":\"$CDMode\"}");
    print("$URL\n");
    print($Request->content(), "\n");
    my $Response = $ua->request($Request);
    if($Response->is_success()) {
        my $fromjson;
        eval { $fromjson = from_json($Response->decoded_content()) };
        if($@) {
            warn("ERROR: unexpected json response : $@");
            print("start HTTP response :\n");
            print($Response->content(), "\n");
            print("stop HTTP response :\n");
        } else {
            $Action = $fromjson->{'action'};
            @Features{@{$fromjson->{'features'}}} = (undef);
        }
    } else {
        warn("ERROR: unexpected HTTP response : ", $Response->status_line());
        print("start HTTP response :\n");
        print($Response->content(), "\n");
        print("stop HTTP response :\n");
    }

    if(%Features)
    {
        mkpath("$ENV{SRC_DIR}/documentation/export") or warn("ERROR: cannot mkpath '$ENV{SRC_DIR}/documentation/export': $!") unless(-d "$ENV{SRC_DIR}/documentation/export");
        open(DITAVAL, ">$ENV{SRC_DIR}/documentation/export/feature.ditaval") or warn("ERROR: cannot open '$ENV{SRC_DIR}/documentation/export/feature.ditaval': $!");
        print(DITAVAL "<?xml version='1.0' encoding='UTF-8'?>\n");
        print(DITAVAL "<val>\n");
        print(DITAVAL "\t<prop action='", $Action eq 'exclude'?'include':'exclude', "' att='feature'/>\n");
        foreach my $Key (keys(%Features)) {
            print(DITAVAL "\t<prop val='$Key' att='feature' action='$Action'/>\n");
        }
        print(DITAVAL "</val>\n");
        close(DITAVAL);
        copy("$ENV{SRC_DIR}/documentation/export/feature.ditaval", "$DROP_DIR/$ENV{Context}/$ENV{BUILD_NUMBER}/feature.ditaval") or warn("ERROR: cannot copy '$ENV{SRC_DIR}/documentation/export/feature.ditaval': $!");
        copy("$ENV{SRC_DIR}/documentation/export/feature.ditaval", "$ENV{HTTP_DIR}/$ENV{Context}/$ENV{BUILD_NAME}/feature.ditaval") or warn("ERROR: cannot copy '$ENV{SRC_DIR}/documentation/export/feature.ditaval': $!");
        mkpath("$ENV{OUTPUT_DIR}/bin/contexts") or warn("ERROR: cannot mkpath '$ENV{OUTPUT_DIR}/bin/contexts': $!") unless(-d "$ENV{OUTPUT_DIR}/bin/contexts");
        copy("$ENV{SRC_DIR}/documentation/export/feature.ditaval", "$ENV{OUTPUT_DIR}/bin/contexts") or warn("ERROR: cannot copy '$ENV{SRC_DIR}/documentation/export/feature.ditaval': $!");
    }
    return(%Features);
}

sub PostTreatment {
    my($IsDataMergeEnabled, $IsFeatureEnabled, $IsCopyToEnabled) = @_;
    foreach my $File (sort({$b=~/\.xml$/ <=> $a=~/\.xml$/} keys(%NewFiles))) {
        next unless($File=~/\.(?:xml|ditamap)$/ and -e "$LOCALIZATION_DIR/$File");
        my($Language, $Lang) = $File =~ /([a-z]{2}-([A-Z]{2}))[\\\/][^\\\/]+$/;
        my $IsModified = 0;
        my(%Params, $DOCUMENT);
        eval { $DOCUMENT = XML::DOM::Parser->new()->parsefile("$LOCALIZATION_DIR/$File", ProtocolEncoding=>'UTF-8') };
        if($@) { warn("ERROR: cannot parse '$File': $@"); next }
        my($Id, $Type) = ($DOCUMENT->getDocumentElement()->getAttribute('id'), $DOCUMENT->getDocumentElement()->getNodeName());        
        delete $RefFiles{$File};

        map({ ${$RefFiles{$File}}{$_->getValue()} = 'feature' } @{$DOCUMENT->findnodes('//@feature')}) if($IsFeatureEnabled);

        if($IsCopyToEnabled and $File=~/\.ditamap$/ and $Type ne 'project-map') {
            for my $TOPICREF (@{$DOCUMENT->getElementsByTagName('topicref')}) {
                next unless(my $SecondaryLoIO = $TOPICREF->getAttribute('copy-to'));
                my($PrimaryLoIO) = $TOPICREF->getAttribute('href');
                $TOPICREF->removeAttribute('copy-to');
                $TOPICREF->setAttribute('href', $SecondaryLoIO);
                $IsModified = 1;
                my($primaryloio) = $PrimaryLoIO =~ /^([^\.]+)/;
                my($secondaryloio) = $SecondaryLoIO =~ /^([^\.]+)/;
                my($Name) = $File =~ /([^\\\/]+)$/;
                foreach my $Lang (@{$raLanguages}) {
                    next unless($Lang eq $Language or ($Language eq $FallbackLanguage and !exists($Manifest{"$Lang/$Name"})));
                    FallbackFile($Lang, $PrimaryLoIO) if(!exists($Manifest{"$Lang/$PrimaryLoIO"}) and $Lang ne $FallbackLanguage);
                    copy("$LOCALIZATION_DIR/$Lang/$PrimaryLoIO", "$LOCALIZATION_DIR/$Lang/$SecondaryLoIO") or warn("ERROR: cannot copy '$LOCALIZATION_DIR/$Lang/$PrimaryLoIO': $!");
                    copy("$LOCALIZATION_DIR/$Lang/$primaryloio.properties", "$LOCALIZATION_DIR/$Lang/$secondaryloio.properties") or warn("ERROR: cannot copy '$LOCALIZATION_DIR/$Lang/$primaryloio.properties': $!");
                    eval
                    {
                        my $SECONDARY_DOCUMENT = XML::DOM::Parser->new()->parsefile("$LOCALIZATION_DIR/$Lang/$SecondaryLoIO");
                        $SECONDARY_DOCUMENT->getDocumentElement()->setAttribute('id', "copy$secondaryloio");
                        for my $RESOURCEID (@{$SECONDARY_DOCUMENT->getElementsByTagName('resourceid')})
                        {
                            next unless($RESOURCEID->getAttribute('appname') eq 'loio');
                            $RESOURCEID->setAttribute('id', $secondaryloio);
                        }
                        open(my $fh, '>:encoding(UTF-8)', "$LOCALIZATION_DIR/$Lang/$SecondaryLoIO") or warn("ERROR: cannot open '$LOCALIZATION_DIR/$Lang/$SecondaryLoIO': $!");
                        $SECONDARY_DOCUMENT->printToFileHandle($fh);
                        close($fh);
                        $SECONDARY_DOCUMENT->dispose();
                    };
                    warn("ERROR: cannot parsefile '$LOCALIZATION_DIR/$Lang/$SecondaryLoIO': $@") if($@);
                    ${$RefFiles{$File}}{"$Lang/$PrimaryLoIO"} = 'localization';
                    $NewFiles{"$Lang/$SecondaryLoIO"} = [undef, undef];
                }
            }
        }
        elsif($File =~ /\.xml$/) {
            for my $SECTION_PFDB ($DOCUMENT->getElementsByTagName('section_pfdb')) {
                my($Id, $Ref) = ($SECTION_PFDB->getAttribute('id'), ($SECTION_PFDB->getAttribute('conref') or $SECTION_PFDB->getAttribute('conkeyref')));
                if($Ref) {
                    ($Ref) = $Ref =~ /^([^#]+)/;
                    ${$RefFiles{$File}}{"$Language/$Ref"} = 'localization';
                    my $RefFile = "$LOCALIZATION_DIR/$Language/$Ref";
                    unless(-f $RefFile) { warn("ERROR: section_pfdb : reference '$RefFile' from '$File' not found"); next }
                    FallbackFile($Language, $Ref) unless(exists($Manifest{"$Language/$Ref"}) or $Language ne $FallbackLanguage);
                    eval {
                        my $DOC = XML::DOM::Parser->new()->parsefile($RefFile, ProtocolEncoding=>'UTF-8');
                        for my $SECTION_PFDB ($DOC->getElementsByTagName('section_pfdb')) {
                            my $Id = $SECTION_PFDB->getAttribute('id');
                            ${$Params{section_pfdb}}{$Id} = $SECTION_PFDB->toString();
                        }
                        $DOC->dispose();
                    }; 
                    warn("ERROR: section_pfdb : cannot parse reference '$RefFile' from '$File': $@") if($@);
                } else { ${$Params{section_pfdb}}{$Id} = $SECTION_PFDB->toString() }
            }
            if($IsDataMergeEnabled) {
                for my $OBJECT ($DOCUMENT->getElementsByTagName('object')) {
                    my $Type = $OBJECT->getAttribute('type');
                    if($Type eq 'application/data-merge') {
                        print("DATA-MERGE: $File\n");
                        my %Params;
                        foreach my $PARAM ($OBJECT->getElementsByTagName('param')) {
                            my($Name, $Value, $Ref) = ($PARAM->getAttribute('name'), $PARAM->getAttribute('value'), ($PARAM->getAttribute('conref') or $PARAM->getAttribute('conkeyref')));
                            $Params{$Name} = $Value;
                            next unless($Ref);
                            ($Ref) = $Ref =~ /^([^#]+)/;
                            ${$RefFiles{$File}}{"$Language/$Ref"} = 'localization';
                            my $RefFile = "$LOCALIZATION_DIR/$Language/$Ref";
                            unless(-f $RefFile) { warn("ERROR: data-merge : reference '$RefFile' from '$File' not found"); next }
                            FallbackFile($Language, $Ref) unless(exists($Manifest{"$Language/$Ref"}) or $Language ne $FallbackLanguage);
                            eval {
                                my $DOC = XML::DOM::Parser->new()->parsefile($RefFile, ProtocolEncoding=>'UTF-8');
                                foreach my $PAR ($DOC->getElementsByTagName('param')) {
                                    my($Name, $Value) = ($PAR->getAttribute('name'), $PAR->getAttribute('value'));
                                    $Params{$Name} = $Value;
                                }
                                $DOC->dispose();
                            };
                            warn("ERROR: data-merge : cannot parse reference '$RefFile' from '$File': $@") if($@);
                        }
                        my $SAPSystem = ($Params{SAP_SYSTEM} or 'AH2');
                        my $TLogo = ($Params{I_TLOGO} or '');
                        my $ObjVers = ($Params{I_OBJVERS} or 'D');
                        my $Language1 = ($Params{I_LANGU} or 'EN');
                        my $Language2 = $Language1 eq 'DE' ? 'EN' : 'DE';
                        (my $ObjNm = ($Params{I_OBJNM} or '')) =~ s/\s+$//;
                        (my $GetSpecificXML = ($Params{I_GET_SPECIFIC_XML} or 'X')) =~ s/\s+$//;
                        $ObjNm =~ s/\///g;
                        my $Fragment = "ditafragment_${SAPSystem}_${TLogo}_${ObjNm}_${ObjVers}_${Language1}_$GetSpecificXML.xml";
                        ${$RefFiles{$File}}{$Fragment} = 'fragment';
                        my $FragmentFile = "$BI_DATA_DIR/output/$Fragment";
                        unless(-f $FragmentFile) { warn("ERROR: data-merge : fragment '$FragmentFile' from '$File' not found"); next }
                        mkpath("$ENV{SRC_DIR}/cms/cache/$Language") or warn("ERROR: cannot mkpath '$ENV{SRC_DIR}/cms/cache/$Language': $!") unless(-d "$ENV{SRC_DIR}/cms/cache/$Language");
                        copy("$LOCALIZATION_DIR/$File", "$ENV{SRC_DIR}/cms/cache/$Language") or warn("ERROR: cannot copy '$LOCALIZATION_DIR/$File': $!");
                        copy("$BI_DATA_DIR/output/$Fragment", "$ENV{SRC_DIR}/cms/cache/$Fragment") or warn("ERROR: cannot copy '$BI_DATA_DIR/output/$Fragment': $!");
                        my $OBJECTPARENT = $OBJECT->getParentNode();
                        eval {
                            my $FRAGMENT = XML::DOM::Parser->new()->parsefile("$BI_DATA_DIR/output/$Fragment", ProtocolEncoding => 'UTF-8');  
                            my $BIREADER = $FRAGMENT->getElementsByTagName('bireader')->item(0); 
                            $BIREADER->setOwnerDocument($DOCUMENT);
                            $OBJECTPARENT->removeChild($OBJECT);
                            map({$OBJECTPARENT->appendChild($_, $OBJECT)} $BIREADER->getElementsByTagName('sectiondiv'));
                            $FRAGMENT->dispose();
                        };
                        warn("ERROR: data-merge : cannot parse fragment '$FragmentFile' from '$File': $@") if($@);
                        $IsModified = 1;
                        open(TXT, ">>$BI_READER_DIR/daily-sap-calls/ABAPReader-$SAPSystem-$Project-calls.txt") or warn("ERROR: cannot open '$BI_READER_DIR/daily-sap-calls/ABAPReader-$SAPSystem-$Project-calls.txt': $!");
                        print(TXT "bi_response_${SAPSystem}_${TLogo}_${ObjNm}_${ObjVers}_${Language1}_$GetSpecificXML.xml;$TLogo;$ObjNm;$ObjVers;$Language1;$GetSpecificXML\n");
                        print(TXT "bi_response_${SAPSystem}_${TLogo}_${ObjNm}_${ObjVers}_${Language2}_$GetSpecificXML.xml;$TLogo;$ObjNm;$ObjVers;$Language2;$GetSpecificXML\n");
                        close(TXT);
                    }
                    elsif($Type eq 'application/bom-data') {
                        print("BOM-DATA: $File\n");     # get FIORI_APP_ID
                        foreach my $PARAM ($OBJECT->getElementsByTagName('param')) {
                            my($Id, $Ref, $Name) = ($PARAM->getAttribute('id'), ($PARAM->getAttribute('conref') or $PARAM->getAttribute('conkeyref')), $PARAM->getAttribute('name'));
                            if($Id eq 'FIORI_APP_ID') { ${$Params{bom_data}}{$Id} = $PARAM->getAttribute('value'); last }
                            next unless($Ref);
                            my($Ref1, $ObjectId1) = $Ref =~ /^([^#]+).+\/([^\/]+)$/;
                            next unless($ObjectId1 eq 'FIORI_APP_ID');
                            ${$RefFiles{$File}}{$Ref1} = 'localization';
                            my $RefFile1 = "$LOCALIZATION_DIR/$Language/$Ref1";
                            unless(-f $RefFile1) { warn("ERROR: bom-data : reference '$RefFile1' from '$File' not found"); next }
                            FallbackFile($Language, $Ref1) unless(exists($Manifest{"$Language/$Ref1"}) or $Language ne $FallbackLanguage);
                            eval {
                                my $DOC = XML::DOM::Parser->new()->parsefile("$LOCALIZATION_DIR/$Language/$Ref1", ProtocolEncoding=>'UTF-8');
                                foreach my $PAR ($DOC->getElementsByTagName('param')) {
                                    next unless($PAR->getAttribute('id') eq $ObjectId1);
                                    ${$Params{bom_data}}{$ObjectId1} = $PAR->getAttribute('value');
                                    last;
                                }
                                $DOC->dispose();
                                if($Name eq " ") {$PARAM->setAttribute("name", $Params{bom_data}{$ObjectId1}); $IsModified=1;}
                            };
                            warn("ERROR: bom-data : cannot parse reference '$RefFile1' from '$File': $@") if($@);
                        }
                    }
                    elsif($Type eq 'application/bom-param') {
                        print("BOM-PARAM: $File\n");    # get BOM_LPV and BOM_RI
                        my $Ref = ($OBJECT->getAttribute('conref') or $OBJECT->getAttribute('conkeyref'));
                        my($Ref1, $ObjectId1) = $Ref =~ /^([^#]+).+\/([^\/]+)$/;
                        ${$RefFiles{$File}}{"$Language/$Ref1"} = 'localization';
                        my $RefFile1 = "$LOCALIZATION_DIR/$Language/$Ref1";
                        unless(-f $RefFile1) { warn("ERROR: bom-param : reference '$RefFile1' from '$File' not found"); next }
                        FallbackFile($Language, $Ref1) unless(exists($Manifest{"$Language/$Ref1"}) or $Language ne $FallbackLanguage);
                        eval {
                            my $DOC1 = XML::DOM::Parser->new()->parsefile($RefFile1);
                            for my $OBJ1 ($DOC1->getElementsByTagName('object')) {
                                next unless($OBJ1->getAttribute('id') eq $ObjectId1);
                                my $Ref = ($OBJ1->getAttribute('conref') or $OBJ1->getAttribute('conkeyref'));
                                next unless($Ref);
                                my($Ref2, $ObjectId2) = $Ref =~ /^([^#]+).+\/([^\/]+)$/;
                                ${$RefFiles{$File}}{"$Language/$Ref2"} = 'localization';
                                my $RefFile2 = "$LOCALIZATION_DIR/$Language/$Ref2";
                                unless(-f $RefFile2) { warn("ERROR: bom-param : reference '$RefFile2' from '$RefFile1' not found"); next }
                                FallbackFile($Language, $Ref2) unless(exists($Manifest{"$Language/$Ref2"}) or $Language ne $FallbackLanguage);
                                my $DOC2;
                                eval { $DOC2 = XML::DOM::Parser->new()->parsefile("$RefFile2") };
                                if($@) { warn("ERROR: bom-param : cannot parse reference '$RefFile2' from '$RefFile1': $@"); next }
                                for my $OBJ2 ($DOC2->getElementsByTagName('object')) {
                                    next unless($OBJ2->getAttribute('id') eq $ObjectId2);
                                    for my $PAR2 ($OBJ2->getElementsByTagName('param')) {
                                        my $Id2 = $PAR2->getAttribute('id');
                                        next unless($Id2 eq 'BOM_LPV' or $Id2 eq 'BOM_RI');
                                        my $Ref = ($PAR2->getAttribute('conref') or $PAR2->getAttribute('conkeyref'));
                                        next unless($Ref);
                                        my($Ref3, $ObjectId3) = $Ref =~ /^([^#]+).+\/([^\/]+)$/;
                                        ${$RefFiles{$File}}{"$Language/$Ref3"} = 'localization';
                                        my $RefFile3 = "$LOCALIZATION_DIR/$Language/$Ref3";
                                        unless(-f $RefFile3) { warn("ERROR: bom-param : reference '$RefFile3' from '$RefFile2' not found"); next }
                                        FallbackFile($Language, $Ref3) unless(exists($Manifest{"$Language/$Ref3"}) or $Language ne $FallbackLanguage);
                                        my $DOC3;
                                        eval { $DOC3 = XML::DOM::Parser->new()->parsefile($RefFile3) };
                                        if($@) { warn("ERROR: bom-param : cannot parse reference '$RefFile3' from '$RefFile2': $@"); next }
                                        for my $PAR3 ($DOC3->getElementsByTagName('param')) {
                                            next unless($PAR3->getAttribute('id') eq $ObjectId3);
                                            ${$Params{bom_data}}{$Id2} = $PAR3->getAttribute('value');
                                        }
                                        $DOC3->dispose();
                                    }
                                }
                                $DOC2->dispose();
                            }
                            $DOC1->dispose();
                        };
                        warn("ERROR: bom-param : cannot parse reference '$RefFile1' from '$File': $@") if($@);
                    }
                    elsif($Type eq 'application/service-map') {
                        print("SERVICE-MAP: $File\n");
                        my($Fragment) = $File =~ /^$Language\/(.+)$/;
                        ${$RefFiles{$File}}{$Fragment} = 'fragment';
                        my $FragmentFile = "$BI_DATA_DIR/output/$Fragment";
                        unless(-f $FragmentFile) { warn("ERROR: service-map : fragment '$FragmentFile' not found"); next }
                        mkpath("$ENV{SRC_DIR}/cms/cache/$Language") or warn("ERROR: cannot mkpath '$ENV{SRC_DIR}/cms/cache/$Language': $!") unless(-d "$ENV{SRC_DIR}/cms/cache/$Language");
                        copy($FragmentFile, "$ENV{SRC_DIR}/cms/cache/$Fragment") or warn("ERROR: cannot copy '$FragmentFile': $!");
                        my $Parent = $OBJECT->getParentNode;
                        $Parent->removeChild($OBJECT);
                        eval {
                            my $FRAGMENT = XML::DOM::Parser->new()->parsefile($FragmentFile, ProtocolEncoding => 'UTF-8');
                            for my $TABLE ($FRAGMENT->getElementsByTagName("table")) {
                               $TABLE->setOwnerDocument($DOCUMENT);
                               $Parent->appendChild($TABLE, $OBJECT);
                            }
                            $FRAGMENT->dispose();
                        };
                        warn("ERROR: service-map : cannot parse fragment '$FragmentFile': $@") if($@);
                        $IsModified = 1;
                    }
                }
            }
            if(exists($Params{section_pfdb})) {
                print("SECTION_PFDB: $File\n");
                my $Title = undef;
                eval { $Title = $DOCUMENT->getElementsByTagName('title')->item(0)->getFirstChild->toString };
                warn("ERROR: section_pfdb : title not found in '$File': $@") if($@);
                my $ContainerVersion = undef;
                (my $ProjectMapCustomProperties = "$ENV{SRC_DIR}/cms/content/localization/$FallbackLanguage/$ProjectMap") =~ s/\.ditamap$/.customproperties/;
                if(-f $ProjectMapCustomProperties) {
                    eval {
                        my $CUSTOMPROPERTIES = XML::DOM::Parser->new()->parsefile($ProjectMapCustomProperties);
                        $ContainerVersion = $CUSTOMPROPERTIES->getElementsByTagName('version')->item(0)->getFirstChild()->getData();
                        $CUSTOMPROPERTIES->dispose();
                    };
                    warn("ERROR: section_pfdb : cannot parse '$ProjectMapCustomProperties': $@") if($@);
                } else { warn("ERROR: section_pfdb : '$ProjectMapCustomProperties' not found")}
                my $Version = '';
                (my $XMLCustomProperties = "$ENV{SRC_DIR}/cms/content/localization/$File") =~ s/\.[^.]+$/.properties/;
                if(-f $XMLCustomProperties) {
                    eval {
                        $CUSTOMPROPERTIES = XML::DOM::Parser->new()->parsefile($XMLCustomProperties);
                        $Version = $CUSTOMPROPERTIES->getElementsByTagName('version')->item(0)->getFirstChild()->getData();
                        $CUSTOMPROPERTIES->dispose();
                    };
                    warn("ERROR: section_pfdb : cannot parse '$XMLCustomProperties': $@") if($@);
                } else { warn("ERROR: section_pfdb : '$XMLCustomProperties' not found") }
                if($Title and $ContainerVersion) {
                    mkpath("$PFDB_DIR/$Language") or warn("ERROR: cannot mkpath '$PFDB_DIR/$Language': $!") unless(-d "$PFDB_DIR/$Language");
                    my $PFDBFile = "$PFDB_DIR/$Language/${Id}_$ContainerVersion.xml";
                    if(open(PFDB, '>:utf8', $PFDBFile)) {
                        print(PFDB "<?xml version='1.0' encoding='UTF-8'?>\n");
                        print(PFDB "<topic id='$Id' version='$Version'>\n");
                        print(PFDB "\t<title>$Title</title>\n");
                        print(PFDB "\t<prolog>\n");
                        print(PFDB "\t\t<metadata>\n");
                        map({print(PFDB "\t\t\t<othermeta content='${$Params{bom_data}}{$_}' name='$_'/>\n")} keys(%{$Params{bom_data}})) if(exists($Params{bom_data}));
                        print(PFDB "\t\t</metadata>\n");
                        print(PFDB "\t</prolog>\n");
                        print(PFDB "\t<body>\n");
                        foreach my $Id (keys(%{$Params{section_pfdb}})) {
                            print(PFDB "\t\t${$Params{section_pfdb}}{$Id}\n");
                        }
                        print(PFDB "\t</body>\n");
                        print(PFDB "</topic>");
                        close(PFDB);
						print("\t$File saved.\n");
                    } else { warn("ERROR: cannot open '$PFDBFile': $!") }
                } else { warn("ERROR: section_pfdb : Could not get Title or Project version of '$File'") }
            }
            if(exists($Params{bom_data}) and exists(${$Params{bom_data}}{FIORI_APP_ID}) and exists(${$Params{bom_data}}{BOM_LPV}) and exists(${$Params{bom_data}}{BOM_RI})) {
                my $FioriId = ${$Params{bom_data}}{FIORI_APP_ID};
                my $Version = ${$Params{bom_data}}{BOM_LPV};
                my $Release = ${$Params{bom_data}}{BOM_RI};
                my $SourceDir = "$BOM_READER_DIR/projects/$Project/source/$FioriId/$Version/$Release";
                my $ExchangeDir = "$BOM_DATA_DIR/output/$FioriId/$Version/$Release";
                my $CallDir = "$BOM_READER_DIR/daily-sap-calls"; 
                my $TxtFile = "BOM_Call_${Version}_$Release.txt";
                open(BAT, ">>$CallDir/bom_data_merge_$Project.bat") or warn("ERROR: cannot open '$CallDir/bom_data_merge_$Project.bat': $!");
                print(BAT "java -jar ..\\libs\\sap\\ABAPReader.jar -log -bommerge -bomreader -outputfolder ..\\bom-response -productversion \"$Version\" -releaseID $Release -text \"..\\projects\\$Project\\$TxtFile\"\n");
                close(BAT);
                my($FileName) = $File =~ /([^\\\/]+)$/;
                my $ProjectDir = "$BOM_READER_DIR/projects/$Project"; 
                mkpath($ProjectDir) or warn("ERROR: cannot mkpath '$ProjectDir': $!") unless(-d $ProjectDir);
                open(TXT, ">>$ProjectDir/$TxtFile") or warn("ERROR: cannot open '$ProjectDir/$TxtFile': $!");
                print(TXT "..\\projects\\$Project\\source\\$FioriId\\$Version\\$Release\\$FileName; ..\\outputs\\$FioriId\\$Version\\$Release\\$FileName\n");
                close(TXT);

                my $BOMFile = exists($ENV{MY_CONFIG_DIR}) ? "$ENV{MY_CONFIG_DIR}/bom/$FileName" : "$ExchangeDir/$FileName";
                ${$RefFiles{$File}}{$BOMFile} = 'bom';
                #FallbackFile($Language, $FileName) unless(exists($Manifest{"$Language/$File"}) or $Language ne $FallbackLanguage);
                unless(-f $BOMFile) { warn("ERROR: bom-param : BOM '$BOMFile' from '$File' not found"); next }
                mkpath("$ENV{SRC_DIR}/cms/cache/bom") or warn("ERROR: cannot mkpath '$ENV{SRC_DIR}/cms/cache/bom': $!") unless(-d "$ENV{SRC_DIR}/cms/cache/bom");
                copy($BOMFile, "$ENV{SRC_DIR}/cms/cache/bom") or warn("ERROR: cannot copy '$BOMFile': $!");
                copy($BOMFile, "$ENV{OUTPUT_DIR}/bin/contexts") or warn("ERROR: cannot copy '$BOMFile': $!");
                eval {
                    my $BOM = XML::DOM::Parser->new()->parsefile($BOMFile);
                    for my $DATA ($DOCUMENT->getElementsByTagName('data')) {
                        my $Name = $DATA->getAttribute('name');
                        next unless($Name eq 'bom_path');
                        my $Value = $DATA->getAttribute('value');
                        my $Parent = $Value =~ /BackendPFCGRole/ ? $DATA->getParentNode->getParentNode->getParentNode->getParentNode : $DATA->getParentNode;
                        my $NodeName = $Parent->getNodeName();
                        unless($NodeName eq 'entry' or $NodeName eq 'sap-technical-name' or $NodeName eq 'ul' or $NodeName eq 'ph') { warn("ERROR: element '$NodeName' in '$File' not defined.\n"); next }                
                        my $ParentID = $Parent->getAttribute('id');
                        my $Child;
                        for my $Element ($BOM->getElementsByTagName($NodeName)) {
                            next unless($Element->getAttribute('id'));
                            my($Id) = $Element->getAttribute('id') =~ /([^\/\\]+)$/;
                            next unless($Id eq $ParentID);
                            $Child = $Element;
                            last;
                        }
                        next unless($Child);
                        next unless(my $PParent = $Parent->getParentNode);
                        $PParent->setOwnerDocument($BOM);
                        $PParent->replaceChild($Child, $Parent);
                        $IsModified = 1;
                    }
                    $BOM->dispose();
                };
                if($@) {
                    warn("ERROR: bom-param : cannot parse BOM '$BOMFile' from '$File': $@");
                } else {
                    mkpath($SourceDir) or warn("ERROR: cannot mkpath '$SourceDir': $!") unless(-d $SourceDir);
                    copy("$LOCALIZATION_DIR/$File", $SourceDir) or warn("ERROR: cannot copy '$LOCALIZATION_DIR/$File': $!");
                }
            }
        }
        if($IsModified) {
            mkpath("$ENV{SRC_DIR}/cms/cache/$Language") or warn("ERROR: cannot mkpath '$ENV{SRC_DIR}/cms/cache/$Language': $!") unless(-d "$ENV{SRC_DIR}/cms/cache/$Language");
            copy("$LOCALIZATION_DIR/$File", "$ENV{SRC_DIR}/cms/cache/$File") or warn("ERROR: cannot copy '$LOCALIZATION_DIR/$File': $!");
            open(my $fh, '>:encoding(UTF-8)', "$LOCALIZATION_DIR/$File") or warn("ERROR: cannot open '$LOCALIZATION_DIR/$File': $!");
            $DOCUMENT->printToFileHandle($fh);
            close($fh);
        }
        $DOCUMENT->dispose();
    }
    foreach my $File (keys(%RefFiles)) {
        my($Language, $Name) = split(/[\\\/]/, $File);
        next unless($Language eq $FallbackLanguage);
        foreach my $Lang (@{$raLanguages}) {
            next unless($Lang ne $Language and !exists($Manifest{"$Lang/$Name"}));
            $RefFiles{"$Lang/$Name"} = {};
            foreach my $Ref (keys(%{$RefFiles{$File}})) {
                if(${$RefFiles{$File}}{$Ref} eq 'fragment') { ${$RefFiles{"$Lang/$Name"}}{$Ref} = ${$RefFiles{$File}}{$Ref} }
                else { 
                    my($RefName) = $Ref =~ /([^\\\/]+)$/;
                    ${$RefFiles{"$Lang/$Name"}}{"$Lang/$RefName"} = ${$RefFiles{$File}}{$Ref};
                } 
            }
            next unless(-f "$ENV{SRC_DIR}/cms/cache/$File");
            mkpath("$ENV{SRC_DIR}/cms/cache/$Lang") or warn("ERROR: cannot mkpath '$ENV{SRC_DIR}/cms/cache/$Lang': $!") unless(-d "$ENV{SRC_DIR}/cms/cache/$Lang");
            copy("$ENV{SRC_DIR}/cms/cache/$File", "$ENV{SRC_DIR}/cms/cache/$Lang/$Name") or warn("ERROR: cannot copy '$ENV{SRC_DIR}/cms/cache/$File': $!");
        }
    }
}

sub FallbackFile
{
    my($Language, $File, $Type) = @_;

    my($Name, $Extension) = $File =~ /^([^\.]+)\.(.+)$/;
    my @Extensions = ($Extension, 'properties');
    push(@Extensions, qw(zip indexedcontent)) if($Extension eq 'image');
    push(@Extensions, qw(customproperties)) if($Type and $Type eq 'project-map');
    foreach my $Ext (@Extensions)
    {    
        print("\tcopy $LOCALIZATION_DIR/$FallbackLanguage/$Name.$Ext\n");
        copy("$LOCALIZATION_DIR/$FallbackLanguage/$Name.$Ext", "$LOCALIZATION_DIR/$Language") or warn("ERROR: cannot copy '$LOCALIZATION_DIR/$FallbackLanguage/$Name.$Ext': $!");
        $NewFiles{"$Language/$Name.$Ext"} = $FallbackFiles{"$Language/$Name.$Ext"} = [undef, $Type];
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