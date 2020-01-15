#!/usr/bin/perl -w

use Sys::Hostname;
use Getopt::Long;
use Data::Dumper;
use Net::SMTP;
use XML::DOM;

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

die("ERROR: SRC_DIR environment variable must be set") unless($ENV{SRC_DIR});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});
die("ERROR: BUILD_NAME environment variable must be set") unless($ENV{BUILD_NAME});
die("ERROR: MY_BUILD_NAME environment variable must be set") unless($ENV{MY_BUILD_NAME});
die("ERROR: PLATFORM environment variable must be set") unless($ENV{PLATFORM});
die("ERROR: BUILD_MODE environment variable must be set") unless($ENV{BUILD_MODE});
die("ERROR: Q_P_BUILDMODE environment variable must be set") unless($ENV{Q_P_BUILDMODE});
die("ERROR: build_number environment variable must be set") unless($ENV{build_number});
die("ERROR: context environment variable must be set") unless($ENV{context});
die("ERROR: MY_DITA_PROJECT_ID environment variable must be set") unless($ENV{MY_DITA_PROJECT_ID});
die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
$From = "$ENV{IMPORT_DIR}/$ENV{context}/".($ENV{build_number}-1). "/contexts/allmodes/files/$ENV{MY_DITA_PROJECT_ID}.project.mf.xml";
$To = $ENV{MY_PROJECTMAP} ? "$ENV{SRC_DIR}/cms/content/projects/$ENV{MY_DITA_PROJECT_ID}.project.mf.xml" : "$ENV{SRC_DIR}/cms/$ENV{MY_DITA_PROJECT_ID}.project.mf.xml";
$Requester = $ENV{MY_BUILD_REQUESTER} || 'rolling build';

########
# Main #
########

exit(0) if($ENV{Q_P_BUILDMODE} eq 'releasedebug' and $ENV{BUILD_MODE} eq 'debug');
die("ERROR: cannot found '$To'") unless(-f $To);

my @Project;
open(DAT, "$ENV{DITA_CONTAINER_DIR}/content/projects/$ENV{MY_BUILD_NAME}.dat") or die("ERROR: cannot open '$ENV{DITA_CONTAINER_DIR}/content/projects/$ENV{MY_BUILD_NAME}.dat': $!");
eval <DAT>;
close(DAT);
$FallbackLanguage = $Project[2];
my %DataMergeFiles;
if(-f "$ENV{SRC_DIR}/cms/TempFolder/Replace-BI-Files-$ENV{MY_BUILD_NAME}.txt")
{
    open(TXT, "$ENV{SRC_DIR}/cms/TempFolder/Replace-BI-Files-$ENV{MY_BUILD_NAME}.txt") or warn("ERROR: cannot open '$ENV{SRC_DIR}/cms/TempFolder/Replace-BI-Files-$ENV{MY_BUILD_NAME}.txt': $!");
    while(<TXT>) { chomp; $DataMergeFiles{$_} = undef }
    close(TXT);
}
if(-f "$ENV{SRC_DIR}/cms/TempFolder/fetched_files.txt")
{
    open(TXT, "$ENV{SRC_DIR}/cms/TempFolder/fetched_files.txt") or warn("ERROR: cannot open '$ENV{SRC_DIR}/cms/TempFolder/fetched_files.txt': $!");
    while(<TXT>) { chomp; $NewFiles{$_} = undef }
    close(TXT);
}
$MANIFEST = XML::DOM::Parser->new()->parsefile($To);
for my $REFERENCE (@{$MANIFEST->getElementsByTagName('reference')})
{
    my($FullPath, $Revision, $Language, $LoIO, $Type, $Container) = split(';', $REFERENCE->getFirstChild()->getData());
    $ToFiles{$FullPath} = [$FullPath, $Revision, $Language||'', $LoIO||'', $Type, $Container];
}
$MANIFEST->dispose();
if(-f $From)
{
    $MANIFEST = XML::DOM::Parser->new()->parsefile($From);
    for my $REFERENCE (@{$MANIFEST->getElementsByTagName('reference')})
    {
        my($FullPath, $Revision, $Language, $LoIO, $Type, $Container) = split(';', $REFERENCE->getFirstChild()->getData());
        $FromFiles{$FullPath} = [$FullPath, $Revision, $Language||'', $LoIO||'', $Type, $Container];
    }
    $MANIFEST->dispose();
    foreach my $FullPath (keys(%FromFiles))
    {
        if(exists($ToFiles{$FullPath})) { push(@changed, $ToFiles{$FullPath}) if(${$ToFiles{$FullPath}}[1] ne ${$FromFiles{$FullPath}}[1]) }
        else { push(@removed, $FromFiles{$FullPath}) }
    }
    foreach my $FullPath (keys(%ToFiles))
    {
        push(@added, $ToFiles{$FullPath}) unless(exists($FromFiles{$FullPath}));
    }
}
open(DAT, "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=win64_x64_$ENV{BUILD_MODE}_properties.dat") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=win64_x64_$ENV{BUILD_MODE}_properties.dat': $!");
eval <DAT>;
close(DAT);
%DeltaProperties = %Properties;
$IsFullCompilation = 0;
if(exists($ENV{MY_PROJECTMAP}))
{
    open(DAT, "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/properties.dat") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/properties.dat': $!");
    eval <DAT>;
    close(DAT);
    open(LOG, "$ENV{OUTPUT_DIR}/logs/Build/deltacompilation.log") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/Build/deltacompilation.log': $!");
    while(<LOG>)
    {
        if(/INFO:DCR001\s/) { $IsFullCompilation = 1; last }
    }
    close(LOG);
}

