#!/usr/bin/perl -w
use Sys::Hostname;
use Getopt::Long;
use FindBin;
use lib ($FindBin::Bin);
use Torch;

##############
# Parameters #
##############

GetOptions("help|?"=>\$Help, "group=s"=>\$ProjectGroup, "jlindir=s"=>\$LogDir, "project=s"=>\$Project);
Usage() if($Help);

$LogDir ||= "$ENV{DROP_DIR}/$ENV{context}/$ENV{build_number}/$ENV{PLATFORM}/$ENV{BUILD_MODE}/logs/$ENV{HOSTNAME}";
$Project ||= $ENV{PROJECT};
$ProjectGroup ||= $ENV{BUILD_PROJECTGROUP};
($Context, $BuildNumber, $Platform, $BuildMode, $Host) = $LogDir =~ /[\\\/]([^\\\/]+)[\\\/]([^\\\/]+)[\\\/]([^\\\/]+)[\\\/]([^\\\/]+)[\\\/][^\\\/]+[\\\/]([^\\\/]+)$/;

$ENV{BUILD_DASHBOARD_ENABLE} = 1;
$ENV{BUILD_DATE_EPOCH} ||= time();

########
# Main #
########

require Site;

$TorchWebService = new Torch($ENV{BUILD_DASHBOARD_WS});
warn("ERROR: cannot create Torch WebService: $@") unless(defined($TorchWebService));
opendir(LOGS, $LogDir) or warn("ERROR: cannot opendir '$LogDir': $!");
print "\nSTART JLIN report\n";
while(defined(my $Area = readdir(LOGS)))
{
    next unless(-e "$LogDir/$Area/JLin/reports/logs");
    print("$Area\n");
    opendir(BU, "$LogDir/$Area/JLin/reports/logs/projects");
    while(defined(my $BuildUnit = readdir(BU)))
    {
        next if($BuildUnit =~ /^\.\.?$/);
        if(open(HTM, "$LogDir/$Area/JLin/reports/logs/projects/$BuildUnit/summary.html"))
        {
            my($Errors, $Errors1, $Errors2);
            while(<HTM>)
            {
                ($Errors1, $Errors2) = /<tfoot>.+?<td align="right"><b>(\d+)<\/b><\/td><td align="right"><b>(\d+)<\/b><\/td>.+?<\/tfoot>/;
                if(defined($Errors2)) { $Errors = $Errors1 + $Errors2; last }
            }
            $Errors = 0 unless(defined($Errors)); 
            close(HTM);
            print("\t$BuildUnit:$Errors\n");
            #print("log($ProjectGroup, Project,", $TorchWebService->get_contact_name(), ",", $TorchWebService->get_contact_email(), "$Context, $Area, $BuildNumber, $BuildMode, $Platform, $ENV{BUILD_DATE_EPOCH}, $ENV{SITE}, $Host, build_unit, ${BuildUnit}_JLin, JLin, undef, $ENV{BUILD_DATE_EPOCH}, $ENV{BUILD_DATE_EPOCH}, ERROR: JLIN: $Errors, $LogDir/$Area/JLin/reports/logs/projects/$BuildUnit/summary.html, $Errors");
            $TorchWebService->log(
                $ENV{BUILD_PROJECTGROUP}?$ENV{BUILD_PROJECTGROUP}:"",
                $ENV{PROJECT}?$ENV{PROJECT}:"",
                $TorchWebService->get_contact_name()?$TorchWebService->get_contact_name():"",
                $TorchWebService->get_contact_email()?$TorchWebService->get_contact_email():"",		
                $Context?$Context:"",
                $Area?$Area:"",
                $BuildNumber?$BuildNumber:"",
                $BuildMode?$BuildMode:"",
                $Platform?$Platform:"",
                (defined $ENV{BUILD_DATE_EPOCH})?$ENV{BUILD_DATE_EPOCH}:0, 
                $ENV{SITE}?$ENV{SITE}:"",
                $Host?$Host:"",
                "build_unit",         # Step Type
                "${BuildUnit}_JLin",  # Step Name
                "JLin",               # Parent Step Name
                0,
                (defined $ENV{BUILD_DATE_EPOCH})?$ENV{BUILD_DATE_EPOCH}:0, 
                (defined $ENV{BUILD_DATE_EPOCH})?$ENV{BUILD_DATE_EPOCH}:0, 
                "ERROR: JLIN: $Errors",		    
                "$LogDir/$Area/JLin/reports/logs/projects/$BuildUnit/summary.html",
                $Errors,
                ""
            );
        } else {warn("WARNING: cannot open '$LogDir/$Area/JLin/reports/logs/projects/$BuildUnit/summary.html': $!") }
    }
    close(BU);
}
closedir(LOGS);
print "\nSTOP JLIN report\n";

END 
{ 
    $TorchWebService->delete_build_session(
        $ProjectGroup, 
        $Project, 
        $TorchWebService->get_contact_name(),
        $TorchWebService->get_contact_email(),
        $Context, 
        $BuildNumber, 
        $BuildMode, 
        $Platform, 
        $ENV{BUILD_DATE_EPOCH}
    ) if($TorchWebService);
}

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : JLinReport.pl -g -j -p
             JLinReport.pl -h.elp|?
   Example : JLinReport.pl -j=\\\\build-drops-lv\\dropzone\\Aurora\\Aurora_cons_jlin\\39\\win64_x64\\release\\logs\\BX624F1215L
    
   [options]
   -help|?    argument displays helpful information about builtin commands.
   -g.roup    specifies the project group name, default is \$ENV{BUILD_PROJECTGROUP}.
   -j.lindir  specifies the jlin log dir, default is \$ENV{DROP_DIR}/\$ENV{context}/\$ENV{build_number}/\$ENV{PLATFORM}/\$ENV{BUILD_MODE}/logs/\$ENV{HOSTNAME}.
   -p.roject  specifies the project name, default is \$ENV{PROJECT}.
USAGE
    exit;
}
