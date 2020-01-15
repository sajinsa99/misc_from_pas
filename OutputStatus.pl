#!/usr/bin/perl -w

use Date::Calc(qw(Today_and_Now Delta_DHMS Localtime));
use Data::Dumper;
use File::Copy;
use File::Path;
use File::Copy;
use XML::DOM;

use FindBin;
use lib ($FindBin::Bin);
$ENV{PROJECT} = 'documentation';
require Site;

$Data::Dumper::Indent = 0;
warn("ERROR: SRC_DIR environment variable must be set") unless($ENV{SRC_DIR});
warn("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});
warn("ERROR: HTTP_DIR environment variable must be set") unless($ENV{HTTP_DIR});
warn("ERROR: DROP_DIR environment variable must be set") unless($ENV{DROP_DIR});
warn("ERROR: BUILD_NAME environment variable must be set") unless($ENV{BUILD_NAME});
warn("ERROR: BUILDREV environment variable must be set") unless($ENV{BUILDREV});
warn("ERROR: BUILD_MODE environment variable must be set") unless($ENV{BUILD_MODE});
warn("ERROR: Q_P_BUILDMODE environment variable must be set") unless($ENV{Q_P_BUILDMODE});
warn("ERROR: context environment variable must be set") unless($ENV{context});

($SRC_DIR = $ENV{SRC_DIR}) =~ s/\\/\//g;
$CMS_DIR = "$SRC_DIR/cms";
$Stream = $ENV{context};
$BuildName = $ENV{BUILD_NAME};
($TextMLServer) = $ENV{MY_TEXTML} =~ /^([^\\\/]+)/;
$Requester = $ENV{MY_BUILD_REQUESTER} || 'Daily build';
if(-f "$SRC_DIR/cms/content/projects/deltafetch.timestamp") { $BackupDone = "$SRC_DIR/cms/content/projects/deltafetch.timestamp" }
else { $BackupDone = (exists($ENV{MY_PROJECTMAP})) ? "$ENV{DITA_CONTAINER_DIR}\\content\\projects\\deltafetch.timestamp" : '\\\\pwdf3741\r$\backups\dita-all\BackupDone.txt' }
($StepStart, $StepStop) = (0xFFFFFFFF, 0);

@Start = Today_and_Now();
opendir(STEP, "$ENV{OUTPUT_DIR}/logs/Build") or warn("ERROR: cannot opendir '$ENV{OUTPUT_DIR}/logs/Build/': $!");
while(defined(my $Summary = readdir(STEP)))
{
    next unless($Summary =~ /_step.summary.txt/);
    open(TXT, "$ENV{OUTPUT_DIR}/logs/Build/$Summary") or warn("WARNING: cannot open '$ENV{OUTPUT_DIR}/logs/Build/$Summary': $!");
    while(<TXT>)
    {
        if(my($Start) = /^== Build start:.+\((\d+)\)/) { $StepStart = $Start if($Start<$StepStart) }
        elsif(my($Stop) = /^== Build end  :.+\((\d+)\)/) { $StepStop = $Stop if($Stop>$StepStop) }
    }
    close(TXT);
}
closedir(STEP);
printf("opendir '$ENV{OUTPUT_DIR}/logs/Build' took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

@Start = Today_and_Now();
mkpath("$ENV{HTTP_DIR}/$ENV{context}/latest") or warn("ERROR: cannot mkpath '$ENV{HTTP_DIR}/$ENV{context}/latest': $!") unless(-d "$ENV{HTTP_DIR}/$ENV{context}/latest");  
opendir(LOGS, "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1") or warn("ERROR: cannot opendir '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1': $!");
while(defined(my $Log = readdir(LOGS)))
{
    next unless($Log =~ /^(?:build|export)_.+_[^_]+_loio[0-9a-f]{32}.*?=.*?\.(?:log|txt)$/i);
    copy("$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1/$Log", "$ENV{HTTP_DIR}/$ENV{context}/latest") or warn("ERROR: cannot copy '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1/$Log': $!");
}
closedir(LOGS);
printf("opendir '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1' took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

@Start = Today_and_Now();
open(DIR, "cmd /c dir /b \"$ENV{HTTP_DIR}/$ENV{context}/latest\" |") or warn("ERROR: cannot execute 'dir': $!");
{ local $/; @Sources{map({/([^\\\/]+)$/;$1} split(/\n/, <DIR>))} = (undef) }
close(DIR);
open(DIR, "cmd /c dir /b \"$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1\" |") or warn("ERROR: cannot execute 'dir': $!");
{ local $/; @Destinations{map({/([^\\\/]+)$/;$1} split(/\n/, <DIR>))} = (undef) }
close(DIR);
foreach my $Log (keys(%Sources))
{
    next if(exists($Destinations{$Log}));
    copy("$ENV{HTTP_DIR}/$ENV{context}/latest/$Log", "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1/$Log") or warn("ERROR: cannot copy '$ENV{HTTP_DIR}/$ENV{context}/latest/$Log': $!");
}
printf("opendir '$ENV{HTTP_DIR}/$ENV{context}/latest' took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

@Start = Today_and_Now();
if(-f "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/properties.dat")
{
    my %Properties;
    open(DAT, "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/properties.dat") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/properties.dat': $!");
    eval <DAT>;
    close(DAT);
    foreach my $Target (qw(compile smoketest prepublishing publishing))
    {
        my @Errors = (0);
        my $Prefix = $Target eq 'compile' ? 'build' : ($Target eq 'prepublishing' ? 'export' : ($Target eq 'smoketest' ? 'smoke': $Target));
        open(LOG, ">$ENV{OUTPUT_DIR}/logs/Build/delta$Target.log") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/Build/delta$Target.log': $!");
        foreach (keys(%Properties))
        {
            my($Type, $Language) = ${$Properties{$_}}[4] =~ /^packages\/([^\/]+)\/([^\/]+)/;
            my $Id = ${$Properties{$_}}[1];
            my $Summary = "${Prefix}_${Type}_${Language}_$Id".($Target eq 'prepublishing' ? "_prepublishing" : "").".summary.txt";
            next if(-f "$ENV{OUTPUT_DIR}/logs/$ENV{context}/$Summary");
            $Summary = "${Prefix}_${Type}_${Language}_$Id".($Target eq 'prepublishing' ? "_prepublishing" : "")."=win64_x64_$ENV{BUILD_MODE}_summary_$Prefix.txt";
            next unless(-f "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1/$Summary");
            my($StepStart, $StepStop, $Errors) = (0xFFFFFFFF, 0, 0);
            open(TXT, "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1/$Summary") or warn("WARNING: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1/$Summary': $!");
            while(<TXT>)
            {
                if(my($Start) = /^== Build start:.+\((\d+)\)/) { $StepStart = $Start if($Start<$StepStart) }
                elsif(my($Stop) = /^== Build end  :.+\((\d+)\)/) { $StepStop = $Stop if($Stop>$StepStop) }
                elsif(/^\[ERROR\s+\@\d+\]/) { $Errors++ }
            }
            close(TXT);
            print(LOG "=+=Errors detected: $Errors\n");
            print(LOG "=+=Summary log file created: $ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1/$Summary\n");
            (my $Log = $Summary) =~ s/_summary//;
            $Log =~ s/.txt$/.log/;
            $Errors[0] += $Errors; 
            push(@Errors, ["$Errors", "Host_1/$Log", "Host_1/$Summary", $ENV{context}, $StepStart, $StepStop]);
        }
        close(LOG);
        next unless($Prefix eq 'build' or $Prefix eq 'export' or $Prefix eq 'smoke');
        open(DAT, ">$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=$ENV{PLATFORM}_$ENV{BUILD_MODE}_delta${Prefix}_1.dat") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=$ENV{PLATFORM}_$ENV{BUILD_MODE}_delta${Prefix}_1.dat': $!");
        print DAT Data::Dumper->Dump([\@Errors], ["*Errors"]);
        close(DAT);
    }
}
printf("create delta took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

@Start = Today_and_Now();
if($Requester ne 'Daily build')
{ 
    if(-f "$ENV{OUTPUT_DIR}/logs/Build/cms.summary.txt")
    {
        open(TXT, "$ENV{OUTPUT_DIR}/logs/Build/cms.summary.txt") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/Build/cms.summary.txt': $!");
        while(<TXT>)
        {
           last if(($CodeSourceDate) = /^== Build start:.+\((\d+)\)/); 
        }
        close(TXT);
    }
}
elsif(-f $BackupDone)
{
    open(INFO , $BackupDone) or warn("ERROR: cannot '$BackupDone': $!"); 
    while(<INFO>)
    {
        last if(($CodeSourceDate) = /gmtime=(\d+)/);
    }
    close(INFO);
}
if(-f "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Activities.txt")
{
    open(TXT, "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Activities.txt") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Activities.txt': $!");
    while(<TXT>) { if(/Impacted outputs\s*:\s*(.+)$/) { $NumberOfImpactedOutputs = $1; last } }
    close(TXT);
}
if(-d "$CMS_DIR\\content\\projects" && -d "$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files")
{
    if(exists($ENV{MY_PROJECTMAP}))  # for the compatibility
    {
        my($Manifest) = <$CMS_DIR/content/projects/*.project.mf.xml> =~ /([^\\\/]+)$/;
        copy("$CMS_DIR/content/projects/$Manifest", "$ENV{HTTP_DIR}/$Stream/$BuildName/$BuildName.project.mf.xml") or warn("ERROR: cannot copy '$CMS_DIR/content/projects/$Manifest' to '$ENV{HTTP_DIR}/$Stream/$BuildName/$BuildName.project.mf.xml': $!");
        copy("$CMS_DIR/content/projects/$Manifest", "$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/") or warn("ERROR: cannot copy '$CMS_DIR/content/projects/$Manifest' to '$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/': $!");
        copy("$ENV{DROP_DIR}/$Stream/latest.xml", "$ENV{DROP_DIR}/$Stream/done.xml") or warn("ERROR: cannot copy '$ENV{DROP_DIR}/$Stream/latest.xml' to '$ENV{DROP_DIR}/$Stream/done.xml': $!");
    }
    # compatibility
    else
    {
        my($CMSProject) = <$CMS_DIR/content/projects/*.project> =~ /([^\\\/]+)\.project$/;
        copy("$CMS_DIR/content/projects/$CMSProject.project", "$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/") or warn("ERROR: cannot copy '$CMS_DIR/content/projects/$CMSProject' to '$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/': $!");
        my $CMSProjectPhIo;
        if($CMSProject =~ /^.{32}$/)
        {
            my $DOC = XML::DOM::Parser->new()->parsefile("$CMS_DIR/content/projects/$CMSProject.properties");
            ($CMSProjectPhIo) = $DOC->getElementsByTagName('name')->item(0)->getFirstChild()->getData() =~ /(.+)\.project$/;
            $DOC->dispose();
        } else { $CMSProjectPhIo = $CMSProject }
        copy("$SRC_DIR/cms/$CMSProjectPhIo.project.mf.xml", "$ENV{HTTP_DIR}/$Stream/$BuildName/$BuildName.project.mf.xml") or warn("ERROR: cannot copy '$SRC_DIR/cms/$CMSProjectPhIo.project.mf.xml' to '$ENV{HTTP_DIR}/$Stream/$BuildName/$BuildName.project.mf.xml': $!");
        copy("$SRC_DIR/cms/$CMSProjectPhIo.project.mf.xml", "$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/") or warn("ERROR: cannot copy '$SRC_DIR/cms/$CMSProjectPhIo.project.mf.xml' to '$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/': $!");
        copy("$ENV{DROP_DIR}/$Stream/latest.xml", "$ENV{DROP_DIR}/$Stream/done.xml") or warn("ERROR: cannot copy '$ENV{DROP_DIR}/$Stream/latest.xml' to '$ENV{DROP_DIR}/$Stream/done.xml': $!");
    }
    # end compatibility
}
%Status = (start=>$StepStart, stop=>$StepStop, requester=>$Requester, textmlserver=>$TextMLServer, status=>{'ok'=>0, 'warning'=>0, 'error'=>0}, errors=>{}, channels=>{}, codesourcedate=>$CodeSourceDate, impactedoutputs=>$NumberOfImpactedOutputs);

foreach my $Target (qw(compile smoketest prepublishing publishing))
{
    next unless(-f "$ENV{OUTPUT_DIR}/logs/Build/$Target.log");
    my @Lines;
    open(LOG, "$ENV{OUTPUT_DIR}/logs/Build/$Target.log") or warn("WARNING: cannot open '$ENV{OUTPUT_DIR}/logs/Build/$Target.log': $!");
    while(<LOG>) { push(@Lines, <LOG>) }
    close(LOG);
    if(-f "$ENV{OUTPUT_DIR}/logs/Build/delta$Target.log")
    {
        open(LOG, "$ENV{OUTPUT_DIR}/logs/Build/delta$Target.log") or warn("WARNING: cannot open '$ENV{OUTPUT_DIR}/logs/Build/delta$Target.log': $!");
        while(<LOG>) { push(@Lines, <LOG>) }
        close(LOG);
    }
    my(%PublishingStatus, %PrepublishingStatus, %PublishingJobIds, %PrepublishingJobIds, %PublishingBuildNumber, %PrepublishingBuildNumber);
    foreach(@Lines)
    {
        if(/^=\+=Errors detected: (\d+)/)
        {
            my $Errors = $1;
            if($Target eq 'compile') { ${$Status{status}}{$Errors?'warning':'ok'}++ }
            elsif($Target eq 'smoketest' && $Errors) { ${$Status{status}}{ok}--; ${$Status{status}}{error}++ }
        }
        elsif(my($Summary) = /^=\+=Summary log file created: (.+\.summary\.txt|.+_summary_.+\.txt)$/)
        {
            $Status{NumberOfDocuments}++ if($Target eq 'compile');
            my($Language, $Id) = $Summary =~ /([a-z]{2}-[A-Z]{2})_([^=_\\\/]+).*\.summary\.txt/;
            ($Language, $Id) = $Summary =~ /([a-z]{2}-[A-Z]{2})_([^=_]+)/ unless($Language);
            if($Target eq 'prepublishing' || $Target eq 'publishing')
            {
                my $Name;
                open(TXT, $Summary) or warn("WARNING: cannot open '$Summary': $!");
                while(<TXT>)
                {
                    next unless(my($Name)=/^\[ERROR\s+\@\d+\]\s*ERROR:\s*==([^=]+)==/);
                    if($Target eq 'prepublishing') { ${${$PrepublishingStatus{$Id}}{$Name}}{$Language}='fail' }
                    else { ${${$PublishingStatus{$Id}}{$Name}}{$Language}='fail' }
                }
                close(TXT);
                (my $Log = $Summary) =~ s/[._]summary([._])/$1/;
                $Log =~ s/\.txt/.log/;
                open(LOG, $Log) or warn("WARNING: cannot open '$Log': $!");
                while(<LOG>)
                {
                    my($Name, $URL, $JobId, $BuildNumber);
                    if(($Name, $URL, $JobId)=/^\[INFO]\s*==([^=]+)==\s+==([^=]+)==\s*Job id is (.+)$/)
                    {
                        if($Target eq 'prepublishing') { ${${${$PrepublishingJobIds{$Id}}{$Name}}{$Language}}{$URL} = $JobId }
                        else { ${${${$PublishingJobIds{$Id}}{$Name}}{$Language}}{$URL} = $JobId }
                    }
                    elsif(($Name, $BuildNumber)=/^\[INFO]\s*==([^=]+)==\s*Build number is (\d+)$/)
                    {
                        if($Target eq 'prepublishing') { ${${$PrepublishingBuildNumber{$Id}}{$Name}}{$Language} = $BuildNumber }
                        else { ${${$PublishingBuildNumber{$Id}}{$Name}}{$Language} = $BuildNumber }
                    }
                }
                close(LOG);
            }
            else
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
                    my $Trgt = $Target eq 'compile' ? 'build' : 'smoke';
                    ${${${$Status{errors}}{build}}{$Trgt}}{$Level}++;
                    ${${${${${$Status{errors}}{documents}}{$Trgt}}{$Id}}{$Language}}{$Level}++;
                }
                close(TXT);
            }
        }
    }
    if($Target eq 'prepublishing' || $Target eq 'publishing')
    {
        if(-f "$ENV{OUTPUT_DIR}/obj/DeliveryChannels.dat")
        {
            open(DAT, "$ENV{OUTPUT_DIR}/obj/DeliveryChannels.dat") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/obj/DeliveryChannels.dat': $!");
            eval <DAT>;
            close(DAT);
            foreach my $PhIO2 (keys(%DeliveryChannels))
            {
                foreach my $rhOutput (@{$DeliveryChannels{$PhIO2}})
                {
                    my($PhIO, $TransType, $Lg, $Nm, $Type, $Status, $URL, $IsCandidate) = @{$rhOutput}{qw(phio transtype language name type status url candidate)};
                    my $Line = "$PhIO2,$PhIO,$TransType,$Lg,$Nm,$Type,$Status,$URL,$IsCandidate";
                    next if(exists($Channels{$Line}));
                    $Channels{$Line} = undef;
                    my($JobId);
                    if($Target eq 'prepublishing' && ($Type eq 'pre-publishing' || $Type eq 'prepublishing'))
                    {
                        $Status = ((exists($PrepublishingStatus{$PhIO2}) && exists(${$PrepublishingStatus{$PhIO2}}{$Nm}) && exists(${${$PrepublishingStatus{$PhIO2}}{$Nm}}{$Lg})) ? 'fail' : 'succeed') if($Status ne 'disabled');
                        $JobId = (exists($PrepublishingJobIds{$PhIO2}) && exists(${$PrepublishingJobIds{$PhIO2}}{$Nm}) && exists(${${$PrepublishingJobIds{$PhIO2}}{$Nm}}{$Lg}) && exists(${${${$PrepublishingJobIds{$PhIO2}}{$Nm}}{$Lg}}{$URL})) ? ${${${$PrepublishingJobIds{$PhIO2}}{$Nm}}{$Lg}}{$URL} : '';
                        $BuildNumber = (exists($PrepublishingBuildNumber{$PhIO2}) && exists(${$PrepublishingBuildNumber{$PhIO2}}{$Nm}) && exists(${${$PrepublishingBuildNumber{$PhIO2}}{$Nm}}{$Lg})) ? ${${$PrepublishingBuildNumber{$PhIO2}}{$Nm}}{$Lg} : '';
                    }
                    elsif($Target eq 'publishing' && $Type eq 'publishing') 
                    { 
                        $Status = $IsCandidate ? ((exists($PublishingStatus{$PhIO2}) && exists(${$PublishingStatus{$PhIO2}}{$Nm}))?'fail':'succeed'):$Status;
                        $JobId = (exists($PublishingJobIds{$PhIO2}) && exists(${$PublishingJobIds{$PhIO2}}{$Nm}) && exists(${${$PublishingJobIds{$PhIO2}}{$Nm}}{$Lg}) && exists(${${${$PublishingJobIds{$PhIO2}}{$Nm}}{$Lg}}{$URL})) ? ${${${$PublishingJobIds{$PhIO2}}{$Nm}}{$Lg}}{$URL} : '';
                        $BuildNumber = (exists($PublishingBuildNumber{$PhIO2}) && exists(${$PublishingBuildNumber{$PhIO2}}{$Nm}) && exists(${${$PublishingBuildNumber{$PhIO2}}{$Nm}}{$Lg})) ? ${${$PublishingBuildNumber{$PhIO2}}{$Nm}}{$Lg} : '';
                    }
                    push(@{${${${$Status{channels}}{$PhIO2}}{$TransType}}{$Lg}}, {name=>$Nm, type=>$Type, status=>$Status, url=>$URL, job_id=>$JobId, build_number=>$BuildNumber});
                }
            }
        } 
    }
}
$Status{stop} = $StepStop = time();

open(DAT, ">$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=$ENV{PLATFORM}_$ENV{BUILD_MODE}_outputstatus_1.dat") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=$ENV{PLATFORM}_$ENV{BUILD_MODE}_outputstatus_1.dat': $!");
print DAT Data::Dumper->Dump([\%Status], ["*Status"]);
close(DAT);

if(exists($ENV{MY_PROJECTMAP}))
{
    if($ENV{Q_P_BUILDMODE} ne 'releasedebug' or $ENV{BUILD_MODE} ne 'debug')
    {
        open(LOG, "$ENV{OUTPUT_DIR}/logs/Build/cms.log") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/Build/cms.log': $!");
        while(<LOG>)
        {
            next unless(/FULL FETCH/);
            open(DAT, ">$ENV{HTTP_DIR}/$ENV{context}/FullBuild.dat") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/FullBuild.dat': $!");
            print(DAT "\$Start=$StepStart;\n");
            print(DAT "\$Stop=$StepStop;\n");
            close(DAT);
            last;
        }
        close(LOG);
    }
}
else
{
    open(DAT, ">$ENV{HTTP_DIR}/$ENV{context}/FullBuild.dat") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/FullBuild.dat': $!");
    print(DAT "\$Start=$StepStart;\n");
    print(DAT "\$Stop=$StepStop;\n");
    close(DAT);
}
printf("finalize took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);