open(ACT, ">$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Activities.txt") or warn("ERROR: cannot open '>$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Activities.txt': $!");
print("[INFO] [Build Mode]\n");
print("[INFO]     $Requester\n");
print(ACT "[Build Mode]\n");
print(ACT "    $Requester\n");
$FetchMode = exists($ENV{MY_PROJECTMAP}) ? ((-f $From) ? 'Delta Fetch from the Container Store' : 'Initial Fetch from the Container Store') : 'Full fetch from the CMS';
print("[INFO] [Fetch Mode]\n");
print("[INFO]     $FetchMode\n");
print(ACT "[Fetch Mode]\n");
print(ACT "    $FetchMode\n");
$CompilationMode = exists($ENV{MY_PROJECTMAP}) ? ($IsFullCompilation ? 'full compilation ('.scalar(keys(%Properties))." outputs)" : 'delta compilation for '.scalar(keys(%DeltaProperties)).'/'. scalar(keys(%Properties)).' outputs') : 'Full compilation for '.scalar(keys(%Properties)).' outputs';
print("[INFO] [Compilation Mode]\n");
print("[INFO]     $CompilationMode\n");
print(ACT "[Compilation Mode]\n");
print(ACT "    $CompilationMode\n");
if(-f $From)
{
    print("[INFO] comparison between '$From' and\n[INFO]                    '$To' :\n");
    print(ACT "\tSource changes between ", $ENV{build_number}-1, " and $ENV{build_number} build revisions :\n");
    print("[INFO]\t\tchanged files : ", scalar(@changed), "\n");
    print("[INFO]\t\tadded files   : ", scalar(@added), "\n");
    print("[INFO]\t\tremoved files : ", scalar(@removed), "\n");
    print(ACT "\tchanged files : ", scalar(@changed), "\n");
    print(ACT "\tadded files   : ", scalar(@added), "\n");
    #print(ACT "\tremoved files : ", scalar(@removed), "\n");
}
else
{
    print("[INFO] No previous build (build number $ENV{build_number})\n");
    print(ACT "No previous build (build number $ENV{build_number})");
}
print("[INFO] Impacted outputs : ", scalar(keys(%DeltaProperties)), "/", scalar(keys(%Properties)),"\n");
print(ACT "\tImpacted outputs : ", scalar(keys(%DeltaProperties)), "/", scalar(keys(%Properties)),"\n");
if(@changed or @removed or @added)
{
    print("[INFO] [Changed source file list]\n");
    print(ACT "[Changed source file list]\n");
    foreach $Kind (qw(changed added removed))
    {
        foreach (@{$Kind})
        {
            my($FullPath, $Revision, $Language, $LoIO, $Type, $Container) = @{$_};
            print("[INFO]\t\t'$FullPath' $Kind [rev=$Revision", exists($ENV{MY_PROJECTMAP})?" $LoIO lang=$Language":'', "]\n");
            print(ACT "\t'$FullPath' $Kind [rev=$Revision", exists($ENV{MY_PROJECTMAP})?" $LoIO lang=$Language":'', "]\n") unless($Kind eq 'removed');
            my($Extension) = $FullPath =~ /([^.]+)$/;
            delete $NewFiles{"$Language/$LoIO.$Extension"};
        }
    }
    foreach (keys(%NewFiles))
    {
        print("[INFO]\t\t'/content/localization/$_' post-treatement\n");
        print(ACT "\t'/content/localization/$_' post-treatement\n");
    }
    open(TXT, ">$ENV{HTTP_DIR}/$ENV{context}/LastManifestModificationDate.txt") or die("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/LastManifestModificationDate.txt': $!");
    print(TXT $ENV{BUILD_DATE});
    close(TXT);
}
print("[INFO] [Impacted output list]\n");
print(ACT "[Impacted output list]\n");
foreach(keys(%DeltaProperties))
{
    my($Title, $LoIO, $Path) = @{$DeltaProperties{$_}}[0,1,4];
    $Path =~ s/00/./;
    print("[INFO]\t\t$Title ($LoIO) : $Path\n");
    print(ACT "\t$Title ($LoIO) : $Path\n");
}
open(LOG, "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1/cms=$ENV{PLATFORM}_$ENV{BUILD_MODE}_prefetch.log") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Host_1/cms=$ENV{PLATFORM}_$ENV{BUILD_MODE}_prefetch.log': $!");
while(<LOG>)
{
    next unless(/^====\s+/);
    print(ACT $_);
    while(<LOG>)
    {
        last if(/^=== exit code:/);
        print(ACT $_);
    }
}
close(LOG);
close(ACT);

