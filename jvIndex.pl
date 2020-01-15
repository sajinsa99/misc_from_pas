#!/usr/bin/perl

##############################################################################
##### declare uses

use CGI 'param';

use JSON;

use File::Path;

use FindBin;
use lib $FindBin::Bin;

use Date::Calc(qw(Delta_DHMS));

use Getopt::Long;
use Net::Ping;



##############################################################################
##### declare vars

#hget from jvPaths.txt
use vars qw(
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
    @realms
    $JOBDB_DIR
    %JOB_BASENAMES
);

#for the script itself
use vars qw (
    $JV_DIR
    $SITE
    %matchStatusImgs
    $MAIN_ELEMENT
);

#param/optionss
use vars qw (
    $paramTopFilter
    $paramJob
    $paramBuild
    $paramMachine
    $paramTask
    $paramProjects
    @paramPrjs
    $jenkinsUser
    $jenkinsPasswd
    $paramJobBase
);



##############################################################################
##### declare functions
sub getVars();
sub getVersion($);
sub autoComplete($$$);
sub subfillSelectHTML($$);
sub HeadHtml();
sub FootHtml();

sub scanJenkins($$$);



##############################################################################
##### init vars
$JV_DIR = $ENV{JV_DIR}
        || "/build/pblack/perforce/perforceBO/internal/cis/1.0/REL/cgi-bin" ;
$SITE   = $ENV{SITE} || "Walldorf";

$configFile ||= "./jvPaths.txt";
&getVars();

$matchStatusImgs{'done'} = "jvCheck.gif";
$matchStatusImgs{'in progress'} = "jvStar_yellow.gif";
$matchStatusImgs{'not started'} = "jvStar_blue.gif";



##############################################################################
##### get options/parameters
if(@ARGV){
    GetOptions(
        "f=s"   => \$paramTopFilter,
        "j=s"   => \$paramJob,
        "b=s"   => \$paramBuild,
        "m=s"   => \$paramMachine,
        "t=s"   => \$paramTask,
        "p=s"   => \$paramProjects,
        "ujg=s" => \$paramJobBase,
    )
}
else {
    $paramTopFilter   = param('topfilter');
    $paramJob         = param('jobInput');
    $paramJob       ||= param('job');
    $paramBuild       = param('buildInput');
    $paramBuild     ||= param('build');
    $paramBuild     ||= param('build_project');
    $paramMachine     = param('machineInput');
    $paramMachine   ||= param('machine');
    $paramMachine   ||= param('machine_os_family');
    $paramTask      ||= param('taskInput');
    $paramTask      ||= param('task');
    $paramTask      ||= param('task_job');
    $paramProjects  ||= param('projectInput');
    $jenkinsUser    ||= param('jenkinsuser');
    $paramJobBase   ||= param('jobbase');
}
#add .txt if missed
$paramJob = "$paramJob.txt" if($paramJob && (!($paramJob =~ /\.txt$/i)) );
$jenkinsUser    ||= "pblack";


if($JOBDB_DIR && (-e $JOBDB_DIR)) {
    if(opendir BUILDVERSIONSDIR, "$JOBDB_DIR") {
        while(defined(my $prj = readdir BUILDVERSIONSDIR)) {
            next if($prj =~ /^\./);
            next if($prj =~ /^mpb$/i);
            if(open IN_PRJ,"$JOBDB_DIR/$prj/dev/schedulers/servers/logicalServers.properties") {
                my $jenkinsServer;
                while(<IN_PRJ>) {
                    chomp;
                    if(/\.mapping\=(.+?)$/) {
                        $jenkinsServer = $1;
                        if(open THIS_JENKINS, "$JOBDB_DIR/$prj/dev/schedulers/servers/$jenkinsServer/server.properties") {
                            while(<THIS_JENKINS>) {
                                chomp;
                                if(/url\=(.+?)$/) {
                                    $JOB_BASENAMES{$prj}{url}    = $1;
                                    $JOB_BASENAMES{$prj}{server} = $jenkinsServer;
                                    last;
                                }
                            }
                            close THIS_JENKINS;
                            if(opendir REALMS, "$JOBDB_DIR/$prj/dev/builds/realms") {
                                while(defined(my $realm = readdir REALMS)) {
                                    next if($realm =~ /^\./);
                                    next if($realm =~ /^default/i);
                                    push @{$JOB_BASENAMES{$prj}{realms}},$realm;
                                }
                                closedir REALMS;
                            }
                        }
                    }
                }
                close IN_PRJ;
            }
        }
        closedir BUILDVERSIONSDIR;
    }
}

##############################################################################
##### MAIN

print "Content-type: text/html\n\n";
&HeadHtml();

