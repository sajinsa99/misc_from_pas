##!/usr/bin/perl -w

use Sys::Hostname;
use File::Compare;
use File::Path;
use File::Copy;
use Net::SMTP;
use XML::DOM;
use JSON;

use FindBin;
use lib ($FindBin::Bin, 'C:\IxiaSoft\TextmlServer43\AdminScripts\Perl', 'C:\IxiaSoft\TextmlServer43\AdminScripts\Perl\5.16');
$ENV{PW_DIR} ||= (($^O eq "MSWin32") ? '\\\\build-drops-wdf\dropzone\documentation\.pegasus' : '/net/build-drops-wdf/dropzone/documentation/.pegasus');
require  Perforce;
use CommonSubs;
$ENV{PROJECT} = 'documentation';
require Site;

$ENV{SMTP_SERVER} ||= "mail.sap.corp";
$SMTPFROM = $SMTPTO = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
$SMTPTO = 'jean.maqueda@sap.com;nathalie.magnier@sap.com;joerg.stiehl@sap.com;samuel.mendoza@sap.com';
$NumberOfEmails = 0;
$HOST = hostname();
$SIG{__DIE__} = sub { SendMail(@_); die(@_) };
$SIG{__WARN__} = sub { SendMail(@_); warn(@_) };

##############
# Parameters #
##############

die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
($TEMP_DIR .= '/textmlserver') =~ s/[\\\/]\d+$//;

$CURRENT_DIR = $FindBin::Bin;
$PRODPASSACCESS_DIR = $ENV{PRODPASSACCESS_DIR} || "$CURRENT_DIR/prodpassaccess";
$CREDENTIAL = "$ENV{PW_DIR}/.credentials.properties";
$MASTER = "$ENV{PW_DIR}/.master.xml";
$Password = `$PRODPASSACCESS_DIR/bin/prodpassaccess --credentials-file $CREDENTIAL --master-file $MASTER get CMS-UTILS password`; chomp($Password);
$User = `$PRODPASSACCESS_DIR/bin/prodpassaccess --credentials-file $CREDENTIAL --master-file $MASTER get CMS-UTILS user`; chomp($User);

# @Severs = [ServerName, Port, DocBaseName, UserName]
push(@Servers, [('automatedtest.wdf.sap.corp', '2501', 'subdita-all', "global.corp.sap\\$User")]);
#push(@Servers, [('dewdftf07016.wdf.sap.corp', '2501', 'new-subdita-all', "global.corp.sap\\$User")]);
push(@Servers, [("ditatesttextml.wdf.sap.corp", "2501", "test-dita-all", "global.corp.sap\\$User")]);
push(@Servers, [("dewdfth13020.wdf.sap.corp", "2500", "sandbox2", "global.corp.sap\\$User")]);
push(@Servers, [("ditaalltextml.wdf.sap.corp", "2501", "dita", "global.corp.sap\\$User")]);
$MAX_NUMBER_OF_STANDALONE = 60;
$SANDBOX2_HOST = 'dewdfth1248b';
$TEST_DITA_HOST = 'dewdfth1248a';
$FEAT_DITA_HOST = 'dewdfth1248a';
$AT_DITA_HOST = 'dewdfth1248c';
@ExcludeOfLoadBalancingHosts{$SANDBOX2_HOST, $TEST_DITA_HOST, $FEAT_DITA_HOST, $AT_DITA_HOST, 'pwdf3311'} = (undef);
$BUILD_DIR = $ENV{BUILD_DIR} || 'C:\Build\shared';
$CIS_DIR = $ENV{CIS_DIR} || 'C:\cis\cgi-bin';
$HTTP_DIR = $ENV{HTTP_DIR};
$AVERAGE_SIZE = 10; # Average build size (Go)
$AVERAGE_DURATION = 1*60*60; # Average build duration (s)
$MAX_CYCLE_DURATION = 6*60*60;
$MAX_FULL_DURATION = 60*60*60; # Max full duration of a build to exclude the host

########
# Main #
########

($Query = <<QUERY) =~ s/\n//gm;
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE query PUBLIC "-//IXIA//DITA CMS QUERY" "cms_query.dtd">
<query RESULTSPACE="AllProjects" VERSION="4.2">
    <orkey>
        <andkey>
            <property NAME="collection">
                <elem>/content/authoring/<anystr/></elem>
            </property>
            <key NAME="objectType">
                <elem>project-map</elem>
            </key>
        </andkey>
        <property NAME="collection">
            <or>
                <elem>/content/projects/<anystr/></elem>
                <elem>/deleted/content/projects/<anystr/></elem>
            </or>
        </property>
    </orkey>
