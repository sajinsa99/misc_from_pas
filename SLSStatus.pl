#!/usr/bin/perl -w

use Getopt::Long;
use Data::Dumper;

##############
# Parameters #
##############

GetOptions("help|?" => \$Help, "file=s@"=>\@LogFiles);
Usage() if($Help);
push(@LogFiles, "$ENV{OUTPUT_DIR}/logs/Build/export_content.log", "$ENV{OUTPUT_DIR}/logs/Build/import_content.log") unless(@LogFiles);
$Data::Dumper::Indent = 0;

$Requester = $ENV{MY_BUILD_REQUESTER} || 'Daily build';

########
# Main #
########

foreach my $LogFile (@LogFiles)
{
    my $Action = ($LogFile=~/structure/) ? 'structure' : (($LogFile=~/import_content/) ? 'import' : 'export');
    ${$Status{$Action}}{errors} =  ${$Status{$Action}}{warnings} = 0;
    ${$Status{$Action}}{user} = $Requester;
    @{${$Status{$Action}}{files}} = ();
    open(LOG, $LogFile)  or die("ERROR: cannot open '$LogFile': $!");
    while(<LOG>)
    {
        ${$Status{$Action}}{errors}++ if(/^\[Error\]/);
        ${$Status{$Action}}{warnings}++ if(/^\[Warning\]/);
        next unless(/\[BeginFileList\]/);
        while(<LOG>)
        {
            last if(/\[EndFileList\]/);
            (my $SLSFile = $_) =~ s/^\s+|\s+$//g;
            my($NameExtension, $LOIO, $Name, $FullPath, $Title) = split(/\s*,\s*/, $SLSFile);
            push(@{${$Status{$Action}}{files}}, {'title'=>$Title, 'fullpath'=>$FullPath, 'loio'=>$LOIO});
        }
    }
    close(LOG);
}
open(DAT, ">$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=$ENV{PLATFORM}_$ENV{BUILD_MODE}_slsstatus_1.dat") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=$ENV{PLATFORM}_$ENV{BUILD_MODE}_slsstatus_1.dat': $!");
print DAT Data::Dumper->Dump([\%Status], ["*Status"]);
close(DAT);

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : SLSStatus.pl -h -f
             SLSStatus.pl -h.elp|?
   Example : SLSStatus.pl -f=export_content.log 
    
   [options]
   -help|?   argument displays helpful information about builtin commands.
   -f.ile    specifies the list of SLS log file name, default is export_content.log and import_content.log.
USAGE
    exit;
}