########## chooses
##### choose top list : jobs, builds, machines
if( (!($paramTopFilter)) && (!($paramJob)) && (!($paramBuild)) && (!($paramMachine)) && (!($paramTask)) && (!($paramJobBase))) {
    my @listProjectBuilds = `perl $JV_DIR/jv.pl -l=allbuilds 2> /dev/null`;
    my @prjs;
    push(@prjs,"allprojects");
    foreach my $projectBuild (@listProjectBuilds) {
        if($projectBuild =~ /^p\s+\:\s+(.+?)$/i) {
            push @prjs,$1 unless(grep /^$1$/,@prjs);
        }
    }
    print "<form name=\"mainChoices\" action=\"./jvIndex.pl\" method=\"post\">\n";
    &autoComplete("projectInput","listProjects",\@prjs);
    print "
    <strong>Choose your filter :</strong><br/>
    <table border=\"0\">
    <tr><td>job</td><td><input type=\"radio\" name=\"topfilter\" value=\"jobs\" /></td></tr>
    <tr><td>build</td><td><input type=\"radio\" name=\"topfilter\" value=\"builds\" /></td></tr>
    <tr><td>machine</td><td><input type=\"radio\" name=\"topfilter\" value=\"machines\" /></td></tr>
    <tr><td>task</td><td><input type=\"radio\" name=\"topfilter\" value=\"tasks\"   /></td></tr>
    <tr><td>jenkins &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<input type=\"radio\" name=\"topfilter\" value=\"jenkins\"/></td><td>jenkins admin : <input type=\"text\" name=\"jenkinsuser\" id=\"jenkinsuser\" size=\"64\" value=\"$jenkinsUser\" /></td></tr>
    <tr><td>jobbase</td><td><input type=\"radio\" name=\"topfilter\" value=\"jobbases\"   /></td></tr>
    <tr><td>&nbsp;<strong>or<strong> type directly one of field:</td></tr>
    <tr><td>&nbsp;(just by a copy-paste directly) :</td></tr>
    <tr><td>this job</td><td><input type=\"text\" name=\"jobInput\" size=\"64\" /></td></tr>
    <tr><td>this build</td><td><input type=\"text\" name=\"buildInput\" size=\"64\" /></td></tr>
    <tr><td>this machine</td><td><input type=\"text\" name=\"machineInput\" size=\"64\" /></td></tr>
    <tr><td>this task</td><td><input type=\"text\" name=\"taskInput\" size=\"64\" /></td></tr>
    <tr><td><strong>or<strong></td><td>syntax: project1;project2  or  project1:build1,build2;project2:build3,build4 or project1;project2:build3,build4 (projects separated by ';' and builds separated by ',')</td></tr>
    <tr><td>all builds for a project (could take a while) <input type=\"radio\" name=\"topfilter\" value=\"allbuilds\"/></td><td><input type=\"text\" name=\"projectInput\" id=\"projectInput\" size=\"64\" /></td></tr>
";
    print "
    <tr><td><input type=\"button\" name=\"buttonTopFilterChoice\" value=\"submit\" onclick=\"submit();\" /></td></tr>
    </table>
</form>
<br/>
";
    goto ENDHTML;
}

##### choose a job
if($paramTopFilter && ($paramTopFilter eq "jobs")) {
    my @jobs = `perl $JV_DIR/jv.pl -l=jobs 2> /dev/null`;
    print "Choose your job file:<br/>\n";
    print "<form name=\"listJobs\" action=\"./jvIndex.pl\" method=\"post\">\n";
    &autoComplete("jobInput","listJobs",\@jobs);
    print "<input type=\"text\" name=\"jobInput\" id=\"jobInput\">&nbsp;&nbsp;<input type=\"button\" name=\"buttonJobInput\" value=\"submit\" onclick=\"submit();\" /><br/><br/>\n";
    &subfillSelectHTML("job",\@jobs);
    print "</form>\n";
    goto ENDHTML;
}
##### choose a build
if($paramTopFilter && ($paramTopFilter eq "builds")) {
    my @builds = `perl $JV_DIR/jv.pl -l=builds 2> /dev/null`;
    print "Choose your build:<br/>\n";
    print "<form name=\"listBuilds\" action=\"./jvIndex.pl\" method=\"post\">\n";
    print "<table border=\"0\">\n";
    print "<tr><td><center>build name</center></td>";
    print "<td><center>per project</center></td></tr>\n";
    print "<tr><td>\n";
    &autoComplete("buildInput","listBuilds",\@builds);
    #print "<input type=\"text\" name=\"buildInput\" id=\"buildInput\">&nbsp;&nbsp;<input type=\"button\" name=\"buttonBuildInput\" value=\"submit\" onclick=\"submit();\" /><br/><br/>\n";
    print "<input type=\"text\" name=\"buildInput\" id=\"buildInput\">\n";
    print "</td>\n";
    print "<td>\n";
    #&subfillSelectHTML("build",\@builds);
    my @projectBuilds = `perl $JV_DIR/jv.pl -l=allbuilds 2> /dev/null`;
    print "<select name=\"build_project\" >\n";
    foreach my $prjBuild (@projectBuilds) {
        chomp $prjBuild;
        ($prjBuild) =~ s-^\s+--;
        my ($indice,$elem) = $prjBuild =~ /^(.+?)\s+\:\s+(.+?)$/;
        if($indice eq "p") {
            print "<optgroup label=\"$elem\">\n";
        }
        else {
            print "<option>$elem</option>\n";
        }
    }
    print "</td>\n";
    print "<td><input type=\"button\" name=\"buttonBuildInput\" value=\"submit\" onclick=\"submit();\" /></td>\n";
    print "</tr></table>\n";
    print "</form>\n";
    goto ENDHTML;
}

