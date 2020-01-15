#!/usr/bin/perl

##############################################################################
##############################################################################
##### declare uses

use IO::File;
use Getopt::Long;
use File::Basename;
use File::Spec::Functions;

use Time::Local;

use CGI 'param';



##############################################################################
##############################################################################
##### declare vars

# for the script itself
use vars qw (
    $CURRENTDIR
    $configFile
    $Site
    %Tasks
    %AllTasks
    %AllTasksJobs
    %AllStatus
    $HTML
    %matchStatusImgs
    %BuildsPlatformMachines
    %MachineBuilds
    $SUB_BUILD
    $AREA
    %AllTaskForABuild
);

# in jvPaths.txt
use vars qw (
    $configFile
    $PREFIXSITE
    $CIS_HTTP_DIR
    $TORCH_HTTP_DIR
    $CIS_DIR
    $JOBS_DIR
    $EVENTS_DIR
    $IMG_SRC
    $P4CLIENT
    $CBTPATH
);

# opt
use vars qw (
    $mainLists
    $opt_job
    $opt_build
    $opt_machine
);

# starting point for search
use vars qw (
    @JOBS
    %MACHINES
    %PLATFORMS_MACHINES
    %BUILDS
    $PLATFORM
    $OBJECT_MODEL
    $Model
    $Info
    %OS_FAMILIES
    $opt_Task
    $opt_OS_FAMILY
    $opt_TasksBuild
);



##############################################################################
##############################################################################
##### declare subs
# list
sub getListJobsFile();
sub getListMachines();
sub getListBuilds();
sub getListProjectsBuilds();
sub getTasksOfBuild($);
sub getListTasks();

sub getCmdJob($);
sub getWaitForsJob($);
sub getStatusJob($);

sub getTasks($);
sub getStatusTask($$$$);
sub getDeps($$$$$);

sub timeTask($$);

sub gen_ID();

sub TransformDateToSeconds($$);



##############################################################################
##############################################################################
##### get options/parameters
if(@ARGV){
    $Getopt::Long::ignorecase = 0;
    GetOptions(
        "c=s"   =>\$configFile,
        "s=s"   =>\$Site,
        "l=s"   =>\$mainLists,
        "j=s"   =>\$opt_job,
        "b=s"   =>\$opt_build,
        "m=s"   =>\$opt_machine,
        "i=s"   =>\$Info,
        "t=s"   =>\$opt_Task,
        "o=s"   =>\$opt_OS_FAMILY,
        "html"  =>\$HTML,
        "tb=s"  =>\$opt_TasksBuild,
    );
}
else {
    $configFile       = param('config');
    $Site             = param('site');
    $mainLists      ||= param('mainlists');
    $opt_job          = param('jobs');
    $opt_build      ||= param('build');
    $opt_machine      = param('machine');
    $Info           ||= param('info');
    $opt_Task       ||= param('task');
    $opt_OS_FAMILY  ||= param('osfamily');
}



##############################################################################
##############################################################################
##### inits

$configFile ||= "./jvPaths.txt";
$Site       ||= $ENV{Site} || "Walldorf";

