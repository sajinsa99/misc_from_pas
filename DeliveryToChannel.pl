#!/usr/bin/perl -w

use Date::Calc(qw(Today_and_Now Delta_DHMS Localtime));
use Archive::Zip(qw(:ERROR_CODES :CONSTANTS));
use HTTP::Request::Common(qw(POST));
use LWP::UserAgent;
use File::Basename;
use Sys::Hostname;
use Getopt::Long;
use File::Copy;
use File::Path;
use XML::DOM;
use JSON;

use FindBin;
use lib ($FindBin::Bin);

##############
# Parameters #
##############

$| = 1;

GetOptions("help|?"=>\$Help, "output=s"=>\$OutputFile, "define=s%"=>\$rhParameters);
Usage() if($Help);
@ChannelMethods{qw(P4 Nx PS HP)} = (\&PushToPerforce, \&PushToNexus, \&PushToPreviewServer, , \&PushToHelpPortal); 
$PROXY = 'http://proxy.wdf.sap.corp:8080';
$P4ROOT = 'C:\p4_pub';
$HOST = hostname();
$CURRENTDIR = $FindBin::Bin;
$ARTIFACTDEPLOYER_HOME = $ENV{ARTIFACTDEPLOYER_HOME} || "$CURRENTDIR/artifactdeployer";
$MAVENCLIENT_HOME = $ENV{MAVENCLIENT_HOME} || "$CURRENTDIR/mavenclient";
die("ERROR: channel not defined. Use -d channel=<channel> parameter") unless($Channel = ${$rhParameters}{channel});
unless($OutputFile) { warn("ERROR: ==$Channel== -o.utput option is mandatory"); Usage() }
die("ERROR: ==$Channel== output file '$OutputFile' not found") unless(-f $OutputFile);
die("ERROR: ==$Channel== channel '$Channel' not supported") unless(exists($ChannelMethods{$Channel}));
die("ERROR: ==$Channel== OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});
die("ERROR: ==$Channel== BUILD_MODE environment variable must be set") unless($ENV{BUILD_MODE});
die("ERROR: ==$Channel== MY_BUILD_REQUESTER environment variable must be set") unless($ENV{MY_BUILD_REQUESTER});
die("ERROR: ==$Channel== MY_BUILD_NAME environment variable must be set") unless($ENV{MY_BUILD_NAME});
die("ERROR: ==$Channel== PLATFORM environment variable must be set") unless($ENV{PLATFORM});
die("ERROR: ==$Channel== SRC_DIR environment variable must be set") unless($ENV{SRC_DIR});
die("ERROR: ==$Channel== build_number environment variable must be set") unless($ENV{build_number});
die("ERROR: ==$Channel== TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
die("ERROR: ==$Channel== BUILD_BOOTSTRAP_DIR environment variable must be set") unless($ENV{BUILD_BOOTSTRAP_DIR});

########
# Main #
########

my($GUID, $PhIO, $Title, $TransType, $Language, $Name, $Type, $Value, $Path) = @{$rhParameters}{qw(loio projectid project_title transtype lang channel type url path)};
open(DAT, "$ENV{OUTPUT_DIR}/obj/DeliveryChannels.dat") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/obj/DeliveryChannels.dat': $!");
eval <DAT>;
close(DAT);
foreach my $PhIO2 (keys(%DeliveryChannels))
{
    next unless($PhIO2 eq $GUID);
    foreach my $rhOutput (@{$DeliveryChannels{$PhIO2}})
    {
        my($GUID2, $Title2, $TransType2, $Language2, $Name2, $Type2, $Status2, $URL2, $IsCandidate) = @{$rhOutput}{qw(id title transtype language name type status url candidate)};
        print("[INFO]: Delivery Channel : id=$PhIO2 phio='$PhIO2' title='$Title2' transtype='$TransType2' language='$Language2' name='$Name2' type='$Type2' status='$Status2' url='$URL2' candidate='$IsCandidate'\n");
    }
}
$ChannelMethods{$Channel}();
print("[INFO] ==$Channel== Build number is $ENV{build_number}\n");

#############
# Functions #
#############

sub PushToPerforce
{
    print("== PUSH TO PERFORCE ==\n");
    map({print("\t$_=${$rhParameters}{$_}\n")} keys(%{$rhParameters}));
    foreach my $Parameter (qw(url path type transtype projectid project_title lang)) { die("ERROR: $Parameter is missing. Use -d $Parameter=<$Parameter>") unless(exists(${$rhParameters}{$Parameter})) }
    return if($OutputFile =~ /\.pdf$/);

    my @Start = Today_and_Now();
    my($Url, $Path, $Type, $TransType, $ProjectID, $ProjectTitle, $Language) = @{$rhParameters}{qw(url path type transtype projectid project_title lang)};
    $Url =~ s/[\\\/]$//;
    $Path =~ s/^[\\\/]//;
    my $URL = "$Url/$Path";
    my($P4Host, $P4Port, $P4Path) = $URL =~ /^p4:\/\/([^:]+):([0-9]*)\/(.*?)\/?$/;
    unless($P4Port && $P4Path && $P4Host) { warn("ERROR: ==$Channel== the url '$URL' is incorrectly formatted"); return }
    $ENV{DISABLE_PERFORCE_PASSWORD_FILE} = 'yes';
    $ENV{P4PORT} = "$P4Host:$P4Port";
    $ENV{P4PASSWD} = $ENV{PUBLISH_PASSWORD};
    require Perforce;
    my $p4 = new Perforce;
    my $P4Client = "${P4Host}_${$}_pub_".lc($HOST);
    my $P4Root = "$P4ROOT\\$P4Host";
    my($P4File) = $OutputFile =~ /([^\\\/]+)$/;
    $P4File = "\/\/$P4Client\/$P4Path/$P4File";
    $p4->SetOptions(" -c $P4Client -u $ENV{PUBLISH_USER} -p $P4Host:$P4Port ");
    my $rhClient = $p4->FetchClient();
    if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); warn("ERROR: ==$Channel== cannot p4 fetch client '$P4Client': ", @{$p4->Errors()}); return }
    ${$rhClient}{Root} = $P4Root;
    $p4->SaveClient($rhClient);
    if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); warn("ERROR: ==$Channel== cannot p4 save client '$P4Client': ", @{$p4->Errors()}); return }
    {
        my $bAddFile;
        foreach(@{$p4->fstat("\"$P4File\"")})
        {
            chomp;
            if(/...headAction delete$/) { $bAddFile=1; last; }
        }
        if($p4->ErrorCount())
        {
            if(${$p4->Errors()}[0]=~/no such file\(s\).$/) { $bAddFile=1; }
            else { chomp(${$p4->Errors()}[-1]); warn("ERROR: ==$Channel== cannot p4 fstat '$P4File': ", @{$p4->Errors()}); return }
        }

        if($bAddFile)
        {
            print("\tp4 add $OutputFile\n");
            mkpath("$P4Root\\$P4Path") unless(-d "$P4Root\\$P4Path");
            copy($OutputFile, "$P4Root\\$P4Path") or warn("ERROR: ==$Channel== cannot copy for adding '$OutputFile': $!");
            $p4->add("\"$P4File\"");
            if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); warn("ERROR: ==$Channel== cannot p4 add '$P4File': ", @{$p4->Errors()}); return }
        }
        else
        {
            print("\tp4 update $OutputFile\n");
            $p4->sync('-f', "\"$P4File\"");
            if($p4->ErrorCount() && (${$p4->Errors()}[0]!~/up-to-date.$/ && ${$p4->Errors()}[0]!~/no such file\(s\).$/)) { chomp(${$p4->Errors()}[-1]); warn("ERROR: ==$Channel== cannot p4 sync '$P4File': ", @{$p4->Errors()}); return }
            $p4->edit("\"$P4File\"");
            if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); warn("ERROR: ==$Channel== cannot p4 edit '$P4File': ", @{$p4->Errors()}); return }
            copy($OutputFile, "$P4Root\\$P4Path") or warn("ERROR: ==$Channel== cannot copy for adding '$OutputFile': $!");
        }
    }

    my $rhChange = $p4->fetchchange();
    if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); warn("ERROR: ==$Channel== cannot p4 fetch change '$P4File': ", @{$p4->Errors()}); return }
    ${$rhChange}{Description} = ["Summary*:	Processed by IxiaSoft Documentation Build System Host=$HOST Project=$ProjectID Title=$ProjectTitle Build=$ENV{build_number} Channel=channelid Type=$Type TransType=$TransType Language=$Language", "Reviewed by:$ENV{PUBLISH_USER}"];
    (my $File = $P4File) =~ s/[^\\\/]+\///;
    @{${$rhChange}{Files}} = grep(/$File/, @{${$rhChange}{Files}});
    my $raChange = $p4->savechange($rhChange);
    if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); warn("ERROR: ==$Channel== cannot p4 save change '$P4File': ", @{$p4->Errors()}); return }
    my($Change) = ${$raChange}[0] =~ /^Change (\d+)/;
    print("\tp4 submit $OutputFile\n");
    $p4->submit("-c$Change") if($Change);
    if($p4->ErrorCount())
    { 
        chomp(${$p4->Errors()}[-1]); warn("ERROR: ==$Channel== cannot p4 submit change '$Change': ", @{$p4->Errors()});
        $p4->revert("\"$P4File\"");
        if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); warn("ERROR: ==$Channel== cannot p4 revert '$P4File': ", @{$p4->Errors()}) }
        $p4->change("-d", $Change);
        if($p4->ErrorCount()) { warn("ERROR: ==$Channel== cannot p4 delete change : '$Change'", @{$p4->Errors()}) }
    }
    $p4->Final() if($p4); 
    printf("push to perforce took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);
}

