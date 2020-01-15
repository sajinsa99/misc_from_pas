##############################################################################
##### declare uses

# basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

# required for the script
use Getopt::Long;
use Sys::Hostname;
use File::Basename;
# for current_dir
use FindBin;
use lib $FindBin::Bin;



##############################################################################
##### declare vars
use vars qw (
    $machine_name
    $current_dir
    $cmd_search_builds
    $flag_build_found
    $count_loop
    $nb_builds_running
);

# options/parameters
use vars qw (
    $opt_help
    $param_project
    $param_build_name
    $opt_tiny_status
    $opt_waitfor
    $param_nb_loop
    $param_duration_loop
    $param_accept_nb_builds_in_parallel
);



##############################################################################
##### declare internal functions
sub init_vars();
sub main();
sub search_running_builds();
sub display_usage();



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "help|?"       =>\$opt_help,
    "project=s"    =>\$param_project,
    "buildname=s"  =>\$param_build_name,
    "ts"           =>\$opt_tiny_status,
    "wf"           =>\$opt_waitfor,
    "n=s"          =>\$param_nb_loop,
    "t=s"          =>\$param_duration_loop,
    "a=s"          =>\$param_accept_nb_builds_in_parallel,
);



##############################################################################
##### MAIN
display_usage() if($opt_help);

init_vars();
main();



##############################################################################
### internal functions
sub init_vars() {
    $machine_name       = hostname();
    $current_dir        = $FindBin::Bin;
    $param_project    ||= "agentry"; # project is like -i=agentry_*.ini or -i=smp3_*.ini
    $cmd_search_builds  = ($^O eq "MSWin32")
                        ? "WMIC PROCESS get Caption,Commandline,Processid | grep -v cmd"
                        : "ps -ef"
                        ;
    $cmd_search_builds .= " | grep -i $param_project | grep -i ini";
    $flag_build_found   = 0; # for code return at the end of script

    if($opt_waitfor) {
        if($param_nb_loop) {
            if( !($param_nb_loop =~ /^\d+$/) ) { # if -n=not numeric value
                if(    ($param_nb_loop =~ /^u$/i)
                    or ($param_nb_loop =~ /^i$/i)
                    or ($param_nb_loop =~ /^d$/i) ) {
                        $param_nb_loop = 122400;
                }
                else {
                    my $warning_msg = "WARNING : $param_nb_loop not recognized,"
                                    . " '-n' could be a number or 'u' (unlimited)"
                                    . " or 'i' (infinite) or 'd' (day)"
                                    ;
                    print "$warning_msg\n";
                    exit;
                }
            }
        }
        else {
            $param_nb_loop = 1;
        }
        if($param_duration_loop) {
            if($param_duration_loop  =~ /^(\d+)[h]$/i) {   # if h for hours
                $param_duration_loop =  $1 * 3600;         # transform to secondes
            }
            if($param_duration_loop  =~ /^(\d+)[m]$/i) {   # if m for minutes
                $param_duration_loop =  $1 * 60;           # transform to secondes
            }
            if($param_duration_loop  =~ /^(\d+)[s]$/i) {   # if s for secondes
                $param_duration_loop =  $1;                # remove 's' to keep value
            }
            # complexe format for psychopath !!! XD
            if(    ($param_duration_loop =~ /^(\d+)[h](\d+)$/i)
                or ($param_duration_loop =~ /^(\d+)\:(\d+)$/i)
                or ($param_duration_loop =~ /^(\d+)[h](\d+)[m]$/i) ) { # if 00h00 or 00h00m or 00:00
                    my $hour = $1;
                    my $min  = $2;
                    # remove first 0 like 01:01
                    ($hour)  =~ s/^0//   if($hour =~ /^0/);
                    ($min)   =~ s/^0//   if($min  =~ /^0/);
                    $param_duration_loop = ($hour * 3600) + ($min * 60) ; # transform to secondes
            }
            # complexe format for mega big psychopath XD
            if(    ($param_duration_loop =~ /^(\d+)[h](\d+)[m](\d+)$/i)
                or ($param_duration_loop =~ /^(\d+)\:(\d+)\:(\d+)$/i)
                or ($param_duration_loop =~ /^(\d+)[h](\d+)[m](\d+)s$/i) ) { # if 00h00m00s or 00h00m00 or 00:00:00
                    my $hour = $1;
                    my $min  = $2;
                    my $sec  = $3;
                    # remove first 0 like 01:01:01
                    ($hour)  =~ s/^0//   if($hour =~ /^0/);
                    ($min)   =~ s/^0//   if($min  =~ /^0/);
                    ($sec)   =~ s/^0//   if($sec  =~ /^0/);
                    # transform to secondes :
                    $param_duration_loop = ($hour * 3600) + ($min * 60) + $sec ;
            }
        }
        else {
            $param_duration_loop = 600; # wait for 10 minutes by default
        }
    }
    else {
        $param_nb_loop       = 1;
        $param_duration_loop = 1;
    }
    $count_loop = 1;
}