if(open CONFIG,$configFile) {
    my $flagSite = 0;
    while(<CONFIG>) {
        chomp;
        next unless($_);
        next if(/^\#/);
        if(/^\[(.+?)\]/){
            if($Site eq $1) {
                $flagSite = 1;
                next;
            }
            else {
                $flagSite = 0;
            }
            next;
        }
        s-\s+\#.+?$--;
        ${$1} = $2 if((/^(.+?)\s+\=\s+(.+?)$/) && ($flagSite == 1));
    }
    close CONFIG;
}

$OBJECT_MODEL = $Model ? "64" : "32" if(defined $Model);
unless($PLATFORM) {
       if($^O eq "MSWin32") { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64"       : "win32_x86"       }
    elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc"   }
    elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64"   : "aix_rs6000"      }
    elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64"       : "hpux_pa-risc"    }
    elsif($^O eq "linux")   { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64"       : "linux_x86"       }
    elsif($^O eq "darwin")  { $PLATFORM = $OBJECT_MODEL==64 ? "mac_x64"         : "mac_x86"         }
}

$matchStatusImgs{'done'} = "jvCheck.gif";
$matchStatusImgs{'in progress'} = "jvStar_yellow.gif";
$matchStatusImgs{'not started'} = "jvStar_blue.gif";



##############################################################################
##############################################################################
##### MAIN

if($opt_TasksBuild) {
    &getListJobsFile();
    &getListBuilds();
    &getTasksOfBuild($opt_TasksBuild);
    foreach my $taskBuild (sort @{$AllTaskForABuild{$opt_TasksBuild}}) {
        print "$taskBuild";
        unless($opt_job) {
            my $result = `grep -l \"$taskBuild\" $JOBS_DIR/*.* | grep -wvi waitfor`;
            chomp($result);
            if($result) {
                $opt_job = basename $result;
            }
        }
        if($opt_job) {
            my $status = &getStatusTask("$taskBuild","$opt_job",0,0);
            print ",$status" if($status);
        }
        print "\n";
    }
    exit;
}

if($opt_Task) {
    unless($opt_job) {
        my $result = `grep -l \"$opt_Task\" $JOBS_DIR/*.* | grep -wvi waitfor`;
        chomp($result);
        if($result) {
            $opt_job = basename $result;
        }
        else {
            print "$opt_Task not found in any job files\n";
            exit;
        }
    }
    &getTasks("job:$opt_job");
    #my $status = &getStatusTask("$opt_Task","$opt_job",1);
    #print "$status" if($status);
    exit;
}

&getListJobsFile();

if($Info && ($Info =~ /^os\_family$/i)) {
    &getListMachines();
    foreach my $os_family (sort keys %OS_FAMILIES) {
        print "$os_family\n";
    }
    exit;
}

if($Info && ($Info =~ /^tasks$/i)) {
    &getListMachines();
    foreach my $task (sort keys %AllTasks) {
        print "$task\n";
    }
    exit;
}

if($Info && ($Info =~ /^lbom$/i) && $opt_machine) { # list builds on a machine
    &getListMachines();
    foreach my $machine (sort keys %MachineBuilds) {
        foreach my $build (sort @{$MachineBuilds{$machine}}) {
            print "$build\n";
        }
    }
    exit;
}

if($Info && ($Info =~ /^lmob$/i) && $opt_build) { # list machines on a build
    &getListMachines();
    foreach my $os_family (sort keys %{$BuildsPlatformMachines{$opt_build}}) {
        if(scalar @{$BuildsPlatformMachines{$opt_build}{$os_family}} > 0) {
            print "os_family: $os_family\n";
            foreach my $machine (sort @{$BuildsPlatformMachines{$opt_build}{$os_family}}) {
                print "machine: $machine\n";
            }
        }
    }
    exit;
}

&getListBuilds()         if(($mainLists) && ($mainLists eq "builds"));
&getListMachines()       if(($mainLists) && ($mainLists eq "machines"));
&getListTasks()          if(($mainLists) && ($mainLists eq "tasks"));
&getListProjectsBuilds() if(($mainLists) && ($mainLists eq "allbuilds"));

if($mainLists && ($mainLists eq "jobs")) {
    print "\n";
    foreach my $jobFile (sort(@JOBS)) {
        print "$jobFile\n";
    }
}

if($mainLists && ($mainLists eq "builds")) {
    foreach my $buildName (sort(keys(%BUILDS))) {
        print "$buildName\n";
    }
}

if($mainLists && ($mainLists eq "allbuilds")) {
    foreach my $projet (sort(keys(%BUILDS))) {
        print "p : $projet\n";
        foreach my $build (sort(@{$BUILDS{$projet}})) {
            print "\tb : $build\n";
        }
    }
}

if($mainLists && ($mainLists eq "machines") && (! $opt_OS_FAMILY)) {
    print "\n";
    foreach my $buildMachine (sort keys %MACHINES) {
        print "$buildMachine\n";
    }
}
if($mainLists && ($mainLists eq "machines") && $opt_OS_FAMILY) {
    foreach my $os_family (sort keys %OS_FAMILIES) {
        if($opt_OS_FAMILY eq $os_family) {
            foreach my $buildMachine (sort @{$OS_FAMILIES{$os_family}}) {
                print "$buildMachine\n";
            }
        }
    }
}

&getTasks("job:$opt_job")         if($opt_job && (! $opt_Task));
&getTasks("build:$opt_build")     if($opt_build);
&getTasks("machine:$opt_machine") if($opt_machine);


exit;



##############################################################################
### my functions
sub getListJobsFile() {
    if(opendir JOBS,$JOBS_DIR) {
        while(defined(my $file = readdir JOBS)) {
            push @JOBS,$file if($file =~ /^$PREFIXSITE/);
        }
        closedir JOBS;
    }
}

sub getListMachines() {
    chdir $CBTPATH or die "ERROR : cannot chdir into '$CBTPATH' :$!";
    $CURRENTDIR = $CBTPATH;
    my %tmp_lbom;
    my %tmp_lmob;
    foreach my $jobFile (sort @JOBS) {
        if(open JOB,"$JOBS_DIR/$jobFile") {
            my $machine ;
            my $os_family;
            my $buildName;
            my $firstMachine;
            while(<JOB>) {
                chomp;
                next if(/^\;/);
                my $line = $_;
                next if($line =~ /^\s+waitfor/i);
                if($Info && ($Info =~ /^tasks$/i)) {
                    $AllTasks{$1} = 1 if($line =~ /^\[(.+?)\]/i);
                }
                if($line =~ /^\[(.+?)\./i) {
                    $machine = $1;
                    next if($opt_machine && (!($machine =~ /^$opt_machine$/i)));
                    $MACHINES{$machine} = 1;
                    if ($opt_OS_FAMILY || ($Info && (($Info =~ /^os\_family$/i) || ($Info =~ /^lmob$/i)))){
                        $os_family = "";
                        if($line =~ /\.aix/i) {
                            $os_family = "aix" ;
                        }
                        elsif ($line =~ /\.hp/i) {
                            $os_family = "hpux" ;
                        }
                        elsif ($line =~ /\.linux/i) {
                            $os_family = "linux" ;
                        }
                        elsif ($line =~ /\.mac/i) {
                            $os_family = "macOS" ;
                        }
                        elsif ($line =~ /\.solaris/i) {
                            $os_family = "solaris" ;
                        }
                        elsif ($line =~ /\.win/i) {
                            $os_family = "windows" ;
                        }
                        if($os_family) {
                            unless(grep /^$machine$/ , @{$OS_FAMILIES{$os_family}}) {
                                push @{$OS_FAMILIES{$os_family}},$machine;
                            }
                        }
                    }
                    next;
                }
                if($Info && ($Info =~ /^lbom$/i) && $opt_machine) { #list builds on a machine
                    next if(!($machine =~ /^$opt_machine$/i));
                    next if(!($line =~ /Build\.pl/i));
                    my $line2 = $line;
                    ($line2) =~ s-\\-\/-g;
                    my $ini = $1 if($line2 =~ /contexts\/(.+?)\s+/i);
                    if($ini) {
                        my $tmp = "${ini}_$machine";
                        next if($tmp_lbom{$tmp});
                        if ( -e "$CBTPATH/contexts/$ini") {
                            $buildName = &ReadIni("$CBTPATH/contexts/$ini","build");
                            unless (grep /^$buildName$/i,@{$MachineBuilds{$opt_machine}}) {
                                push @{$MachineBuilds{$opt_machine}},$buildName;
                                $tmp_lbom{$tmp}=1;
                            }
                        }
                    }
                    next;
                }
                if($Info && ($Info =~ /^lmob$/i) && $opt_build) { #list machines of a build
                    next if($line =~ /^\s+waitfor/i);
                    next if(!($line =~ /Build\.pl/i));
                    next if(grep /^$machine$/i,@{$BuildsPlatformMachines{$opt_build}{$os_family}});
                    my $line2 = $line;
                    ($line2) =~ s-\\-\/-g;
                    $SUB_BUILD  = $1 if($line2 =~ /SUB_BUILD\=(.+?)\&/i);
                    $AREA       = $1 if($line2 =~ /AREA\=(.+?)\&/i);
                    my $ini     = $1 if($line2 =~ /contexts\/(.+?)\s+/i);
                    if($ini) {
                        my $tmp = "${ini}_${opt_build}_${os_family}_$machine";
                        next if($tmp_lmob{$tmp});
                        if ( -e "$CBTPATH/contexts/$ini") {
                            $buildName = &ReadIni("$CBTPATH/contexts/$ini","build");
                            if($buildName =~ /^$opt_build$/i) {
                                unless (grep /^$machine$/i,@{$BuildsPlatformMachines{$opt_build}{$os_family}}) {
                                    push @{$BuildsPlatformMachines{$opt_build}{$os_family}},$machine;
                                    $tmp_lmob{$tmp}=1;
                                }
                            }
                        }
                    }
                    next;
                }
            }
            close JOB;
        }
    }
}


sub getListBuilds() {
    my %tmpInis;
    chdir $CBTPATH or die "ERROR : cannot chdir into '$CBTPATH' :$!";
    $CURRENTDIR = $CBTPATH;
    foreach my $jobFile (sort @JOBS) {
        if(open JOB,"$JOBS_DIR/$jobFile") {
            while(<JOB>) {
                chomp;
                next if(/^\;/);
                next unless(/Build\.pl/i);
                s-\\-\/-g;
                $SUB_BUILD  = $1 if(/SUB_BUILD\=(.+?)\&/i);
                $AREA       = $1 if(/AREA\=(.+?)\&/i);
                my $ini     = $1 if(/contexts\/(.+?)\s+/i);
                if($ini) {
                    unless($tmpInis{$ini}) {
                        if ( -e "$CBTPATH/contexts/$ini") {
                            my $buildName = &ReadIni("$CBTPATH/contexts/$ini","build");
                            $BUILDS{$buildName} = $ini  if($buildName);
                            $tmpInis{$ini} = $buildName if($buildName);
                        }
                    }
                }
            }
            close JOB;
        }
    }
}

sub getListTasks() {
    chdir $CBTPATH or die "ERROR : cannot chdir into '$CBTPATH' :$!";
    $CURRENTDIR = $CBTPATH;
    foreach my $jobFile (sort @JOBS) {
        if(open JOB,"$JOBS_DIR/$jobFile") {
            print "j : $jobFile\n";
            while(<JOB>) {
                chomp;
                next if(/^\;/);
                next if(/^\[config\]/i);
                if(/^\[(.+?)\]/i) {
                    print "t : $1\n";
                }
            }
        }
        close JOB;
    }
    #OS_FAMILIES
}

sub getListProjectsBuilds() {
    my %tmpInis;
    chdir $CBTPATH or die "ERROR : cannot chdir into '$CBTPATH' :$!";
    $CURRENTDIR = $CBTPATH;
    foreach my $jobFile (sort @JOBS) {
        if(open JOB,"$JOBS_DIR/$jobFile") {
            while(<JOB>) {
                chomp;
                next if(/^\;/);
                next unless(/Build\.pl/i);
                s-\\-\/-g;
                $SUB_BUILD  = $1 if(/SUB_BUILD\=(.+?)\&/i);
                $AREA       = $1 if(/AREA\=(.+?)\&/i);
                my $ini = $1 if(/contexts\/(.+?)\s+/i);
                if($ini) {
                    unless($tmpInis{$ini}) {
                        if ( -e "$CBTPATH/contexts/$ini") {
                            my $buildName = &ReadIni("$CBTPATH/contexts/$ini","build");
                            if($buildName) {
                                my $project = &ReadIni("$CBTPATH/contexts/$ini","project");
                                if($project) {
                                    unless(grep /^$buildName$/,@{$BUILDS{$project}}) {
                                        push @{$BUILDS{$project}},$buildName;
                                    }
                                    $tmpInis{$ini} = $buildName if($buildName);
                                }
                            }
                        }
                    }
                }
            }
            close JOB;
        }
    }
}

sub getTasksOfBuild($) {
    my ($thisBuild) = @_;
    my $thisIni = $BUILDS{$thisBuild};
    foreach my $jobFile (sort @JOBS) {
        if(open JOB,"$JOBS_DIR/$jobFile") {
            my $task;
            while(<JOB>) {
                chomp;
                next unless($_);
                next if(/^\;/);
                my $line = $_;
                if($line =~ /^\[(.+?)\]$/i) {
                    $task = $1;
                    next;
                }
                ($line) =~ s-\\-\/-g;
                if($line =~ /^\s+command\s+\=\s+/i) {
                    next unless($task);
                    if($line =~ /contexts\/(.+?)\s+/i) {
                        my $ini = $1 ;
                        if($ini =~ /^$thisIni$/i) {
                            if($task) {
                                unless(grep /^$task$/,@{$AllTaskForABuild{$thisBuild}}) {
                                    push @{$AllTaskForABuild{$thisBuild}},$task;
                                }
                            }
                        }
                        next;
                    }
                    next;
                }
            }
        }
        close JOB;
    }
}

sub getTasks($) {
    my ($elem) = @_;
    my @jobFilesToSearch;
    my %Cmds;
    my %OffSet;
    my ($sourceElem,$pattern) = split ':',$elem;
    if($elem =~ /^job\:(.+?)$/i) {
        my $tmp = $1;
        ($tmp) =~ s-^$PREFIXSITE\_--i;
        ($tmp) =~ s-\.txt$--i;
        push @jobFilesToSearch,$tmp;
    }
    else {
        my @reps = `grep -wl \"$pattern\" $JOBS_DIR/*`;
        foreach my $rep (sort(@reps)) {
            chomp $rep;
            (my $order = $rep)  =~ s-^$JOBS_DIR\/$PREFIXSITE\_--i;
            ($order) =~ s-\.txt$--i;
            push @jobFilesToSearch,$order;
        }
    }
    foreach my $jobFile (sort @jobFilesToSearch) {
        if(open JOB,"$JOBS_DIR/${PREFIXSITE}_$jobFile.txt") {
            my $flag = 0;
            my $taskFound;
            while(<JOB>) {
                chomp;
                next if(/^\;/);
                next if(/^\[config\]/i);
                if(/^\[(.+?)\]/i) {
                    $taskFound = $1;
                    if($opt_job) {
                        if($opt_Task) {
                            next if(!($opt_Task =~ /^$taskFound$/i));
                        }
                        push @{$Tasks{$jobFile}},$taskFound;
                        $flag = 1;
                    }
                    else {
                        if($taskFound =~ /$pattern\./i) {
                            push @{$Tasks{$jobFile}},$taskFound;
                            $flag = 1;
                        }
                        else {
                            $flag = 0;
                        }
                    }
                }
                if(($flag == 1) && $taskFound) {
                    push @{$taskFound},$1    if(/^?\s+waitfor\s+\=\s+(.+?)$/i);
                    $Cmds{$taskFound}   = $1 if(/^?\s+command\s+\=\s+(.+?)$/i);
                    $OffSet{$taskFound} = $1 if(/^?\s+start_offset\s+\=\s+(.+?)$/i);
                }
            }
            close JOB;
        }
    }

    my $mainNbDone  = 0;
    my $mainNbInpg  = 0;
    my $mainNbToDo  = 0;

    if(scalar keys %Tasks > 0) {
        my $start = 0;
        ###foreach jobs
        foreach my $job (reverse keys %Tasks) {
            ###job
            my $nbDone  = 0;
            my $nbInpg  = 0;
            my $nbToDo  = 0;
            my $nbTotal = 0;
            foreach my $task (@{$Tasks{$job}}) {
                my $status = ($AllTasks{$task}) ? $AllTasks{$task}
                             : &getStatusTask($task,"${PREFIXSITE}_$job",0,0);
                $AllTasks{$task} = $status unless($AllTasks{$task});
                $AllTasksJobs{$task} ||= $job;
                $nbDone++ if($status =~ /^done$/i);
                $nbInpg++ if($status =~ /^in progress$/i);
                $nbToDo++ if($status =~ /^not started$/i);
                $nbTotal++;
            }
            $mainNbDone = $mainNbDone + $nbDone;
            $mainNbInpg = $mainNbInpg + $nbInpg;
            $mainNbToDo = $mainNbToDo + $nbToDo;
            if($HTML) {
                my $displayJobBlock = ($start == 0) ? "block" : "none";
                print "<fieldset><legend><span onclick=\"document.getElementById('${PREFIXSITE}_$job').style.display = (document.getElementById('${PREFIXSITE}_$job').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">&nbsp;<strong>${PREFIXSITE}_$job.txt";
                if($nbDone > 0) {
                    print " - $nbDone <font color=\"green\">done</font>";
                }
                if($nbInpg > 0) {
                    print " - $nbInpg <font color=\"#FF8C00\">in progress</font>";
                }
                if($nbToDo > 0) {
                    print " - $nbToDo <font color=\"blue\">not started</font>";
                }
                print " - total : $nbTotal</strong></span></legend>\n";
                print "<div id=\"${PREFIXSITE}_$job\" style=\"display:none\">\n";
                $start = 1;
            }
            else {
                print "job: ${PREFIXSITE}_$job.txt\n";
            }
            foreach my $task (@{$Tasks{$job}}) {
                my $status = ($AllTasks{$task}) ? $AllTasks{$task}
                             : &getStatusTask($task,"${PREFIXSITE}_$job",0,0);
                $AllTasks{$task} = $status unless($AllTasks{$task});
                $AllTasksJobs{$task} ||= $job;
                ###main task
                if($HTML) {
                    my $dateTimeTask = &timeTask($task,"${PREFIXSITE}_$job");
                    print "<ul class=\"mktree\" id=\"$task\">\n";
                    if($status  =~ /^done$/i) {
                        print "\t<li><a id=\"aId_$task\">$task</a>&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$status}\" alt=\"$dateTimeTask\" />\n";
                    }
                    else {
                        print "\t<li class=\"liOpen\"><a id=\"aId_$task\">$task</a>&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$status}\" alt=\"$dateTimeTask\" />\n";
                    }
                    my $cmd = $Cmds{$task};
                    my $offset = $OffSet{$task} if($OffSet{$task});
                    print "\t<br/><font size=\"2\" color=\"#98AFC7\">start offset = $offset</font>\n" if($OffSet{$task});
                    print "\t<br/><font size=\"2\" color=\"gray\">cmd = $cmd</font>\n";
                }
                else {
                    print "  * $task ---> $status\n";
                    print "  cmd = $Cmds{$task}\n";

                }
                ###dependecies
                my $nbDeps = 0;
                foreach my $dep (@{$task}) {
                    $nbDeps++;
                    my $realDep = $dep;
                    my $realJob = "${PREFIXSITE}_$job";
                    if($dep=~ /^jobs\/(.+?)\:(.+?)$/i) {
                        $realJob = $1;
                        $realDep = $2;
                    }
                    my $depStatus = ($AllTasks{$realDep})
                                    ? $AllTasks{$realDep}
                                    : &getStatusTask($realDep,$realJob,0,0);
                    $AllTasks{$realDep} = $status unless($AllTasks{$realDep});
                    if($HTML) {
                        my $dateTimeTask = &timeTask($realDep,"${PREFIXSITE}_$job");
                        print "\t<ul>\n";
                        if($depStatus  =~ /^done$/i) {
                            print "\t\t<li><a href=\"#aId_$realDep\">$realDep</a>&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$depStatus}\" alt=\"$dateTimeTask\" />\n";
                        }
                        else {
                            print "\t\t<li class=\"liOpen\"><a href=\"#aId_$realDep\">$realDep</a>&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$depStatus}\" alt=\"$dateTimeTask\" />\n";
                        }
                    }
                    else {
                        print "    +- $realDep ---> $depStatus\n";
                    }
                    $AllTasksJobs{$realDep} ||= $realJob;
                    &getDeps($realDep,$realJob,6,$nbDeps,"aId");
                    if($HTML) {
                        print "\t\t</li>\n";
                        print "\t</ul>\n";
                    }
                }
                print "\t</li>\n" if($HTML);
                print "</ul>\n"   if($HTML);
                #print "cmd : $Cmds{$task}\n";
                unless($HTML) { print "\n"; }
            }
            print "</div></fieldset>\n" if($HTML);
        }
    }

    #show per os_family
    if($HTML && ($sourceElem ne "machine")) {
        my %thisPlatforms;
        foreach my $job (reverse keys %Tasks) {
            foreach my $task (@{$Tasks{$job}}) {
                my $status = ($AllTasks{$task})
                             ? $AllTasks{$task}
                             : &getStatusTask($task,"${PREFIXSITE}_$job",0,0);
                $AllTasks{$task} = $status unless($AllTasks{$task});
                $AllTasksJobs{$task} ||= $job;
                my $os_family;
                if($task =~ /\.aix/i) {
                    $os_family = "aix" ;
                }
                elsif ($task =~ /\.hp/i) {
                    $os_family = "hpux" ;
                }
                elsif ($task =~ /\.linux/i) {
                    $os_family = "linux" ;
                }
                elsif ($task =~ /\.mac/i) {
                    $os_family = "macOS" ;
                }
                elsif ($task =~ /\.solaris/i) {
                    $os_family = "solaris" ;
                }
                elsif ($task =~ /\.win/i) {
                    $os_family = "windows" ;
                }
                if($os_family) {
                    push @{$thisPlatforms{$os_family}},"$task";
                    $stats{$os_family}{$status}++;
                }
            }
        }
        print "</br>\n";
        print "<fieldset><legend><span onclick=\"document.getElementById('os_families_$pattern').style.display = (document.getElementById('os_families_$pattern').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">&nbsp;<strong>Per OS_FAMILY</strong></span></legend>\n";
        print "<div id=\"os_families_$pattern\" style=\"display:none\">\n";
        print "<ul class=\"mktree\" id=\"tree_os_families_$pattern\">\n";
        foreach my $osFam (sort qw(aix hp linux macOS solaris windows)) {
            next unless(@{$thisPlatforms{$osFam}});
            my $sizeOSFam = scalar @{$thisPlatforms{$osFam}};
            if($sizeOSFam > 0) {
                my $overallOSFam;
                foreach my $status (sort keys %matchStatusImgs) {
                    if($stats{$osFam}{$status} == $sizeOSFam) {
                        $overallOSFam = $status;
                        last;
                    }
                    else {
                            $overallOSFam = "in progress";
                    }
                }
                if($overallOSFam eq "done") {
                    print "<li>$osFam &nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$overallOSFam}\" alt=\"$overallOSFam\" />\n";
                }
                else {
                    print "<li class=\"liOpen\">$osFam &nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$overallOSFam}\" alt=\"$overallOSFam\" />\n";
                }
                print "<ul>\n";
                foreach my $task (sort @{$thisPlatforms{$osFam}}) {
                    my $status = ($AllTasks{$task}) ? $AllTasks{$task} : &getStatusTask($task,"${PREFIXSITE}_$job",0,0);
                    if($status  =~ /^done$/i) {
                        print "\t<li><a id=\"osfId_$task\">$task</a>&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$status}\" alt=\"$dateTimeTask\" />\n";
                    }
                    else {
                        print "\t<li class=\"liOpen\"><a id=\"osfId_$task\">$task</a>&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$status}\" alt=\"$dateTimeTask\" />\n";
                    }
                    my $cmd = $Cmds{$task};
                    my $offset = $OffSet{$task} if($OffSet{$task});
                    print "\t<br/><font size=\"2\" color=\"#98AFC7\">start offset = $offset</font>\n" if($OffSet{$task});
                    print "\t<br/><font size=\"2\" color=\"gray\">cmd = $cmd</font>\n";
                    #deps
                    my $nbDeps = 0;
                    if(scalar @{$task} > 0) {
                        foreach my $dep (@{$task}) {
                            $nbDeps++;
                            my $realDep = $dep;
                            my $realJob = "${PREFIXSITE}_$job";
                            if($dep=~ /^jobs\/(.+?)\:(.+?)$/i) {
                                $realJob = $1;
                                $realDep = $2;
                            }
                            my $depStatus = ($AllTasks{$realDep}) ? $AllTasks{$realDep} : &getStatusTask($realDep,$realJob,0,0);
                            $AllTasks{$realDep} = $status unless($AllTasks{$realDep});
                            my $dateTimeTask = &timeTask($realDep,"${PREFIXSITE}_$job");
                            print "\t\t<ul>\n";
                            if($depStatus  =~ /^done$/i) {
                                print "\t\t\t<li><a href=\"#osfId_$realDep\">$realDep</a>&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$depStatus}\" alt=\"$dateTimeTask\" />\n";
                            }
                            else {
                                print "\t\t\t<li class=\"liOpen\"><a href=\"#osfId_$realDep\">$realDep</a>&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$depStatus}\" alt=\"$dateTimeTask\" />\n";
                            }
                            $AllTasksJobs{$realDep} ||= $realJob;
                            &getDeps($realDep,$realJob,6,$nbDeps,"osfId");
                            print "\t\t</li>\n";
                            print "\t\t</ul>\n";
                        }
                    }
                    print "\t</li>\n";
                }
                print "</ul>\n";
                print "</li>\n";
            }
        }
        print "</ul>\n";
        print "</div>\n";
        print "</fieldset>\n";
    }

    #show order

    if(scalar keys %AllTasks >0) {
        my %AllTimes;
        my @Pending;
        foreach my $task (sort keys %AllTasksJobs) {
            my $job = $AllTasksJobs{$task};
            ($job) =~ s-\.txt$--i;
            $job =  "${PREFIXSITE}_$job" if(!($job =~ /^$PREFIXSITE\_/i));
            if ( -e "$EVENTS_DIR/$job/$task") {
                if(open DONE,"$EVENTS_DIR/$job/$task") {
                    while(<DONE>) {
                        chomp;
                        if($_ =~ /^end_time\:\s+(.+?)\/(.+?)\/(.+?)\s+(.+?)\:(.+?)\:(.+?)\s+$Site$/i) {
                            my ($year,$month,$day,$hour,$min,$sec) = ($1,$2,$3,$4,$5,$6);
                            my $seconds = &TransformDateToSeconds("$year-$month-$day","$hour:$min:$sec");
                            #push @{$Ends{$seconds}},"$task done $day/$month/$year $hour:$min:$sec";
                            push @{$AllTimes{$seconds}},"$task done $day/$month/$year $hour:$min:$sec";
                            last;
                        }
                    }
                    close DONE;
                }
            }
            elsif ( -e "$EVENTS_DIR/$job/$task.inpg") {
                if(open INPG,"$EVENTS_DIR/$job/$task.inpg") {
                    while(<INPG>) {
                        chomp;
                        if($_ =~ /^start_time\:\s+(.+?)\/(.+?)\/(.+?)\s+(.+?)\:(.+?)\:(.+?)\s+$Site$/i) {
                            my ($year,$month,$day,$hour,$min,$sec) = ($1,$2,$3,$4,$5,$6);
                            my $seconds = &TransformDateToSeconds("$year-$month-$day","$hour:$min:$sec");
                            #push @{$Starts{$seconds}},"$task in progress since $day/$month/$year $hour:$min:$sec";
                            push @{$AllTimes{$seconds}},"$task in progress since $day/$month/$year $hour:$min:$sec";
                            last;
                        }
                    }
                    close INPG;
                }
            }
            else {
                push @Pending,"$task not started";
            }
        }
        if($HTML) {
            print "\n<br/>\n";
            print "<fieldset><legend><span onclick=\"document.getElementById('show_order').style.display = (document.getElementById('show_order').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">&nbsp;<strong>Order of jobs</strong></span></legend>\n";
            print "<div id=\"show_order\" style=\"display:none\">";
            print "order : from the most recent to the oldest:<br/><br/>\n";
        }
        else {
            print "\n==================================================\n\n";
        }
        my $total1 = scalar keys %AllTimes;
        my $total2 = scalar @Pending;
        my $total = $total1 + $total2;
        foreach my $dateTime (sort { $b<=>$a }(keys %AllTimes)) {
            foreach my $task (sort @{$AllTimes{$dateTime}}) {
                if($HTML) {
                    ($task) =~ s-done-<strong><font color=\"green\">done</font></strong>-;
                    ($task) =~ s-in progress-<strong><font color=\"#FF8C00\">in progress</font></strong>-;
                    print "$total - $task<br/>\n";
                }
                else {
                    print "$total - $task\n";
                }
            }
            $total--;
        }
        foreach my $pending (@Pending) {
            if($HTML) {
                ($pending) =~ s-not started-<strong><font color=\"blue\">not started</font></strong>-;
                print "$total - $pending<br/>\n";
            }
            else {
                print "$total - $pending\n";
            }
            $total--;
        }
        if($HTML) {
            print "</div>\n";
            print "</fieldset>\n";
        }
    }
    #"progress bar"
    if($HTML && (scalar keys %AllTasks > 0)) {
        my $subTitle = $opt_Task || $opt_build || $opt_machine || $opt_job;
        print "
<br/>
<fieldset><legend><span onclick=\"document.getElementById('progress_bar').style.display = (document.getElementById('progress_bar').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">&nbsp;<strong>Progression</strong></span></legend>
<div id=\"progress_bar\" style=\"display:none\">
";
        print "
        <script type=\"text/javascript\">
\$(function () {
        \$('#progress_bar_graph').highcharts({
            chart: {
                type: 'bar'
            },
            title: {
                text: 'Progression'
            },
            xAxis: {
                categories: ['$subTitle']
            },
            yAxis: {
                min: 0,
                title: {
                    text: 'Remaining'
                }
            },
            legend: {
                reversed: true
            },
            plotOptions: {
                series: {
                    stacking: 'normal'
                }
            },
                series: [
            {
                name: 'not started',
                data: [$mainNbToDo]
            },
            {
                name: 'in progress',
                data: [$mainNbInpg]
            },
            {
                name: 'done',
                data: [$mainNbDone]
            }
            ]
        });
    });
        </script>
        <center><div id=\"progress_bar_graph\" style=\"min-width: 310px; max-width: 800px; height: 200px; margin: 0 auto\"></div></center>
</div>
</fieldset>
";
    }
    #graph dep
    if($HTML && (scalar keys %AllTasks > 0)) {
        print "
<br/>
<fieldset><legend><span onclick=\"document.getElementById('graph_deps').style.display = (document.getElementById('graph_deps').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">&nbsp;<strong>graph_deps</strong></span></legend>
<div id=\"graph_deps\" style=\"display:block\">
    <script type=\"text/javascript\">
var redraw;
var height = 800;
var width = screen.width - 100;

window.onload = function() {

    var render = function(r, n) {
            var set = r.set().push(
                r.rect(n.point[0]-30, n.point[1]-13, 60, 44).attr({\"fill\": \"\#feb\", r : \"12px\", \"stroke-width\" : n.distance == 0 ? \"3px\" : \"1px\" })).push(
                r.text(n.point[0], n.point[1] + 10, (n.label || n.id) + \"\\n\" + (n.distance == undefined ? \"\" : n.distance) + \"\"));
            return set;
        };

    var g = new Graph();
    /* creating nodes and passing the new renderer function to overwrite the default one */
";
    foreach my $task (sort keys %AllTasks) {
        print "    g.addNode(\"$task\", {render:render});\n";
    }
    #end of graph js function
    print "
    /* modify the addEdge function to attach random weights */
    g.addEdge2 = g.addEdge;
    g.addEdge = function(from, to, style) { !style && (style={}); style.weight = Math.floor(Math.random()*10) + 1; g.addEdge2(from, to, style); };

    /* connections */
";
    foreach my $task (sort keys %AllTasks) {
        foreach my $dep (@{$task}) {
            print "    g.addEdge(\"$dep\", \"$task\", {weight:9, directed: true, stroke : \"black\"});\n";
        }
    }
    print "
    /* layout the graph using the Spring layout implementation */
    var layouter = new Graph.Layout.Spring(g);
    layouter.layout();

    /* draw the graph using the RaphaelJS draw implementation */
    var renderer = new Graph.Renderer.Raphael('canvas_graph_deps', g, width, height);
};

-->
    </script>
    <div id=\"canvas_graph_deps\"></div>
</div>
</fieldset>
";
    }
}


sub getStatusTask($$$$) {
    my ($thisTask,$thiJob,$CheckIfInJob,$verbose) = @_;
    if($CheckIfInJob == 1)  {
        $thiJob = "$thiJob.txt" if(!($thiJob =~ /\.txt$/i));
        my $result = `grep \"$thisTask\" $JOBS_DIR/$thiJob`;
        chomp $result;
        unless($result) {
            my $result2 = `grep -l \"$thisTask\" $JOBS_DIR/*.* | grep -wvi waitfor`;
            chomp $result2;
            if($result2) {
                $thiJob = basename $result2;
                print "\t!!! $thisTask is in $thiJob !!!\n" if($verbose == 1);
            }
            else {
                return "ERROR : $thisTask is not in $thiJob\n" ;
            }
        }
    }
    ($thiJob) =~ s-\.txt$--i;
    if( -e "$EVENTS_DIR/$thiJob") {
        return "done"        if ( -e "$EVENTS_DIR/$thiJob/$thisTask");
        return "in progress" if ( -e "$EVENTS_DIR/$thiJob/$thisTask.inpg");
        return "not started" if(( ! -e "$EVENTS_DIR/$thiJob/$thisTask.inpg") && ( ! -e "$EVENTS_DIR/$thiJob/$thisTask"));
    }
    else {
        return "ERROR : $EVENTS_DIR/$thiJob not found";
    }
}

sub getDeps($$$$$) {
    my ($thisTask,$thiJob,$nb,$level,$id) = @_;
    if(open JOB_DEPS,"$JOBS_DIR/$thiJob.txt") {
        my $flag = 0;
        while(<JOB_DEPS>) {
            chomp;
            next if(/^\;/);
            $flag = 1 if(/^\[$thisTask\]/);
            if(($flag==1) && (/^\s+waitfor\s+\=\s+(.+?)$/i)) {
                my $tmpDep = $1;
                my $realDep = $tmpDep;
                my $realJob = $thiJob;
                if($tmpDep=~ /^jobs\/(.+?)\:(.+?)$/i) {
                    $realJob = $1;
                    $realDep = $2;
                }
                my $depStatus = ($AllStatus{$realDep})
                              ? $AllStatus{$realDep}
                              : &getStatusTask($realDep,$realJob,0)
                              ;
                $AllStatus{$realDep} = $depStatus unless($AllStatus{$realDep});
                $level++;
                if($HTML) {
                    my $dateTimeTask = &timeTask($realDep,"${PREFIXSITE}_$thiJob");
                    print ("\t" x $level ,"<ul>\n");
                    if($depStatus  =~ /^done$/i) {
                        print ("\t" x $level ,"\t<li><a href=\"#$id_$realDep\">$realDep</a>&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$depStatus}\" alt=\"$dateTimeTask\" />\n");
                    }
                    else {
                        print ("\t" x $level ,"\t<li class=\"liOpen\"><a href=\"#$id_$realDep\">$realDep</a>&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$depStatus}\" alt=\"$dateTimeTask\" />\n");
                    }
                }
                else {
                    print (" " x $nb ,"+- $realDep ---> $depStatus\n");
                }
                $nb = $nb + 2;
                $AllTasksJobs{$realDep} ||= $realJob;
                &getDeps($realDep,$realJob,$nb,$level,$id);
                if($HTML) {
                    print ("\t" x $level ,"\t</li>\n");
                    print ("\t" x $level ,"</ul>\n");
                }
            }
            last if($flag==1) && (/^\s+command/i);
        }
        close JOB_DEPS;
    }
}

sub timeTask($$) {
    my ($task,$job) = @_ ;
    if ( -e "$EVENTS_DIR/$job/$task") {
        if(open DONE,"$EVENTS_DIR/$job/$task") {
            my $status;
            while(<DONE>) {
                chomp;
                if($_ =~ /^end_time\:\s+(.+?)\/(.+?)\/(.+?)\s+(.+?)\:(.+?)\:(.+?)\s+$Site$/i) {
                    my ($year,$month,$day,$hour,$min,$sec) = ($1,$2,$3,$4,$5,$6);
                    my $seconds = &TransformDateToSeconds("$year-$month-$day","$hour:$min:$sec");
                    $status = "finished on $day/$month/$year at $hour:$min:$sec";
                    last;
                }
            }
            close DONE;
            return $status;
        }
    }
    elsif ( -e "$EVENTS_DIR/$job/$task.inpg") {
        if(open INPG,"$EVENTS_DIR/$job/$task.inpg") {
            my $status;
            while(<INPG>) {
                chomp;
                if($_ =~ /^start_time\:\s+(.+?)\/(.+?)\/(.+?)\s+(.+?)\:(.+?)\:(.+?)\s+$Site$/i) {
                    my ($year,$month,$day,$hour,$min,$sec) = ($1,$2,$3,$4,$5,$6);
                    my $seconds = &TransformDateToSeconds("$year-$month-$day","$hour:$min:$sec");
                    #push @{$Starts{$seconds}},"$task in progress since $day/$month/$year $hour:$min:$sec";
                    #push @{$AllTimes{$seconds}},"$task in progress since $day/$month/$year $hour:$min:$sec";
                    $status = "in progress since $day/$month/$year $hour:$min:$sec";
                    last;
                }
            }
            close INPG;
            return $status;
        }
    }
    else {
        return "not started";
    }
}

sub gen_ID() {
    my $tmp ;
    my @letters=( ('a'..'z'), ('A'..'Z'), (0..9) );
    $tmp .= $letters[rand($#letters)] for (1..16) ;
    $tmp = "idmktree$tmp";
    return $tmp ;
}

sub TransformDateToSeconds($$) {
    #2014-04-04,09:14:01
    my ($Date,$Time) = @_;
    my ($hour,$min,$sec)   = $Time =~ /^(\d+)\:(\d+)\:(\d+)$/;
    my ($Year,$Month,$Day) = $Date =~ /^(\d+)\-(\d+)\-(\d+)$/;
    $Month = $Month - 1;
    my @temps = ($sec,$min,$hour,$Day,$Month,$Year);
    # 051104 6:30:12)
    return timelocal @temps;
}


##############################################################################
### functions from Build.pl, requested to parse the ini file
sub ReadIni
{
    my ($Config,$thisReturn) = @_;
    my @Lines = PreprocessIni($Config);
    my $i = -1;
    my $Context;
    my $Project;
    SECTION: for($_=$Lines[++$i]; $i<@Lines; $_=$Lines[++$i])
    {
        next unless(my($Section) = /^\[(.+)\]/);
        for($_=$Lines[++$i]; $i<@Lines; $_=$Lines[++$i])
        {
            redo SECTION if(/^\[(.+)\]/);
            next if(/^\s*$/ || /^\s*#/);
            s/^\s*//;
            s/\s*$//;
            chomp;
            if($Section eq "context")         { $Context = $_; Monitor(\$Context)}
            elsif($Section eq "project")      { $Project = $_; Monitor(\$Project) }
            elsif($Section eq "environment")
            {
                my($Platform, $Env) = split('\s*\|\s*', $_);
                unless($Env) { $Platform="all"; $Env=$_ }
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL);
                my($Key, $Value) = $Env =~ /^(.*?)=(.*)$/;
                $Value = ExpandVariable(\$Value) if($Key=~/^PATH/);
                $Value = ExpandVariable(\$Value) if($Value =~ /\${$Key}/);
                ${$Key} = $Value;
                Monitor(\${$Key}); Monitor(\$ENV{$Key});

            }
            elsif($Section eq "localvar")
            {
                my($Platform, $Var) = split('\s*\|\s*', $_);
                unless($Var) { $Platform="all"; $Var=$_ }
                next unless($Platform=~/^all$/i || $Platform eq $PLATFORM || ($^O eq "MSWin32" && $Platform=~/^windows$/i) || ($^O ne "MSWin32" && $Platform=~/^unix$/i) || $Platform eq $OBJECT_MODEL);
                my($Key, $Value) = $Var =~ /^(.*?)=(.*)$/;
                $Value = ExpandVariable(\$Value) if($Value =~ /\${$Key}/);
                ${$Key} = $Value;
                Monitor(\${$Key});
            }
        }
    }
    return $Context if($thisReturn eq "build");
    return $Project if($thisReturn eq "project");
}

sub PreprocessIni
{
    my($File, $rhDefines) = @_; $File=ExpandVariable(\$File); $File =~ s/[\r\n]//g;
    my(@Lines, $Define);

    my $fh = new IO::File($File, "r") or die("ERROR: cannot open '$File': $!");
    while(my $Line = $fh->getline())
    {
        $Line =~ s/^[ \t]+//; $Line =~ s/[ \t]+$//;
        if(my($Defines) = $Line =~ /^\s*\#define\s+(.+)$/) { @{$rhDefines}{split('\s*,\s*', $Defines)} = (undef) }
        elsif(($Define) = $Line =~ /^\s*\#ifdef\s+(.+)$/)
        {
            next if(exists(${$rhDefines}{$Define}));
            while(my $Line = $fh->getline()) { last if($Line =~ /^\s*\#endif\s+$Define$/) }
        }
        elsif(($Define) = $Line =~ /^\s*\#ifndef\s+(.+)$/)
        {
            next unless(exists(${$rhDefines}{$Define}));
            while(my $Line = $fh->getline()) { last if($Line =~ /^\s*\#endif\s+$Define$/) }
        }
        elsif($Line =~ /^\s*\#endif\s+/) { }
        elsif(my($IncludeFile) = $Line =~ /^\s*\#include\s+(.+)$/)
        {
            Monitor(\$IncludeFile); $IncludeFile =~ s/[\r\n]//g;
            unless(-f $IncludeFile)
            {
                my $Candidate = catfile(dirname($File), $IncludeFile);
                $IncludeFile = $Candidate if(-f $Candidate);
            }
            push(@Lines, PreprocessIni($IncludeFile, $rhDefines))
        }
        else { push(@Lines, $Line) }
    }
    $fh->close();
    return @Lines;
}

sub Monitor
{
    my($rsVariable) = @_;
    return undef unless(tied(${$rsVariable}) || (${$rsVariable} && ${$rsVariable}=~/\${.*?}/));
    push(@MonitoredVariables, [$rsVariable, ${$rsVariable}]);
    return tie ${$rsVariable}, 'main', $rsVariable;
}

sub TIESCALAR
{
    my($Pkg, $rsVariable) = @_;
    return bless($rsVariable);
}

sub FETCH
{
    my($rsVariable) = @_;

    my $Variable = ExpandVariable($rsVariable);
    return $Variable unless($IsVariableExpandable);
    for(my $i=0; $i<@MonitoredVariables; $i++)
    {
        next unless($MonitoredVariables[$i]);
        unless(ExpandVariable(\${$MonitoredVariables[$i]}[1]) =~ /\${.*?}/)
        {
            ${${$MonitoredVariables[$i]}[0]} = ${$MonitoredVariables[$i]}[1];
            untie ${$MonitoredVariables[$i]}[0];
            $MonitoredVariables[$i] = undef;
        }
    }
    @MonitoredVariables = grep({$_} @MonitoredVariables);
    return ${$rsVariable};
}

sub STORE
{
    my($rsVariable, $Value) = @_;
    ${$rsVariable} = $Value;
}

sub ExpandVariable
{
    my($rsVariable) = @_;
    my $Variable = ${$rsVariable};
    return "" unless(defined($Variable));
    while($Variable =~ /\${(.*?)}/g)
    {
        my $Name = $1;
        $Variable =~ s/\${$Name}/${$Name}/ if(defined(${$Name}));
        $Variable =~ s/\${$Name}/$ENV{$Name}/ if(!defined(${$Name}) && defined($ENV{$Name}));
    }
    ${$rsVariable} = $Variable if($IsVariableExpandable);
    return $Variable;
}
