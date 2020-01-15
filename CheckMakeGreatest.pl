#############################################################################
##### declare uses

## basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

## required for the script
use Getopt::Long;
use Sys::Hostname;



##############################################################################
##### abbreviations
# cbt : core.build.tools
# bld : build
# rev : revision
# drz : drozpone



##############################################################################
##### declare vars

# system
use vars qw (
    $host_name
    $DROP_DIR
);

# paths
use vars qw (
    $cbt_path
    $DROP_DIR
);

# nexus
use vars qw (
    $nexus_repo
    $nexus_final_version
    $nexus_Suffix
);

# for build
use vars qw (
    $Site
    $Project
    $ini_file
    $component_bld_name
    $current_bld_rev
    $bld_modes
    %bld_status
);

# platforms
use vars qw (
    @platforms
    $param_platforms
);

# triggers
use vars qw (
    $bld_trigger_log_file
    $flag_bld_started
    $triggered_bld
    $trigger_file
);

# for rebuild.pl
use vars qw (
    $CIS_Steps
    @QSets
    $QSet_line_for_rebld_cmd
);

# for newRefBuild
use vars qw (
    $opt_no_greatest
    $opt_gr_trigger
    $opt_drz_declare
);

# for script itself
use vars qw (
    $output_log_file
);

# options / paramaeters without variable listed above
use vars qw (
    $opt_help
);



##############################################################################
##### declare functions
sub display_usage();
sub get_component_build_rev();



##############################################################################
##### get options/parameters
# by alphebetic order
$Getopt::Long::ignorecase = 0;
GetOptions(
    "DZ!"           =>\$opt_drz_declare,
    "GR!"           =>\$opt_gr_trigger,
    "help|?"        =>\$opt_help,
    "ini=s"         =>\$ini_file,
    "modes=s"       =>\$bld_modes,
    "nogreatest!"   =>\$opt_no_greatest,
    "nxfv=s"        =>\$nexus_final_version,
    "nxrepo=s"      =>\$nexus_repo,
    "nxsuffix=s"    =>\$nexus_Suffix,
    "platforms=s"   =>\$param_platforms,
    "qset=s@"       =>\@QSets,
    "steps=s"       =>\$CIS_Steps,
    "tb"            =>\$triggered_bld,
    "tf=s"          =>\$trigger_file,
    "version=s"     =>\$current_bld_rev,
);

$component_bld_name = shift @ARGV;

if($component_bld_name) {
    if($ARGV[0] eq "all") {
        push @platforms,"win32_x86";
        push @platforms,"win64_x64";
        push @platforms,"solaris_sparc";
        push @platforms,"solaris_sparcv9";
        push @platforms,"linux_x86";
        push @platforms,"linux_x64";
        push @platforms,"aix_rs6000";
        push @platforms,"aix_rs6000_64";
        push @platforms,"mac_x86";
        push @platforms,"mac_x64";
        push @platforms,"linux_ppc64";
    }
    else {
        @platforms = @ARGV ;
    }
}
&display_usage() if($opt_help);


##############################################################################
##### init vars

# environment vars
if((scalar @QSets) > 0) {
    foreach (@QSets) {
        my($Variable, $String) = /^(.+?):(.*)$/;
        $ENV{$Variable} = $String;
        $QSet_line_for_rebld_cmd .= " -q=$Variable:$String";
    }
}

$host_name = hostname();
$cbt_path = $ENV{CBTPATH} if($ENV{CBTPATH});
$cbt_path ||= ($^O eq "MSWin32")
             ? "c:/core.build.tools/export/shared"
             : "$ENV{HOME}/core.build.tools/export/shared"
             ;

die "ERROR : $cbt_path not found\n" if( ! -e $cbt_path);
chdir $cbt_path or die "ERROR : cannot chdir into $cbt_path : $!\n";

$Site = $ENV{'SITE'} || "Walldorf";
unless(    $Site eq "Levallois"
        || $Site eq "Walldorf"
        || $Site eq "Vancouver"
        || $Site eq "Bangalore"
        || $Site eq "Paloalto"
        || $Site eq "Lacrosse" ) {
            my $msgError = "ERROR: SITE environment variable"
                         . " or 'perl $0 -s=my_site' must be set\n"
                         . "available sites :"
                         . "   Levallois"
                         . " | Walldorf"
                         . " | Vancouver"
                         . " | Bangalore"
                         . " | Paloalto"
                         . " | Lacrosse"
                         ;
            die "\n$msgError\n";
}
$ENV{'SITE'} = $Site;

