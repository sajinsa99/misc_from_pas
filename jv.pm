package jv;



##############################################################################
##### declare uses
use Exporter;



##############################################################################
##### declare functions
sub GetAllInfos();
sub GetAllBuildsRev();
sub GetBuildRev($);
sub GetAllIP();
sub GetIP($);
sub GetBuildTaskStatus($);
sub GetMachineTaskStatus($);
sub NSLOOKUP($$);
sub WriteTitle($);



##############################################################################
##### declare vars
use vars qw (
    $SITE
    $PrefixSite
    @STARTS
    @sortedPLATFORMS
    $JOBS_DIR
    $EVENTS_DIR
    $CIS_DIR
    %JOBS
    %JobsTasksBuild
    %PLATFORMS
    %BLDMACHINES
    %BUILDMACHINES
    %BUILDS
    %BuildsTasks
    %BuildsRev
    %TASKS
    %StartsBuildsTasks
    %StartsMachinesTasks
    %CMDS
    %IPS
    @event_dirs
    $CIS_HTTP_DIR
    $TORCH_HTTP_DIR
    $NSLOOKUP_CMD
    $IMG_SRC
);

@ISA    = qw(Exporter);
@EXPORT = qw (
    &GetAllInfos
    &GetStatusTask
    &GetAllBuildsRev
    &GetBuildRev
    &GetAllIP
    &GetBuildTaskStatus
    &GetMachineTaskStatus
    &GetIP
    &WriteTitle
    &NSLOOKUP
    $SITE
    $PrefixSite
    @STARTS
    @sortedPLATFORMS
    $JOBS_DIR
    $EVENTS_DIR
    $CIS_DIR
    %JOBS
    %JobsTasksBuild
    %PLATFORMS
    %BLDMACHINES
    %BUILDMACHINES
    %BUILDS
    %BuildsTasks
    %BuildsRev
    %TASKS
    %StartsBuildsTasks
    %StartsMachinesTasks
    %CMDS
    %IPS
    @event_dirs
    $CIS_HTTP_DIR
    $TORCH_HTTP_DIR
    $NSLOOKUP_CMD
    $IMG_SRC
);



##############################################################################
##### init vars
### environment
#get Site
$SITE ||= $ENV{SITE} || "Walldorf";