my (%SecondaryFiles, %FallbackFiles);
open(DAT, "$ENV{OUTPUT_DIR}/logs/Build/CMSProjectFetch.dat") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/Build/CMSProjectFetch.dat': $!");
{ local $/; eval <DAT> }
close(DAT);
my(@ImpactedOutputs, %O2OMetadatas);
open(DAT, "$ENV{OUTPUT_DIR}/logs/Build/DeltaCompilation.dat") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/Build/DeltaCompilation.dat': $!");
{ local $/; eval <DAT> }
close(DAT);
$IsPreviousBuildWithPublishingErrors = 'no';
foreach (@ImpactedOutputs)
{
    next unless(${$_}[2] eq 'impacted by previous error');
    $IsPreviousBuildWithPublishingErrors = 'yes';
    last;
}
($BuildMode = $ENV{MY_BUILD_REQUESTER} || 'rolling build') =~ s/buildondemand/build on demand/;
$BuildMode =~ s/Daily/rolling/;

open(HTM, ">$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Activities.htm") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/Activities.htm': $!");
print(HTM "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n");
print(HTM "<html>\n");
print(HTM "\t<head>\n");
print(HTM "\t\t<meta http-equiv='content-type' content='text/html; charset=UTF-8'/>\n");
print(HTM "\t\t<title>Activities</title>\n");
print(HTM "\t\t<style type='text/css'>\n");
print(HTM "\t\t\tbody {font-family:'Helvetica Neue',Helvetica,Arial; font-size:14px; line-height:20px; font-weight:400; -webkit-font-smoothing:antialiased; font-smoothing:antialiased;}\n");
print(HTM "\t\t\t#myTable { border-collapse: collapse; width: 100%; border: 1px solid #ddd; font-size: 14px; }\n");
print(HTM "\t\t\t#myTable th, #myTable td { text-align: left; padding: 10px; }\n");
print(HTM "\t\t\t#myTable tr { border-bottom: 1px solid #ddd; }\n");
print(HTM "\t\t\t#myTable tr.header, #myTable tr:hover { background-color: #f1f1f1; }\n");
print(HTM "\t\t</style>\n");
print(HTM "\t</head>\n");
print(HTM "\t<body>\n");
print(HTM "\t\t<fieldset>\n");
print(HTM "\t\t\t<legend>Summary</legend>\n");
print(HTM "\t\t\t<table>\n");
print(HTM "\t\t\t\t<tr valign='top'>\n");
print(HTM "\t\t\t\t\t<td>\n");
print(HTM "\t\t\t\t\t\t<table>\n");
print(HTM "\t\t\t\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t\t\t\t<td><b>Build Mode</b> :</td>\n");
print(HTM "\t\t\t\t\t\t\t\t<td>$BuildMode</td>\n");
print(HTM "\t\t\t\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t\t\t\t<td><b>Fetch Mode</b> :</td>\n");
print(HTM "\t\t\t\t\t\t\t\t<td>$FetchMode[0]", ($FetchMode[1] ? " due of $FetchMode[1]":''), "</td>\n");
print(HTM "\t\t\t\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t\t\t\t<td><b>Compilation Mode</b> :</td>\n");
print(HTM "\t\t\t\t\t\t\t\t<td>$CompilationMode</td>\n");
print(HTM "\t\t\t\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t\t\t</table>\n");
print(HTM "\t\t\t\t\t</td>\n");
print(HTM "\t\t\t\t\t<td>\n");
print(HTM "\t\t\t\t\t\t<table>\n");
print(HTM "\t\t\t\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t\t\t\t<td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>Build triggered due to the following</b> : </td>\n");
print(HTM "\t\t\t\t\t\t\t\t<td>source content has changed : ", ((@changed or @removed or @added) ? 'yes' : 'no'), "</td>\n");
print(HTM "\t\t\t\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t\t\t\t<td></td>\n");
print(HTM "\t\t\t\t\t\t\t\t<td>local cms folder missing : ", ($FetchMode[1] eq 'cms folder missing' ? 'yes':'no'), "</td>\n");
print(HTM "\t\t\t\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t\t\t\t<td></td>\n");
print(HTM "\t\t\t\t\t\t\t\t<td>output to output linking metadata has changed : ", keys(%O2OMetadatas) ? 'yes' : 'no', "</td>\n");
print(HTM "\t\t\t\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t\t\t\t<td></td>\n");
print(HTM "\t\t\t\t\t\t\t\t<td>data merge changes : ", keys(%DataMergeFiles) ? 'yes' : 'no', "</td>\n");
print(HTM "\t\t\t\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t\t\t\t<td></td>\n");
print(HTM "\t\t\t\t\t\t\t\t<td>previous build had pre-publishing/fatal errors : $IsPreviousBuildWithPublishingErrors</td>\n");
print(HTM "\t\t\t\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t\t\t</table>\n");
print(HTM "\t\t\t\t\t</td>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t</table>\n");
print(HTM "\t\t</fieldset><br/>\n");