##### choose a machine
if($paramTopFilter && ($paramTopFilter eq "machines")) {
    my @machines = `perl $JV_DIR/jv.pl -l=machines 2> /dev/null`;
    print "<form name=\"listMachines\" action=\"./jvIndex.pl\" method=\"post\">\n";
    print "Choose your machine:<br/><br/>\n";
    print "<table border=\"0\">\n";
    ### all machines
    print "<tr><td><center>machine name</center></td>\n";
    #print "<tr><td>machine name<br/>";
    #&subfillSelectHTML("machine",\@machines);
    #print "</td>\n";
    ### per os family
    my @os_families = `perl $JV_DIR/jv.pl -i=os_family 2> /dev/null`;
    print "<td>\n";
    print "<center>per os_family</center>\n";
    print "</td>\n";

    print "</tr>\n";
    print "<tr><td>\n";
    &autoComplete("machineInput","listMachines",\@machines);
    print "<input type=\"text\" name=\"machineInput\" id=\"machineInput\">\n";
    print "</td>\n";
    print "<td>\n";
    print "<select name=\"machine_os_family\" >\n";
    foreach my $os_family (@os_families) {
        chomp $os_family;
        if($os_family) {
            my @machines2 = `perl $JV_DIR/jv.pl -l=machines -o=$os_family 2> /dev/null`;
            my $size = scalar @machines2;
            if(scalar @machines2 > 0) {
                print "<optgroup label=\"$os_family\">\n";
                foreach my $machine2 (@machines2) {
                    chomp($machine2);
                    print "<option>$machine2</option>\n" if($machine2);
                }
            }
        }
    }
    print "</select>\n";
    print "</td>\n";
    print "<td><input type=\"button\" name=\"buttonMachineInput\" value=\"submit\" onclick=\"submit();\" /></td>\n";
    print "</tr></table>\n";
    print "</form>\n";
    goto ENDHTML;
}

##### choose a task
if($paramTopFilter && ($paramTopFilter eq "tasks")) {
    my @jobstasks = `perl $JV_DIR/jv.pl -l=tasks 2> /dev/null`;
    my @allTasks;
    foreach my $task (@jobstasks) {
        chomp($task) ;
        next if (/^j\s+:\s+/);
        my ($realTaskName) = $task =~ /^t\s+:\s+(.+?)$/;
        push @allTasks,$realTaskName;
    }
    print "<form name=\"listTasks\" action=\"./jvIndex.pl\" method=\"post\">\n";
    print "Choose your task:<br/><br/>\n";
    print "<table border=\"0\">\n";
    ### all machines
    print "<tr><td><center>task name</center></td>\n";
    print "<td>\n";
    print "<center>per job file</center>\n";
    print "</td>\n";

    print "</tr>\n";
    print "<tr><td>\n";
    &autoComplete("taskInput","listTasks",\@allTasks);
    print "<input type=\"text\" name=\"taskInput\" id=\"taskInput\">\n";
    print "</td>\n";
    print "<td>\n";
    print "<select name=\"task_job\" >\n";
    foreach my $elem (@jobstasks) {
        chomp $elem;
        if($elem =~ /^j\s+:\s+(.+?)$/) {
            print "<optgroup label=\"$1\">\n";
        }
        if($elem =~ /^t\s+:\s+(.+?)$/) {
            print "<option>$1</option>\n";
        }
    }
    print "</select>\n";
    print "</td>\n";
    print "<td><input type=\"button\" name=\"buttonTaskInput\" value=\"submit\" onclick=\"submit();\" /></td>\n";
    print "</tr></table>\n";
    print "</form>\n";
    goto ENDHTML;
}

