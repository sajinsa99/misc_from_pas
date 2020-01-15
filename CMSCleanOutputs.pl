#!/usr/bin/perl -w

use Encode;

##############
# Parameters #
##############

die("ERROR: SRC_DIR environment variable must be set") unless($ENV{SRC_DIR});
die("ERROR: PROJECT environment variable must be set") unless($ENV{PROJECT});
die("ERROR: Context environment variable must be set") unless($ENV{Context});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});

########
# Main #
########

open(GMK, "$ENV{SRC_DIR}/$ENV{PROJECT}/export/$ENV{Context}.gmk") or die("ERROR: cannot open '$ENV{SRC_DIR}/$ENV{PROJECT}/export/$ENV{Context}.gmk': $!");
LINE: while(<GMK>)
{
    next unless(my($Target) = /(^build_.*):\s*$/);
    open(TXT, "$ENV{OUTPUT_DIR}/logs/$ENV{Context}/$Target.summary.txt") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/$ENV{Context}/$Target.summary.txt': $!");
    my $Level;
    while(<TXT>)
    {
        next unless(/^\[ERROR\s+\@\d+\]/);
        if(/\[sapLevel:(\w+?)\]/i) { $Level = $1 }
        elsif(/\s\[\w+?\]\[(INFO|FATAL)\]/) { $Level = $1 }
        elsif(/(?:build failed|Error occurred during initialization of VM|com.ixiasoft.outputgenerator.packager.sap.LinkRemapper - Two versions of container|Failed to deploy artifacts|CORBA.COMM_FAILURE|Exception in thread|FATAL:\s*com\.ixiasoft\.)/i) { $Level = 'FATAL' }
    }
    close(TXT);
    next LINE unless($Level and $Level =~ /FATAL/i);
    while(<GMK>)
    {
        next unless(my($Output) = /test\s+-s\s+"(.*?)"/);
        $Output =~ s/\$\((.+?)\)/$ENV{$1}/ge;
        $Output =~ s/^\\//;
        $Output =~ s/\//\\/g;
        $Output = encode('cp1252', $Output);
        unlink($Output) or warn("ERROR: cannot unlink '$Output' : $!") if(-f $Output);
        last;
    }
}
close(GMK);