#!/usr/bin/perl -w

use Date::Calc(qw(Today_and_Now Delta_DHMS));
use Sys::Hostname;
use File::Compare;
use Data::Dumper;
use File::Copy;
use File::Path;
use Net::SMTP;
use XML::DOM;

use FindBin;
use lib($FindBin::Bin);
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

die("ERROR: MY_BUILD_NAME environment variable must be set") unless($Project=$ENV{MY_BUILD_NAME});
die("ERROR: SRC_DIR environment variable must be set") unless($SRC_DIR=$ENV{SRC_DIR});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($OUTPUT_DIR=$ENV{OUTPUT_DIR});
die("ERROR: q_p_buildcycles environment variable must be set") unless($BUILD_CYCLE=$ENV{q_p_buildcycles});
die("ERROR: Context environment variable must be set") unless($ENV{Context});
die("ERROR: BUILD_NAME environment variable must be set") unless($ENV{BUILD_NAME});
die("ERROR: PLATFORM environment variable must be set") unless($ENV{PLATFORM});
die("ERROR: BUILD_MODE environment variable must be set") unless($ENV{BUILD_MODE});
die("ERROR: PACKAGES_DIR environment variable must be set") unless($ENV{PACKAGES_DIR});
die("ERROR: MY_DITA_PROJECT_ID environment variable must be set") unless($ENV{MY_DITA_PROJECT_ID});
die("ERROR: O2OMETA_DIR environment variable must be set") unless($ENV{O2OMETA_DIR});
die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});