##### choose all builds
if($paramTopFilter && ($paramTopFilter eq "allbuilds")) {
    my %Builds;
    my @listProjectBuilds = `perl $JV_DIR/jv.pl -l=allbuilds 2> /dev/null`;
    my $prj;
    $paramProjects = "" if($paramProjects eq "allprojects");
    #@paramPrjs = split(';',$paramProjects) if($paramProjects);
    my @tmpPrjs = split ';',$paramProjects if($paramProjects);
    my %tmpBuilds;
    foreach my $paramPrj (@tmpPrjs) {
        if($paramPrj =~ /^(.+?)\:(.+?)$/) {
            my $prj = $1 ;
            push(@paramPrjs,$prj);
            foreach my $build (split ',',$2) {
                push @{$tmpBuilds{$prj}},$build;
            }
        }
        else {
            push(@paramPrjs,$paramPrj);
        }
    }
    foreach my $projectBuild (@listProjectBuilds) {
        if($projectBuild =~ /^p\s+\:\s+(.+?)$/i) {
            $prj = $1;
            next if($paramProjects && (!(grep /^$prj$/i ,@paramPrjs)));
        }
        if($projectBuild =~ /^\s+b\s+\:\s+(.+?)$/i) {
            my $buildName = $1;
            if($prj) {
                next if($paramProjects && (!(grep /^$prj$/i ,@paramPrjs)));
                push @{$Builds{$prj}},$buildName unless(grep /^$buildName$/ ,@{$Builds{$prj}});
            }
        }
    }
    print "<br/>Over all builds status (<strong><font color=\"#FFA500\">could take some time</font></strong>)<br/><br/>\n";
    foreach my $project (sort keys %Builds) {
        next if($paramProjects && (!(grep /^$project$/i ,@paramPrjs)));
        print "<fieldset><legend><span onclick=\"document.getElementById('prj_$project').style.display = (document.getElementById('prj_$project').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">&nbsp;<strong>$project</strong></span></legend>\n";
        print "<div id=\"prj_$project\" style=\"display:none\">\n";
        print "<ul class=\"mktree\" id=\"tree_$project\">\n\n";
        foreach my $build (sort @{$Builds{$project}}) {
            next if(@{$tmpBuilds{$project}} && (!(grep /^$build$/i,@{$tmpBuilds{$project}})));
            my @results = `perl $JV_DIR/jv.pl -tb=$build 2> /dev/null`;

            #restruct and statistic
            my %thisPlatforms;
            my $statusDone = 0;
            my $statusInpg = 0;
            my $statusToDo = 0;
            my $overAllStatus;
            my $nbTask = 0;
            my %stats;
            foreach my $taskStatus (sort @results) {
                chomp $taskStatus;
                my ($task,$status) = split ',',$taskStatus;
                $_ = $task;
                SWITCH:
                {
                    /\.aix/i        and push @{$thisPlatforms{aix}}    ,$taskStatus    and $stats{aix}{$status}++;
                    /\.hp/i         and push @{$thisPlatforms{hp}}     ,$taskStatus    and $stats{hp}{$status}++;
                    /\.linux/i      and push @{$thisPlatforms{linux}}  ,$taskStatus    and $stats{linux}{$status}++;
                    /\.mac/i        and push @{$thisPlatforms{macOS}}  ,$taskStatus    and $stats{macOS}{$status}++;
                    /\.solaris/i    and push @{$thisPlatforms{solaris}},$taskStatus    and $stats{solaris}{$status}++;
                    /\.win/i        and push @{$thisPlatforms{windows}},$taskStatus    and $stats{windows}{$status}++;
                }
                $_ = $status;
                SWITCH:
                {
                    /^done$/i           and $statusDone++;
                    /^in\s+progress$/i  and $statusInpg++;
                    /^not\s+started$/i  and $statusToDo++;
                }
                $nbTask++;
            }
            if($statusDone == $nbTask) {
                $overAllStatus = "done";
            }
            elsif($statusToDo == $nbTask) {
                $overAllStatus = "not started";
            }
            else {
                $overAllStatus = "in progress";
            }

            #prints
            #print build
            if($overAllStatus eq "done") {
                print "\t<li><a href=\"./jvIndex.pl?build=$build\"\">$build</a> &nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$overAllStatus}\" alt=\"$overAllStatus\" />\n";
            }
            else {
                print "\t<li class=\"liOpen\"><a href=\"./jvIndex.pl?build=$build\"\">$build</a> &nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$overAllStatus}\" alt=\"$overAllStatus\" />\n";
            }
            foreach my $osFam (sort qw(aix hp linux macOS solaris windows)) {
                next unless(@{$thisPlatforms{$osFam}});
                my $sizeOSFam = scalar @{$thisPlatforms{$osFam}};
                if($sizeOSFam > 0) {
                    my $overallOSFam;
                    foreach my $status (sort keys %matchStatusImgs) {
                        next unless($stats{$osFam}{$status});
                        if ($stats{$osFam}{$status} == $sizeOSFam) {
                            $overallOSFam = $status;
                            last;
                        }
                        else {
                            $overallOSFam = "in progress";
                        }
                    }
                    #print os
                    print "\t\t<ul>\n";
                    if($overallOSFam eq "done") {
                        print "\t\t\t<li>$osFam &nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$overallOSFam}\" alt=\"$overallOSFam\" />\n";
                    }
                    else {
                        print "\t\t\t<li class=\"liOpen\">$osFam &nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$overallOSFam}\" alt=\"$overallOSFam\" />\n";
                    }
                    #print task per os
                    print "\t\t\t\t<ul>\n";
                    foreach my $taskStatus (sort @{$thisPlatforms{$osFam}}) {
                        my ($task,$status) = split ',',$taskStatus;
                        print "\t\t\t\t\t<li>$task&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$status}\" alt=\"$status\" /></li>\n";
                    }
                    print "\t\t\t\t</ul>\n";
                    print "\t\t\t</li>\n";
                    print "\t\t</ul>\n";
                }
            }
            print "\t</li>\n";
        }
        print "</ul>\n";
        print "</div></fieldset>\n";
    }
    goto ENDHTML;
}