#get paths accordling with Site
if(open(PATHS,"./jvPaths.txt")) {
    my $flagSite;
    my $osFamily = ($^O eq "MSWin32") ? "windows" : "unix";
    my $osFamilyFound;
    while(<PATHS>) {
        chomp;
        next if(/^\;/);
        next if(/^\#/);
        s/^\s+$//; #remove empty line with spaces
        next unless($_);
        if(/^\[(.+?)\]/){
            if($SITE eq $1) {
                $flagSite = 1;
                next;
            } else {
                $flagSite = 0;
            }
        }
        if(($flagSite) && ($flagSite == 1)) {
            $PrefixSite     = $1 if(/^PREFIXSITE\s+\=\s+(.+?)$/);
            $CIS_HTTP_DIR   = $1 if(/^CIS_HTTP_DIR\s+\=\s+(.+?)$/);
            $TORCH_HTTP_DIR = $1 if(/^TORCH_HTTP_DIR\s+\=\s+(.+?)$/);
            ($CIS_DIR)      = $1 if(/^CIS_DIR\s+\=\s+(.+?)$/);
            ($JOBS_DIR)     = $1 if(/^JOBS_DIR\s+\=\s+(.+?)$/);
            ($EVENTS_DIR)   = $1 if(/^EVENTS_DIR\s+\=\s+(.+?)$/);
            ($NSLOOKUP_CMD) = $1 if(/^NSLOOKUP_CMD\s+\=\s+(.+?)$/);
            ($IMG_SRC)      = $1 if(/^IMG_SRC\s+\=\s+(.+?)$/);
            next;
        }
    }
    close(PATHS);
}



##############################################################################
### my functions

sub GetAllInfos() {
    @sortedPLATFORMS
    = qw(win32_x86
         win64_x64
         linux_x86
         linux_x64
         solaris_sparc
         solaris_sparcv9
         aix_rs6000
         aix_rs6000_64
         hpux_pa-risc
         hpux_ia64
        );
    @STARTS
    = qw(01_30_IW
         04_00
         07_00
         09_00
         10_00
         11_00
         12_00
         13_00
         15_00
         15_30
         17_00
         19_00_NonSuite
         19_00_Suite
         21_00
         22_00
         23_00
         00_00
         01_00
         02_00
        );

    foreach my $start (@STARTS) {
        my $jobFile ="$JOBS_DIR/${PrefixSite}_$start.txt";
        if( -e "$JOBS_DIR/${PrefixSite}_$start.txt") {
            if(open(JOB_FILE,$jobFile)) {
                my $event_dir;
                my $previousTask;
                my $previousMachine;
                my $previousBuild;
                while(<JOB_FILE>) {
                    chomp;
                    s-^\s+$--;
                    next unless($_);
                    next if(/^\;/);
                    next if(/\[config\]/);
                    if(/event_dir\s+\=\s+(.+?)$/) {
                        $event_dir = $1;
                    }
                    unless($event_dir) {
                        $event_dir =lc("${PrefixSite}_$start");
                        unless(grep /^$event_dir$/,@event_dirs) {
                            push(@event_dirs,$event_dir);
                        }
                    }
                    # get task, machine and platform
                    my $thisPlatform;
                    my $thisMachine;
                    my $thisTask;
                    if(/\[(.+?)\]/) {
                        $thisTask=$1;
                        ($thisMachine) = $thisTask =~ /^(.+?)\./;
                        foreach my $platform (@sortedPLATFORMS) {
                            if($thisTask =~ /$platform/) {
                                $thisPlatform = $platform;
                            }
                        }
                    }
                    #print "1: $thisPlatform $thisMachine $thisTask\n" if($thisPlatform =~ /^win/i);
                    if($thisPlatform) {
                        unless(grep /^$thisMachine$/,
                                    @{$PLATFORMS{$thisPlatform}}) {
                            push(@{$PLATFORMS{$thisPlatform}},$thisMachine);
                        }
                    }
                    if($thisMachine) {
                        unless(grep /^$thisMachine$/,
                                    @{$JOBS{$start}}) {
                            push(@{$JOBS{$start}},$thisMachine)
                        }
                        $previousMachine=$thisMachine;
                    }
                    if($thisTask) {
                        unless(grep /^$thisTask$/,
                                    @{$BLDMACHINES{$thisMachine}}) {
                            push(@{$BLDMACHINES{$thisMachine}},$thisTask)
                        }
                        $previousTask = $thisTask;
                        $StartsMachinesTasks{$thisMachine}{$thisTask}
                                      =$start;
                    }
                    # get waitfor
                    my $thisWaitFor;
                    if(/^\s+waitfor\s+\=\s+(.+?)$/) {
                        $thisWaitFor=$1;
                        unless(grep /^$thisWaitFor$/,
                                    @{$TASKS{$previousTask}}) {
                            push(@{$TASKS{$previousTask}},$thisWaitFor)
                        }
                    }
                    # get cmd
                    my $thisCmd;
                    if(/^\s+command\s+\=\s+(.+?)$/) {
                        $thisCmd=$1;
                        ($thisCmd) =~ s-\&-\&amp\;-g;   #escape &
                        ($thisCmd) =~ s-\>-\&gt\;-g;    #escape >
                        ($thisCmd) =~ s-\$-\&\#36\;-g;  #escape $
                        $thisCmd   = "${thisCmd} start $start";
                        $CMDS{$previousTask} = $thisCmd;
                    }
                    # get build
                    my $thisBuild;
                    if(/contexts\/(.+?).ini\s+/i) {
                        $thisBuild=$1;
                    }
                    elsif(/contexts\\(.+?).ini\s+/i) {
                        $thisBuild=$1;
                    }
                    if($thisBuild) {
                        unless(grep /^$thisBuild$/,
                                    @{$BUILDS{$previousMachine}}) {
                            push(@{$BUILDS{$previousMachine}},$thisBuild);
                        }
                        unless(grep /^$previousTask$/,
                                    @{$BuildsTasks{$thisBuild}}) {
                            push(@{$BuildsTasks{$thisBuild}},$previousTask);
                            $StartsBuildsTasks{$thisBuild}{$previousTask}=$start;
                            push(@{$JobsTasksBuild{$start}{$thisBuild}},$previousTask);
                        }
                        unless(grep /^$previousMachine$/,
                                    @{$BUILDMACHINES{$thisBuild}}) {
                            push(@{$BUILDMACHINES{$thisBuild}},$previousMachine);
                        }
                    }
                }
                close(JOB_FILE);
            }
        }
    } #end foreach

    GetAllIP();
} # end sub


sub WriteTitle($) {
    (my $Title) = @_;
    print "<center><h1>$Title</h1></center>\n";
    print "<br/>\n";
}

sub GetBuildTaskStatus($) {
    (my $thisBuild) = @_;
    my $localSite = lc($PrefixSite);
    my $nbTotalTasksPerBuild = 0;
    my $nbTaskDone = 0;
    my $nbTaskInpg = 0;
    my $nbTaskNotStarted = 0;
    while( ($task, $startTime) =
        each(%{$StartsBuildsTasks{$thisBuild}}) ) {
        $nbTotalTasksPerBuild++;
        my $task2 = lc($task);
        if( -e "$EVENTS_DIR/${localSite}_$startTime/$task2") {
            $nbTaskDone++;
        } else {
            if( -e "$EVENTS_DIR/${localSite}_$startTime/$task2.inpg") {
                $nbTaskInpg++;
            } else {
                $nbTaskNotStarted++;
            }
        }
    }
    my $status = "";
    if($nbTotalTasksPerBuild == $nbTaskDone) {
        $status = "<img src=\"$IMG_SRC/jvCheck.gif\" alt=\"Done\""
                . "title=\"nb total tasks: $nbTotalTasksPerBuild,"
                . " $nbTotalTasksPerBuild Done\" border=\"0\" />"
                ;
    } else {
        if($nbTaskNotStarted == $nbTotalTasksPerBuild) {
            $status = "<img src=\"$IMG_SRC/jvStar_blue.gif\""
                    . "alt=\"Not Started\" title=\"nb total tasks:"
                    . " $nbTotalTasksPerBuild, 0 Not Started\""
                    . " border=\"0\" />"
                    ;
        } else {
            $status = "<img src=\"$IMG_SRC/jvStar_yellow.gif\""
                    . " alt=\"Inpg\" title=\"nb total tasks:"
                    . " $nbTotalTasksPerBuild,  $nbTaskDone Done"
                    . ", $nbTaskNotStarted Not Started"
                    . " and $nbTaskInpg In Progress ...\" border=\"0\" />"
                    ;
        }
    }
    return $status;
}

sub GetMachineTaskStatus($) {
    (my $thisMachine)        = @_;
    my $localSite            = lc($PrefixSite);
    my $nbTotalTasksPerBuild = 0;
    my $nbTaskDone           = 0;
    my $nbTaskInpg           = 0;
    my $nbTaskNotStarted     = 0;
    while( ($task, $startTime) =
        each(%{$StartsMachinesTasks{$thisMachine}}) ) {
        $nbTotalTasksPerBuild++;
        my $task2 = lc($task);
        if( -e "$EVENTS_DIR/${localSite}_$startTime/$task2") {
            $nbTaskDone++;
        } else {
            if( -e "$EVENTS_DIR/${localSite}_$startTime/$task2.inpg") {
                $nbTaskInpg++;
            } else {
                $nbTaskNotStarted++;
            }
        }
    }
    my $status = "";
    if($nbTotalTasksPerBuild == $nbTaskDone) {
        $status = "<img src=\"$IMG_SRC/jvCheck.gif\""
                . " alt=\"Done\" title=\"nb total tasks:"
                . " $nbTotalTasksPerBuild, $nbTotalTasksPerBuild"
                . " Done\" border=\"0\" />"
                ;
    } else {
        if($nbTaskNotStarted == $nbTotalTasksPerBuild) {
            $status = "<img src=\"$IMG_SRC/jvStar_blue.gif\""
                    . " alt=\"Not Started\" title=\"nb total tasks:"
                    . " $nbTotalTasksPerBuild,"
                    . " 0 Not Started\" border=\"0\" />"
                    ;
        } else {
            $status = "<img src=\"$IMG_SRC/jvStar_yellow.gif\""
                    . " alt=\"Inpg\" title=\"nb total tasks:"
                    . " $nbTotalTasksPerBuild, $nbTaskDone Done,"
                    . " $nbTaskNotStarted Not Started and"
                    . " $nbTaskInpg In Progress"
                    . " ...\" border=\"0\" />"
                    ;
        }
    }
    return $status;
}

sub GetStatusTask($$) {
    my ($startTime,$task) = @_;
    my $status = "";
    if($task=~/^jobs\/(.+?)\.txt\:/) {
        $startTime = $1;
        ($startTime) =~ s/^$SITE\_//;
        ($task) =~ s/^jobs.+?\://;
    }
    my $localSite = lc($PrefixSite);
    ($task) = lc($task);
    if( -e "$EVENTS_DIR/${localSite}_$startTime/$task") {
        $status = "<img src=\"$IMG_SRC/jvCheck.gif\""
                . " alt=\"Done\" title=\"Done\" />"
                ;
    } else {
        if( -e "$EVENTS_DIR/${localSite}_$startTime/$task.inpg") {
        $status = "<img src=\"$IMG_SRC/jvStar_yellow.gif\""
                . " alt=\"Inpg\" title=\"In Progress ...\" />"
                ;
        } else {
                $status = "<img src=\"$IMG_SRC/jvStar_blue.gif\""
                        . " alt=\"Not Started\""
                        . " title=\"Not Started\" />"
                        ;
            }
    }
    return $status;
}

sub GetAllBuildsRev() {
    foreach my $Build (sort(keys(%BuildsTasks))) {
        my $bldRev = GetBuildRev($Build);
        $BuildsRev{$Build}=$bldRev;
    }
}

sub GetBuildRev($) {
    (my $thisBuildName) = @_;
    my $tmpBuildRev;
    if(opendir(CISDIR,"$CIS_DIR/$thisBuildName")) {
        my $oldIndice = "00000";
        while(defined(my $buildCIS = readdir(CISDIR))) {
            next if( -f "$CIS_DIR/$thisBuildName/$buildCIS" );
            next if($buildCIS =~ /^\./);
            ($buildCIS) =~ s-\.\d+$--;
            if( -d "$CIS_DIR/$thisBuildName/$buildCIS" ) {
                (my $tmpIndice) = $buildCIS =~ /\_(\d+)$/;
                if($tmpIndice > $oldIndice) {
                    $tmpBuildRev = $buildCIS;
                    $oldIndice = $tmpIndice;
                }
            }
        }
        closedir(CISDIR);
    }
    return $tmpBuildRev if($tmpBuildRev);
}

sub GetAllIP() {
    if( ! -e "./jv_table_adresses_ip.txt" ) {
        if(open(IPS,">jv_table_adresses_ip.txt")) {
            foreach my $buildMachine (keys(%BLDMACHINES)) {
                $IPS{$buildMachine} = GetIP($buildMachine);
                print IPS "$buildMachine=$IPS{$buildMachine}\n";
            }
            close(IPS);
        } else {
            foreach my $buildMachine (keys(%BLDMACHINES)) {
                $IPS{$buildMachine} = GetIP($buildMachine);
            }
        }
    } else {
        if(open(IPS,"./jv_table_adresses_ip.txt")) {
            while(<IPS>) {
                chomp;
                my ($machine,$ip) = $_ =~ /^(.+?)\=(.+?)$/;
                $IPS{$machine} = $ip;
            }
            close(IPS);
        }
    }
}

sub GetIP($) {
    (my $thisBuildMachine) = @_;
    my $ip;
    if( -e "./jv_table_adresses_ip.txt" ) {
        if(open(IPS,"./jv_table_adresses_ip.txt")) {
            while(<IPS>) {
                chomp;
                if(/^$thisBuildMachine/) {
                    ($ip) = $_
                          =~ /^$thisBuildMachine\=(.+?)$/;
                }
            }
            close(IPS);
        }
        unless($ip) {
            $ip = NSLOOKUP($thisBuildMachine,0);
        }
    } else {
        $ip = NSLOOKUP($thisBuildMachine,0);
    }
    return $ip
}

sub NSLOOKUP($$) {
    my ($thisBuildMachine,$updateFile) = @_;
    my $tmpIP;
    if(open(NSLOOKUPCMD,"$NSLOOKUP_CMD $thisBuildMachine|")) {
        while(<NSLOOKUPCMD>) {
            chomp;
            next unless(/^Address/);
            s/\#\d+$//;
            ($tmpIP) = $_ =~ /^Address\:\s+(.+?)$/;
        }
        close(NSLOOKUPCMD);
        if($updateFile == 1) {
            if(open(IPS,">>jv_table_adresses_ip.txt")) {
                print IPS "$thisBuildMachine=$tmpIP\n";
            }
            close(IPS);
        }
    } else {
        $tmpIP = "not found";
    }
    return $tmpIP;
}