$CURRENTDIR = $FindBin::Bin;
$NEW_COLLECTION_DIR = "$ENV{PACKAGES_DIR}/collection";
$PREVIOUS_COLLECTION_DIR = "$ENV{O2OMETA_DIR}/collection";
$reRef1 = qr/<(topicref|mapref|navref|link|xref|image).*?(?<!con)ref[\s\n]*=[\s\n]*["']([0-9a-zA-Z]{32}\.(?:xml|ditamap|image|res))/;
$reRef2 = qr/[\s\n](conref)[\s\n]*=[\s\n]*["']([0-9a-zA-Z]{32}\.(?:xml|ditamap|image|res))/;
$filter = qr/\.(?:xml$|ditamap$|image$|res$)/;
my %TabFiles;

$IsRobocopy = $^O eq "MSWin32" ? (`which robocopy.exe 2>&1`=~/robocopy.exe$/i  ? 1 : 0) : 0;
$ROBOCOPY_OPTIONS = $ENV{ROBOCOPY_OPTIONS} || "/MIR /NP /NFL /NDL /R:3";

########
# Main #
########

@Start = Today_and_Now();

$IsIncrementalFetch = $IsFetchFinished = 0;
open(LOG, "$ENV{OUTPUT_DIR}/logs/Build/cms.log") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/Build/cms.log': $!");
while(<LOG>) {
    if(/^INCREMENTAL FETCH/i) { $IsIncrementalFetch = 1 }
    elsif(/^THE FETCH IS FINISHED/i) { $IsFetchFinished = 1 }
}
close(LOG);
warn("ERROR: [FETP002E][ERROR] [sapLevel:ERROR] Due to a project fetch failure, delta compilation is disabled. Please ask your power user to raise a ticket to CMS Admin team.") unless($IsFetchFinished and (!$IsIncrementalFetch or -f "$SRC_DIR/cms/TempFolder/fetched_files.txt"));

($IsFeatureFound, $IsFeatureErrorFound) = (0, 0);
open(DAT, "$ENV{SRC_DIR}/cms/content/projects/RefFiles.dat") or warn("ERROR: cannot open '$ENV{SRC_DIR}/cms/content/projects/RefFiles.dat': $!");
eval <DAT>;
close(DAT);
FILE: foreach my $File (keys(%RefFiles)) {
    last FILE if($IsFeatureFound = IsRefFeatureFound($File));
}
if($IsFeatureFound) {
    my $Summary = "$OUTPUT_DIR/logs/Build/cms.summary.txt";
    if(-e $Summary) {
        open(TXT, $Summary) or warn("WARNING: cannot open '$Summary': $!");
        while(<TXT>) {
            if(/ERROR: unexpected HTTP response/ or /ERROR: unexpected json response/ or /ERROR: cannot parsefile.+conditionaltext.xml/) { $IsFeatureErrorFound=1; last }
        }
        close(TXT);
    }
}
unlink("$OUTPUT_DIR/logs/Build/FeatureImpactedOutputs.dat") or warn("ERROR: cannot unlink '$OUTPUT_DIR/logs/Build/FeatureImpactedOutputs.dat': $!") if(-f "$OUTPUT_DIR/logs/Build/FeatureImpactedOutputs.dat");
if($IsFeatureErrorFound) {
    my $ProjectMap ||= $ENV{MY_PROJECTMAP} || ProjectMapFromProject(<$SRC_DIR/cms/content/projects/*.project>);
    my @OutputsImpactedByFeature;
    my $PROJECTMAP = XML::DOM::Parser->new()->parsefile("$SRC_DIR/cms/content/localization/en-US/$ProjectMap");
    for my $OUTPUT (@{$PROJECTMAP->getElementsByTagName('output')})
    {
        my($Id, $TransType) = ($OUTPUT->getAttribute('id'), $OUTPUT->getAttribute('transtype'));
        my $BuilddableMapRef = $OUTPUT->getElementsByTagName('buildable-mapref')->item(0)->getAttribute('href');
        for my $DELIVRABLE (@{$OUTPUT->getElementsByTagName('deliverable')})
        {
            next unless($DELIVRABLE->getAttribute('status') eq 'enabled');
            $Lang = $DELIVRABLE->getAttribute('lang');
            next unless(IsImpactedByFeature("$Lang/$BuilddableMapRef"));
            push(@OutputsImpactedByFeature, [$DELIVRABLE->getAttribute('filename'), $Lang, 'impacted by feature flag incident', $TransType, $Id, $OUTPUT->getAttribute('navtitle')]);
        }
    }
    open(DAT, ">$OUTPUT_DIR/logs/Build/FeatureImpactedOutputs.dat") or warn("ERROR: cannot open '$OUTPUT_DIR/logs/Build/FeatureImpactedOutputs.dat': $!");
    print(DAT Data::Dumper->Dump([\@OutputsImpactedByFeature], ["*OutputsImpactedByFeature"]));
    close(DAT);
    %Sources = ();
}

exit 0 unless(exists($ENV{MY_PROJECTMAP}));

open(DAT0, ">$OUTPUT_DIR/logs/Build/DeltaCompilation.dat") or warn("ERROR: cannot open '$OUTPUT_DIR/logs/Build/DeltaCompilation.dat': $!");

open(DAT, "$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.dat") or die("ERROR: cannot open '$ENV{DITA_CONTAINER_DIR}/content/projects/$Project.dat': $!");
eval <DAT>;
close(DAT);
($ProjectMap, $FallbackLanguage) = @Project[0,2];
$Delta = "$SRC_DIR/cms/content/localization/en-US/${ProjectMap}delta";
$Empty = "$SRC_DIR/cms/content/localization/en-US/$ProjectMap.empty";
unlink($Delta) or warn("ERROR: cannot unlink '$Delta': $!") if(-f $Delta);
unlink($Empty) or warn("ERROR: cannot unlink '$Empty': $!") if(-f $Empty);

unless(-f "$SRC_DIR/cms/TempFolder/fetched_files.txt") {
    rmtree($ENV{O2OMETA_DIR}) or warn("ERROR: cannot rmtree '$ENV{O2OMETA_DIR}': $!") if(-d $ENV{O2OMETA_DIR});
    mkpath($ENV{O2OMETA_DIR}) or warn("ERROR: cannot mkpath '$ENV{O2OMETA_DIR}': $!");
    CopyFiles("$ENV{PACKAGES_DIR}/collection", "$ENV{O2OMETA_DIR}/collection") if(-d "$ENV{PACKAGES_DIR}/collection");
    CopyFiles("$ENV{PACKAGES_DIR}/metadata", "$ENV{O2OMETA_DIR}/metadata") if(-d "$ENV{PACKAGES_DIR}/metadata");
    print("INFO:DCR001 '$SRC_DIR/cms/TempFolder/fetched_files.txt' not found, DeltaCompilation not activated\n");
    exit 0;
}

opendir(LG, "$SRC_DIR/cms/content/localization") or  warn("WARNING: cannot opendir '$SRC_DIR/cms/content/localization': $!");
while(defined(my $Language = readdir(LG)))
{
    next unless($Language =~ /^([a-z]{2}-[A-Z]{2})$/);
    LoadDir("$SRC_DIR/cms/content/localization/$Language", $Language);
}
closedir(LG);

foreach my $File ("fetched_files.txt")
{
    next unless(-f "$SRC_DIR/cms/TempFolder/$File");
    open(TXT, "$SRC_DIR/cms/TempFolder/$File") or warn("ERROR: cannot open '$SRC_DIR/cms/TempFolder/$File': $!");
    while(<TXT>)
    {
        chomp();
        $FetchedFiles{$_} = undef;
        my($Language) = /^([a-z]{2}-[A-Z]{2})/;
        $FetchedLanguages{$Language} = undef;
    }
    close(TXT);
}

$PROJECTMAP = XML::DOM::Parser->new()->parsefile("$SRC_DIR/cms/content/localization/en-US/$ENV{MY_PROJECTMAP}");
$ProjectMapId = $PROJECTMAP->getElementsByTagName('project-map')->item(0)->getAttribute('id');
$PROJECTMAP->dispose();

system("cd /d $CURRENTDIR/buildconfigurator & buildconfigurator.bat --buildcycles $ENV{q_p_buildcycles} --ixiaprojectid $ENV{MY_DITA_PROJECT_ID} --projectmap $SRC_DIR/cms/content/localization/en-US/$ENV{MY_PROJECTMAP} --targetpath $SRC_DIR/$ENV{PROJECT}/export");
open(TXT, "$SRC_DIR/documentation/export/collections.txt") or warn("ERROR: cannot open '$SRC_DIR/documentation/export/collections.txt': $!");
@Collections = split(/\s+/, <TXT>);
close(TXT);

my %O2OMetadatas;
foreach (@Collections)
{
    (my $Collection = $_) =~ s/^collection_(.+)00(.+)$/col_${ProjectMapId}_$1.$2.xml/;
    unless(-f "$NEW_COLLECTION_DIR/$Collection") { warn("ERROR: cannot found '$NEW_COLLECTION_DIR/$Collection'"); next }
    my $COLLECTION = XML::DOM::Parser->new()->parsefile("$NEW_COLLECTION_DIR/$Collection");
    for my $COLOUTPUT (@{$COLLECTION->getElementsByTagName('colOutput')})
    {
        my $HRef = $COLOUTPUT->getAttribute('href');
        next if($HRef =~ /\/${ProjectMapId}_/);
        $HRef =~ s/metadata.xml/mapping.dat/;
        my $NewMapping = "$NEW_COLLECTION_DIR/$HRef";
        my $PreviousMapping = "$PREVIOUS_COLLECTION_DIR/$HRef";

        my($Language) = $Collection =~ /(.{5})\.xml$/;
        $NewMapping =~ s/$Language/$FallbackLanguage/ unless(-f $NewMapping);
        $PreviousMapping =~ s/$Language/$FallbackLanguage/ unless(-f $PreviousMapping);
        unless(-f $NewMapping) { warn("ERROR: cannot found '$NewMapping' for '$Collection'"); next }
        
        next if(-f $PreviousMapping and compare($NewMapping, $PreviousMapping)==0);
        my(%NewHRefs, %PreviousHRefs);
        open(DAT, $NewMapping) or warn("ERROR: cannot open '$NewMapping': $!");
        { local $/; map({ $NewHRefs{${$_}[0]}=${$_}[1] unless(exists($NewHRefs{${$_}[0]})) } @{eval(<DAT>)}) }
        close(DAT);
        if(-f $PreviousMapping)
        {
            open(DAT, $PreviousMapping) or warn("ERROR: cannot open '$PreviousMapping': $!");
            { local $/; map({ $PreviousHRefs{${$_}[0]}=${$_}[1] unless(exists($PreviousHRefs{${$_}[0]})) } @{eval(<DAT>)}) }
            close(DAT);
        }
        FILE: for my $File (keys(%NewHRefs))
        {
            unless(exists($PreviousHRefs{$File}))
            {
                print("INFO:DCR005 new mapping '$File' in '$Collection'.\n");
                $FetchedFiles{"$Language/$File"} = $O2OMetadatas{"$Language/$File"} = undef;
                $FetchedLanguages{$Language} = undef;
                next;
            }
            foreach my $Key (keys(%{$NewHRefs{$File}}))
            {
                next if(exists(${$PreviousHRefs{$File}}{$Key}) and ${$NewHRefs{$File}}{$Key} eq ${$PreviousHRefs{$File}}{$Key});
                print("INFO:DCR006 The link in '$File' change for the key '$Key' : '${$NewHRefs{$File}}{$Key}' is different from '${$PreviousHRefs{$File}}{$Key}'.\n");
                $FetchedFiles{"$Language/$File"} = $O2OMetadatas{"$Language/$File"} = undef;
                $FetchedLanguages{$Language} = undef;
                next FILE;
            }
            foreach my $Key (keys(%{$PreviousHRefs{$File}}))
            {
                next if(exists(${$NewHRefs{$File}}{$Key}));
                print("INFO:DCR007 The key '$Key' from '$File' was removed.\n");
                $FetchedFiles{"$Language/$File"} = $O2OMetadatas{"$Language/$File"} = undef;
                $FetchedLanguages{$Language} = undef;
                next FILE;
            }
        }
    }
    $COLLECTION->dispose();
}

if(exists($FetchedFiles{"en-US/$ProjectMap"}))
{
    unless(-f "$SRC_DIR/cms/content/localization/en-US/$ProjectMap.previous") { print("INFO:DCR002 The projectmap 'en-US/$ProjectMap' is updated: Delta Compilation not possible\n"); exit 0 }
    my $rhPreviousOutputs = Outputs("$SRC_DIR/cms/content/localization/en-US/$ProjectMap.previous"); 
    my $rhCurrentOutputs = Outputs("$SRC_DIR/cms/content/localization/en-US/$ProjectMap");
    foreach my $Id (keys(%{$rhCurrentOutputs}))
    {
        $ImpactedInProjectMap{$Id} = undef if(!exists(${$rhPreviousOutputs}{$Id}) or ${$rhPreviousOutputs}{$Id} ne ${$rhCurrentOutputs}{$Id});
    }
}

$PROJECTMAP = XML::DOM::Parser->new()->parsefile("$SRC_DIR/cms/content/localization/en-US/$ProjectMap");
for my $OUTPUT (@{$PROJECTMAP->getElementsByTagName('output')})
{
    my($Id, $TransType) = ($OUTPUT->getAttribute('id'), $OUTPUT->getAttribute('transtype'));
    my $BuilddableMapRef = $OUTPUT->getElementsByTagName('buildable-mapref')->item(0)->getAttribute('href');
    for my $DELIVRABLE (@{$OUTPUT->getElementsByTagName('deliverable')})
    {
        my $BUILDCYCLE = $DELIVRABLE->getAttribute('buildCycle');
        next unless($DELIVRABLE->getAttribute('status') eq 'enabled' and $BUILD_CYCLE=~/$BUILDCYCLE/i);
        $Lang = $DELIVRABLE->getAttribute('lang');
        my $IsDeliveryChannelFound = 0;
        for my $DELIVERYCHANNEL (@{$DELIVRABLE->getElementsByTagName('deliveryChannel')})
        {
            if($DELIVERYCHANNEL->getAttribute('status') eq 'enabled' and $DELIVERYCHANNEL->getAttribute('type') eq 'pre-publishing') { $IsDeliveryChannelFound=1; last }
        }
        (my $TrnsTp = $TransType) =~ s/\./00/;
        if($IsDeliveryChannelFound)
        {
            my $Summary = "$ENV{HTTP_DIR}/$ENV{context}/latest/export_${TrnsTp}_${Lang}_${Id}_prepublishing=win64_x64_release_summary_export.txt";
            if(-e $Summary)
            {
                open(TXT, $Summary) or warn("WARNING: cannot open '$Summary': $!");
                while(<TXT>)
                {
                    if(/^\[ERROR\s+\@\d+\]/) { $PublishingInError{"${Id}_${Lang}_$TransType"} = undef; last }
                }
                close(TXT);
            }
            $Summary = "$ENV{HTTP_DIR}/$ENV{context}/latest/smoke_${TrnsTp}_${Lang}_${Id}=win64_x64_release_summary_smoke.txt";
            if(-e $Summary)
            {
                open(TXT, $Summary) or warn("WARNING: cannot open '$Summary': $!");
                while(<TXT>)
                {
                    if(/^\[ERROR\s+\@\d+\]/) { $PublishingInError{"${Id}_${Lang}_$TransType"} = undef; last }
                }
                close(TXT);
            }
        }
        else
        {
            my $Summary = "$ENV{HTTP_DIR}/$ENV{context}/latest/build_${TrnsTp}_${Lang}_${Id}=win64_x64_release_summary_build.txt";
            if(-e $Summary)
            {
                open(TXT, $Summary) or warn("WARNING: cannot open '$Summary': $!");
                while(<TXT>)
                {
                
                    next unless(/^\[ERROR\s+\@\d+\]/);
                    my $Level;
                    if(/\[sapLevel:(\w+?)\]/i) { $Level = $1 }
                    elsif(/\s\[\w+?\]\[(INFO|FATAL)\]/) { $Level = $1 }
                    elsif(/(?:build failed|Error occurred during initialization of VM|com.ixiasoft.outputgenerator.packager.sap.LinkRemapper - Two versions of container|Failed to deploy artifacts|CORBA.COMM_FAILURE|Exception in thread|FATAL:\s*com\.ixiasoft\.)/i) { $Level = 'FATAL' }
                    elsif(/ERROR:\s*com\.ixiasoft\./i || /cannot add signature/i) { $Level = 'ERROR' }
                    else { $Level = 'WARN' }
                    if($Level eq 'FATAL') { $PublishingInError{"${Id}_${Lang}_$TransType"} = undef; last }
                }
                close(TXT);
            }
        }
        $ImpactingFile = undef;
        unless(($IsFeatureErrorFound and IsImpacted("$Lang/$BuilddableMapRef")) or (exists($PublishingInError{"${Id}_${Lang}_$TransType"}) or exists($ImpactedInProjectMap{"${Id}_${Lang}_$TransType"}) or (exists($FetchedLanguages{$Lang}) and IsImpacted("$Lang/$BuilddableMapRef"))))
        {
            $DELIVRABLE->setAttribute('status','disabled');
            next;
        }
        my $Message;
        if(exists($ImpactedInProjectMap{"${Id}_${Lang}_$TransType"}) and $ImpactingFile ne 'feature flag incident') { $Message = "impacted by en-US/$ProjectMap (projectmap)" }
        elsif(exists($PublishingInError{"${Id}_${Lang}_$TransType"}) and $ImpactingFile ne 'feature flag incident') { $Message = 'impacted by previous error' }
        else { $ImpactingFile||=$Sources{"$Lang/$BuilddableMapRef"}; $Message = "impacted by $ImpactingFile" } 
        $Sources{"$Lang/$BuilddableMapRef"} = $ImpactingFile if($ImpactingFile);
        push(@ImpactedOutputs, [$DELIVRABLE->getAttribute('filename'), $Lang, $Message, $TransType, $Id, $OUTPUT->getAttribute('navtitle')]);
    }
}

rmtree($ENV{O2OMETA_DIR}) or warn("ERROR: cannot rmtree '$ENV{O2OMETA_DIR}': $!") if(-d $ENV{O2OMETA_DIR});
mkpath($ENV{O2OMETA_DIR}) or warn("ERROR: cannot mkpath '$ENV{O2OMETA_DIR}': $!");
CopyFiles("$ENV{PACKAGES_DIR}/collection", "$ENV{O2OMETA_DIR}/collection");
CopyFiles("$ENV{PACKAGES_DIR}/metadata", "$ENV{O2OMETA_DIR}/metadata");

if(@ImpactedOutputs)
{
    $PROJECTMAP->getXMLDecl()->setEncoding('utf-8');
    open(my $XML, '>:encoding(UTF-8)', $Delta) or die("ERROR: cannot open '$Delta': $!");
    $PROJECTMAP->printToFileHandle($XML);
    close($XML);
    @ImpactedOutputs = sort({${$a}[1] cmp ${$b}[1] or ${$a}[0] cmp ${$a}[0]} @ImpactedOutputs);
    for(my $i=0; $i<@ImpactedOutputs; $i++)
    {
        my($Name, $Language, $Message, $TransType) = @{$ImpactedOutputs[$i]};
        printf("%04u: %s %s '%s' %s\n", $i+1, $Language, $TransType, $Name, $Message);
    }
    print(DAT0 Data::Dumper->Dump([\@ImpactedOutputs], ["*ImpactedOutputs"]));
    print(DAT0 Data::Dumper->Dump([\%O2OMetadatas], ["*O2OMetadatas"]));
}
else
{
    print("INFO:DCR003 no impacted outputs\n");
    open(IN, ">$Delta");
    close(IN);
    open(IN, ">$Empty");
    close(IN);
    if(exists($ENV{BUILDREV}) and exists($ENV{BUILD_NAME}))
    {
        rmtree("$ENV{IMPORT_DIR}/$ENV{MY_BUILD_NAME}/$ENV{BUILDREV}") or warn("ERROR: cannot rmtree '$ENV{IMPORT_DIR}/$ENV{MY_BUILD_NAME}/$ENV{BUILDREV}': $!");
        rmtree("$ENV{HTTP_DIR}/$ENV{MY_BUILD_NAME}/$ENV{BUILD_NAME}") or warn("ERROR: cannot rmtree '$ENV{HTTP_DIR}/$ENV{MY_BUILD_NAME}/$ENV{BUILD_NAME}': $!");
        open(VER, "$ENV{IMPORT_DIR}/$ENV{MY_BUILD_NAME}/version.txt") or warn("ERROR: cannot open '$ENV{IMPORT_DIR}/$ENV{MY_BUILD_NAME}/version.txt': $!"); 
        chomp(my $BuildNumber = <VER>);
        close(VER);
        if($ENV{BUILDREV} == $BuildNumber)
        {
            open(VER, ">$ENV{IMPORT_DIR}/$ENV{MY_BUILD_NAME}/version.txt") or die("ERROR: cannot open '$ENV{IMPORT_DIR}/$ENV{MY_BUILD_NAME}/version.txt': $!");
            print(VER $ENV{BUILDREV}-1, "\n");
            close(VER);
        }
        open(DAT, ">$ENV{HTTP_DIR}/$ENV{MY_BUILD_NAME}/NothingToDo.dat") or die("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{MY_BUILD_NAME}/NothingToDo.dat': $!");
        print(DAT '@NothingToDo=(', time(), ", 'no impacted outputs')");
        close(DAT);
    }
    kill('KILL', $ENV{BUILD_PID}) or warn("ERROR: cannot kill '$ENV{BUILD_PID}': $!");
}
$PROJECTMAP->dispose();
printf("Impacted took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);
print("Number of parsed files: ", scalar(keys(%Sources)), "\n");
close(DAT0);

#############
# Functions #
#############

sub Outputs
{
    my($ProjectMap) = @_;
    
    my $PROJECTMAP = XML::DOM::Parser->new()->parsefile($ProjectMap);
    my %OutputMetas;
    for my $OUTPUTMETA (@{$PROJECTMAP->getElementsByTagName('outputmeta')})
    {
        my $Id = $OUTPUTMETA->getAttribute('id');
        $OutputMetas{$Id} = $OUTPUTMETA->toString();
    }
    my %Renderings;
    for my $RENDERING (@{$PROJECTMAP->getElementsByTagName('rendering')})
    {
        my $Id = $RENDERING->getAttribute('id');
        $Renderings{$Id} = $RENDERING->toString();
    }
    my %Profilings;
    for my $PROFILING (@{$PROJECTMAP->getElementsByTagName('profiling')})
    {
        my $Id = $PROFILING->getAttribute('id');
        $Profilings{$Id} = $PROFILING->toString();
    }
    my %DeliveryChannelSettings;
    for my $DELIVERYCHANNELSETTING (@{$PROJECTMAP->getElementsByTagName('deliveryChannelSetting')})
    {
        my $Id = $DELIVERYCHANNELSETTING->getAttribute('id');
        $DeliveryChannelSettings{$Id} = $DELIVERYCHANNELSETTING->toString();
    }
    my $Dependencies = join('', sort(map({$_->toString()} @{$PROJECTMAP->getElementsByTagName('dependency')})));
    
    my %Outputs;
    for my $OUTPUT (@{$PROJECTMAP->getElementsByTagName('output')})
    {
        my $OutputAttributes = '';
        foreach my $Name (sort(keys(%{$OUTPUT->getAttributes()})))
        {
            next unless($Name);
            $OutputAttributes .= "$Name=".$OUTPUT->getAttribute($Name);
        }
        my($Id, $TransType, $OutputMeta, $Rendering, $Profiling) = ($OUTPUT->getAttribute('id'), $OUTPUT->getAttribute('transtype'), $OUTPUT->getAttribute('outputmeta'), $OUTPUT->getAttribute('rendering'), $OUTPUT->getAttribute('profiling'));
        for my $DELIVRABLE (sort({$a->toString() cmp $b->toString()} @{$OUTPUT->getElementsByTagName('deliverable')}))
        {
            my $BUILDCYCLE = $DELIVRABLE->getAttribute('buildCycle');
            next unless($DELIVRABLE->getAttribute('status') eq 'enabled' and $BUILD_CYCLE=~/$BUILDCYCLE/i);
            my $Lang = $DELIVRABLE->getAttribute('lang');
            warn("ERROR: duplicate ${Id}_${Lang}_$TransType in '$ProjectMap'") if(exists($Outputs{"${Id}_${Lang}_$TransType"}));
            $Outputs{"${Id}_${Lang}_$TransType"} = $OutputAttributes;
            $Outputs{"${Id}_${Lang}_$TransType"} .= $DELIVRABLE->toString();
            $Outputs{"${Id}_${Lang}_$TransType"} .= $OutputMetas{$OutputMeta} if(exists($OutputMetas{$OutputMeta}));
            $Outputs{"${Id}_${Lang}_$TransType"} .= $Renderings{$Rendering} if(exists($Renderings{$Rendering}));
            $Outputs{"${Id}_${Lang}_$TransType"} .= $Profilings{$Profiling} if(exists($Profilings{$Profiling}));
            $Outputs{"${Id}_${Lang}_$TransType"} .= $Dependencies;
            for my $DeliveryChannel (sort(map({$_->getAttribute('deliveryChannelSetting')} @{$DELIVRABLE->getElementsByTagName('deliveryChannel')})))
            {
                $Outputs{"${Id}_${Lang}_$TransType"} .= $DeliveryChannelSettings{$DeliveryChannel} if(exists($DeliveryChannelSettings{$DeliveryChannel}));
            }
        }
    }
    $PROJECTMAP->dispose();
    return \%Outputs;
}

sub IsImpacted
{
    my($File) = @_;

    return $Sources{$File} if(exists($Sources{$File}));
    $Sources{$File} = 0;
    if(exists($FetchedFiles{$File})) {
        if($IsFeatureErrorFound and IsRefFeatureFound($File)) {
            ($Sources{$File}, $ImpactingFile) = (1, 'feature flag incident');
            return $Sources{$File};
        }
        ($Sources{$File}, $ImpactingFile) = (1, $File);
        return $Sources{$File} unless($IsFeatureErrorFound);
    }
    local $^W = 0;
    my $rhRefs = GetRefs($File);
    foreach my $Ref (keys(%{$rhRefs})) {
        my $HRef = "$Lang/$Ref";
        if($IsFeatureErrorFound and IsRefFeatureFound($HRef)) {
            ($Sources{$HRef}, $ImpactingFile) = (1, 'feature flag incident');
            return $Sources{$HRef};
        }
        unless($TabFiles{$HRef}) { print(STDERR "WARN: cannot find reference '$HRef' from source '$SRC_DIR/cms/content/localization/$File'\n"); next }
        my $Tag = ${$rhRefs}{$Ref};
        if($Tag =~ /(?:navref|link|xref|image)/) {
            if(exists($FetchedFiles{$HRef})) {
                ($Sources{$File}, $Sources{$HRef}, $ImpactingFile) = (1, 1, $HRef);
                return $Sources{$File} unless($IsFeatureErrorFound);
            }
        }
        elsif(IsImpacted($HRef)) {
            $Sources{$File} = 1; 
            return $Sources{$File} unless($IsFeatureErrorFound);
        }
    }
    return $Sources{$File};
}

sub IsImpactedByFeature
{
    my($File) = @_;

    return $Sources{$File} if(exists($Sources{$File}));
    return $Sources{$File} = 1 if(IsRefFeatureFound($File));
    $Sources{$File} = 0;
    local $^W = 0;
    my $rhRefs = GetRefs($File);
    foreach my $Ref (keys(%{$rhRefs})) {
        my $HRef = "$Lang/$Ref";
        return $Sources{$File} = $Sources{$HRef} = 1 if(IsRefFeatureFound($HRef));
        my $Tag = ${$rhRefs}{$Ref};
        next if($Tag =~ /(?:navref|link|xref|image)/);
        return 1 if(IsImpactedByFeature($HRef));
    }
    return $Sources{$File};
}

sub IsRefFeatureFound {
    my($File) = @_;

    if(exists($RefFiles{$File})) {
        foreach my $Ref (keys(%{$RefFiles{$File}})) {
            return 1 if(${$RefFiles{$File}}{$Ref} eq 'feature');
        }
    }
    return 0;
}

sub GetRefs
{
    my($File) = @_;

    my($Lines, %Refs);
    unless(open(IN, "$SRC_DIR/cms/content/localization/$File")) { warn("ERROR: cannot open '$SRC_DIR/cms/content/localization/$File': $!"); return \%Refs }
    { local $/; $Lines = <IN> }
    close(IN);
    %Refs = reverse($Lines=~/$reRef1/sg, $Lines=~/$reRef2/sg);
    return \%Refs;
}
sub CopyFiles
{
    my($Source, $Destination, $Message) = @_;
    my $Result;
    if($^O eq "MSWin32")
    { 
        $Source =~ s/\//\\/g;
        if(-e $Source)
        {
            $Destination =~ s/\//\\/g;
            $Destination =~ s/\\$//;
            ($Destination) = $Destination =~ /^(.*\\)[^\\]+$/ if(-f $Source);
            my $CopyCmd;
            if($IsRobocopy && !(-f $Source)) { $CopyCmd = "robocopy $ROBOCOPY_OPTIONS" }
            else { $CopyCmd = "xcopy " . (-f $Source ? "/CQRYD" : "/ECIQHRYD") }
            mkpath($Destination) or warn("ERROR: cannot mkpath '$Destination': $!") unless(-e $Destination);
            $Result = system("$CopyCmd \"$Source\" \"$Destination\"");
            $Result &= 0xff;
            warn("ERROR: cannot copy '$Source' to '$Destination': $! at ". (scalar(localtime()))) if($Result);
        } else { warn("ERROR: '$Source' not found") }
    }
    else
    { 
        $Source =~ s/\\/\//g;
        if(-e $Source)
        {
            $Destination =~ s/\\/\//g;
            mkpath($Destination) or warn("ERROR: cannot mkpath '$Destination': $!") unless(-e $Destination);
            for my $Attempt (1..3)
            {
                print("new attempt ($Attempt/3)\n") if($Attempt>1);
                if(-d $Source) { $Result = system("cp -dRuf --preserve=mode,timestamps \"$Source/.\" $Destination 1>$NULLDEVICE") }
                else { $Result = system("cp -dRuf --preserve=mode,timestamps \"$Source\" $Destination 1>$NULLDEVICE") }
                last unless($Result);
                warn(($Attempt==3?"ERROR":"WARNING").": cannot copy '$Source/.' to '$Destination' (attempt $Attempt/3): $!");
                sleep(24);    
            }
        } else { warn("ERROR: '$Source' not found") }
    }   
    print($Message) if($Message);
    return $Result;
}

sub LoadDir
{
    my ($dir,$Lang)=@_;
    if(opendir(DIR,$dir))
    {
        my @files= readdir DIR;
        foreach(@files)
        {
            chomp;
            next unless($_=~/$filter/);
            $TabFiles{"$Lang/$_"}=1;
        }
        closedir DIR;
    }
    else
    {
        print "ERROR: cannot open dir $dir: $!\n";
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
    print(HTML "<br/>Stack Trace:<br/>\n");
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