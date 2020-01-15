use LWP::UserAgent;
use Getopt::Long;
use File::Copy;

use FindBin;
use lib $FindBin::Bin;
use Perforce;

##############
# Parameters #
##############

GetOptions("help|?"=>\$Help, "project=s"=>\$ENV{Project}, "build=s"=>\$BuildName, "client=s"=>\$Client, "mode=s"=>\$BUILD_MODE, "object=i"=>\$OBJECT_MODEL);
Usage() if($Help);

unless($OBJECT_MODEL) { warn("ERROR: the object model parameter is mandatory.\n"); Usage() }
unless($ENV{Project}) { warn("ERROR: the project parameter is mandatory.\n"); Usage() }
unless($BUILD_MODE)   { warn("ERROR: the mode parameter is mandatory.\n"); Usage() }
unless($BuildName)    { warn("ERROR: the build parameter is mandatory.\n"); Usage() }
unless($Client)       { warn("ERROR: the client parameter is mandatory.\n"); Usage() }
require Site;

if($^O eq "MSWin32")    { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64" : "win32_x86"  }
elsif($^O eq "solaris") { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc"  }
elsif($^O eq "aix")     { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64" : "aix_rs6000"  }
elsif($^O eq "hpux")    { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64" : "hpux_pa-risc" }
elsif($^O eq "linux")   { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64" : "linux_x86"  }
if("debug"=~/^$BUILD_MODE/i) { $BUILD_MODE="debug" } elsif("release"=~/^$BUILD_MODE/i) { $BUILD_MODE="release" } elsif("releasedebug"=~/^$BUILD_MODE/i) { $BUILD_MODE="releasedebug" }

$URL = "http://rmcqapps.product.businessobjects.com/Internal_Applications/ReleaseManagement/BuildInfo";
@Months = qw(January February March April May June July August September October November December);
die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/[\\\/]\d+$//;
($Context, $BuildNumber) = $BuildName =~ /^(.+)_(\d+)$/;
$BuildNumber =~ s/^0*//;

########
# Main #
########

$p4 = new Perforce;
$rhClient = $p4->FetchClient($Client);
die("ERROR: cannot fetch client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount());
($SRC_DIR = ${$rhClient}{Root}) =~ s/^\s+//;
$p4->SetClient($Client);
die("ERROR: cannot set client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount());
$OUTPUT_DIR  = $ENV{OUTPUT_DIR} || (($ENV{OUT_DIR} || ($SRC_DIR=~/^(.*)[\\\/]/, "$1/$PLATFORM"))."/$BUILD_MODE");

$ua = LWP::UserAgent->new();
($Day, $Month, $Year) = (gmtime())[3, 4, 5];
$Date = "${Day}th $Months[$Month] ".(1900+$Year);

open(DAT, "$OUTPUT_DIR/logs/NewRevisions.dat") or die("ERROR: cannot open '$OUTPUT_DIR/logs/NewRevisions.dat': $!");
{
    local $/ = undef; 
    eval <DAT>;
    close(DAT);	
}
foreach my $raRevision (@Revisions)
{
	my($File, $Revision, $Action, $Change, $History, $Import) = @{$raRevision};
    my($Area) = $File =~ /^\/\/components\/(.+?)\//; 	
 	($Area) = $File =~ /^\/{2}(?:[^\/]*[\/]){3}(.+?)\// unless($Area);
    ${$Changes{$Area}}{$Change} = undef;
}
foreach(@Changes)
{
	my($Change, $User, $Time, $raAdapts, $Description, $History, $Import) = @{$_};
	@Adapts{@{$raAdapts}} = ();
}
$Request = HTTP::Request->new(GET => "$URL/GetFRInfo.cqpl?liste_id=".join(',', keys(%Adapts)));
$Response = $ua->request($Request);
die($Response->status_line()) unless($Response->is_success());
foreach(split("\n", $Response->content()))
{
    my($Adapt, $Synopsis) = (split(/\s*::\s*/, $_))[1,2];
    ${$Adapts{$Adapt}}[1] = $Synopsis;
}
$Request = HTTP::Request->new(GET => "$URL/GetDataFromId.cqpl?liste_id=".join(',', keys(%Adapts)));
$Response = $ua->request($Request);
die($Response->status_line()) unless($Response->is_success());
foreach (split("\n", $Response->content()))
{
    my($Adapt, $State) = (split(/\s*::\s*/, $_))[0,2];
    ${$Adapts{$Adapt}}[0] = $State;
}

AREA: foreach my $Area (keys(%Changes))
{
    opendir(REL, "$SRC_DIR/$Area") or warn("ERROR: cannot opendir '$SRC_DIR/$Area': $!");
    while(defined(my $File = readdir(REL)))
    {
        next unless($File =~ /^ReleaseNotes/i);
        copy("$SRC_DIR/$Area/$File", "$ENV{DROP_DIR}/$Context/$BuildNumber") or warn("ERROR: cannot copy 'SRC_DIR/$Area/$File': $!");
    }
    closedir(REL);

	my(%CurrentAdapts, $Comments, $ReleaseNotes);
	my $ReleaseNotesChange; 
	foreach(sort({${$b}[0]<=>${$a}[0]} @Changes))
	{
    	my($Change, $User, $Time, $raAdapts, $Description, $History, $Import) = @{$_};
        next unless(exists(${$Changes{$Area}}{$Change}));
        next if($User =~ /(?:polling task|Reviewed|Action|hours|loceng|mwf)/i);

        @CurrentAdapts{@{$raAdapts}} = ();
        my($WhatAndHow) = $Description =~ /What and how:(.+)Install components:/s;
        if($WhatAndHow =~ /\s*Release\s*notes\s*file\s*:\s*(.+)\s*action\s*:\s*update/is)
        {
            $ReleaseNotes = $1;
            $ReleaseNotesChange = $Change;
            ($Comments = $WhatAndHow) =~ s/-?\s*Release\s*notes\s*file\s*:\s*.+\s*action\s*:\s*update//is;
            last if($Comments);
        }
    }
    next AREA unless($Comments);

    open(DST, ">$TEMPDIR/ReleaseNotes_$$.txt") or die("ERROR: cannot open '$TEMPDIR/ReleaseNotes_$$.txt': $!");            
    print(DST "\t$Date\n");
    print(DST "\t", '*' x length($Date), "\n");
    chomp($Comments);
    print(DST $Comments);
    print(DST "- $BuildName\n");
    print(DST "\nST:\n");
    print(DST "FixedNeedsTest  PR Synopsis\n");
	foreach my $Adapt (sort(keys(%CurrentAdapts)))
	{
	    my($State, $Synopsis) = @{$Adapts{$Adapt}};
	    next unless($State eq "FixedNeedsTest");
	    print(DST "$Adapt   $Synopsis\n");
    }
    print(DST "\nClosed          PR Synopsis\n");
	foreach my $Adapt (sort(keys(%CurrentAdapts)))
	{
	    my($State, $Synopsis) = @{$Adapts{$Adapt}};
	    next unless($State eq "Closed");
	    print(DST "$Adapt   $Synopsis\n");
    }
    print(DST "\nDev:\n");
	foreach(@Changes)
	{
    	my($Change, $User, $Time, $raAdapts, $Description, $History, $Import) = @{$_};
        next unless(exists(${$Changes{$Area}}{$Change}));
        next if($Change == $ReleaseNotesChange);
        next if($User =~ /(?:polling task|Reviewed|Action|hours|loceng|mwf)/i);
    	print(DST "Change $Change on $Time by $User\n");
        my($Summary)    = $Description =~ /Summary:(.*?)Reviewed by:/is;
    	my($Task)       = $Description =~ /Task:(.*?)Action:/is;
    	my($WhatAndHow) = $Description =~ /What and how:(.*?)Install components:/is;
        chomp($Summary); chomp($Task); chomp($WhatAndHow);
    	print(DST "\tSummary: $Summary\n")         if($Summary);
    	print(DST "\tTask: $Task\n")               if($Task);
    	if($WhatAndHow) { print(DST "\tWhat And How:"); foreach(split("\n", $WhatAndHow)) { print(DST "\t$_\n") } }
    	print(DST "\n");
    }
    
    $p4->sync("$SRC_DIR/$Area/$ReleaseNotes");
    warn("ERROR: cannot 'sync': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/no such file\(s\).$/ && ${$p4->Errors()}[0]!~/up-to-date.$/);
    if(open(SRC, "$SRC_DIR/$Area/$ReleaseNotes"))
    {
        while(<SRC>) { print(DST) }    
        close(SRC);
        close(DST);
        my $rhChange = $p4->FetchChange();
        warn("ERROR: cannot p4 fetch change: ", @{$p4->Errors()}) if($p4->ErrorCount());
        ${$rhChange}{Description} = ["Summary:CVOM", "Reviewed by:builder"];
        my $raChange = $p4->SaveChange($rhChange);
        warn("ERROR: cannot p4 save change: ", @{$p4->Errors()}) if($p4->ErrorCount());
        my($Change) = ${$raChange}[0] =~ /^Change (\d+)/;
        $p4->edit("-c$Change", "$SRC_DIR/$Area/$ReleaseNotes");
        warn("ERROR: cannot p4 edit: ", @{$p4->Errors()}) if($p4->ErrorCount());
        copy("$TEMPDIR/ReleaseNotes_$$.txt", "$SRC_DIR/$Area/$ReleaseNotes") or warn("ERROR: cannot copy '$TEMPDIR/ReleaseNotes_$$.txt': $!");
        $p4->submit("-c$Change");
        warn("ERROR: cannot p4 submit: ", @{$p4->Errors()}) if($p4->ErrorCount());
    } else { close(DST); warn("ERROR: cannot open '$SRC_DIR/$Area/$ReleaseNotes': $!") }
    copy("$SRC_DIR/$Area/$ReleaseNotes", "$ENV{DROP_DIR}/$Context/$BuildNumber") or die("ERROR: cannot copy '$SRC_DIR/$Area/$ReleaseNotes': $!");            
}

END { $p4->Final() if($p4) }

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : CVOM.pl -p  
             CVOM.pl -h.elp|?
   Example : CVOM.pl -p=Titan -s=Titan_Stable -b=Titan_Stable_00536 -c=Titan_Stable_lvwin038 -M=r -o=32
    
   [options]
   -h.elp|?    argument displays helpful information about builtin commands.
   -b.uild     specifies the build name. 
   -m.ode      debug or release or releasedebug, default is release.
   -o.bject    specifies the object model, 32 or 64 bits.
   -p.roject   specifies the project name. 
   -c.lient    specifies the client name. 
USAGE
    exit;
}