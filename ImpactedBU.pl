#!/usr/bin/perl -w

use Getopt::Long;

##############
# Parameters #
##############

$DEPENDS_DIR = 'C:\depends';
$PLATFORM = 'win64_x64';

GetOptions("Files=s"=>\$File);

#push(@Files, 'WebI/repeng/modules/xmlcube/MemDlg.cpp');
#push(@Files, 'WebI/WebI_WS_Publisher/commons/src/com/businessobjects/helper/roSchema/Axis.java');

########
# Main #
########

open(IN, "$File") or die("ERROR: cannot open '$File': $!");
while(<IN>) { chomp(); push(@Files, $_) }
close(IN);

open(DAT, "$DEPENDS_DIR/$PLATFORM/aurora.read.dat") or die("ERROR: cannot open '$DEPENDS_DIR/$PLATFORM/aurora.read.dat': $!");
UNIT: while(<DAT>)
{
    next unless(my($Area, $Unit) = /\@{\$g_read\{'(.+):(.+)'}}/);
    while(<DAT>)
    {
        next UNIT if(/^}/);
        my $Line = $_;
        next unless(grep({$Line =~ /'\$SRC_DIR\/$_'/} @Files));
        $ImpactedBUs0{"$Area:$Unit"} = undef;
    }
}
close(DAT);

open(LOG, "$DEPENDS_DIR/aurora.database.log") or die("ERROR: cannot open '$DEPENDS_DIR/aurora.database.log': $!");
while(<LOG>)
{
    next unless(/^aurora:([^:]+:[^:]+)\|aurora:([^:]+:[^:]+)\|/ && exists($ImpactedBUs0{$2}));
    $ImpactedBUs1{$1} = undef;
}
close(LOG);

print("Level 0:\n");
foreach (keys(%ImpactedBUs0)) { print("\t$_\n") }
print("Level 1:\n");
foreach (keys(%ImpactedBUs1)) { print("\t$_\n") }

#############
# Functions #
#############