sub PushToNexus
{
    print("== PUSH TO NEXUS ==\n");
    map({print("\t$_=${$rhParameters}{$_}\n")} keys(%{$rhParameters}));
    foreach my $Parameter (qw(url group artifact version type)) { die("ERROR: ==$Channel== $Parameter is missing. Use -d $Parameter=<$Parameter>") unless(exists(${$rhParameters}{$Parameter})) }

    my @Start = Today_and_Now();
    my($URL, $Group, $Artifact, $Version, $Type) = @{$rhParameters}{qw(url group artifact version type)};
    $Version .= '-SNAPSHOT' if($Type eq 'prepublishing');
    if($TransType eq 'eclipsehelp.sap' && $Type eq 'publishing' && $URL =~ /deploy\.releases\.sbop$/)
    {
        open(PROP, ">$TEMPDIR/codesign_$$.config.properties") or warn("ERROR: cannot open '$TEMPDIR/codesign_$$.config.properties': $!");
        print(PROP "codesign.sap.server.url=https://signproxy.wdf.sap.corp:28443/sign\n");
        print(PROP "codesign.sap.ssl.keystore=\\\\\\\\build-drops-wdf\\\\dropzone\\\\documentation\\\\.pegasus\\\\bobj.ks\n");
        print(PROP "codesign.sap.ssl.truststore=\\\\\\\\build-drops-wdf\\\\dropzone\\\\documentation\\\\.pegasus\\\\trust.ts\n");
        my $pw = `$ENV{BUILD_BOOTSTRAP_DIR}/export/shared/prodpassaccess/bin/prodpassaccess get codesign.sap.ssl.keystore.pass password --credentials-file \\\\build-drops-wdf/dropzone/documentation/.pegasus/.pw.properties --master-file \\\\build-drops-wdf/dropzone/documentation/.pegasus/.master.xml`; chomp($pw);
        print(PROP "codesign.sap.ssl.keystore.pass=$pw\n");
        $pw = `$ENV{BUILD_BOOTSTRAP_DIR}/export/shared/prodpassaccess/bin/prodpassaccess get codesign.sap.ssl.truststore.pass password --credentials-file \\\\build-drops-wdf/dropzone/documentation/.pegasus/.pw.properties --master-file \\\\build-drops-wdf/dropzone/documentation/.pegasus/.master.xml`; chomp($pw);
        print(PROP "codesign.sap.ssl.truststore.pass=$pw\n");
        close(PROP);
        my $Result = `$MAVENCLIENT_HOME/bin/mavenclient --cfg-file $TEMPDIR/codesign_$$.config.properties --file $OutputFile --groupid $Group --artifactid $Artifact --version $Version --signingtech JARSIGNING`;
        unlink("$TEMPDIR/codesign_$$.config.properties") or warn("ERROR: ==$Channel== cannot unlink '$TEMPDIR/codesign_$$.config.properties': $!");
        die("ERROR: ==$Channel== cannot add signature: $Result") unless($Result =~ /signed successfully/m);
    }
    open(GROOVY, ">$TEMPDIR/data_$$.groovy") or warn("ERROR: ==$Channel== cannot open '$TEMPDIR/data_$$.groovy': $!");
    print(GROOVY "artifacts builderVersion:\"1.1\", {\n\tgroup \"$Group\", {\n\t\tartifact \"$Artifact\", {\n\t\t\tfile \"$OutputFile\"\n\t\t}\n\t}\n}");
    close(GROOVY);
    chdir("$ARTIFACTDEPLOYER_HOME/bin") or warn("ERROR: ==$Channel== cannot chdir '$ARTIFACTDEPLOYER_HOME/bin': $!");	
    my $ReleaseMetadata = (-f "$ENV{OUTPUT_DIR}/obj/releaseMetadata.txt") ? "--metadata-type-id sbop.build.context --metadata-type-name \"Metadata Sbop Build Context\" --metadata-file $ENV{OUTPUT_DIR}/obj/releaseMetadata.txt" : '';
    my $Result = `artifactdeployer.cmd pack $ReleaseMetadata -f $TEMPDIR/data_$$.groovy -p $TEMPDIR/data_$$.df 2>&1`;
    warn("ERROR: ==$Channel== cannot pack '$OutputFile': $Result") if($Result);
    $Result = `artifactdeployer.cmd deploy --artifact-version $Version -p $TEMPDIR/data_$$.df --repo-url $URL --repo-user $ENV{NEXUS_USER} --repo-passwd $ENV{NEXUS_PASSWORD} 2>&1`;
    warn("ERROR: ==$Channel== cannot deploy '$OutputFile': $Result") if($Result);
    printf("push to nexus took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);
}

sub PushToPreviewServer
{
    print("== PUSH TO PREVIEW SERVER ==\n");
    map({print("\t$_=${$rhParameters}{$_}\n")} keys(%{$rhParameters}));
    foreach my $Parameter (qw(url loio visibility lang metadata metadatadir)) { die("ERROR: ==$Channel== $Parameter is missing. Use -d $Parameter=<$Parameter>") unless(exists(${$rhParameters}{$Parameter})) }
    
    my @Start = Today_and_Now();
    my($URL, $LoIO, $Visibility, $Language, $MetaData, $MetaDataDir) = @{$rhParameters}{qw(url loio visibility lang  metadata metadatadir)};
    my($MetadataVersion, $ProjectPhIO, $ProjectName) = ('', '', '');
    eval
    {
        my $DOC = XML::DOM::Parser->new()->parsefile("$MetaDataDir/metadata.xml");
        my $PROJECT = $DOC->getElementsByTagName('project')->item(0);
        ($ProjectName, $ProjectPhIO) = ($PROJECT->getAttribute('name'), $PROJECT->getAttribute('project_phio'));
        for my $PARAM (@{$DOC->getElementsByTagName('deliverable')->item(0)->getElementsByTagName('param')})
        {
            next unless($PARAM->getAttribute('name') eq 'version');
            $MetadataVersion = $PARAM->getAttribute('value');
            last;
        }
        $DOC->dispose();
    };
    if($@) { warn("ERROR: ==$Channel==  cannot read metadata '$MetaDataDir/metadata.xml' : $@"); return }
    my $OutputFileWithMetadata;
    eval { $OutputFileWithMetadata = CommonPushTasks() };
    return if($@);
    print("Send '$OutputFileWithMetadata' to '$URL'...\n");
    my $ua = LWP::UserAgent->new() or warn("ERROR: ==$Channel== cannot create LWP agent: $!");
    $ua->proxy(['http', 'https'] => $PROXY);
    my $Request = POST $URL, Content_Type=>'multipart/form-data', Content=>[archive=>["$OutputFileWithMetadata", basename($OutputFileWithMetadata), "Content-Type"=>"application/zip"], Pubmode=>$ENV{MY_BUILD_REQUESTER}eq'buildondemand'?'Ondemand':'Daily', Omaploio=>$LoIO, Visibility=>$Visibility, language=>$Language, version=>$MetadataVersion, build=>$ENV{build_number}, project_name=>$ProjectName, project_phio=>$ProjectPhIO];
    $Request->authorization_basic($ENV{DPS_USER}, $ENV{DPS_PASSWORD}) if($ENV{DPS_USER} && $ENV{DPS_PASSWORD});
    my $Response = $ua->request($Request);
    if($Response->is_success())
    {
        my $fromjson;
        eval { $fromjson = from_json($Response->decoded_content()) };
        if($@)
        {
            warn("ERROR: ==$Channel== unexpected json response : $@");
            print($Response->content(), "\n");
        }
        else
        {
            warn("ERROR: ==$Channel== response content: ", $Response->content()) unless($fromjson->{'status'} eq 'OK');
            print("[INFO] ==$Channel== ==$URL== Job id is ", $fromjson->{'data'}{'job_id'}, "\n");
        }
    }
    else
    {
        warn($Response->status_line()=~/(?:200|201|302)/?"WARNING":"ERROR", ": ==$Channel== unexpected HTTP response : ", $Response->status_line());
        print($Response->content(), "\n");
    }
    printf("push to preview server took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);
}

sub PushToHelpPortal
{
    print("== PUSH TO HELP PORTAL ==\n");
    map({print("\t$_=${$rhParameters}{$_}\n")} keys(%{$rhParameters}));

    my @Start = Today_and_Now();
    printf("push to help portal took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);
}

sub CommonPushTasks()
{
    warn("ERROR: ==$Channel== channelid is missing. Use -d channelid=<channelid>") unless(exists(${$rhParameters}{channelid}));
    my $MetadataFile = "${$rhParameters}{metadatadir}/metadata.xml";
    warn("ERROR: ==$Channel== '$MetadataFile' not found!") unless(-f $MetadataFile);

    print("Add metadata...\n"); 
    my $Dir = "$ENV{OUTPUT_DIR}/bin/zip_with_metadata/${$rhParameters}{channelid}/$ENV{BUILD_MODE}";
    mkpath($Dir) or die("ERROR: ==$Channel== cannot mkpath '$Dir': $!") unless(-d $Dir);
    my $OutputFileWithMetadata = "$Dir/OutputWithMetadata.zip";
    local $SIG{__WARN__} = sub {};   # As the read method returns screen warning messages, disable them
    my $ZIP = Archive::Zip->new();
    unless($ZIP->read($OutputFile)==AZ_OK) { my($Name)=$OutputFile=~/([^\\\/]*)$/; die("ERROR: ==$Channel== cannot addfile '$OutputFile': $!") unless($ZIP->addFile($OutputFile, $Name)) }
    warn("ERROR: ==$Channel== cannot updateMember '$MetadataFile': $!") unless($ZIP->updateMember(${$rhParameters}{metadata}, $MetadataFile));
    warn("ERROR: ==$Channel== cannot writeToFileHandle '$OutputFileWithMetadata': $!") unless($ZIP->writeToFileNamed($OutputFileWithMetadata)==AZ_OK);
    return $OutputFileWithMetadata;
}

sub Usage
{
   print <<USAGE;
   Usage   : DeliveryToChannel.pl -o -d 
   Example : DeliveryToChannel.pl -h
             DeliveryToChannel.pl -o=myfile.jar -d url=http://help.sap.com -d version=14.0.0
       
   -help|?   argument displays helpful information about builtin commands.
   -d.efine  specifies list of key/value
   -o.utput  specifies the output file name.
USAGE
    exit 0;
}