if($paramTopFilter && ($paramTopFilter eq "jenkins")) {
    my @listUrlJenkins;
    if( ! -e "$JV_DIR/jv_json_jenkins" ) {
        mkpath("$JV_DIR/jv_json_jenkins");
    }
    if(open LIST_JENKINS,"./jv_${jenkinsUser}_jenkins.txt") {
        while(<LIST_JENKINS>) {
            chomp;
            next unless($_);
            next if(/^\#/); #next comment
            my $line = $_;
            push @listUrlJenkins,$line;
        }
        close LIST_JENKINS;
    }
    if(scalar @listUrlJenkins > 0) {
        #use Data::Dumper;

        foreach my $jenkins (@listUrlJenkins) {
            my ($srv) = $jenkins =~ /\:\/\/(.+?)\:\d+/i;
            &scanJenkins($jenkins,$srv,"");
        }
        print "<br/>\n";
    }
    goto ENDHTML;
}

if($paramTopFilter && ($paramTopFilter eq "jobbases")) {
    print "<form name=\"listJobBases\" action=\"./jvIndex.pl\" method=\"get\">\n";
    print "Choose your jobbase:<br/><br/>\n";
    print "<table border=\"0\">\n";
    print "<tr><td><select name=\"jobbase\" >\n";
    foreach my $prj (sort keys %JOB_BASENAMES) {
        print "<option>$prj</option>\n";
    }
    print "</select>\n";
    print "</td><td>jenkins user : <input type=\"text\" name=\"jenkinsuser\" size=\"64\" value=\"$jenkinsUser\"/></td></tr>\n";
    print "<tr><td><input type=\"button\" name=\"jobBaseBuildInput\" value=\"submit\" onclick=\"submit();\" /></td></tr>\n";
    print "</tr></table>\n";
    print "</form>\n";
    goto ENDHTML;
}

if($paramJobBase) {
    my $jenkinsServer   = $JOB_BASENAMES{$paramJobBase}{server};
    my $jenkins         = $JOB_BASENAMES{$paramJobBase}{url};
    my ($srv)           = $jenkins =~ /\:\/\/(.+?)\:\d+/i;
    my @realms          = @{$JOB_BASENAMES{$paramJobBase}{realms}};
    &scanJenkins($jenkins,$srv,\@realms);
    goto ENDHTML;
}

##### choose a specific task
if($paramTask) {
    print "<center><h3>$paramTask</h3></center><br/>\n";
    my $status = `perl $JV_DIR/jv.pl -t=$paramTask -html 2> /dev/null`;
    chomp $status;
    print $status if($status);
        #print "$paramTask&nbsp;&nbsp;<img src=\"$IMG_SRC/$matchStatusImgs{$status}\" alt=\"$status\" />";
    goto ENDHTML;
}

if($paramJob || $paramBuild || $paramMachine) {
    $MAIN_ELEMENT = $paramJob || $paramBuild || $paramMachine;
    my $rev = &getVersion($paramBuild) if($paramBuild);
    print "<center><h3>$MAIN_ELEMENT";
    print " - $rev" if($rev);
    print "</h3></center><br/>\n";
    my $option;
    if($paramJob) {
        $option ="-j=$paramJob";
    }
    if($paramBuild) {
        $option ="-b=$paramBuild";
        my @osFamiliesAndMachines =`perl $JV_DIR/jv.pl -i=lmob -b=$paramBuild 2> /dev/null`;
        print "<fieldset><legend><span onclick=\"document.getElementById('infos_elem').style.display = (document.getElementById('infos_elem').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">&nbsp;<strong>machine(s) for $paramBuild</strong></span></legend>\n";
        print "<div id=\"infos_elem\" style=\"display:none\"><br/>";
        foreach my $osFamilyAndMachine (@osFamiliesAndMachines) {
            chomp $osFamilyAndMachine;
            if($osFamilyAndMachine =~ /^os_family:\s+(.+?)$/i) {
                my $os_family = $1;
                print "\t<span style=\"margin:20px;\">$os_family</span><br/>\n";
            }
            if($osFamilyAndMachine =~ /^machine:\s+(.+?)$/i) {
                my $machine = $1;
                print "\t\t<span style=\"margin:40px;\"><a href=\"./jvIndex.pl?machine=$machine\">$machine</a></span><br/>\n";
            }
        }
        print "</div><br/>\n";
        print "</fieldset>\n";
        print "<br/>\n";
        print "<br/>\n";
    }
    if($paramMachine) {
        $option ="-m=$paramMachine";
        my @builds =`perl $JV_DIR/jv.pl -i=lbom -m=$paramMachine 2> /dev/null`;
        if(scalar @builds > 0) {
            print "<fieldset><legend><span onclick=\"document.getElementById('infos_elem').style.display = (document.getElementById('infos_elem').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">&nbsp;<strong>build(s) done on $paramMachine</strong></span></legend>\n";
            print "<div id=\"infos_elem\" style=\"display:none\"><br/>";
            foreach my $build (sort @builds) {
                chomp $build;
                my $rev = &getVersion($build);
                print "\t<span style=\"margin:20px;\"><a href=\"./jvIndex.pl?build=$build\">$build</a>&nbsp;&nbsp;$rev</span><br/>\n";
            }
            print "</div><br/>\n";
            print "</fieldset>\n";
            print "<br/>\n";
            print "<br/>\n";
        }
    }
    if(open RESULTS , "perl $JV_DIR/jv.pl -html $option 2> /dev/null |") {
        my $start = 0;
        my $startMainTask = 0;
        my $mainTask;
        my $nbdeps = 0;
        while(<RESULTS>) {
            chomp;
            #start
            print $_,"\n";
        }
        close RESULTS;
    }
    goto ENDHTML;
}

ENDHTML:
&FootHtml();
exit 0;

##############################################################################
### my functions
sub getVars() {
    if(open CONFIG,"$configFile") {
        my $flagSite = 0;
        while(<CONFIG>) {
            chomp;
            next unless($_);
            next if(/^\#/);
            if(/^\[(.+?)\]/){
                if($SITE eq $1) {
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
}

sub getVersion($) {
    my ($buildName) = @_ ;
    my $version;
    chdir $CBTPATH;
    my $dropdir = `perl $CBTPATH/rebuild.pl -i=contexts/$buildName.ini -si=dropdir 2> /dev/null`;
    chomp $dropdir;
    if($dropdir) {
        if( -e "$dropdir/$buildName/version.txt") {
            if(open VER,"$dropdir/$buildName/version.txt") {
                chomp($version = <VER>);
                $version = int $version;
                close VER;
            }
            else {
                if(opendir BUILDVERSIONSDIR, "$dropdir/$buildName") {
                    while(defined(my $next = readdir BUILDVERSIONSDIR)) {
                        $version = $1 if ($next =~ /^(\d+)(\.\d+)?$/ && $1 > $version && -d "$dropdir/$buildName/$next");
                    }
                    closedir BUILDVERSIONSDIR;
                }
            }
        }
    }
    chdir $JV_DIR;
    return $version;
}

sub autoComplete($$$) {
    my ($id,$thisList,$elems) = @_;
    print "
<script type=\"text/javascript\">
var $thisList = [
";
    my $line;
    foreach my $elem (@{$elems}) {
        chomp $elem;
        $line .= "\t\"$elem\",\n" if($elem)
    }
    ($line) =~ s-\,\n$--;
    print "$line";
    print "
];

\$(document).ready(function() {
    \$( \"#$id\" ).autocomplete({ source : $thisList });
});
</script>
";
}

sub subfillSelectHTML($$) {
    my ($id,$elems) = @_;
    print "<select name=\"$id\" onchange=\"submit()\">\n";
    foreach my $elem (@{$elems}) {
        chomp $elem;
        print "<option>$elem</option>\n" if($elem);
    }
    print "</select>\n";
}

##### html part
sub HeadHtml() {
    $CIS_HTTP_DIR   .= "?streams=$paramBuild" if($paramBuild && $CIS_HTTP_DIR);
    print "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">
<html xmlns=\"http://www.w3.org/1999/xhtml\">
<head>
    <title>Jobs Viewer 2.0</title>
    <meta http-equiv=\"content-type\" content=\"text/html; charset=UTF-8\" />
    <meta http-equiv=\"cache-control\" content=\"no-cache\" />
    <meta http-equiv=\"pragma\" content=\"no-cache\" />

    <link rel=\"stylesheet\" type=\"text/css\"  href=\"../jv_js/jquery-ui.css\"></link>
    <script type=\"text/javascript\" src=\"../jv_js/jquery-1.11.0.min.js\"></script>
    <script type=\"text/javascript\" src=\"../jv_js/jquery-ui-1.10.4.min.js\"></script>

    <link rel=\"stylesheet\" type=\"text/css\"  href=\"../jv_js/mktree.css\"></link>
    <script type=\"text/javascript\" src=\"../jv_js/mktree.js\"></script>

    <script type=\"text/javascript\" src=\"../jv_js/raphael-min.js\"></script>
    <script type=\"text/javascript\" src=\"../jv_js/dracula_graffle.js\"></script>
    <script type=\"text/javascript\" src=\"../jv_js/dracula_graph.js\"></script>
    <script type=\"text/javascript\" src=\"../jv_js/dracula_algorithms.js\"></script>

    <script type=\"text/javascript\" src=\"../jv_js/highcharts.js\"></script>
    <script type=\"text/javascript\" src=\"../jv_js/modules/exporting.js\"></script>
</head>
<body>
    <center>
        <h1><a href=\"./jvIndex.pl\">Job Viewer 2.0</a></h1>
        <img src=\"$IMG_SRC/flag_$SITE.gif\" alt=\"$SITE\" />
";
    print "     <h1><a href=\"$CIS_HTTP_DIR\" target=\"_blank\">CIS</a></h1>\n" if($CIS_HTTP_DIR);
    print "
    </center>
<br/>
<hr></hr>
<br/>
";
}

sub FootHtml() {
    print "
<br/>
<br/>
<hr></hr>
Legends:
<table border=\"0\">
";
    foreach my $status (sort keys %matchStatusImgs) {
        my $myColor;
        $myColor = "green"   if($status =~ /done/i);
        $myColor = "#FF8C00" if($status =~ /in progress/i);
        $myColor = "blue"    if($status =~ /not started/i);
        print "<tr><td><strong><font color=\"$myColor\">$status</font></strong></td><td><img src=\"$IMG_SRC/$matchStatusImgs{$status}\" alt=\"$status\" /></td></tr>\n";
    }
print "
</table>
<br/>
<br/>
</body>
</html>
";
}

sub scanJenkins($$$) {
    my ($jenkins,$srv,$realms) = @_ ;

    eval {
         my $p = Net::Ping->new();
        unless ( $p->ping($srv) ) {
            print "ERROR : $srv is not reachable</br>\n";
            $p->close();
            return;
        }
        $p->close();
    };
    if ($@) {
        print "</br>ERROR : $srv is not reachable</br>\n";
        return;
    }

    my ($LocalSec,$LocalMin,$LocalHour,$LocalDay,$LocalMonth,$LocalYear,$wday,$yday,$isdst) = localtime time;
    $LocalYear = $LocalYear + 1900;
    $LocalMonth++;

    my $passwd;
    my $this_jira_user = `prodpassaccess get jenkins_jv user`;
    chomp $this_jira_user;
    if($this_jira_user =~ /^$jenkinsUser$/) {
        $passwd = `prodpassaccess get jenkins_jv password`;
        chomp $passwd;
    }
    else {
    	print "<br/>ERROR : $jenkinsUser not found in prodpassaccess<br/>\n";
    	exit 1;
    }


    #get view if needed
    my $curlCmd = "curl -u $jenkinsUser:$passwd $jenkins/api/json"
                . " > $JV_DIR/jv_json_jenkins/$srv.json"
                . " 2> $JV_DIR/jv_json_jenkins/$srv.log"
                ;
    system $curlCmd;
    undef $curlCmd;
    my $search404Srv = `grep -i \"ERROR 404\" \"$JV_DIR/jv_json_jenkins/$srv.json\"`;
    chomp $search404Srv;
    unless($search404Srv) {
        my $search401rv = `grep -i \"ERROR 401\" \"$JV_DIR/jv_json_jenkins/$srv.json\"`;
        chomp $search401rv;
        goto HTTP_401 if($search401rv);
        my $jenkinsConfig;
        if(open JSON,"$JV_DIR/jv_json_jenkins/$srv.json") {
            $jenkinsConfig = decode_json(<JSON>);
            close JSON;
        }
        my %jenkinsViews;
        foreach my $view (@{$jenkinsConfig->{'views'}}) {
            $jenkinsViews{$$view{name}} = $$view{url};
        }
        my %flagJobs;
        print "<fieldset><legend><span onclick=\"document.getElementById('$srv').style.display = (document.getElementById('$srv').style.display=='none') ? 'block' : 'none';\" onmouseover=\"this.style.cursor='pointer'\" onmouseout=\"this.style.cursor='auto'\">$jenkins</strong></span></legend>\n";
        print "<div id=\"$srv\" style=\"display:none\"><br/>";
        print "<table border=\"0\">\n";
        foreach my $view (sort keys %jenkinsViews) {
            next if($view =~ /^all$/i); #to do separately
            next if($realms && (!(grep /^$view$/i , @$realms)));
            my $name = $view;
            my $name2 = $name;
            ($name2) =~ s-\s+-_-g; #replace space by _ for filename
            my $url  = $jenkinsViews{$view};
            my $curlCmd = "curl -u $jenkinsUser:$passwd $url/api/json"
                        . " > $JV_DIR/jv_json_jenkins/${srv}_$name2.json"
                        . " 2> $JV_DIR/jv_json_jenkins/${srv}_$name2.log"
                        ;
           system $curlCmd;
           undef $curlCmd;
            my $search404View = `grep -i \"ERROR 404\" \"$JV_DIR/jv_json_jenkins/${srv}_$name2.json\"`;
            unless($search404View) {
                my $jobsPerView;
                if(open JSON,"$JV_DIR/jv_json_jenkins/${srv}_$name2.json") {
                    $jobsPerView = decode_json(<JSON>);
                    close JSON;
                }
                print "<tr><td><strong>$name :</strong></td></tr>\n";
                foreach my $jobsForThisView (@{$jobsPerView->{'jobs'}}) {
                    my $jenkinsJobName = $jobsForThisView->{'name'};
                    $flagJobs{$jenkinsJobName}=1;
                    my $curlCmd = "curl -u $jenkinsUser:$passwd $jenkins/job/$jenkinsJobName/lastBuild/api/json"
                                . " > $JV_DIR/jv_json_jenkins/${srv}_lastBuild_$jenkinsJobName.json"
                                . " 2> $JV_DIR/jv_json_jenkins/${srv}_lastBuild_$jenkinsJobName.log"
                                ;
                    system $curlCmd;
                    undef $curlCmd;
                    my $search404 = `grep -i \"ERROR 404\" \"$JV_DIR/jv_json_jenkins/${srv}_lastBuild_$jenkinsJobName.json\"`;
                    chomp $search404;
                    unless($search404) {
                        print "<tr><td>$jenkinsJobName</td>";
                        my $infoBuild;
                        if(open JSON,"$JV_DIR/jv_json_jenkins/${srv}_lastBuild_$jenkinsJobName.json") {
                            $infoBuild = decode_json(<JSON>);
                            close JSON;
                            if($infoBuild->{'result'} =~ /SUCCESS/i) {
                                 print "<td><img src=\"./images/green.gif\" alt=\"job success\"/></td><td>$infoBuild->{'result'}</td>";
                            }
                            if($infoBuild->{'result'} =~ /FAILURE/i) {
                                print "<td><img src=\"./images/red.gif\" alt=\"job failed\"/></td><td> $infoBuild->{'result'}</td>";
                            }
                            if($infoBuild->{'result'} =~ /ABORTED/i) {
                                print "<td><img src=\"./images/grey.gif\" alt=\"job aborted\"/></td><td> $infoBuild->{'result'}</td>";
                            }
                            unless($infoBuild->{'result'}) {
                                print "<td><img src=\"./images/yellow.gif\" alt=\"job in progress\"/></td><td> in progress</td>";
                            }
                            print "<td><a href=\"$infoBuild->{'url'}\" target=\"_BLANK\">$jenkinsJobName</a></td>";
                            my ($jenkinsYear,$jenkinsMonth,$jenkinsDay,$jenkinsHour,$jenkinsMin,$jenkinsSec) = $infoBuild->{'id'} =~ /^(\d+)\-(\d+)\-(\d+)\_(\d+)\-(\d+)\-(\d+)$/;
                            my @lifeHMS = Delta_DHMS($jenkinsYear,$jenkinsMonth,$jenkinsDay,$jenkinsHour,$jenkinsMin,$jenkinsSec,$LocalYear,$LocalMonth,$LocalDay,$LocalHour,$LocalMin,$LocalSec);
                            my $sLifeHMS = sprintf "%u d %u h %02u mn", @lifeHMS;
                            print "<td>$jenkinsYear/$jenkinsMonth/$jenkinsDay $jenkinsHour:$jenkinsMin:$jenkinsSec</td>";
                            print "<td>+ $sLifeHMS</td>";
                            my $curlCmd = "curl -u $jenkinsUser:$passwd $jenkins/job/$jenkinsJobName/lastBuild/consoleText"
                                        . " > $JV_DIR/jv_json_jenkins/${srv}_lastBuild_consoleText_$jenkinsJobName.txt"
                                        . " 2> $JV_DIR/jv_json_jenkins/${srv}_lastBuild_consoleText_$jenkinsJobName.log"
                                        ;
                            system $curlCmd;
                            if( -e "$JV_DIR/jv_json_jenkins/${srv}_lastBuild_consoleText_$jenkinsJobName.txt" ) {
                                print "<td><a href=\"../jv_json_jenkins/${srv}_lastBuild_consoleText_$jenkinsJobName.txt\" target=\"_BLANK\">consoleText</a></td>";
                            }
                            print "</tr>\n";
                        }
                    }
                    else {
                        print "<tr><td>$jenkinsJobName</td><td><img src=\"./images/grey.gif\" alt=\"no build found/stored\"/></td><td> no build found/stored</td><td><a href=\"$jenkins/job/$jenkinsJobName\">$jenkinsJobName</a></td></tr>\n";
                    }
                }
                print "<tr><td>&nbsp;</td></tr>\n";
            }
        }
        unless($realms) {
            my $flagOrphan = 0 ;
            foreach my $job (@{$jenkinsConfig->{'jobs'}}) {
                next if($flagJobs{$job->{'name'}});
                $flagOrphan++;
            }
            if($flagOrphan > 0) {
                print "<tr><td><strong>ALL :</strong></td></tr>\n";
                foreach my $job (@{$jenkinsConfig->{'jobs'}}) {
                    next if($flagJobs{$job->{'name'}});
                    print "<tr><td>$job->{'name'}</td>";
                    system "curl -u $jenkinsUser:$passwd $jenkins/job/$job->{'name'}/lastBuild/api/json > $JV_DIR/jv_json_jenkins/${srv}_lastBuild_$job->{'name'}.json 2> $JV_DIR/jv_json_jenkins/${srv}_lastBuild_$job->{'name'}.log";
                    my $search404 = `grep -i \"ERROR 404\" \"$JV_DIR/jv_json_jenkins/${srv}_lastBuild_$job->{'name'}.json\"`;
                    chomp $search404;
                    unless($search404) {
                        print "<tr><td>$job->{'name'}</td>";
                        if(open JSON,"$JV_DIR/jv_json_jenkins/${srv}_lastBuild_$job->{'name'}.json") {
                            my $infoBuild = decode_json(<JSON>);
                            close JSON;
                            if($infoBuild->{'result'} =~ /SUCCESS/i) {
                                 print "<td><img src=\"./images/green.gif\" alt=\"job success\"/></td><td>$infoBuild->{'result'}</td>";
                            }
                            if($infoBuild->{'result'} =~ /FAILURE/i) {
                                print "<td><img src=\"./images/red.gif\" alt=\"job failed\"/></td><td> $infoBuild->{'result'}</td>";
                            }
                            if($infoBuild->{'result'} =~ /ABORTED/i) {
                                print "<td><img src=\"./images/grey.gif\" alt=\"job aborted\"/></td><td> $infoBuild->{'result'}</td>";
                            }
                            unless($infoBuild->{'result'}) {
                                print "<td><img src=\"./images/yellow.gif\" alt=\"job in progress\"/></td><td> in progress</td>";
                            }
                            print "<td><a href=\"$infoBuild->{'url'}\" target=\"_BLANK\">$job->{'name'}</a></td>";
                            my ($jenkinsYear,$jenkinsMonth,$jenkinsDay,$jenkinsHour,$jenkinsMin,$jenkinsSec) = $infoBuild->{'id'} =~ /^(\d+)\-(\d+)\-(\d+)\_(\d+)\-(\d+)\-(\d+)$/;
                            my @lifeHMS = Delta_DHMS($jenkinsYear,$jenkinsMonth,$jenkinsDay,$jenkinsHour,$jenkinsMin,$jenkinsSec,$LocalYear,$LocalMonth,$LocalDay,$LocalHour,$LocalMin,$LocalSec);
                            my $sLifeHMS = sprintf("%u d %u h %02u mn", @lifeHMS);
                            print "<td>$jenkinsYear/$jenkinsMonth/$jenkinsDay $jenkinsHour:$jenkinsMin:$jenkinsSec</td>";
                            print "<td>+ $sLifeHMS</td>";
                            system "curl -u $jenkinsUser:$passwd $jenkins/job/$job->{'name'}/lastBuild/consoleText > $JV_DIR/jv_json_jenkins/${srv}_lastBuild_consoleText_$job->{'name'}.txt 2> $JV_DIR/jv_json_jenkins/${srv}_lastBuild_consoleText_$job->{'name'}.log";
                            if( -e "$JV_DIR/jv_json_jenkins/${srv}_lastBuild_consoleText_$job->{'name'}.txt" ) {
                                print "<td><a href=\"../jv_json_jenkins/${srv}_lastBuild_consoleText_$job->{'name'}.txt\" target=\"_BLANK\">consoleText</a></td>";
                            }
                            print "</tr>\n";
                        }
                    }
                    else {
                        print "<tr><td>$job->{'name'}</td><td><img src=\"./images/grey.gif\" alt=\"no build found/stored\"/></td><td> no build found/stored</td><td><a href=\"$jenkins/job/$job->{'name'}\">$job->{'name'}</a></td></tr>\n";
                    }
                }
            }
        }
        print "</table>\n";
        print "</div></fieldset><br/>\n";
        goto END_SCAN;
    }
    HTTP_401:
    print "Error 401 Empty password<br/>";
    END_SCAN:
}