print(HTM "\t\t<table>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t\t<td><b>Impacted outputs</b> :</td>\n");
print(HTM "\t\t\t\t<td>", ($IsFullCompilation ? scalar(keys(%Properties)) : scalar(keys(%DeltaProperties))), "/", scalar(keys(%Properties)),"</td>\n");
print(HTM "\t\t\t</tr>\n");
print(HTM "\t\t</table>\n");
print(HTM "\t\t<table id='myTable'>\n");
print(HTM "\t\t\t<thead>\n");
print(HTM "\t\t\t\t<tr class='header'>\n");
print(HTM "\t\t\t\t\t<th>Title</th>\n");
print(HTM "\t\t\t\t\t<th>Loio</th>\n");
print(HTM "\t\t\t\t\t<th>Language</th>\n");
print(HTM "\t\t\t\t\t<th>Transtype</th>\n");
print(HTM "\t\t\t\t\t<th>Path</th>\n");
print(HTM "\t\t\t\t\t<th>Impacted by</th>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t</thead>\n");
print(HTM "\t\t\t<tbody>\n");
foreach(@ImpactedOutputs)
{
    my($FileName, $Language, $Message, $TransType, $LoIO, $Title) = @{$_};
    $Message =~ s/^impacted by //;
    print(HTM "\t\t\t\t<tr>\n");
    print(HTM "\t\t\t\t\t<td>$Title</td>\n");
    print(HTM "\t\t\t\t\t<td>$LoIO</td>\n");
    print(HTM "\t\t\t\t\t<td>$Language</td>\n");
    print(HTM "\t\t\t\t\t<td>$TransType</td>\n");
    print(HTM "\t\t\t\t\t<td>packages/$TransType/$Language/$ENV{BUILD_MODE}/$FileName</td>\n");
    print(HTM "\t\t\t\t\t<td>$Message</td>\n");
    print(HTM "\t\t\t\t</tr>\n");
}
print(HTM "\t\t\t</tbody>\n");
print(HTM "\t\t</table><br/>\n");