sub main() {
    print "\n";
    while(1) {
        if($opt_waitfor) {
            print "\n\n\t==== iteration number : $count_loop/$param_nb_loop ====\n\n";
        }
        search_running_builds();

        if($flag_build_found == 0) {
            if($opt_tiny_status) {
                print "\ngo\n";
            }
            else {
                print "\nAny $param_project build is running on $machine_name\n";
            }
            exit 0;
        }
        else {
            if($opt_tiny_status) {
                print "\nnogo\n";
            }
            if($opt_waitfor) {
                if( $param_accept_nb_builds_in_parallel && ($param_accept_nb_builds_in_parallel < $nb_builds_running)) {
                    if($opt_tiny_status) {
                        print "\ngo\n";
                    }
                    else {
                        print "\n$nb_builds_running build(s) run in parallel but can go\n";
                    }
                    exit 0;
                }
            }
            else {
                exit 1;
            }
        }
        print "\n";
        last if($param_nb_loop == $count_loop);
        $count_loop++;
        $flag_build_found = 0;
        my $counter = 1;
        my $cr      = "\r";
        $| = 1; # Set the 'autoflush' on stdout
        while ($counter <= $param_duration_loop) {
            print ".";
            sleep 1;
            print "\n" if(($counter % 60) == 0); # next line per minute
            $counter++;
        }
    }
}

sub search_running_builds() {
    if(open COMMAND,"$cmd_search_builds 2>&1 |") {
        my %builds_running;
        $nb_builds_running = 0;
        while(<COMMAND>) {
            chomp;
            my $result = $_;
            if($result =~ /\s+\-i\=(.+?)\.ini/i) {
                my $ini_file_name = $1;
                my $basic_ini_file_name = basename $ini_file_name;
                my $arch = "32";
                if($result =~ /\s+\-64/) {
                    $arch = "64";
                }
                #### search real context
                # search qsets for rebuild
                # in case, qset influence in the buildname|context
                my @options;
                if($result =~ /\-q\=/i) {
                    @options = split '-q',$result;
                }
                if($result =~ /\-qset\=/i) {
                    @options = split '-qset',$result;
                }
                my $qsets;
                foreach my $option (sort @options) {
                    next unless($option=~ /\=/);
                    next if($option=~ /Build\.pl/i);
                    ($option) =~ s-\s+.+?$--; # remove unexpected parts
                    $qsets .=" -q$option";
                }
                # build rebuild.pl command line
                my $rebuild_cmd   = "perl $current_dir/rebuild.pl"
                                  . " -i=$ini_file_name.ini"
                                  ;
                if($qsets) {
                    $rebuild_cmd .= " $qsets";
                }
                $rebuild_cmd     .= " -si=context";
                # search buildname (or context)
                my $context = `$rebuild_cmd`;
                chomp $context;
                my $build_name = $context || $basic_ini_file_name;
                if($param_build_name) { # if searching specific build of $project
                    if($param_build_name =~ /^$build_name$/i) {
                        unless($opt_tiny_status) {
                            if( ! $builds_running{$build_name}{$arch} || $opt_waitfor ) { # print only if not already found
                                print "WARNING ! Build $build_name in $arch, is on going\n";
                                $builds_running{$build_name}{$arch} = 1;
                            }
                        }
                        $nb_builds_running++;
                        $flag_build_found = 1;
                    }
                }
                else {
                    unless($opt_tiny_status) {
                        if( ! $builds_running{$build_name}{$arch} || $opt_waitfor ) { # print only if not already found
                            print "WARNING ! Build $build_name in $arch, is on going\n";
                            $builds_running{$build_name}{$arch} = 1;
                        }
                    }
                    $nb_builds_running++;
                    $flag_build_found = 1;
                }
            }
        }
        close COMMAND;
    }
}

sub display_usage() {
    print <<FIN_USAGE;

    Description : $0 can search buils running on $machine_name
This feature is for self-service jenkins to inform to stakeholder
if he can star a new build (through jenkins) or not.

    Usage   : perl $0 [options]
    Example : perl $0 -h

[options]
    -h    argument displays helpful information about builtin commands.
    -p    choose project name (in the prefix of ini file name),
          eg: -p=agentry if ini file name=agentry_cons_client_dev.ini
    -b    choose a specific build name (see in CIS Dashboard)
          eg: -b=agentry_cons_client_dev
    -ts   return a tiny status, thisis helpful for scripting/automation
    -wf   wait for build(s) finished
     -n   choose number of loop, by default, -n=1
          you can also specify
          'u' (unlimited) or 'i' (infinite)
          or 'd' (day),
          in this case, -n=122400 (=nb seconds per day)
          !!! request -wf option !!!
    -t    choose wait time between each iteration, by default -t=1 (1 second)
          you can specify seconds or minutes or hours like below:
            -t=1  for 1 second or -t=1s for 1 second
            -t=1m for 1 minute
            -t=1h for 1 hour
            -t=01:00 or -t=01:00:00     for 1h
            -t=01h00 or -t=01h00m       for 1h
            -t=01h00m00s or -t=01h00m00 for 1h
          $0 will convert this parameter in seconds
          !!! request -wf option !!!
    -a    accept nb builds running in parallel
          !!! request -wf option !!!

FIN_USAGE
exit 0;
}
