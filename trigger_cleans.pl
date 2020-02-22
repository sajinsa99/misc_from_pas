use strict ;
use warnings;
use diagnostics;

use Getopt::Long;

##############################################################################
##############################################################################
##### declare vars

## options/parameters
my ($param_treshold,$param_landscape,$param_slave,$param_display,$param_dryrun,$param_force);

## misc
my ($xmakemonitoringserver,$port,@buildruntimes,%Slaves,@adm_heartbeat);



##############################################################################
##############################################################################
##### get parameters/options
$Getopt::Long::ignorecase = 0;
GetOptions(
    "t=s"   =>\$param_treshold,
    "l=s"   =>\$param_landscape,
    "s=s"   =>\$param_slave,
    "d=s"   =>\$param_display,
    "dr=s"  =>\$param_dryrun,
    "F=s"   =>\$param_force,
);



##############################################################################
##############################################################################
##### init vars
$xmakemonitoringserver = "xmakemonitoringserver.mo.sap.corp";
$port = 3000;

$ENV{TRESHOLD}  ||= $param_treshold  || "90";
$ENV{LANDSCAPE} ||= $param_landscape || "all";
$ENV{SLAVE}     ||= $param_slave     || "all";
$param_display  ||= "all"; # to display slaves to clean
$param_dryrun   ||= "false";
$param_force    ||= "false";
if($param_display && $param_display !~ /^all$/ && $param_display !~ /^clean$/ ) {
    print "ERROR : -d=$param_display unknown value, available values:all|clean";
    exit 1;
}
if($param_force eq "true" && $param_dryrun eq "true") {
    print "\nWARNING : -dr & -F were set, -F will be ignored\n";
}



##############################################################################
##############################################################################
##### display infos
print "\n";
print "treshold  : $ENV{TRESHOLD}\n";
print "landscape : $ENV{LANDSCAPE}\n";
print "slave     : $ENV{SLAVE}\n";
print "\n";



##############################################################################
##############################################################################
##### get all data
@adm_heartbeat = `curl http://$xmakemonitoringserver:$port/adm_heartbeat`;
chomp @adm_heartbeat;

#### get available runtimes
#json module not isntalled on xmakemonitoring serve
my @json_build_runtimes = `curl --insecure https://github.wdf.sap.corp/raw/xmake-ci/infrastructure/master/data/xmake/runtimes/activeValues.json`;
my $start = 0;
foreach my $line (@json_build_runtimes) {
    if($line =~ /\:\s+\[/) {
            $start = 1;
            next;
    }
    if($line =~ /\]/) {
            $start = 0;
    }
    if($start == 1) {
            my ($runtime) = $line =~ /\"(.+?)\"/i;
            push @buildruntimes , $runtime unless(grep /^$runtime$/ , @buildruntimes);
    }
}
push @buildruntimes , "systemtests" ;



##############################################################################
##############################################################################
##### search slaves to clean
if (scalar @adm_heartbeat > 0) {
    my ($landscape,$hostname_inline,$mount_name,$hostname,$name,$filesystem,$total,$used,$label);
    foreach my $line (@adm_heartbeat) {
            if($line =~ /\[LabelingInfo\]/i) {
                    ($landscape,$hostname_inline,$hostname,$name,$label) = $line
                    =~ /landscape\=\"(.+?)\"\s+hostname_inline\=\"(.+?)\"\s+hostname\=\"(.+?)\"\s+name\=\"(.+?)\"\s+label\=\"(.+?)\"/i ;
                    next unless defined $landscape;
                    next unless defined $hostname;
                    next unless defined $label;
                    next unless defined $name;
                    next unless grep /^$label$/i , @buildruntimes;
                    next if ($ENV{LANDSCAPE} !~ /^all$/i && $ENV{LANDSCAPE} !~ /^$landscape$/i);
                    next if ($ENV{SLAVE}     !~ /^all$/i && ($hostname !~ /^$ENV{SLAVE}/i && $label !~ /^$ENV{SLAVE}/i && $name !~ /^$ENV{SLAVE}/i) );
                    $Slaves{$hostname}{landscape} = $landscape;
                    $Slaves{$hostname}{label}     = $label;
                    $Slaves{$hostname}{name}      = $name;
            }
            if($line =~ /\[AllMountUsage\]/i) {
                    ($landscape,$hostname_inline,$mount_name,$hostname,$name,$filesystem,$total,$used) = $line
                    =~ /\s+landscape\=\"(.+?)\"\s+hostname\_inline\=\"(.+?)\"\s+mount\_name\=\"(.+?)\"\s+hostname\=\"(.+?)\"\s+name\=\"(.+?)\"\s+filesystem\=\"(.+?)\"\s+total\=\"(.+?)\"\s+used\=\"(.+?)\"\s+/i ;
                    next unless defined $landscape;
                    next unless defined $hostname;
                    next unless defined $label;
                    next unless defined $name;
                    next if ($ENV{LANDSCAPE} !~ /^all$/i && $ENV{LANDSCAPE} !~ /^$landscape$/i);
                    next if ($ENV{SLAVE}     !~ /^all$/i && ($hostname !~ /^$ENV{SLAVE}/i && $label !~ /^$ENV{SLAVE}/i && $name !~ /^$ENV{SLAVE}/i) );
                    unless($Slaves{$hostname}{clean}) {
                            if($total && $total > 0 && $used) {
                                    my $percent_used = ( $used / $total ) * 100;
                                    $percent_used    = sprintf("%.0f", $percent_used);
                                    $Slaves{$hostname}{percent_used} = $percent_used ;
                                    if($percent_used >= $ENV{TRESHOLD}) {
                                            $Slaves{$hostname}{clean} = "true";
                                    }  else  {
                                            $Slaves{$hostname}{clean} = "false";
                                    }
                            }  else  {
                                    $Slaves{$hostname}{percent_used} = "unknown";
                                    $Slaves{$hostname}{clean}        = "false";
                            }
                    }
            }
    }
}



##############################################################################
##############################################################################
##### display slaves and trigger clean if needed
if (scalar keys %Slaves > 0) {
    my $CURL_OUT="curl -X GET $xmakemonitoringserver:$port/workspace_cleanup_trigger -s -k --data-urlencode data=";
    print "\n\n";
    print "hostname - landscape - name - label - disk space percent used - clean\n\n";
    my $nb_slaves_to_clean = 0;
    foreach my $hostname (sort keys %Slaves) {
            my $landscape    = $Slaves{$hostname}{landscape} ;
            my $label        = $Slaves{$hostname}{label} ;
            my $name         = $Slaves{$hostname}{name} ;
            my $percent_used = $Slaves{$hostname}{percent_used} || "n/a";
            my $clean        = $Slaves{$hostname}{clean}        || "false";
            next unless defined $landscape;
            $clean = "true" if($param_force eq "true");
            if($param_display eq "all") {
                    print "$hostname - $landscape - $name - $label - $percent_used - $clean\n";
            }
            elsif($param_display eq "clean" && $clean eq "true") {
                    print "$hostname - $landscape - $name - $label - $percent_used - $clean\n";
            }
            if($clean eq "true") {
                    my $trigger_clean_cmd = $CURL_OUT . "\"$hostname,$landscape,\"";
                    print "\ttrigger clean command : $trigger_clean_cmd\n";
                    if($param_dryrun eq "true") {
                            print "dryrun mode detected, no trigger called\n\n";
                            next;
                    }
                    system "$trigger_clean_cmd";
                    $nb_slaves_to_clean++;
                    print "\n";
            }
    }
    print "\nnb trigger sent : $nb_slaves_to_clean\n";
}
print "\n\n";
