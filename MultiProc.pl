#!/usr/bin/perl -w

# core
use Date::Calc(qw(Today_and_Now Delta_DHMS));
use POSIX qw(:sys_wait_h);
use File::Basename;
use Data::Dumper;
use Getopt::Long;
use Tie::IxHash;
use File::Path;
use File::Copy;
use Cwd;

use FindBin ();
use lib ($FindBin::Bin);
use Exec;

$|++;

$CURRENTDIR = "$FindBin::Bin";
die("ERROR: TEMP environment variable must be set") unless(my $TEMP=$ENV{TEMP});
$TEMP =~ s/[\\\/]\d+$//;
@PRIORITIES = qw(LOW BELOWNORMAL NORMAL HIGH);
($WAITING, $INPROGRESS, $FINISHED) = (1..3);
$NULLDEVICE = $^O eq "MSWin32" ? "nul" : "/dev/null";
$DEP_EXTENSION = $ENV{DEP_EXTENSION} || "dep";
 
##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"       => \$Help,
           "dashboard=s"  => \$Dashboard,
           "execute!"     => \$Execute,
           "info!"        => \$Info,
           "gmake=s@"     => \@Makefiles,
           "mode=s"       => \$BUILD_MODE,
           "parallel=i"   => \$NumberOfComputers,
           "rank=i"       => \$Rank,
           "source=s"     => \$SRC_DIR,
           "thread=i"     => \$MAX_NUMBER_OF_PROCESSES,
           "64!"          => \$Model);

Usage() if($Help);

$Execute = 1 unless(defined $Execute);
$Info = 1    unless(defined $Info);