print(HTM "\t\t<table>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t\t<td><b>Source changes between ", $ENV{build_number}-1, " and $ENV{build_number} build revisions</b> :</td>\n");
print(HTM "\t\t\t\t<td>changed files : ", scalar(@changed), "</td>\n");
print(HTM "\t\t\t</tr>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t\t<td></td>\n");
print(HTM "\t\t\t\t<td>added files : ", scalar(@added), "</td>\n");
print(HTM "\t\t\t</tr>\n");
print(HTM "\t\t</table>\n");
print(HTM "\t\t<table id='myTable'>\n");
print(HTM "\t\t\t<thead>\n");
print(HTM "\t\t\t\t<tr class='header'>\n");
print(HTM "\t\t\t\t\t<th>Full path</th>\n");
print(HTM "\t\t\t\t\t<th>Status</th>\n");
print(HTM "\t\t\t\t\t<th>Loio</th>\n");
print(HTM "\t\t\t\t\t<th>Revison</th>\n");
print(HTM "\t\t\t\t\t<th>Language</th>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t</thead>\n");
print(HTM "\t\t\t<tbody>\n");
foreach $Kind (qw(changed added removed))
{
    foreach (@{$Kind})
    {
        my($FullPath, $Revision, $Language, $LoIO, $Type, $Container) = @{$_};
        print(HTM "\t\t\t\t<tr>\n");
        print(HTM "\t\t\t\t\t<td>$FullPath</td>\n");
        print(HTM "\t\t\t\t\t<td>$Kind</td>\n");
        print(HTM "\t\t\t\t\t<td>$LoIO</td>\n");
        print(HTM "\t\t\t\t\t<td>$Revision</td>\n");
        print(HTM "\t\t\t\t\t<td>$Language</td>\n");
        print(HTM "\t\t\t\t</tr>\n");
    }
}
print(HTM "\t\t\t</tbody>\n");
print(HTM "\t\t</table><br/>\n");

