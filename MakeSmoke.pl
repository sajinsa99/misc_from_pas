#!/usr/bin/perl -w

use Getopt::Long;
use Data::Dumper;
use File::Copy;
use Encode;

##############
# Parameters #
##############

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "dashboard=s"=>\$Dashboard, "gmake=s"=>\$Makefile);
Usage() if($Help);
unless($Dashboard)  { print(STDERR "ERROR: -d.ashboard option is mandatory.\n"); Usage() }
unless($Makefile)   { print(STDERR "ERROR: -m.akefile option is mandatory.\n"); Usage() }
die("ERROR: SRC_DIR environment variable must be set") unless($ENV{SRC_DIR});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});
die("ERROR: HOSTNAME environment variable must be set") unless($ENV{HOSTNAME});
die("ERROR: BUILD_MODE environment variable must be set") unless($ENV{BUILD_MODE});
die("ERROR: PLATFORM environment variable must be set") unless($ENV{PLATFORM});
die("ERROR: MY_BUILD_NAME environment variable must be set") unless($ENV{MY_BUILD_NAME});
die("ERROR: context environment variable must be set") unless($ENV{context});
die("ERROR: build_number environment variable must be set") unless($ENV{build_number});
($HTTP_DIR) = $Dashboard =~ /^(.+)[\\\/].+$/;

########
# Main #
########

$Errors[0] = 0;
open(GMK, $Makefile) or die("ERROR: cannot open '$Makefile': $!");
binmode(GMK, ':utf8');
LINE: while(<GMK>)
{
    next unless(my($Target) = /(^smoke_.*):\s*$/);
    my $Errors = 0;
    while(<GMK>)
    {
        next unless(my($Output) = /^\s+\@test\s+-s\s+"([^"]+)"/);

        $Output =~ s/\$\((.+?)\)/$ENV{$1}/ge;
        $Output =~ s/^\\//;
        $Output =~ s/\//\\/g;
        $Output = encode('cp1252', $Output);
        my $BuildStart = time();
        $Errors = 1 unless(-f $Output);
        my $BuildStop = time();
        
        print("=+=Summary log file created: $ENV{OUTPUT_DIR}/logs/$ENV{MY_BUILD_NAME}/$Target.summary.txt\n");
        print("=+=Errors detected: $Errors\n");

        print("$ENV{OUTPUT_DIR}/logs/$ENV{MY_BUILD_NAME}/$Target.log\n");
        open(LOG, ">$ENV{OUTPUT_DIR}/logs/$ENV{MY_BUILD_NAME}/$Target.log") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/$ENV{MY_BUILD_NAME}/$Target.log': $!");
        print(LOG "=== Build start: $BuildStart\n");  
        print(LOG "[SMKP0001F][sapLevel:FATAL] '$Output' is not found.\n") if($Errors);
        print(LOG "=== Build stop: $BuildStop\n");
        close(LOG);
        copy("$ENV{OUTPUT_DIR}/logs/$ENV{context}/$Target.log", "$HTTP_DIR/Host_1/$Target=$ENV{PLATFORM}_$ENV{BUILD_MODE}_smoke.log") or warn("ERROR: cannot copy '$ENV{OUTPUT_DIR}/logs/$ENV{context}/$Target.log': $!");
        copy("$ENV{OUTPUT_DIR}/logs/$ENV{context}/$Target.log", "$HTTP_DIR/../latest/$Target=$ENV{PLATFORM}_$ENV{BUILD_MODE}_smoke.log") or warn("ERROR: cannot copy '$ENV{OUTPUT_DIR}/logs/$ENV{context}/$Target.log': $!");

        open(TXT, ">$ENV{OUTPUT_DIR}/logs/$ENV{MY_BUILD_NAME}/$Target.summary.txt") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/$ENV{MY_BUILD_NAME}/$Target.summary.txt': $!");
        print(TXT "== Build Info: machine=$ENV{HOSTNAME}, area=$ENV{MY_BUILD_NAME}, order=1, buildmode=$ENV{BUILD_MODE}, platform=$ENV{PLATFORM}, context=$ENV{context}, revision=$ENV{build_number}\n"); 
        print(TXT "== Sections with errors: 0\n\n");
        print(TXT "== Build start: ". localtime($BuildStart) . " ($BuildStart)\n");
        print(TXT "\n[ERROR \@2] [SMKP0001F][sapLevel:FATAL] '$Output' is not found.\n") if($Errors);
        print(TXT "== Build end  : ". localtime($BuildStop) . " ($BuildStop)\n\n");
        print(TXT "Summary took 0 s (0 h 00 mn 00 s)\n");
        close(TXT);
        copy("$ENV{OUTPUT_DIR}/logs/$ENV{context}/$Target.summary.txt", "$HTTP_DIR/Host_1/$Target=$ENV{PLATFORM}_$ENV{BUILD_MODE}_summary_smoke.txt") or warn("ERROR: cannot copy '$ENV{OUTPUT_DIR}/logs/$ENV{context}/$Target.summary.txt': $!");
        copy("$ENV{OUTPUT_DIR}/logs/$ENV{context}/$Target.summary.txt", "$HTTP_DIR/../latest/$Target=$ENV{PLATFORM}_$ENV{BUILD_MODE}_summary_smoke.txt") or warn("ERROR: cannot copy '$ENV{OUTPUT_DIR}/logs/$ENV{context}/$Target.summary.txt': $!");

        $Errors[0] += $Errors;
        push(@Errors, [$Errors, "Host_1/$Target=$ENV{PLATFORM}_$ENV{BUILD_MODE}_smoke.log", "Host_1/$Target=$ENV{PLATFORM}_$ENV{BUILD_MODE}_summary_smoke.txt", $ENV{MY_BUILD_NAME}, $BuildStart, $BuildStop]);
        next LINE;
    }
}

if(open(DAT, ">$Dashboard"))
{
    $Data::Dumper::Indent = 0;
    print DAT Data::Dumper->Dump([\@Errors], ["*Errors"]);
    close(DAT);
} else { warn("ERROR: cannot open '$Dashboard': $!") }

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : MakeSmoke.pl.pl -h -g -d
   Example : MakeSmoke.pl.pl -h
             MakeSmoke.pl.pl -m=gnu.gmk -d=dashboard.dat
   -gmake      specifies the makefile name.
   -d.ashboard specifies the dashboard .dat file name.

USAGE
    exit;
}