</query>
QUERY

# %Hosts{$Host} = [{Drive}=[$NumberOfBuilds,size,free], $CPU, $Clock, $RAM, $NumberOfBuilds, $Load, $Free, $Size]
$Coo = "$CURRENT_DIR/events-documentation.coo";
system("p4 print -o $Coo //depot2/Main/Stable/Build/shared/events-documentation.coo"); 
open(COO, $Coo) or die("ERROR: cannot open '$Coo': $!");
while(<COO>)
{
    next unless(my($Hosts) = /group_member\s*=\s*([^;]+)/);
    $Hosts =~ s/\s//g;
    @Hosts{split(',', lc($Hosts))} = (undef);
    last;
}
close(COO);
die("ERROR: cannot find hosts in $Coo") unless(keys(%Hosts));
$DitaHardware = "$CURRENT_DIR/ditahardware/DITAHardware.xml";
system("p4 print -o $DitaHardware //internal/core.build.tools/1.0/REL/export/shared/ditahardware/DITAHardware.xml"); 
eval {
    my $HW = XML::DOM::Parser->new()->parsefile($DitaHardware);
    for my $SYSTEM (@{$HW->getElementsByTagName('system')})
    {
        (my $Host = lc($SYSTEM->getAttribute('name'))) =~ s/\.[^\.]+\.sap\.corp$//;
        next unless(exists($Hosts{$Host}));
        $Hosts{$Host} = [undef, $SYSTEM->getElementsByTagName('cpu')->item(0)->getFirstChild()->getData(),  $SYSTEM->getElementsByTagName('clock')->item(0)->getFirstChild()->getData(), $SYSTEM->getElementsByTagName('ram')->item(0)->getFirstChild()->getData(), 0, 0, 0];
        map({${${$Hosts{$Host}}[0]}{$_} = [0, undef, undef]} split(',', $SYSTEM->getElementsByTagName('driverunningbuild')->item(0)->getFirstChild()->getData()));
        for my $DRIVE (@{$SYSTEM->getElementsByTagName('drive')})
        {
            my($Letter, $Size, $Free) = ($DRIVE->getAttribute('letter'), $DRIVE->getAttribute('size'), $DRIVE->getAttribute('free'));
            ($Letter) = $Letter =~ /^([A-Z])/i;
            next unless(exists(${${$Hosts{$Host}}[0]}{$Letter}));
            ${$Hosts{$Host}}[5] = 0;
            ${$Hosts{$Host}}[6] += $Free;
            ${$Hosts{$Host}}[7] += $Size;
            @{${${$Hosts{$Host}}[0]}{$Letter}}[1,2] = ($Size, $Free);
        }
        if(-f "$HTTP_DIR/JobViewer/Cycles/00.00/$Host/History.dat")
        {
            my(@History, @Statistics);
            open(DAT, "$HTTP_DIR/JobViewer/Cycles/00.00/$Host/History.dat") or warn("ERROR: cannot open '$HTTP_DIR/JobViewer/Cycles/00.00/$Host/History.dat': $!");
            { local $/; eval <DAT> }
            close(DAT);
            ${$Hosts{$Host}}[5] = $Statistics[0];
        }
    }
    $HW->dispose();
};
die("ERROR: cannot find hardware in '$DitaHardware': $@") if($@);
map({ die("ERROR: cannot find project '$_' in '$DitaHardware'") unless(${$Hosts{$_}}[0])} keys(%Hosts));

