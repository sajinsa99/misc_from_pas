#!/usr/bin/perl -w

use Time::Local;
use File::Copy;

use FindBin;
use lib ($FindBin::Bin);
$ENV{PROJECT} = 'documentation';
require Site;
$CURRENT_DIR = $FindBin::Bin;
system("p4 print -o $CURRENT_DIR/DAM.pm //internal/cis/1.0/REL/cgi-bin/DAM.pm");
our($DAM_HREF);
require DAM;
DAM->import();

##############
# Parameters #
##############

@CYCLES = qw(00.00);

########
# Main #
########

@Today = localtime();

copy("$ENV{DITA_CONTAINER_DIR}/content/projects/PDC.dat", "$ENV{HTTP_DIR}/JobViewer") or warn("ERROR: cannot copy '$ENV{DITA_CONTAINER_DIR}/content/projects/PDC.dat': $!");
copy("$ENV{DITA_CONTAINER_DIR}/content/projects/ProjectDependencies.dat", "$ENV{HTTP_DIR}/JobViewer") or warn("ERROR: cannot copy '$ENV{DITA_CONTAINER_DIR}/content/projects/ProjectDependencies.dat': $!");
$Coo = "$CURRENT_DIR/events-documentation.coo";
system("p4 print -o $Coo //depot2/Main/Stable/Build/shared/events-documentation.coo");
copy($Coo, "$ENV{HTTP_DIR}/JobViewer") or warn("ERROR: cannot copy 'Coo': $!");
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

foreach my $Cycle (@CYCLES)
{
    foreach my $Host (keys(%Hosts))
    {
        next unless(-d "$ENV{HTTP_DIR}/JobViewer/Cycles/$Cycle/$Host");
        my(@Dependencies, @Builds, %Builds, $StartCycle, $StopCycle);
        # $Deps{$Project} = [$Title, $BuildName, $Status, $Host, $Start, $Stop, $CMSStatus, $Order, $rhChildren, $rhParents]
        %Deps = ();
        open(DAT, "$ENV{HTTP_DIR}/JobViewer/Cycles/$Cycle/$Host/ProjectDependencies.dat") or warn("ERROR:cannot open '$ENV{HTTP_DIR}/JobViewer/Cycles/$Cycle/$Host/ProjectDependencies.dat': $!");
        { local $/=''; eval(<DAT>) }
        close(DAT);
        foreach my $Project (keys(%dependencies))
        {
            my($Level, $Title, $Status, $raDependencies) = @{$dependencies{$Project}};
            $Project =~ s/\.project$//;
            ${$Deps{$Project}}[0] = $Title;
            ${$Deps{$Project}}[6] = $Status;
            for(my $Level=0; $Level< @{$raDependencies}; $Level++)
            {
                my $IsFound = 0;
                foreach my $Dependency (@{$raDependencies})
                {
                    my($L,$P,$T,$S) = split(/\s*,\s*/, $Dependency);
                    next unless($L==$Level+2);
                    $P =~ s/\.project$//;
                    ${${$Deps{$P}}[8]}{$Project} = undef;
                    ${${$Deps{$Project}}[9]}{$P} = undef;
                    $IsFound = 1;;
                }
                last if($IsFound);
            }
        }
        open(DAT, "$ENV{HTTP_DIR}/JobViewer/Cycles/$Cycle/$Host/Cycle.dat") or warn("ERROR:cannot open '$ENV{HTTP_DIR}/JobViewer/Cycles/$Cycle/$Host/Cycle.dat': $!");
        { local $/=''; eval(<DAT>) }
        close(DAT);
        my $Stp = $StopCycle || '';
        $StartCycle ||= timelocal(0, 0, 0, @Today[3..5]);
        $StopCycle ||= timelocal(59, 59, 23, @Today[3..5]);
        open(DAT, "$ENV{HTTP_DIR}/JobViewer/Cycles/$Cycle/$Host/Build.dat") or warn("ERROR:cannot open '$ENV{HTTP_DIR}/JobViewer/Cycles/$Cycle/$Host/Build.dat': $!");
        { local $/=''; eval(<DAT>) }
        close(DAT);
        $Order = 1;
        map({ ${$Deps{${$_}[0]}}[7] = $Order++ if(exists($Deps{${$_}[0]}) and (${$Deps{${$_}[0]}}[6] eq 'Project:active' or ${$Deps{${$_}[0]}}[6] eq 'Project:active-translation')) } @Builds);
        map({ ${$Deps{${$_}[0]}}[3] = $Host } @Builds);
        @Builds{map({${$_}[0]} @Builds)} = (undef);
        while(1)
        {
            my $NumberOfBuilds = keys(%Builds);
            foreach my $Project (keys(%Builds))
            {
                my($rhChildren, , $rhParents) = @{$Deps{$Project}}[8,9];
                %Builds = (%Builds, %{$rhChildren}) if($rhChildren);
                %Builds = (%Builds, %{$rhParents}) if($rhParents);
            }
            last if(keys(%Builds) == $NumberOfBuilds);
        }
        push(@Dependencies, "\t\t{\"id\":\"1\", \"name\":\"START\", \"build\":\"\", \"status\":\"finished\", \"host\":\"\", \"start\":\"\", \"stop\":\"\", \"cmsstatus\":\"Project:active\", \"order\":\"0\", \"parents\":\"null\"}");
        foreach my $Project (keys(%Builds))
        {
            Status($Project, $StartCycle, $StopCycle);
            my($Title, $BuildName, $Status, $Host, $Start, $Stop, $CMSStatus, $Order, $rhChildren, $rhParents) = @{$Deps{$Project}}[0..9];
            ${$rhParents}{1} = undef unless(keys(%{$rhParents}));
            $Title||=''; $BuildName||=''; $Status||=''; $Host||=''; $Start||=''; $Stop||=''; $CMSStatus||=''; $Order||='';
            push(@Dependencies, "\t\t{\"id\":\"$Project\", \"name\":\"$Title\", \"build\":\"$BuildName\", \"status\":\"$Status\", \"host\":\"$Host\", \"start\":\"$Start\", \"stop\":\"$Stop\", \"cmsstatus\":\"$CMSStatus\", \"order\":\"$Order\", \"parents\":".(keys(%{$rhParents}) ? ("[".join(", ", map({"{\"id\":\"$_\"}"} keys(%{$rhParents})))."]"):"\"null\"")."}");
        }
        open(JSON, ">$ENV{HTTP_DIR}/JobViewer/Cycles/$Cycle/$Host/Dependencies_${Host}_$Cycle.json") or die("ERROR: cannot open '$ENV{HTTP_DIR}/JobViewer/Cycles/$Cycle/$Host/Dependencies_${Host}_$Cycle.json': $!");
        {
            print(JSON "{\n");
            print(JSON "\t\"dependencies\" :\n");
            print(JSON "\t[\n");
            print(JSON join(",\n", @Dependencies));
            print(JSON "\n\t],\n");
            print(JSON "\t\"cycle\" :  {\"start\":\"$StartCycle\", \"stop\":\"$Stp\"}\n");
            print(JSON "}\n");
        }
        close(JSON);
    }
}

