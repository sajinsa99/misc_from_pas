##############################################################################
##### declare uses

# basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

# required for the script
use File::Path;
use Getopt::Long;
use Sys::Hostname;



##############################################################################
##### abbreviations
# cl : changelist
# cspec : cspec



##############################################################################
##### declare vars

# system
use vars qw (
    $host_name
);

# for p4
use vars qw (
    $p4
    %rootDir_for_cspec
);

# options / paramaeters without variable listed above
use vars qw (
    $opt_help
    $param_cspec
    $opt_quiet_mode
    $opt_force_delete
);



##############################################################################
##### declare functions
sub p4_login();
sub get_all_cspecs();
sub delete_this_cspec($);
sub delete_pending_cls_for_this_cspec($);
sub revert_opened_files_for_this_cspec($);

sub display_usage();
sub start_script();
sub end_script();



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "F"         =>\$opt_force_delete,
    "Q"         =>\$opt_quiet_mode,
    "c=s"       =>\$param_cspec,
    "help|?"    =>\$opt_help,
);



##############################################################################
##### init vars
$host_name = hostname();



##############################################################################
##### MAIN
&display_usage() if($opt_help);

&start_script();

&p4_login();
&get_all_cspecs();

if(%rootDir_for_cspec) {
    while( my ($cspec,$rootdir) = each %rootDir_for_cspec) {
        next if($param_cspec && !($param_cspec eq $cspec));
        print "\n$cspec - $rootdir\n";
        if( ! -e $rootdir) {
            if($opt_quiet_mode) {
                &delete_this_cspec($cspec);
            }
            else  {
                my $question = "$rootdir not found,"
                             . " $cspec could be deleted,"
                             . " do you want to delete it (yes/no) ? :"
                             ;
                print "$question\n";
                my $rep = <STDIN>;
                chomp $rep;
                if($rep =~ /^yes$/i) {
                    &delete_this_cspec($cspec);
                }
            }
        }
        else {
            if($opt_force_delete) {
                if($opt_quiet_mode) {
                    &delete_this_cspec($cspec);
                }
                else {
                    print "Do you want to delete $cspec (yes/no) ? :\n";
                    my $rep = <STDIN>;
                    chomp $rep;
                    if($rep =~ /^yes$/i) {
                        &delete_this_cspec($cspec);
                    }
                }
            }
        }
    }
}
else {
    print "no cspec detected on $host_name\n";
}

&end_script();



##############################################################################
### internal functions

sub p4_login() {
    require Perforce;
    $p4 = new Perforce;
    my $warning_level = 2;
    my $warning_message = $warning_level>0 ? "ERROR" : "WARNING";
    eval { $p4->Login("-s") };
    if($@) {
        if($warning_level < 2) {
            warn "$warning_message: User not logged : $@";
        }
        else {
            die "ERROR: User not logged : $@";
        }
        $p4 = undef;
    }
    elsif($p4->ErrorCount()) {
        if($warning_level < 2) {
            warn "$warning_message: User not logged : ",@{$p4->Errors()};
        }
        else {
            die "ERROR: User not logged : ",@{$p4->Errors()},"\n";
        }
        $p4 = undef;
    }
}

sub get_all_cspecs() {
    my $p4_clients_cmd = "p4 clients | grep -i $host_name 2>&1";
    open P4_CLIENTS,"$p4_clients_cmd | "
        or die "ERROR : issue with command line : $p4_clients_cmd : $!";
        while(<P4_CLIENTS>) {
            chomp;
            next unless($_);
            next if(/UPDATE_BOOTSTRAP_VIEW/i); # don't touch bootstrap
            my ($cspec,$root)
                = $_
                =~ /^Client (.+?) \d+\/\d+\/\d+ root (.+?) \'Created by/
                ;
            $rootDir_for_cspec{$cspec} = $root;
        }
    close P4_CLIENTS;
}

sub delete_this_cspec($) {
    my ($cspec) = @_;
    # delete pending cl first
    &delete_pending_cls_for_this_cspec($cspec);
    system "p4 client -d $cspec";
    # delete on HDD
    my $rootDir = $rootDir_for_cspec{$cspec};
    ($rootDir) =~ s-\/src$--i;
    if( -d $rootDir) {
        rmtree $rootDir;
    }
}

sub delete_pending_cls_for_this_cspec($) {
    my ($cspec) = @_;
    # delete opened files first
    &revert_opened_files_for_this_cspec($cspec);
    my @list_pending_cls;
    my $p4_search_cl_cmd = "p4 changelists -c $cspec -s pending 2>&1";
    if(open P4_PENDING_CL,"$p4_search_cl_cmd |") {
        while(<P4_PENDING_CL>) {
            chomp;
            next unless($_);
            if(/^Change (\d+) on/i) {
                push @list_pending_cls,$1;
            }
        }
        close P4_PENDING_CL;
    }
    if(@list_pending_cls) {
        print "\tpending cl(s):\n";
        foreach my $cl (sort {$a <=> $b} @list_pending_cls) {
            system "p4 -c $cspec change -d $cl";
        }
    }
}

sub revert_opened_files_for_this_cspec($) {
    my ($cspec) = @_;
    my @files_to_revert;
    if(open P4_OPEN,"p4 -c $cspec opened 2>&1 |") {
        while(<P4_OPEN>) {
            chomp;
            next unless($_);
            last if(/^File\(s\) not opened on this client/i);
            my ($file) = $_ =~ /^(.+?)\#/i;
            push @files_to_revert,$file;
        }
        close P4_OPEN;
    }
    if(@files_to_revert) {
        print "\topened file(s):\n";
        foreach my $fileToRevert (@files_to_revert) {
            system "p4 -c $cspec revert $fileToRevert";
        }
    }
}

#############
sub display_usage() {
    print <<FIN_USAGE;

$0 can delete (cspec and workdir) cspec(s) of machine $host_name.
$0 does not touch the bootstrap cspec.
$0 search the workdir of a build cspec found in $host_name, if \$root\/'src' was not found,
the cspec is a candidate to be deleted
but, if the script found the folder \$root\/'src', it can skip it or delete it with option -F

Usage   : perl $0 [options]
Example : perl $0 -h

[options]
-F      Force deleting cspec even if 'src' was found.
-Q      Quiet mode, by default,
        for each cspec found that it can be deleted, a question is asked,
        to skip it, use -Q
-c      choose a specific cspec to delete
-h|?    argument displays helpful information about builtin commands.

for more details, see here :
https://wiki.wdf.sap.corp/wiki/display/MultiPlatformBuild/deleteGhostsP4clients.pl+user+guide

FIN_USAGE
    exit;
}

sub start_script() {
    my $date_start = scalar localtime;
    print "\nSTART of '$0' at $date_start\n";
    print  "#" x length "START of '$0' at $date_start","\n";
    print "\n";
}

sub end_script() {
    print "\n\n";
    my $date_end = scalar localtime;
    print  "#" x length "END of '$0' at $date_end","\n";
    print "END of '$0' at $date_end\n";
    exit;
}