if($component_bld_name) {
    $Project = "components";
    $ENV{PROJECT} = $Project || "components";
    require Site;
    $DROP_DIR = $ENV{DROP_DIR};
    $bld_trigger_log_file = "$DROP_DIR/$component_bld_name/trigger.log";
    $flag_bld_started = 0;
}

if($component_bld_name) {
    my $component_bld_rev = &get_component_build_rev();
    $output_log_file = "$DROP_DIR/"
                     . "$component_bld_name/"
                     . "$component_bld_rev/"
                     . "autoGreatest.log"
                     ;
}
else {
        my $cmd_rebld = "perl $cbt_path/rebuild.pl -i=$ini_file";
        $cmd_rebld .= $QSet_line_for_rebld_cmd if($QSet_line_for_rebld_cmd);
        my $Context  = `$cmd_rebld -si=context`;
        chomp $Context;
        $DROP_DIR = `$cmd_rebld -si=dropdir`;
        chomp $DROP_DIR;
        my $bld_rev ||= `$cmd_rebld -si=revision`;
        chomp $bld_rev;
        $output_log_file = "$DROP_DIR/"
                         . "$Context/"
                         . "$bld_rev/"
                         . "autoGreatest.log"
                         ;
}



##############################################################################
##### MAIN
open STDOUT,"| tee -ai $output_log_file";

print "\n\nsee also in $output_log_file\n\n";

my $dateStart = scalar localtime;
print <<INFOS;

\tinfos:
\t------

date/time : $dateStart
HOSTNAME : $host_name
PLATFORM : $^O

INFOS

if($triggered_bld) {
    print "build triggered : yes\n\n";
}
else {
    print "build triggered : no\n\n";
}