# %Projects{Project} = [Title, Host, Drive, Mode, Server, DocBase, $Port, [DependencyProject], $NumberOfOutputs, $IsExcluded]
for(@Servers)
{
    my($Server, $Port, $DocBase, $User) = @{$_};
    if($DocBase eq 'dita' or $DocBase eq 'new-subdita-all')
    {
        my $DitaContainerDir = $ENV{DITA_CONTAINER_DIR};
        $DitaContainerDir .= '/AT' if($DocBase eq 'new-subdita-all');
        # %PDC{projects} = order
        my(@PDC, @NewPDC);
        unless(open(DAT, "$DitaContainerDir/content/projects/PDC.dat"))
        {
            die("ERROR: cannot open '$DitaContainerDir/content/projects/PDC.dat': $!") if($DocBase eq 'new-subdita-all');
            warn("ERROR: cannot open '$DitaContainerDir/content/projects/PDC.dat': $!");
            next;
        }
        { local $/; eval(<DAT>) }
        close(DAT);
        foreach my $raPDC (@PDC)
        {
            my %Prjcts;
            my $Order = 0;
            foreach (@{$raPDC})
            {
                my($Project, $Status) = @{$_};
                next unless($Status eq 'Project:active' or $Status eq 'Project:active-translation');
                $Prjcts{$Project} = $Order++; 
            }
            push(@NewPDC, \%Prjcts) if(keys(%Prjcts));
        }
        @PDC = @NewPDC;
        foreach my $rhPDC (@PDC)
        {
            foreach my $Project (keys(%{$rhPDC}))
            {
                my $Title;
                eval
                {
                    my $XML = XML::DOM::Parser->new()->parsefile("$DitaContainerDir/content/projects/$Project.project");
                    $Title = $XML->getElementsByTagName('title')->item(0)->getFirstChild()->getData();
                    $XML->dispose();
                }; 
                if($@) { warn("ERROR: cannot find title in '$DitaContainerDir/content/projects/$Project.project': $@"); next }
                my(@Modes, $NumberOfOutputs);
                open(STAT, "$DitaContainerDir/content/projects/$Project.stat") or warn("ERROR: cannot open '$DitaContainerDir/content/projects/$Project.stat': $!");
                while(<STAT>)
                {
                    if(my($Mode)=/_buildmode=(.+)$/) { push(@Modes, $Mode) }
                    elsif(/^daily_00\s*=\s*(\d+)/) { $NumberOfOutputs = $1 }
                }
                close(STAT);
                unless(@Modes) { warn("ERROR: cannot find build cycles in '$DitaContainerDir/content/projects/$Project.stat': $!") ; next }
                my $Mode = (grep({/^releasedebug$/} @Modes) or (grep({/^release$/} @Modes) and grep({/^debug$/} @Modes))) ? 'releasedebug' : (grep({/^release$/} @Modes) ? 'release' : 'debug'); 
                $Projects{$Project} = [$Title, undef, undef, $Mode, $Server, $DocBase, $Port, $rhPDC, $NumberOfOutputs, 0];
            }
        }
    }
    else
    {
        rmtree($TEMP_DIR) or warn("ERROR: cannot rmtree '$TEMP_DIR': $!") if(-e $TEMP_DIR);
        mkpath($TEMP_DIR) or warn("ERROR: cannot mkpath '$TEMP_DIR': $!") unless(-e $TEMP_DIR);

        my($CMSServer, $LoginAttendant);
        eval { ($CMSServer, $LoginAttendant) = CommonSubs::ConnectToServer("$Server:$Port", $User, $Password) };
        if($@) { warn("ERROR: $@"); next }
        my $CMSDocBase = CommonSubs::ConnectToDocbase($CMSServer, $DocBase);

        ($Ret, $ErrorLog, $ResSpace) = CommonSubs::CreateResultSpaceFromXML($Query, $CMSDocBase);
        CommonSubs::DisplayLog(__PACKAGE__, $ErrorLog, $Ret, "Cannot create result space with file $Query on document base $DocBaseName on server $Server.\n", CommonSubs::W_OFF);
        die unless($Ret==0);
        $Files = new textml43::vectordoc;
        ($Ret, $ErrorLog) = $CMSDocBase->GetDocuments($ResSpace, , 0, $ResSpace->GetCount(), CommonSubs::TEXTML_DOCUMENT_CONTENT + CommonSubs::TEXTML_DOCUMENT_CUSTOMPROPERTIES, $Files);
        CommonSubs::DisplayLog(__PACKAGE__, $ErrorLog, $Ret, "cannot get documents on document base $DocBaseName on server $Server.\n", CommonSubs::W_OFF);

        for(my $i=0; $i<$Files->size(); $i++)
        {
            (my $File = new textml43::Document) = $Files->get($i);
            ($Ret, $ErrorLog) = CommonSubs::SaveDocumentOnDisk($TEMP_DIR, $File, $File->Collection(), $File->Name(), CommonSubs::W_OFF, CommonSubs::W_ON);
            CommonSubs::DisplayLog(__PACKAGE__, $ErrorLog, $Ret, "Cannot save the document of document base $DocBaseName on server $Server.\n", CommonSubs::W_OFF);
        }
        $XMLParser = new XML::Parser(Style => 'Tree');
        for(my $i=0; $i<$Files->size(); $i++)
        {
            (my $Project = new textml43::Document) = $Files->get($i);
            next unless($Project->Name() =~ /\.project$/);
            (my $PhIO = $Project->Name()) =~ s/\.project$//;
            my($Status, $Title, @Deliverables);
            if($Project->Collection() eq '/deleted/content/projects/') { $Status = 'todelete' }
            else
            {
                my $CUSTOMPROPERTIES = $XMLParser->parsefile("$TEMP_DIR".$Project->Collection()."$PhIO.project.customproperties");
                for(my $i=0; $i<@{${$CUSTOMPROPERTIES}[1]}; $i++)
                {
                    if(${${$CUSTOMPROPERTIES}[1]}[$i] =~ /status/) { $Status = ${${${$CUSTOMPROPERTIES}[1]}[$i+1]}[2]; last }
                }
            }
            unless($Status) { warn("ERROR: status not found in '$TEMP_DIR".$Project->Collection()."$PhIO.project.customproperties'"); next }
            next unless($Status eq 'Project:active' or $Status eq 'Project:active-translation');
            my $PROJECT = $XMLParser->parsefile("$TEMP_DIR".$Project->Collection().$Project->Name());
            for(my $i=0; $i<@{${$PROJECT}[1]}; $i++)
            {
                if(${${$PROJECT}[1]}[$i] =~ /title/) { $Title = ${${${$PROJECT}[1]}[$i+1]}[2]; last }
            }
            unless($Title) { warn("ERROR: title not found in '$TEMP_DIR".$Project->Collection().$Project->Name()); next }
            for(my $i=0; $i<@{${$PROJECT}[1]}; $i++)
            {
                if(${${$PROJECT}[1]}[$i] =~ /projectbody/)
                {
                    my $PROJECTBODY = ${${$PROJECT}[1]}[$i+1];
                    for(my $j=0; $j<@{$PROJECTBODY}; $j++)
                    {
                        if(${$PROJECTBODY}[$j] =~ /deliverables/)
                        {
                            my $DELIVERABLES = ${$PROJECTBODY}[$j+1];
                            for(my $k=0; $k<@{$DELIVERABLES}; $k++)
                            {
                                if(${$DELIVERABLES}[$k] =~ /deliverable/)
                                {
                                    my $DELIVERABLE = ${$DELIVERABLES}[$k+1];
                                    for(my $l=0; $l<@{$DELIVERABLE}; $l++)
                                    {
                                        if(${$DELIVERABLE}[$l] =~ /fullpath/) { push(@Deliverables, ${${$DELIVERABLE}[$l+1]}[2]); }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if(@Deliverables)
            {
                my $rhBuildCycles;
                foreach my $Deliverable (@Deliverables)
                {
                    next unless(-e "$TEMP_DIR$Deliverable");
                    my $DOCUMENT = XML::DOM::Parser->new()->parsefile("$TEMP_DIR$Deliverable");
                    my $DocType = $DOCUMENT->getDoctype()->getNodeName();
                    if($DocType eq 'project-map')
                    {
                        if($DOCUMENT->getElementsByTagName('output')->getLength()>0)
                        {
                            system("$CURRENT_DIR/buildconfigurator/buildconfigurator --buildType true --buildTypeFile $TEMP_DIR/jsonFile.json --projectmap $TEMP_DIR$Deliverable > nul");
                            local $/;
                            open(JSON, "$TEMP_DIR/jsonFile.json") or die("ERROR: cannot open '$TEMP_DIR/jsonFile.json': $!");
                            $rhBuildCycles = from_json(<JSON>);
                            close(JSON);
                        }
                    }
                    $DOCUMENT->dispose();
                }
                ${$rhBuildCycles}{DAILY_00} = ['PRODUCTION'] unless($rhBuildCycles && keys(%{$rhBuildCycles}));
                my $BuildMode = 'release';
                foreach my $BuildCycle (keys(%{$rhBuildCycles}))
                {
                    foreach my $Mode (@{${$rhBuildCycles}{$BuildCycle}})
                    {
                        if(($BuildMode eq 'debug' and $Mode eq 'PRODUCTION') or ($BuildMode eq 'release' and $Mode eq 'DRAFT')) { $BuildMode = 'releasedebug'; last }
                        $BuildMode = ($Mode eq 'DRAFT') ? 'debug' : 'release';
                    }
                }
                $Projects{$PhIO} = [$Title, undef, undef, lc($BuildMode), $Server, $DocBase, $Port, undef, undef, 0];
            }
        }
        #CommonSubs::Logout($LoginAttendant, "$Server:$Port");
    }
}

$p4 = new Perforce;
$JobFile = "$BUILD_DIR/jobs/documentation.txt";
$p4->sync('-f', $JobFile);
warn("ERROR: cannot sync '$JobFile': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);   
open(IN, '<:utf8', $JobFile) or die("ERROR: cannot open '$JobFile': $!");
while(<IN>)
{
    next unless(my($Title, $IsExcluded) = /;Title=(.+)\s+\([^\s]+\)\s*(\S*)/);
    $IsExcluded = ($IsExcluded and $IsExcluded=~/yes/i) ? 1 : 0;
    my $Line = <IN>;
    my($Host) = $Line =~ /^s*\[([^.]+)/;
    die("ERROR: malformated line '$Line' in '$JobFile'") unless($Host);
    $Line = <IN>;
    my($Project, $Server, $Port, $DocBase, $Drive, $Mode) = $Line =~ /BuildDoc\.bat\s+(\S+)\s+(\S+):(\d+)\/(\S+)\s+([A-Z])\s+(\S+)/;
    die("ERROR: malformated line '$Line' in '$JobFile'") unless($Project and $Server and $Port and $DocBase and $Drive and $Mode);
    ${$Hosts{$Host}}[4]++;
    ${${${$Hosts{$Host}}[0]}{$Drive}}[0]++;
    $JobProjects{$Project} = [$Title, $Host, $Drive, $Mode, $Server, $DocBase, $Port, undef];
    if(exists($Projects{$Project}))
    {
        ${$Projects{$Project}}[1] = $Host;
        ${$Projects{$Project}}[2] = $Drive;
        ${$Projects{$Project}}[9] = $IsExcluded;
    }
    push(@Projects, $Project);
    my $FullDuration = 0;
    if(-f "$HTTP_DIR/$Project/FullBuild.dat")
    {
        my($Start, $Stop);
        open(DAT, "$HTTP_DIR/$Project/FullBuild.dat") or warn("ERROR: cannot open '$HTTP_DIR/$Project/FullBuild.dat': $!");
        { local $/; eval <DAT> }
        close(DAT);
        $FullDuration = $Stop-$Start if($Start and $Stop);
    }
    elsif(-f "$ENV{DROP_DIR}/$Project/version.txt")
    {
        open(VER, "$ENV{DROP_DIR}/$Project/version.txt") or warn("ERROR: cannot open '$ENV{DROP_DIR}/$Project/version.txt': $!");
        my $Revision = int(<VER>);
        close(VER);
        warn("ERROR: $HTTP_DIR/$Project/FullBuild.dat not found") if($Revision > 1);
    }
    print("$Host excluded because a full build is too long : $FullDuration > $MAX_FULL_DURATION\n") if($FullDuration > $MAX_FULL_DURATION);
    $ExcludeOfLoadBalancingHosts{$Host} = undef if($FullDuration > $MAX_FULL_DURATION);
}
close(IN);
    
$UpdateJob = 0;
foreach my $Project (keys(%Projects))
{
    next if(exists($JobProjects{$Project}));
    my $Host = NextHost($Project);
    my $Drive = NextDrive($Host, $Project);
    my($Title, $DocBase) = @{$Projects{$Project}}[0,5]; 
    print("[INFO] TO ADD : project '$Project' ($Title) from '$DocBase' in '$Host' drive $Drive.\n");
    $UpdateJob = 1;
    $DAMAdd{$Project} = [$Title, $DocBase];
}

foreach my $JobProject (keys(%JobProjects))
{
    my($JobTitle, $JobHost, $JobDrive, $JobMode, $JobServer, $JobDocBase, $JobPort) = @{$JobProjects{$JobProject}}[0..6];
    if(exists($Projects{$JobProject}))
    {
        NextDrive(NextHost($JobProject), $JobProject);
        my($Title, $Host, $Drive, $Mode, $Server, $DocBase, $Port) = @{$Projects{$JobProject}}[0..6];
        if($JobTitle ne $Title)
        {
            print("[INFO] TO CHANGE: The project '$JobProject' ($JobTitle) changed it title from '$JobTitle' to '$Title'.\n");
            $UpdateJob = 1;
            $DAMChanges{$JobProject} = [$Title, $DocBase];
        }
        if($JobDocBase ne $DocBase)
        {
            print("[INFO] TO CHANGE: The project '$JobProject' ($JobTitle) changed it docbase from '$JobDocBase' to '$DocBase'.\n");
            $UpdateJob = 1;
            $DAMChanges{$JobProject} = [$Title, $DocBase];
        }
        if($JobHost ne $Host)
        {
            print("[INFO] TO CHANGE: The project '$JobProject' ($JobTitle) changed it host from '$JobHost' to '$Host'.\n");
            $UpdateJob = 1;
        }
        if($JobDrive ne $Drive)
        {
            print("[INFO] TO CHANGE: The project '$JobProject' ($JobTitle) changed it drive from '$JobDrive' to '$Drive'.\n");
            $UpdateJob = 1;
        }
        if($JobMode ne $Mode)
        {
            print("[INFO] TO CHANGE: The project '$JobProject' ($JobTitle) changed it mode from '$JobMode' to '$Mode'.\n");
            $UpdateJob = 1;
        }
        if($JobServer ne $Server)
        {
            print("[INFO] TO CHANGE: The project '$JobProject' ($JobTitle) changed it CMS server from '$JobServer' to '$Server'.\n");
            $UpdateJob = 1;
        }
        if($JobPort ne $Port)
        {
            print("[INFO] TO CHANGE: The project '$JobProject' ($JobTitle) changed it CMS port from '$JobPort' to '$Port'.\n");
            $UpdateJob = 1;
        }
    }
    else
    {
        print("[INFO] TO DELETE: The project '$JobProject' ($JobTitle) is not active in '$ENV{DITA_CONTAINER_DIR}/content/projects/PDC.dat'.\n");
        $UpdateJob = 1;
        $DAMDel{$JobProject} = undef;
    }
}

open(JOB, '>:utf8', "$TEMP_DIR/$$.temp") or die("ERROR: cannot open '$TEMP_DIR/$$.temp': $!");
print(JOB "[config]\n");
print(JOB  "    event_dir = documentation\n\n");
print(JOB "; machine.project.context.platform.mode.type.product\n\n");
foreach my $Project (sort({${$Projects{$a}}[1] cmp ${$Projects{$b}}[1] or ${$Projects{$a}}[0] cmp ${$Projects{$b}}[0] } keys(%Projects)))
{
    my($Title, $Host, $Drive, $Mode, $Server, $DocBase, $Port, $rhPDC, $NumberOfOutputs, $IsExcluded) = @{$Projects{$Project}};
    print(JOB ";Title=$Title ($Project)", $IsExcluded ? ' exclude=yes' : '', "\n");
    print(JOB "[$Host.documentation.$Project.win64_x64.config.compile.all]\n");
    print(JOB "    command = cmd /c ( C:\\Builds\\BuildDoc.bat $Project $Server:$Port/$DocBase $Drive $Mode )\n\n");
}
close(JOB);
P4Submit($JobFile, "$TEMP_DIR/$$.temp");

if(%DAMAdd or %DAMDel or %DAMChanges)
{
    $p4->sync('-f', "$CIS_DIR\\DAM.pm");
    die("ERROR: cannot sync '$CIS_DIR\\DAM.pm': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);
    open(IN, "$CIS_DIR\\DAM.pm") or die("ERROR: cannot open '$CIS_DIR\\DAM.pm': $!");
    my @Lines = <IN>;
    close(IN);
    my $i;
    for($i=0; $i<@Lines; $i++)
    {
        if(grep({$Lines[$i]=~/$_/} (keys(%DAMDel), keys(%DAMChanges)))) { $Lines[$i]=undef; next }
        last if($Lines[$i]=~/#>>>INSERT PROJECT BEFORE HERE<<</);
    }
    my @NewLines;
    foreach my $Project (keys(%DAMAdd), keys(%DAMChanges))
    {
        my($Title, $DocBaseName) = exists($DAMAdd{$Project}) ? @{$DAMAdd{$Project}} : @{$DAMChanges{$Project}};
        
        $Title =~ s/'/\\'/g;
        $DocBaseName =~ s/test-dita-all/test-dita/;
        $DocBaseName =~ s/feat-dita-all/feat-dita/;
        $DocBaseName =~ s/new-subdita-all/subdita/;
        $DocBaseName =~ s/subdita-all/subdita/;
        push(@NewLines, "\$PROJECTS{documentation}\{$Project\} = ['$Title','$DocBaseName'];\n");   
    }
    splice(@Lines, $i, 0, @NewLines) if(@NewLines);
    @Lines = grep({defined($_)} @Lines);
    my %Lines;
    open(OUT, '>:utf8', "$TEMP_DIR/$$.temp") or die("ERROR: cannot open '$TEMP_DIR/$$.temp': $!");
    foreach (@Lines) { print OUT if not $Lines{$_}++ }
    close(OUT);
    P4Submit("$CIS_DIR\\DAM.pm", "$TEMP_DIR/$$.temp");
}

# Check Integrity
$p4->sync('-f', $JobFile);
warn("ERROR: cannot sync '$JobFile': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);   
open(IN, $JobFile) or die("ERROR: cannot open '$JobFile': $!");
@Lines = <IN>;
close(IN);
%JobProjects = ();
for(my $i=0; $i<@Lines; $i++)
{
    next unless(my($JobTitle) = $Lines[$i] =~ /;Title=(.+)\s\(/);
    my($JobHost) = $Lines[$i+1] =~ /^s*\[([^.]+)/;
    die("ERROR: malformated line '$Lines[$i+1]' in '$JobFile'") unless($JobHost);
    my($JobProject, $JobTextML, $JobDrive, $JobMode) = $Lines[$i+2] =~ /BuildDoc\.bat\s+(\S+)\s+(\S+)\s+([A-Z])\s+(\S+)/;
    unless($JobProject and $JobTextML and $JobDrive and $JobMode) { warn("ERROR: malformated line '$Lines[$i+2]' in '$JobFile'"); next }
    warn("ERROR: project $JobProject in $JobFile is duplicate") if(exists($JobProjects{$JobProject}));
    $JobProjects{$JobProject} = undef;
}
$p4->sync('-f', "$CIS_DIR\\DAM.pm");
die("ERROR: cannot sync '$CIS_DIR\\DAM.pm': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);
open(IN, "$CIS_DIR\\DAM.pm") or die("ERROR: cannot open '$CIS_DIR\\DAM.pm': $!");
$LineNumber = 0;
while(<IN>)
{
    $LineNumber++;
    if(my($Project, $Title, $DocBase) = /\$PROJECTS\s*{\s*documentation\s*}{\s*(.*?)\s*}\s*=\s*\[\s*'(.*?)'\s*,\s*'(.+?)'\s*\]/)
    {
        warn("ERROR: [$LineNumber] project '$Project' ($Title) in $HTTP_DIR\\DAM.pm not found in the job file") if($Project !~ /^dita_output/ && !exists($JobProjects{$Project}) && ($DocBase eq 'dita' || $DocBase eq 'sandbox2' || $DocBase eq 'test-dita-all' || $DocBase eq 'feat-dita-all' || $DocBase eq 'new-subdita-all'));
        print(STDERR "ERROR: [$LineNumber] project '$Project' ($Title) in $HTTP_DIR\\DAM.pm is duplicate\n") if(exists($DAMProjects{$Project}));
        $DAMProjects{$Project} = undef;
    }
}
close(IN);
foreach my $Project (keys(%JobProjects)) { warn("[WARNING] project '$Project' not found in '$CIS_DIR\\DAM.pm'") unless(exists($DAMProjects{$Project})) }

END { $p4->Final() if($p4) }

#############
# Functions #
#############

sub NextHost {
    my($Project) = @_;

    my($Host, $DocBaseName, $rhPDC, $IsExcluded) = @{$Projects{$Project}}[1,5,7,9];
    return $Host if($Host);

    if($DocBaseName eq 'sandbox2') { return ${$Projects{$Project}}[1] = $SANDBOX2_HOST }
    if($DocBaseName eq 'test-dita-all') { return ${$Projects{$Project}}[1] = $TEST_DITA_HOST }
    if($DocBaseName eq 'feat-dita-all') { return ${$Projects{$Project}}[1] = $FEAT_DITA_HOST }
    if($DocBaseName eq 'new-subdita-all' or $DocBaseName eq 'subdita-all') { return ${$Projects{$Project}}[1] = $AT_DITA_HOST }

    # %Projects{Project} = [Title, Host, Drive, Mode, Server, DocBase, $Port, [DependencyProject], $NumberOfOutputs, $IsExcluded]
    # %Hosts{$Host} = [{Drive}=[$NumberOfBuilds,size,free], cpu, clock, ram, $NumberOfBuilds, $Load, $Free, $Size]

    print("I: Free, Load, Size, CPU\n");
    my @Hosts = grep({!exists($ExcludeOfLoadBalancingHosts{$_}) and ${$Hosts{$_}}[6]>=$AVERAGE_SIZE and ${$Hosts{$_}}[5]<=($MAX_CYCLE_DURATION-$AVERAGE_DURATION) and ((${$Projects{$Project}}[8]>=1000 and ${$Hosts{$_}}[1]>24) or (${$Projects{$Project}}[8]<1000 and ${$Hosts{$_}}[1]<=24))} keys(%Hosts));
    print("II: Free, Load\n") unless(@Hosts);
    @Hosts = grep({!exists($ExcludeOfLoadBalancingHosts{$_}) and ${$Hosts{$_}}[6]>=$AVERAGE_SIZE and ${$Hosts{$_}}[5]<=($MAX_CYCLE_DURATION-$AVERAGE_DURATION) } keys(%Hosts)) unless(@Hosts);
    print("III: Free\n") unless(@Hosts);
    @Hosts = grep({!exists($ExcludeOfLoadBalancingHosts{$_}) and ${$Hosts{$_}}[6]>=$AVERAGE_SIZE } keys(%Hosts)) unless(@Hosts);
    print("IV:\n") unless(@Hosts);
    @Hosts = grep({!exists($ExcludeOfLoadBalancingHosts{$_})} keys(%Hosts)) unless(@Hosts);
    my $Host = (sort({${$Hosts{$b}}[5]<=>${$Hosts{$a}}[5]} @Hosts))[0];
    die("ERROR: cannot find host for the project '$Project'") unless($Host); 
    ${$Hosts{$Host}}[4]++;
    ${$Hosts{$Host}}[5] += $AVERAGE_DURATION;
    return ${$Projects{$Project}}[1] = $Host;
}

sub NextDrive
{
    my($Host, $Project) = @_;
    
    return ${$Projects{$Project}}[2] if(${$Projects{$Project}}[2]);	
    my $Drive = (sort({ ${${${$Hosts{$Host}}[0]}{$b}}[2] <=> ${${${$Hosts{$Host}}[0]}{$a}}[2]} keys(%{${$Hosts{$Host}}[0]})))[0];
    die("ERROR: cannot find drive for '$Host'") unless($Drive);
    ${${${$Hosts{$Host}}[0]}{$Drive}}[0]++;
    ${${${$Hosts{$Host}}[0]}{$Drive}}[2] -= $AVERAGE_SIZE;
    ${$Hosts{$Host}}[6] -= $AVERAGE_SIZE;
    return ${$Projects{$Project}}[2] = $Drive;
}

sub P4Submit
{
    my($P4File, $File) = @_;

    return unless(compare($P4File, $File));
    $p4->sync('-f', "\"$P4File\"");
    if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/) { chomp(${$p4->Errors()}[-1]); die("ERROR: cannot sync '$P4File': ", @{$p4->Errors()}) }
    $p4->edit("\"$P4File\"");
    if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); die("ERROR: cannot p4 edit '$P4File': ", @{$p4->Errors()}) }        
    copy($File, $P4File) or die("ERROR: cannot copy '$File': $!");
    my $rhChange = $p4->fetchchange();
    if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); die("ERROR: cannot p4 fetch change: ", @{$p4->Errors()}) }
    ${$rhChange}{Description} = ["Summary*:new CMS builds", "Reviewed by*:$User"];
    my $raChange = $p4->savechange($rhChange);
    if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); die("ERROR: cannot p4 save change: ", @{$p4->Errors()}) }
    my($Change) = ${$raChange}[0] =~ /^Change (\d+)/;
    $p4->submit("-c$Change") ;
    if($p4->ErrorCount())
    {
        chomp(${$p4->Errors()}[-1]);
        my @Errors = @{$p4->Errors()};
        $p4->revert("\"$P4File\"");
        if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); warn("ERROR: cannot p4 revert '$P4File': ", @{$p4->Errors()}) }
        $p4->change("-d", $Change);
        if($p4->ErrorCount()) { chomp(${$p4->Errors()}[-1]); warn("ERROR: cannot p4 delete change '$Change': ", @{$p4->Errors()}) }
        die("ERROR: cannot p4 submit change '$Change' ($P4File): @Errors");
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
    print(HTML "Stack Trace:<br/>\n");
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