print(HTM "\t\t<table>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t\t<td><b>Fallback language</b> :</td>\n");
print(HTM "\t\t\t\t<td>language : $FallbackLanguage</td>\n");
print(HTM "\t\t\t</tr>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t\t<td></td>\n");
print(HTM "\t\t\t\t<td>copied files : ", scalar(keys(%FallbackFiles)), "</td>\n");
print(HTM "\t\t\t</tr>\n");
print(HTM "\t\t</table>\n");
print(HTM "\t\t<table id='myTable'>\n");
print(HTM "\t\t\t<thead>\n");
print(HTM "\t\t\t\t<tr class='header'>\n");
print(HTM "\t\t\t\t\t<th>File</th>\n");
print(HTM "\t\t\t\t\t<th>Language</th>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t</thead>\n");
print(HTM "\t\t\t<tbody>\n");
print(HTM "\t\t\t\t<tr>\n");
foreach (keys(%FallbackFiles))
{
    my($Language, $File) = split(/\//);
    print(HTM "\t\t\t\t<tr>\n");
    print(HTM "\t\t\t\t\t<td>$File</td>\n");
    print(HTM "\t\t\t\t\t<td>$Language</td>\n");
    print(HTM "\t\t\t\t</tr>\n");
}
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t</tbody>\n");
print(HTM "\t\t</table><br/>\n");

print(HTM "\t\t<table>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t<td><b>secondary files for copy-to</b> :</td>\n");
print(HTM "\t\t\t<td>", scalar(keys(%SecondaryFiles)), "</td\n");
print(HTM "\t\t\t</tr>\n");
print(HTM "\t\t</table>\n");
print(HTM "\t\t<table id='myTable'>\n");
print(HTM "\t\t\t<thead>\n");
print(HTM "\t\t\t\t<tr class='header'>\n");
print(HTM "\t\t\t\t\t<th>File</th>\n");
print(HTM "\t\t\t\t\t<th>Language</th>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t</thead>\n");
print(HTM "\t\t\t<tbody>\n");
print(HTM "\t\t\t\t<tr>\n");
foreach (keys(%SecondaryFiles))
{
    my($Language, $File) = split(/\//);
    print(HTM "\t\t\t\t<tr>\n");
    print(HTM "\t\t\t\t\t<td>$File</td>\n");
    print(HTM "\t\t\t\t\t<td>$Language</td>\n");
    print(HTM "\t\t\t\t</tr>\n");
}
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t</tbody>\n");
print(HTM "\t\t</table><br/>\n");

print(HTM "\t\t<table>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t\t<td><b>Output to output linking</b> :</td>\n");
print(HTM "\t\t\t\t<td>", scalar(keys(%O2OMetadatas)), "</td>\n");
print(HTM "\t\t\t</tr>\n");
print(HTM "\t\t</table>\n");
print(HTM "\t\t<table id='myTable'>\n");
print(HTM "\t\t\t<thead>\n");
print(HTM "\t\t\t\t<tr class='header'>\n");
print(HTM "\t\t\t\t\t<th>File</th>\n");
print(HTM "\t\t\t\t\t<th>Language</th>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t</thead>\n");
print(HTM "\t\t\t<tbody>\n");
foreach (keys(%O2OMetadatas))
{
    my($Language, $File) = split(/\//);
    print(HTM "\t\t\t\t<tr>\n");
    print(HTM "\t\t\t\t\t<td>$File</td>\n");
    print(HTM "\t\t\t\t\t<td>$Language</td>\n");
    print(HTM "\t\t\t\t</tr>\n");
}
print(HTM "\t\t\t</tbody>\n");
print(HTM "\t\t</table><br/>\n");

print(HTM "\t\t<table>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t\t<td><b>Data merge</b> :</td>\n");
print(HTM "\t\t\t\t<td>", scalar(keys(%DataMergeFiles)), "</td>\n");
print(HTM "\t\t\t</tr>\n");
print(HTM "\t\t</table>\n");
print(HTM "\t\t<table id='myTable'>\n");
print(HTM "\t\t\t<thead>\n");
print(HTM "\t\t\t\t<tr class='header'>\n");
print(HTM "\t\t\t\t\t<th>File</th>\n");
print(HTM "\t\t\t\t\t<th>Language</th>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t</thead>\n");
print(HTM "\t\t\t<tbody>\n");
foreach (keys(%DataMergeFiles))
{
    my($Language, $File) = split(/\//);
    print(HTM "\t\t\t\t<tr>\n");
    print(HTM "\t\t\t\t\t<td>$File</td>\n");
    print(HTM "\t\t\t\t\t<td>$Language</td>\n");
    print(HTM "\t\t\t\t</tr>\n");
}
print(HTM "\t\t\t</tbody>\n");
print(HTM "\t\t</table>\n");

print(HTM "\t</body>\n");
print(HTM "</html>\n");
close(HTM);

#############
# Functions #
#############

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