#############
# Functions #
#############

sub Status
{
    my($Project, $StartCycle, $StopCycle) = @_;
    
    my $CMSStatus = ${$Deps{$Project}}[6];
    return ${$Deps{$Project}}[2] = 'inactive' unless($CMSStatus eq 'Project:active' or $CMSStatus eq 'Project:active-translation');

    my $BuildNumber = 0;
    if(-f "$ENV{IMPORT_DIR}/$Project/version.txt")
    {
        open(VER, "$ENV{IMPORT_DIR}/$Project/version.txt") or warn("ERROR: cannot open '': $!");
        chomp($BuildNumber = <VER>);
        close(VER);
        $BuildNumber = sprintf("%05d", $BuildNumber)
    }
    return ${$Deps{$Project}}[2]='not started' unless($BuildNumber);
    
    my $BuildName = ${$Deps{$Project}}[1] = "${Project}_$BuildNumber";
    my($Start, $Stop, $IsInProgress) = (0xFFFFFFFF, 0, 1);
    my @Errors;
    unless(${$Deps{$Project}}[3])
    {
        open(DAT, "$DAM_DIR/$Project/$BuildName/$BuildName=${DEFAULT_PLATFORM}_release_host_1.dat") or warn("ERROR: cannot open '$DAM_DIR/$Project/$BuildName/$BuildName=${DEFAULT_PLATFORM}_release_host_1.dat': $!");
        (${$Deps{$Project}}[3]) = <DAT> =~ /^([^\s]+)/;
        close(DAT);
    }
    if(-f "$DAM_DIR/$Project/NothingToDo.dat")
    {
        my @NothingToDo;
        open(DAT, "$DAM_DIR/$Project/NothingToDo.dat") or warn("ERROR: cannot open '$DAM_DIR/$Project/NothingToDo.dat': $!");
        { local $/; eval <DAT> }
        close(DAT);
        if($NothingToDo[0]>=$StartCycle)
        {
            foreach my $Step (qw(build export prefetch smoke))
            {
                open(DAT, "$DAM_DIR/$Project/$BuildName/$BuildName=${DEFAULT_PLATFORM}_release_${Step}_1.dat") or warn("ERROR: cannot open '$DAM_DIR/$Project/$BuildName/$BuildName=${DEFAULT_PLATFORM}_release_${Step}_1.dat': $!");
                 { local $/; eval <DAT> }
                close(DAT);
                return ${$Deps{$Project}}[2] = 'nothing to do with errors' if($Errors[0]);
            }
            return ${$Deps{$Project}}[2] = 'nothing to do without errors';
        }
    }
    open(DAT, "$DAM_DIR/$Project/$BuildName/$BuildName=${DEFAULT_PLATFORM}_release_infra_1.dat") or warn("ERROR: cannot open '$DAM_DIR/$Project/$BuildName/$BuildName=${DEFAULT_PLATFORM}_release_infra_1.dat': $!");
    { local $/; eval <DAT> }
    close(DAT);
    foreach(@Errors[1..$#Errors])
    {
        my($Errors, $Log, $Summary, $Area, $Strt, $Stp) = @{$_};
        $Start = ${$Deps{$Project}}[4] = $Strt if($Strt < $Start);
        $Stop = ${$Deps{$Project}}[5] = $Stp if($Stp > $Stop);
        $IsInProgress = 0 if($Area eq 'smoke_step');
    }
    return ${$Deps{$Project}}[2]='in progress' if($IsInProgress and $Start>=$StartCycle and $Stop<=$StopCycle);
    return ${$Deps{$Project}}[2]='not started' if($Start>=$StopCycle or $Stop<=$StartCycle);
    foreach my $Step (qw(build export prefetch smoke))
    {
        open(DAT, "$DAM_DIR/$Project/$BuildName/$BuildName=${DEFAULT_PLATFORM}_release_${Step}_1.dat") or warn("ERROR: cannot open '$DAM_DIR/$Project/$BuildName/$BuildName=${DEFAULT_PLATFORM}_release_${Step}_1.dat': $!");
         { local $/; eval <DAT> }
        close(DAT);
        return ${$Deps{$Project}}[2] = 'finished with errors' if($Errors[0]);
    }
    return ${$Deps{$Project}}[2] = 'finished without errors';
}