$ENV{OBJECT_MODEL} = $OBJECT_MODEL = $Model ? "64" : ($ENV{OBJECT_MODEL} || "32"); 
if($^O eq "MSWin32")    { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64" : "win32_x86"  }
elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc"  }
elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64" : "aix_rs6000"  }
elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64" : "hpux_pa-risc" }
elsif($^O eq "linux")   { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64" : "linux_x86"  }
elsif($^O eq "darwin")  { $PLATFORM = $OBJECT_MODEL==64 ? "mac_x64" : "mac_x86"  }
unless($ENV{NUMBER_OF_PROCESSORS})
{
    if($^O eq "solaris")   { ($ENV{NUMBER_OF_PROCESSORS}) = `psrinfo -v | grep "Status of " | wc -l` =~ /(\d+)/ }
    elsif($^O eq "aix")    { ($ENV{NUMBER_OF_PROCESSORS}) = `lsdev -C | grep Process | wc -l` =~ /(\d+)/ }
    elsif($^O eq "hpux")   { ($ENV{NUMBER_OF_PROCESSORS}) = `ioscan -fnkC processor | grep processor | wc -l` =~ /(\d+)/ }
    elsif($^O eq "linux")  { ($ENV{NUMBER_OF_PROCESSORS}) = `cat /proc/cpuinfo | grep processor | wc -l` =~ /(\d+)/ }
    elsif($^O eq "darwin") { ($ENV{NUMBER_OF_PROCESSORS}) = `system_profiler SPHardwareDataType | grep –i processors|cut –d”:” –f2` }
    warn("ERROR: the environement variable NUMBER_OF_PROCESSORS is unknow") unless($ENV{NUMBER_OF_PROCESSORS});
}
$MAX_NUMBER_OF_PROCESSES ||= $ENV{MAX_NUMBER_OF_PROCESSES} || $ENV{NUMBER_OF_PROCESSORS}+2 || 8;
$MAX_NUMBER_OF_PROCESSES = 60 if($MAX_NUMBER_OF_PROCESSES >60);

$BUILD_MODE ||= $ENV{BUILD_MODE} || "release";
$SRC_DIR    ||= $ENV{SRC_DIR};
if("debug"=~/^$BUILD_MODE/i) { $BUILD_MODE="debug" } elsif("release"=~/^$BUILD_MODE/i) { $BUILD_MODE="release" }
unless(@Makefiles) { print(STDERR "the -g parameter is mandatory\n\n"); Usage() }
unless($SRC_DIR)   { print(STDERR "the -s parameter is mandatory\n\n"); Usage() }
$Dashboard = undef if(!exists($ENV{BUILD_CIS_DASHBOARD_ENABLE}) || $ENV{BUILD_CIS_DASHBOARD_ENABLE}==0);
($HTTPDIR) = $Dashboard =~ /^(.+)[\\\/].+$/ if($Dashboard);
($Phase) = $Dashboard =~ /([^_]+?)_\d+.dat$/ if($Dashboard);
$NumberOfComputers       ||= 1;
$Rank                    ||= 1;
$Rank--;

$ENV{MULTIPROC_MAKEOPTS} = "" unless(exists($ENV{MULTIPROC_MAKEOPTS}));
$ENV{OUTPUT_DIR}  ||= ($ENV{OUT_DIR} || ($SRC_DIR=~/^(.*)[\\\/]/, "$1/$PLATFORM"))."/$BUILD_MODE";
$ENV{BUILD_MODE} = $BUILD_MODE;
$ENV{PLATFORM}   = $PLATFORM;
$ENV{OS_FAMILY}  = $^O eq "MSWin32" ? "windows" : "unix";
$ENV{SRC_DIR}    = $SRC_DIR;

$OUTLOGDIR = $ENV{OUTLOG_DIR} || "$ENV{OUTPUT_DIR}/logs";
$Submit   = $ENV{SUBMIT_LOG} ? "-submit" : "";
$Warnings = 0;
$IsDITA = -d "$SRC_DIR/cms";

########
# Main #
########

my @Start = Today_and_Now();
$ENV{build_parentstepname}=$ENV{build_stepname} if(exists $ENV{build_stepname});
$ENV{build_steptype}="build_unit";

# set %Deps{Area:Unit} = [Command, Priority, Cost, [depends], Order, Status] #
# set %Depends{Unit} = [[depends],Priority,Cost,Area]
tie my %Deps, "Tie::IxHash";
foreach (@Makefiles)
{
    my($Makefile, $Targets) = /^([^=]+)=?(.*)/;

    # Makefile path can be relative to SRC_DIR
    if ( $Makefile !~ m@^[a-zA-Z]:/@ && $Makefile !~ m@^/@ )
    {
      $Makefile=$SRC_DIR . "/" . $Makefile;
    }

    my @Areas = Read("AREAS", $Makefile); # Area List
    my $IsAreaMakefile = @Areas ? 1 : 0;
    ($Areas[0]) = $Makefile =~ /([^\/\\]+).gmk$/ unless($IsAreaMakefile);
    my(@ExpandedAreas, @ExpandedUnits);
    if($Targets)
    {
        if(my($File)=$Targets=~/^=(.+)$/)
        { 
            if(open(TARGETS, $File))
            { 
                $Targets = <TARGETS>;
                close(TARGETS);
            } else {die("ERROR: cannot open $File': $!");}    
        }
        $Targets = join(';', map({/^[^:]+:[^:]+:([^:]+)/} split(/\s*,\s*/, $Targets))) if($Targets=~/^[^;]+:[^;]+:[^;]+:[^;]+/);  # POMs
        foreach my $Target (split(/\s*;\s*/, $Targets))
        {
            $Target = "$Areas[0]:$Target" unless($IsAreaMakefile);
            my($Area, $UnitTarget) = split(":", $Target);
            $UnitTarget ||= "*";

            #Check if wildcard is used (only * and ? are accepted)
            if( $Area =~ /^([-\+]?)(.*[*?].*)$/ ) {
              my $removal_mark=$1;
              my $RE=$2;
              if ( $removal_mark !~ /-/ ){$removal_mark="";}
              $RE=~s/\./\\./g;
              $RE=~s/\*/.*/g;
              $RE=~s/\?/./g;
              #When wildcard is used, the user expects to match only areas having their source code available
              push(@ExpandedAreas, map( { check_regex_match_source_file($_) ? ("${removal_mark}$_:$UnitTarget") : () }  grep(/^$RE$/, @Areas)));
            }
            else { push(@ExpandedAreas, "$Area:$UnitTarget") }
        }
        @ExpandedAreas = grep({my $AreaTarget="-$_"; !grep({$AreaTarget=~/^$_/} @ExpandedAreas)} grep(/^[^-]/, @ExpandedAreas));
        $Warnings = 1;
    }
    else { @ExpandedAreas = map({"$_:*"} @Areas) }
    foreach my $Target (@ExpandedAreas) 
    {
        my($Area, $UnitTargets) = split(":", $Target);
        my $Make = $IsAreaMakefile ? "$SRC_DIR/$Area/$Area.gmk" : $Makefile;
        #In case an area is versionned (Area==A/1.2.3) the path "$Area/$Area.gmk" calculated above won't work. Fixing this in the line below:
        $Make =~ s/\/[^\/\\]+.gmk/.gmk/ unless(-e $Make);
        my @Units = Read('UNITS', $Make); # Unit List
        my(@ExpandedUnits);
        foreach my $Target (split(/\s*,\s*/, $UnitTargets))
        {
            if(($RE) = $Target =~ /^-(.*[*?].*)$/) { $RE=~s/\./\\./g; $RE=~s/\*/.*/g; $RE=~s/\?/./g; push(@ExpandedUnits, map({"-$_"} grep(/^$RE$/, @Units))) }
            elsif(($RE) = $Target =~ /^\+?(.*[*?].*)$/) { $RE=~s/\./\\./g; $RE=~s/\*/.*/g; $RE=~s/\?/./g; push(@ExpandedUnits, grep(/^$RE$/, @Units)) }
            else { push(@ExpandedUnits, $Target) }
        }
        @ExpandedUnits = grep({my $Target="-$_"; !grep({$Target =~ /^$_$/} @ExpandedUnits)} grep(/^[^-]/, @ExpandedUnits)) if(grep(/^-/, @ExpandedUnits));
        map({$Deps{"$Area:$_"}=$Make} @ExpandedUnits);
        $Warnings = 1;

        map({$Depends{$_}=[undef, undef, undef, $Area] } @Units);
#        my $Depfile;
#        ($Depfile = $Make) =~ s/\.gmk$/.$ENV{OS_FAMILY}$OBJECT_MODEL.$DEP_EXTENSION/;
#        ($Depfile = $Make) =~ s/\.gmk$/.$ENV{OS_FAMILY}.$DEP_EXTENSION/ unless(-e $Depfile);
#        ($Depfile = $Make) =~ s/\.gmk$/.$PLATFORM.$DEP_EXTENSION/ unless(-e $Depfile);
        my $Depfile = $Make;
        if(0)
        {
            $Depfile =~ s/\.gmk$/.$ENV{OS_FAMILY}$OBJECT_MODEL.dep/;
            ($Depfile = $Make) =~ s/\.gmk$/.$ENV{OS_FAMILY}.dep/ unless(-e $Depfile);
        }
        else { $Depfile =~ s/\.gmk$/.$ENV{OS_FAMILY}.dep/ }
        ($Depfile = $Make) =~ s/\.gmk$/.$PLATFORM.dep/ unless(-e $Depfile);
        if(open(DEP, $Depfile))
        {
            while(<DEP>)
            {
                if(/^\s*(.+)_deps\s*=\s*\$\(.+,\s*([^,]*?)\s*\)/)
                {
                    unless(exists($Depends{$1})) { warn("WARNING: $1 is obsolete in $Depfile"); next }
                    warn("ERROR: $1 is duplicated in $Depfile and $SRC_DIR/${$Depends{$1}}[3]/${$Depends{$1}}[3].$ENV{OS_FAMILY}",($OBJECT_MODEL==64?$OBJECT_MODEL:""),".$DEP_EXTENSION.") if($Area ne ${$Depends{$1}}[3]);
                    my @Depends = split(/\s+/, $2);
                    ${$Depends{$1}}[0] = @Depends ? \@Depends : undef;   
                    @{$Depends{$1}}[1,2] = ("DEFAULT", 0) unless(${$Depends{$1}}[1]); # if priority is undef, dependencies are lost later. So a default priority must be absolutly set !
                }
                elsif(/^\s*(.+)_prio\s*=\s*(.+)\s*,\s*(\d+)/)
                { 
                    unless(exists($Depends{$1})) { warn("WARNING: $1 is obsolete in $Depfile"); next }
                    @{$Depends{$1}}[1,2] = ($2, $3);
                }
            }
            close(DEP);
        } else { warn("WARNING: cannot open '$Depfile': $!") if(@Units) }
    }
}
    
my $UnitOrder = 0;
foreach my $AreaUnit (keys(%Deps))
{
    my($Area, $Unit) = split(":", $AreaUnit);
    my $Make = $Deps{$AreaUnit};
    if($^O eq "MSWin32") { $Make =~ s/\//\\/g } else { $Make =~ s/\\/\//g }
    my($Path, $Name) = $Make =~ /^(.+)[\\\/]([^\\\/]+\.gmk)$/;
    my($raDepends, $Priority, $Cost);
    if(exists($Depends{$Unit}) && ${$Depends{$Unit}}[1]) { ($raDepends, $Priority, $Cost) = @{$Depends{$Unit}}[0..2] }
    else { warn("WARNING: dependencies of $Unit does not exist in $Area dependency file"); ($raDepends, $Priority, $Cost) = (undef, "DEFAULT" ,0) } 
    $Priority = $Priority=~/^DEFAULT$/ ? 0 : ($Priority=~/^LOW$/ ? -4 : ($Priority=~/^BELOWNORMAL$/ ? -3 : ($Priority=~/^NORMAL$/ ? -2 : ($Priority=~/^HIGH$/ ? -1: 0))));
    mkpath("$TEMP/$Area/$Unit") or die("ERROR: cannot mkpath '$TEMP/$Area/$Unit': $!") unless(-e "$TEMP/$Area/$Unit");
    my $Command = $^O eq "MSWin32" ? "cd /D \"$Path\" & set TEMP=$TEMP\\$Area\\$Unit& set TMP=$TEMP\\$Area\\$Unit& set TMPDIR=$TEMP\\$Area\\$Unit& make $ENV{MULTIPROC_MAKEOPTS} -i -f $Name $Unit nodeps=1" : "cd $Path ; export TEMP=$TEMP/$Area/$Unit ; export TMP=$TEMP/$Area/$Unit ; export TMPDIR=$TEMP/$Area/$Unit ; make $ENV{MULTIPROC_MAKEOPTS} -i -f $Name $Unit nodeps=1";
    
    my @Depends;
    foreach my $DepUnit (@{$raDepends})
    {
        next unless(exists($Depends{$DepUnit}));
        my $DepArea  = ${$Depends{$DepUnit}}[3];
        next unless(exists($Deps{"$DepArea:$DepUnit"}));
        push(@Depends, "$DepArea:$DepUnit");
    }
    $Deps{$AreaUnit} = [$Command, $Priority, $Cost, \@Depends, ++$UnitOrder, $WAITING]; 
}

foreach my $AreaUnit (keys(%Deps))
{
    my($raDepends) = @{$Deps{$AreaUnit}}[3];
    foreach my $DependAreaUnit (@{$raDepends}) { ${$Deps{$DependAreaUnit}}[1] = 1 if(${$Deps{$DependAreaUnit}}[1] == 0) }
}

## set @Machines = [Weight, $rhUnits] ##
if($NumberOfComputers > 1)
{
    my @Leaves;
    foreach my $Unit (keys(%Deps))
    {
        my($Priority, $Cost) = @{$Deps{$Unit}}[1,2];
        next if($Priority > 0); # with son
        my %Parents;
        Parents($Unit, \%Parents);
        map({$Cost+=${$Deps{$_}}[3]} keys(%Parents));
        push(@Leaves, [$Unit, $Cost, \%Parents]); 
    }
    @Leaves = sort({${$b}[1]<=>${$a}[1]} @Leaves); # sorted by Weight
    
    for(my $i=0; $i<$NumberOfComputers; $i++) { $Machines[$i] = [0, undef] } 
    my %AllocatedUnits;
    foreach(@Leaves)
    {
        # to find the least loaded machine
        my $MachineMin = 0;
        for(my $i=0; $i<$NumberOfComputers; $i++)
        {
            $MachineMin = $i if(${$Machines[$i]}[0] < ${$Machines[$MachineMin]}[0]);
        }
        
        # to find the least expensive unit in terms of duplication
        my $UnitMin = 0;
        my $DuplicationCost = 100000;
        for(my $j=0; $j<@Leaves; $j++)
        {
            my($Unit, $Cost, $rhDepends) = @{$Leaves[$j]};
            next if(exists($AllocatedUnits{$Unit}));
            #my $Cost = DuplicationCost($Unit, $Cost, $rhDepends, $MachineMin);
            if($Cost < $DuplicationCost) { $UnitMin = $j;  $DuplicationCost = $Cost }
        }

        # to load the Min Machine with Min Unit and their parent units
        my($Unit, $rhDepends) = @{$Leaves[$UnitMin]}[0,2];
        ${${$Machines[$MachineMin]}[1]}{$Unit} = undef;      # Unit
        ${$Machines[$MachineMin]}[0] += ${$Deps{$Unit}}[3];  # Weight
        foreach my $Unit (keys(%{$rhDepends}))
        {
            next if(exists(${${$Machines[$MachineMin]}[1]}{$Unit}));
            ${${$Machines[$MachineMin]}[1]}{$Unit} = undef;      # Parent Unit 
            ${$Machines[$MachineMin]}[0] += ${$Deps{$Unit}}[3];  # Parent Weight;
        }
        $AllocatedUnits{$Unit} = undef;
    }
    @Machines = sort({${$b}[0] <=> ${$a}[0]} @Machines); # machines sorted by Weight
    #map({ $ExcludeDeps{$_}=undef unless(exists(${${$Machines[$Rank]}[1]}{$_})) } keys(%Deps));
    $NumberOfCommands = keys(%{${$Machines[$Rank]}[1]});

    ## debug ##
    my $Cost = 0;
    DEBUGUNIT: foreach my $Unit (keys(%Deps))
    {
        $Cost += ${$Deps{$Unit}}[3];
        for(my $i=0; $i<@Machines; $i++)
        {
            next DEBUGUNIT if(exists(${${$Machines[$i]}[1]}{$Unit}));
        }
        print("$Unit is missing !!!!\n");
    }
    print("Weight: ", HHMMSS($Cost), "\n");
    for(my $i=0; $i<@Machines; $i++)
    {
        print("Machine $i (",HHMMSS(${$Machines[$i]}[0]),"): ", scalar(keys(%{${$Machines[$i]}[1]})),"/", scalar(keys(%Deps)), "\n");
        foreach my $Unit (keys(%{${$Machines[$i]}[1]}))
        {
            print("\t$Unit (", HHMMSS(${$Deps{$Unit}}[3]), ")\n");
        }
    }
    ## fin debug ##
}
else { $NumberOfCommands = keys(%Deps) }


# Critical Path #
foreach my $AreaUnit (keys(%Deps))
{
    my %Loops;
    $CriticalPaths{$AreaUnit} = CriticalPath($AreaUnit, \%Loops, 0);
}

my @CriticalPaths = sort({ $CriticalPaths{$b} <=> $CriticalPaths{$a} } keys(%CriticalPaths));
for(my $i=0; $i<$MAX_NUMBER_OF_PROCESSES && $i<@CriticalPaths; $i++)
{
    print("### Critical Path $i ###\n");
    my $AreaUnit = $CriticalPaths[$i];
    my $TotalCost = $CriticalPaths{$AreaUnit};
    
    my($Cost, $raDepends) = @{$Deps{$AreaUnit}}[2,3];
    print("\t$AreaUnit:$Cost\n");
    while($raDepends && @{$raDepends})
    {
        $AreaUnit = ${$raDepends}[0];
        foreach my $ParentAreaUnit (@{$raDepends})
        {
            $AreaUnit = $ParentAreaUnit if($CriticalPaths{$ParentAreaUnit} > $CriticalPaths{$AreaUnit});
            ${$Deps{$AreaUnit}}[1] = 2 if(${$Deps{$AreaUnit}}[1]>=0);
        }
        ($Cost, $raDepends) = @{$Deps{$AreaUnit}}[2,3];
        print("\t$AreaUnit:$Cost\n");
    }
    print("Total: ", HHMMSS($TotalCost), "\n");
}
map({ ${$Deps{$_}}[1]+=4 if(${$Deps{$_}}[1]<0) } keys(%Deps));

## Run ##
exit unless($Execute);
warn("ERROR: no found build unit, nothing to do") unless(keys(%Deps));

if($Dashboard)
{
    my @Errors;
    $Errors[0] = undef;
    if(open(DAT, $Dashboard))
    {
        local $/ = undef; 
        eval <DAT>;
        close(DAT);
        for(my $i=1; $i<@Errors; $i++)
        {
            my($NumberOfErrors, $LogFile, $SummaryFile, $Area, $Start, $Stop) = @{$Errors[$i]};
            next unless($Area);
            my($Unit) = $LogFile =~ /^.*?([^\\\/]+?)=/;
            $Units{$Unit} = undef; 
        }   
    }
    else
    { 
        my($DashboardPath) = $Dashboard =~ /^(.*)[\\\/]/; 
        unless(-e $DashboardPath)
        {
            eval { mkpath ($DashboardPath) };
            warn("ERROR: cannot mkpath '$DashboardPath': $!") if ($@);
        }
    }
    unless($IsDITA)
    {
        foreach my $AreaUnit (sort({ ${$Deps{$a}}[4]<=>${$Deps{$b}}[4] } keys(%Deps)))
        {
            my($Area, $Unit) = split(":", $AreaUnit);
            push(@Errors, [undef, "Host_".($Rank+1)."/$Unit=${PLATFORM}_${BUILD_MODE}_$Phase.log", "Host_".($Rank+1)."/$Unit=${PLATFORM}_${BUILD_MODE}_summary_$Phase.txt", $Area]) unless(exists($Units{$Unit}));
        }
    }
    if(open(DAT, ">$Dashboard"))
    {
        $Data::Dumper::Indent = 0;
        print DAT Data::Dumper->Dump([\@Errors], ["*Errors"]);
        close(DAT);
    } else { warn("ERROR: cannot open '$Dashboard': $!") }
}

$jobs = Exec->new;
$NumberOfNoFinishedCommands = $NumberOfProcess = 0;
UNT: foreach my $AreaUnit (sort({${$Deps{$b}}[1]<=>${$Deps{$a}}[1] || ${$Deps{$a}}[4]<=>${$Deps{$b}}[4]} (keys(%Deps))))
{
    last if($NumberOfProcess>=$MAX_NUMBER_OF_PROCESSES); # no need to continue the loop, maximum of process loaded !
    my($Area, $Unit) = split(":", $AreaUnit);
    my($Command, $Priority, $Cost, $raDepends, $Order, $Status) = @{$Deps{$AreaUnit}};
    next if(@{$raDepends});
    mkpath("$OUTLOGDIR/$Area") or die("ERROR: cannot open '$OUTLOGDIR/$Area': $!") unless(-e "$OUTLOGDIR/$Area");
    my $PID;
    $ENV{UNIT} = $Unit;
    if($^O eq "MSWin32") { $PID = CreateFork("echo === Build start: ".time()." >$OUTLOGDIR/$Area/$Unit.log & $Command >>$OUTLOGDIR/$Area/$Unit.log 2>&1", $Priority, $AreaUnit) }
    else { $PID = CreateFork("echo === Build start: ".time()." >$OUTLOGDIR/$Area/$Unit.log ; $Command >>$OUTLOGDIR/$Area/$Unit.log 2>&1", $Priority, $AreaUnit) }
    if(defined $PID)
    {
        ${$Deps{$AreaUnit}}[5] = $INPROGRESS;
        $PIDs{$PID} = $AreaUnit;
    }
}

$pid = -1;
do
{
    $pid = $jobs->wait();

    if(exists($PIDs{$pid}))
    {
        my $AreaUnit = $PIDs{$pid};
        # Because open/fork are performed not only for running build targets but also for process_logs, some pid attached to process_logs() command can be returned changing & damaging potentially internal counters values
        $NumberOfProcess--;
        $NumberOfNoFinishedCommands++;

        my($Area, $Unit) = split(":", $AreaUnit);
        ${$Deps{$AreaUnit}}[5] = $FINISHED;
        my($Command, $Priority, $Cost, $raDepends, $Order, $Status) = @{$Deps{$AreaUnit}};
        print("---$AreaUnit $NumberOfProcess($NumberOfNoFinishedCommands/$NumberOfCommands) at ", scalar(localtime()), "\n");
        system("echo === Build stop: ".time()." >>$OUTLOGDIR/$Area/$Unit.log");
        
        my($NumberOfErrors, $Start, $Stop);
        $ENV{area} = $Area;
        $ENV{order} = $Order;
        if(open(LOG, "perl $CURRENTDIR/process_log.pl $Submit -real $OUTLOGDIR/$Area/$Unit.log 2>&1 |"))
        {
            while(<LOG>)
            { 
                print;
                if(/^=\+=Errors detected: (\d+)/i) { $NumberOfErrors = $1 }
                elsif(/^=\+=Start: (.+)$/i)        { $Start = $1 }
                elsif(/^=\+=Stop: (.+)$/i)         { $Stop = $1 }
            }
            close(LOG);
        } else { warn("ERROR: cannot run 'perl $CURRENTDIR/process_log.pl $Submit -real $OUTLOGDIR/$Area/$Unit.log 2>&1': $!"); }
        delete($ENV{area});
        delete($ENV{order});

        if($Dashboard)
        {
            if($IsDITA)
            {
                $Errors[0] += $NumberOfErrors;
                push(@Errors, [$NumberOfErrors, "Host_".($Rank+1)."/$Unit=${PLATFORM}_${BUILD_MODE}_$Phase.log", "Host_".($Rank+1)."/$Unit=${PLATFORM}_${BUILD_MODE}_summary_$Phase.txt", $Area, $Start, $Stop]);
            }
            else
            {
                my @StartDashboard = Today_and_Now();
                my @Errors;
                if(open(DAT, $Dashboard)) { eval <DAT>; close(DAT) }
                else { warn("ERROR: cannot open '$Dashboard': $!") }
                for(my $i=1; $i<@Errors; $i++)
                {
                    my($LogFile, $Ar) = @{$Errors[$i]}[1,3];
                    my($BuildUnit) = $LogFile =~ /^.*?([^\\\/]+?)=/;
                    if($Unit eq $BuildUnit && $Area eq $Ar)
                    {
                        $Errors[$i] = [$NumberOfErrors, "Host_".($Rank+1)."/$Unit=${PLATFORM}_${BUILD_MODE}_$Phase.log", "Host_".($Rank+1)."/$Unit=${PLATFORM}_${BUILD_MODE}_summary_$Phase.txt", $Area, $Start, $Stop];
                        copy("$OUTLOGDIR/$Area/$Unit.log", "$HTTPDIR/Host_".($Rank+1)."/$Unit=${PLATFORM}_${BUILD_MODE}_$Phase.log") or warn("ERROR: cannot copy '$OUTLOGDIR/$Area/$Unit.log': $!");
                        copy("$OUTLOGDIR/$Area/$Unit.summary.txt", "$HTTPDIR/Host_".($Rank+1)."/$Unit=${PLATFORM}_${BUILD_MODE}_summary_$Phase.txt") or warn("ERROR: cannot copy '$OUTLOGDIR/$Area/$Unit.summary.txt': $!");
                        $Errors[0] += $NumberOfErrors;
                        last;
                    } 
                }
                if(open(DAT, ">$Dashboard"))
                {
                    $Data::Dumper::Indent = 0;
                    print DAT Data::Dumper->Dump([\@Errors], ["*Errors"]);
                    close(DAT);
                } else { warn("ERROR: cannot open '$Dashboard': $!") }
                printf("dashboard for %s took: %u h %02u mn %02u s\n", $Unit, (Delta_DHMS(@StartDashboard, Today_and_Now()))[1..3]);
            }
        }
    }

    $NewFork = 0;
    UNIT: foreach my $AreaUnit (sort({${$Deps{$b}}[1]<=>${$Deps{$a}}[1] || ${$Deps{$a}}[4]<=>${$Deps{$b}}[4]} (keys(%Deps))))
    {
        my($Area, $Unit) = split(":", $AreaUnit);
        my($Command, $Priority, $Cost, $raDepends, $Order, $Status) = @{$Deps{$AreaUnit}};
        next if($Status != $WAITING);

        foreach my $ParentAreaUnit (@{$raDepends}) { next UNIT if(${$Deps{$ParentAreaUnit}}[5] != $FINISHED) }
        mkpath("$OUTLOGDIR/$Area") or die("ERROR: cannot open '$OUTLOGDIR/$Area': $!") unless(-e "$OUTLOGDIR/$Area");
        my $PID;
        $ENV{UNIT} = $Unit;
        if($^O eq "MSWin32") { $PID = CreateFork("echo === Build start: ".time()." >$OUTLOGDIR/$Area/$Unit.log & $Command >>$OUTLOGDIR/$Area/$Unit.log 2>&1", $Priority, $AreaUnit) }
        else { $PID = CreateFork("echo === Build start: ".time()." >$OUTLOGDIR/$Area/$Unit.log ; $Command >>$OUTLOGDIR/$Area/$Unit.log 2>&1", $Priority, $AreaUnit) }
        if(defined $PID)
        {
            ${$Deps{$AreaUnit}}[5] = $INPROGRESS;
            $PIDs{$PID} = $AreaUnit;
        }
        $NewFork = 1;
        last if($NumberOfProcess >= $MAX_NUMBER_OF_PROCESSES);
    }
} until $pid == -1 && $NewFork == 0;

if($Dashboard and $IsDITA)
{
    my @StartDashboard = Today_and_Now();
	my @Errs = @Errors;
    if(open(DAT, $Dashboard))
    {
        local $/ = undef; 
        eval <DAT>;
        close(DAT);
	} else { warn("ERROR: cannot open '$Dashboard': $!") }
    for(my $i=1; $i<@Errs; $i++)
    {
        my($LogFile, $Area) = @{$Errs[$i]}[1,3];
        my($Unit) = $LogFile =~ /^.*?([^\\\/]+?)=/;
        copy("$OUTLOGDIR/$Area/$Unit.log", "$HTTPDIR/Host_".($Rank+1)."/$Unit=${PLATFORM}_${BUILD_MODE}_$Phase.log") or warn("ERROR: cannot copy '$OUTLOGDIR/$Area/$Unit.log': $!");
        copy("$OUTLOGDIR/$Area/$Unit.summary.txt", "$HTTPDIR/Host_".($Rank+1)."/$Unit=${PLATFORM}_${BUILD_MODE}_summary_$Phase.txt") or warn("ERROR: cannot copy '$OUTLOGDIR/$Area/$Unit.summary.txt': $!");
		push(@Errors, $Errs[$i]);
	}
    if(open(DAT, ">$Dashboard"))
    {
        $Data::Dumper::Indent = 0;
        print DAT Data::Dumper->Dump([\@Errors], ["*Errors"]);
        close(DAT);
    } else { warn("ERROR: cannot open '$Dashboard': $!") }
    printf("dashboard took: %u h %02u mn %02u s\n", (Delta_DHMS(@StartDashboard, Today_and_Now()))[1..3]);
}

foreach my $AreaUnit (keys(%Deps))
{
    my($Command, $Priority, $Cost, $raDepends, $Order, $Status) = @{$Deps{$AreaUnit}};
    warn("ERROR: $AreaUnit will be not executed because of ", join(',', grep({${$Deps{$_}}[5] != $FINISHED} @{$raDepends})), " is not FINISHED\n") if($Status != $FINISHED);
}
printf("execution took: %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

#############
# Functions #
#############

sub Read 
{
    my($Variable, $Makefile) = @_;

    my $Values;
    my $CurrentDir = getcwd();
    my($DirName) = $Makefile =~ /^(.+)[\\\/]/;
    my $IsFound = 0;
    chdir($DirName) or warn("WARNING: cannot chdir '$DirName': $!");
    if(open(MAKE, "make $ENV{MULTIPROC_MAKEOPTS} -f $Makefile INIT_PHASE=1 display_\L$Variable 2>$NULLDEVICE |"))
    {
        while(<MAKE>)
        {
            $IsFound = 1 if(/\s*$Variable\s*=/);
            last if(($Values) = /\s*$Variable\s*=\s*(.+)$/i);
        }
        close(MAKE);
    }
    chdir($CurrentDir) or die("ERROR: cannot chdir '$CurrentDir': $!");
    unless($IsFound)
    {
        if(open(MAKE, $Makefile))
        {
            while(<MAKE>)
            {
                next unless(($Values) = /^\s*$Variable\s*:?=\s*([^\\]+)\s*/);
                if(/\\\s*$/)
                {
                    while(<MAKE>)
                    {
                        next if(/^#/);
                        chomp;
                        $Values .= " $1" if(/\s*([^\\]+)\s*\\?/);
                        last unless(/\\\s*$/);
                    }
                }
                last;
            }
            close(MAKE);
        }
    }
    warn("WARNING: $Variable not found in '$Makefile'") if(!$Values && $Variable ne "AREAS");
    $Values ||= "";
    chomp($Values);
    $Values =~ s/^\s+//;
    $Values =~ s/\s+$//;
    return split(/\s+/, $Values);
}

sub CriticalPath
{
    my($AreaUnit, $rhLoops, $Level) = @_;
    return $CriticalPaths{$AreaUnit} if(exists($CriticalPaths{$AreaUnit}));
    
    my($Cost, $raDepends) = @{$Deps{$AreaUnit}}[2,3];
    my $ParentCriticalPath = 0;
    ${$rhLoops}{$AreaUnit} = undef;
    foreach my $ParentAreaUnit (@{$raDepends})
    {
        if(exists(${$rhLoops}{$ParentAreaUnit}))
        {
            warn("ERROR: a dependency loop exists :");
            my @Nodes;
            IsLooping($ParentAreaUnit, \@Nodes, 0);
            print("end dependency loop.\n");
            next;
        }
        $CriticalPaths{$ParentAreaUnit} = CriticalPath($ParentAreaUnit, $rhLoops, $Level+1);
        $ParentCriticalPath = $CriticalPaths{$ParentAreaUnit} if($CriticalPaths{$ParentAreaUnit} > $ParentCriticalPath);
    }
    delete ${$rhLoops}{$AreaUnit};
    return $Cost += $ParentCriticalPath;
}

sub IsLooping
{
    my($Area, $raNodes, $Level) = @_;

    return 1 if(grep({$_ eq $Area} @{$raNodes}));
    push(@{$raNodes}, $Area);
    foreach my $ParentArea (@{${$Deps{$Area}}[3]})
    {
        if(IsLooping($ParentArea, $raNodes, $Level+1))
        { 
            if(grep({$_ eq $ParentArea} @{$raNodes}))
            {
                print("\t$ParentArea\n");
                @{$raNodes} = grep({$_ ne $ParentArea} @{$raNodes});
                return 1;
            }
            return 0;
        }
    }
    pop(@{$raNodes});
    return 0;
}

sub Parents
{
    my($Unit, $rhParents) = @_;
    foreach my $Depend (@{${$Deps{$Unit}}[3]}) # $raDepends
    {
        next if(exists(${$rhParents}{$Depend}) || ${$Deps{$Depend}}[5]==$FINISHED);
        ${$rhParents}{$Depend} = undef;
        Parents($Depend, $rhParents);
    }
}

sub DuplicationCost
{
    my($Unit, $Cost, $rhParents, $MachineIndex) = @_;

    $Cost -= ${$Deps{$Unit}}[2];
    UNIT: foreach my $ParentUnit (keys(%{$rhParents}))
    {
        if(exists(${${$Machines[$MachineIndex]}[1]}{$ParentUnit})) { $Cost-=${$Deps{$ParentUnit}}[2]; next }
        for(my $i=0; $i<@Machines; $i++)
        {
            next if($i == $MachineIndex);
            next UNIT if(exists(${${$Machines[$i]}[1]}{$ParentUnit}));
        }
        $Cost -= ${$Deps{$ParentUnit}}[2];
    }
    return $Cost;
}

sub CreateFork
{
    my($Command, $Priority, $Name) = @_;
    
    my $job=$jobs->start($SRC_DIR, $Command, $Priority);
    if(defined $job) {
        $NumberOfProcess++;
        print("+++$Name =$PRIORITIES[$Priority]= $NumberOfProcess($NumberOfNoFinishedCommands/$NumberOfCommands) at ", scalar(localtime()), "\n");    	
    }
    return $job;
}

sub HHMMSS {
    my($Difference) = @_;
    my $s = $Difference % 60;
    $Difference = ($Difference - $s)/60;
    my $m = $Difference % 60;
    my $h = ($Difference - $m)/60;
    return sprintf("%03u h %02u mn %02u s", $h, $m, $s);
}

#In case wildcard is used in makefile syntax, the user expects to only match existing makefiles so this function checks that.
sub check_regex_match_source_file
{
  my($matched_area) = @_;
  my $Makefile = "$SRC_DIR/$matched_area/$matched_area.gmk";
  if ( -f $Makefile ) { return 1;}
  else {$Makefile =~ s/\/[^\/\\]+.gmk/.gmk/;} #Taking care of versionned areas, where $matched_area can be "A/1.2.3", in this case the path "$Area/$Area.gmk" won't work.
  return ( -f $Makefile );
}

sub Usage
{
   print <<USAGE;
   Usage   : MultiProc.pl [options]
             MultiProc.pl -h.elp|?
   Example : MultiProc.pl -g=aurora.gmk 
    
   [options]
   -help|?     argument displays helpful information about builtin commands.
   -d.ashboard specifies the dashboard .dat file name.
   -e.xecute   to execute the makefile (-e.xecute) or not (-noe.execute) but to display makefile errors, default is -execute.
   -i.nfo      displays makefile errors (-i.nfo) or not (-noi.nfo), default is -info.
   -g.make     specifies an array of the makefiles with targets, the syntax is makefile[=area[:unit,unit,..];area[:unit,unit,..];..] or makefile=POM,POM,... or makefile==filepath
   -m.ode      may be either d.ebug or r.elease, default is release.
   -p.arallel  specifies the number of machines, default is 1.
   -r.ank      specifies the rank of this machine, default is 1.
   -s.ource    specifies the root source dir, default is \$ENV{SRC_DIR}.
   -t.hread    specifies the maximum number of simultaneous threads, default is MAX_NUMBER_OF_PROCESSES or NUMBER_OF_PROCESSORS+2.
   -64         forces the 64 bits (-64) or not (-no64), default is -no64 i.e 32 bits.
USAGE
    exit;
}