if($component_bld_name && -e $bld_trigger_log_file) {
    # bld started with triggerStartbuild.pl, old method
    # get current version
    my $component_bld_rev = &get_component_build_rev();
    print  "\nlast version built: $component_bld_rev\n";
    $current_bld_rev ||= $component_bld_rev || "latest";
    print  "version to promote : $current_bld_rev\n";
    print  "\nbased on trigger file : $bld_trigger_log_file\n";
    if( -e "$DROP_DIR/$component_bld_name/${component_bld_rev}_greatest") {
        print "\n$component_bld_rev is already a greatest, nothing to do\n";
        close STDOUT;
        exit 0;
    }
    open FILE,"$bld_trigger_log_file";
    while (<FILE>) {
        chomp;
        if(/^start\=yes/i) {
            $flag_bld_started = 1;
        }
        if(/^(\S+) greatest=(\S+)/) {
            print  "=== $1 --> $2\n";
            if( ! $bld_status{$1} || ($2 ne "yes") ) {
                $bld_status{$1} = $2 ;
            }
        }
    }
    close FILE;
    if($flag_bld_started == 1) {
        foreach (@platforms) {
            if(%bld_status && ($bld_status{$_} ne "yes")) {
                die "ERROR : build $_ with errors or missing, no greatest\n";
            }
        }
        my $tmpDisplay  = "\nexec : perl $ENV{HOME}/core.build.tools/shared/"
                        . "newrefbuild.pl -jenkins -nocheck -nomail"
                        . " -p=$Project -c=$component_bld_name"
                        . " -g=$current_bld_rev \n"
                        ;
        print  $tmpDisplay;
        if(defined $opt_no_greatest) {
            print  "\n----------> exiting without making greatest\n";
            close STDOUT;
            exit 0 ;
        }
        my $cmd  = "perl $ENV{HOME}/core.build.tools/shared/newrefbuild.pl "
                 . " -jenkins -nocheck -nomail"
                 . " -p=$Project -c=$component_bld_name -g=$current_bld_rev"
                 ;
        system $cmd;
    }
    else {
        print  "\nbuild not started, no need to do a greatest.\n";
    }
}
else {
# otherwise : new method,strongly recommanded
    ($ini_file) =~ s-\\-\/-g; # unix path
    if( -e $ini_file) {
        chdir $cbt_path or die "ERROR : cannot chdir into $cbt_path : $!\n";
        my $cmd_rebld = "perl $cbt_path/rebuild.pl -i=$ini_file";
        $cmd_rebld .= $QSet_line_for_rebld_cmd if($QSet_line_for_rebld_cmd);
        $DROP_DIR ||= `$cmd_rebld -si=dropdir`;
        chomp $DROP_DIR;
        my $Context  = `$cmd_rebld -si=context`;
        chomp $Context;
        $current_bld_rev ||= `$cmd_rebld -si=revision` || "latest";
        chomp $current_bld_rev;
        if( -e "$DROP_DIR/$Context/${current_bld_rev}_greatest") {
            print "\n$current_bld_rev is already a greatest, nothing to do\n";
            close STDOUT;
            exit 0;
        }
        if($triggered_bld) {
            $current_bld_rev = "latest";
            my $flag_bld_started = 0;
            $trigger_file ||= "$DROP_DIR/$Context/trigger.log";
            if(open FILE,$trigger_file) {
                while (<FILE>) {
                    chomp;
                    if(/^start\=yes/i) {
                        $flag_bld_started = 1;
                        last;
                    }
                    if(/^start\=no/i) {
                        $flag_bld_started = 0;
                        last;
                    }
                }
                close FILE;
            }
            if($flag_bld_started == 0) {
                print  "\nbuild not started, no need to do a greatest.\n";
                close STDOUT;
                exit 0;
            }
        }
        my $options = ($CIS_Steps) ? "$CIS_Steps" : "build";
        $options .= ":$bld_modes"       if($bld_modes);
        $options .= ":$param_platforms" if($param_platforms);
        my $go_greatest = 0;
        my $cmdrb = "perl $cbt_path/rebuild.pl";
        $cmdrb   .= " -r=$current_bld_rev"   if($current_bld_rev ne "latest");
        $cmdrb   .= " -i=$ini_file";
        $cmdrb   .= $QSet_line_for_rebld_cmd if($QSet_line_for_rebld_cmd);
        $cmdrb   .= " -oas=$options";
        if(open GENERAL_STATUS,"$cmdrb 2>&1 |") {
            print  "cmd : $cmdrb\n";
            while(<GENERAL_STATUS>) {
                chomp;
                $go_greatest = 1 if(/^general\s+status\s+\:\s+passed$/i);
                print  "$_\n";
            }
            close GENERAL_STATUS;
        }
        if($go_greatest == 1) {
            my $Project = `$cmd_rebld -si=project` ;
            chomp $Project;
            if($Project && $Context) {
                my $cmd = "perl $ENV{HOME}/core.build.tools/shared/"
                        . "newrefbuild.pl -jenkins -nocheck -nomail"
                        . " -p=$Project -c=$Context -g=$current_bld_rev"
                        ;
                my $cmd_rebld = "perl $cbt_path/rebuild.pl -i=$ini_file";
                $nexus_final_version ||= `$cmd_rebld -si=version`;
                chomp $nexus_final_version;
                if($nexus_repo && $nexus_final_version && $nexus_Suffix) {
                    $cmd = "$cmd -nexus=$nexus_repo,"
                         . "$nexus_final_version,"
                         . "$nexus_Suffix"
                         ;
                }
                $cmd   .= " -GR" if($opt_gr_trigger);
                $cmd   .= " -DZ" if($opt_drz_declare);
                print  "\nexec : $cmd\n";
                if(defined $opt_no_greatest) {
                    print  "\n--------> exiting without making greatest\n";
                    close STDOUT;
                    exit 0 ;
                }
                system $cmd;
            }
        }
        else {
            print  "\n===> no greatest\n";
            close STDOUT;
            exit 1;
        }
    }
}

print  "\n";
close STDOUT;
exit 0;



##############################################################################
### internal functions
sub get_component_build_rev() {
    my $this_version;
    if(open VER,"$DROP_DIR/$component_bld_name/version.txt") {
        chomp($this_version = <VER>);
        $this_version = int $this_version;
        close VER;
    }
    return $this_version;
}


sub display_usage() {
    print <<FIN_USAGE;

 $0 will flag a build, the latest rev,
 as a new greatest if compile is green on listed platforms for a build mode.

    Usage   : perl $0 [options]
    Example : perl $0 -h

 [options]
    -h|?    argument displays helpful information about builtin commands.
    -s  step listed in CIS (infra,build,setup,test,smoke,bat),
        by default -s=build
    -m  build mode,
        by default -m=release,debug,releasedebug
    -p  list of platforms to check
            avaialable platforms :
            win32_x86
            solaris_sparc
            linux_x86
            aix_rs6000
            win64_x64
            solaris_sparcv9
            linux_x64
            aix_rs6000_64
            mac_x64
            mac_x86
            linux_ppc64
    -nxrepo     for nexus upload(s) in deploy.your value
    -nxfv       final version of the artifact(s)
    -nxsuffix   suffix version
            e.g.: -nxsuffix=SNAPSHOT
    -nogreatest no execution of newrefbuild.pl
            Can check if a build rev could be promoted as a new greatest
    -tb     for triggered builds, check greatest if build start=yes
    -tf     specifiy trigger file, by default -tf=\$DROPDIR/\$Context/trigger.log

FIN_USAGE
    exit 0;
}
