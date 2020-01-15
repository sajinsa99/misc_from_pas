#!/usr/bin/perl -w

use Getopt::Long;
use File::Path;
use XML::DOM;
use FindBin;
use lib ($FindBin::Bin);
use Perforce;

##############
# Parameters #
##############

die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "all!"=>\$IsClientsToCompile, "build=s"=>\$BuildParameters, "client=s"=>\$Client, "ini=s"=>\$Config, "log=s"=>\$Log, "filters=s"=>\$Filters, "fclean!"=>\$Clean);
Usage() if($Help);
unless($BuildParameters) { print(STDERR "the -b parameter is mandatory\n"); Usage() }
unless($Client)          { print(STDERR "the -c parameter is mandatory\n"); Usage() }
unless($Config)          { print(STDERR "the -i parameter is mandatory\n"); Usage() }
unless($Log)             { print(STDERR "the -l parameter is mandatory\n"); Usage() }
$TEMPDIR =~ s/[\\\/]\d+$//;
$CURRENTDIR = $FindBin::Bin;
$IsClientsToCompile = 0 unless(defined($IsClientsToCompile));
map({push(@Filters, qr/$_/)} split(/\s*;\s*/, $Filters));

#########
# Main #
#########

$p4 = new Perforce;
$p4->SetOptions("-c \"$Client\"");

$rhClient = $p4->FetchClient($Client);
die("ERROR: cannot fetch client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount());
($SRC_DIR = ${$rhClient}{Root}) =~ s/^\s+//;
($OUTPUT_DIR) = $SRC_DIR =~ /^(.*)[\\\/]/;
if($^O eq "MSWin32")    { $OUTPUT_DIR .= (-e "$OUTPUT_DIR/win32_x86")     ? "/win32_x86"     : "/win64_x64"  }
elsif($^O eq "solaris") { $OUTPUT_DIR .= (-e "$OUTPUT_DIR/solaris_sparc") ? "/solaris_sparc" : "/solaris_sparcv9"  }
elsif($^O eq "aix")     { $OUTPUT_DIR .= (-e "$OUTPUT_DIR/aix_rs6000")    ? "/aix_rs6000"    : "/aix_rs6000_64"  }
elsif($^O eq "hpux")    { $OUTPUT_DIR .= (-e "$OUTPUT_DIR/hpux_pa-risc")  ? "/hpux_pa-risc"  : "/hpux_ia64"  }
elsif($^O eq "linux")   { $OUTPUT_DIR .= (-e "$OUTPUT_DIR/linux_x86")     ? "/linux_x86"     : "/linux_x64"  }
$OUTPUT_DIR .= "/release";

# %Targets{Target} = UserEMail
$CHANGELOG = XML::DOM::Parser->new()->parsefile("$ENV{HUDSON_HOME}/jobs/$ENV{JOB_NAME}/builds/$ENV{BUILD_ID}/changelog.xml");
for my $ENTRY (@{$CHANGELOG->getElementsByTagName("entry")})
{
    my $User = $ENTRY->getElementsByTagName("user")->item(0)->getFirstChild()->getData();
    unless(exists($Users{$User}))
    {
        my $rhUser = $p4->user("-o", $User);
        die("ERROR: cannot 'user': ", @{$p4->Errors()}) if($p4->ErrorCount());
        $Users{$User} = ${$rhUser}{Email};
        $Users{$User} =~ s/^\s*//;
        $Users{$User} =~ s/\s*$//;
    }
    FILE: for my $FILE (@{$ENTRY->getElementsByTagName("file")})
    {
        my $FilePath = $FILE->getElementsByTagName("name")->item(0)->getFirstChild()->getData();

        # filtering #
        foreach my $RE (@Filters) { next FILE if($FilePath =~ /$RE/) }
        $p4->sync("-n", "\"$FilePath\"");
        warn("ERROR: cannot 'sync': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/- file\(s\) up-to-date\.$/ && ${$p4->Errors()}[0]!~/no such file\(s\)\.$/ && ${$p4->Errors()}[0]!~/- file\(s\) not in client view\.$/ && ${$p4->Errors()}[0]!~/- must refer to client/);
        next FILE if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/- file\(s\) up-to-date\.$/);

        my($Target) = $FilePath =~ /^\/\/[^\/]+\/([^\/]+)/;
        $Targets{$Target} = $Users{$User};

        my $Action = $FILE->getElementsByTagName("action")->item(0)->getFirstChild()->getData();
        if($Action eq "delete")
        {
            foreach my $Dir (qw(bin logs))
            {
                my $Folder = "$OUTPUT_DIR/$Target/Dir";
                rmtree($Folder) or warn("ERROR: cannot rmtree '$Folder': $!") if(-e $Folder);
                mkpath($Folder) or warn("ERROR: cannot mkpath '$Folder': $!");
            }
        }
    }
}
$CHANGELOG->dispose();
unless(%Targets) { print(STDERR "NOTHING TO DO\n"); exit(0) }

if($IsClientsToCompile)
{
	opendir(AREA, "$SRC_DIR") or die("ERROR: cannot opendir '$SRC_DIR': $!");
	while(defined(my $Area = readdir(AREA)))
	{
	    next unless(-e "$SRC_DIR/$Area/pom.xml");
	    print("$SRC_DIR/$Area/pom.xml\n");
	    my $POM = XML::DOM::Parser->new()->parsefile("$SRC_DIR/$Area/pom.xml");
	    my $DEPENDENCIES = $POM->getElementsByTagName("dependencies")->item(0);
	    if($DEPENDENCIES)
	    {
	        for my $DEPENDENCY (@{$DEPENDENCIES->getElementsByTagName("dependency", 0)})
	        {
	            my $ArtifactId = $DEPENDENCY->getElementsByTagName("artifactId", 0)->item(0)->getFirstChild()->getData();
	            $ClientTargets{$Area}=undef if(grep({$ArtifactId eq $_} keys(%Targets)));
	        }
	    }
	    $POM->dispose();
	}
	closedir(AREA);
}

my $DebugFile = $^O eq "MSWin32" ? "C:\\bin\\$ENV{JOB_NAME}.txt" : "$ENV{HOME}/$ENV{JOB_NAME}.txt";
open(DEBUG, ">>$DebugFile") or warn("ERROR: cannot open '$DebugFile': $!");
print(DEBUG "$ENV{BUILD_NUMBER}:", join(";", sort(keys(%Targets))), "\n");
close(DEBUG);

$TargetPath = "$TEMPDIR/$ENV{JOB_NAME}/$ENV{BUILD_ID}";
$TargetFile = "$TargetPath/Targets.txt";
mkpath($TargetPath) or die("ERROR: cannot open '$TargetPath': $!") unless(-d $TargetPath);
open(TARGETS, ">$TargetFile") or die("ERROR: cannot open '$TargetFile': $!");
print(TARGETS join(";", sort(keys(%Targets), keys(%ClientTargets))));
close(TARGETS);

if($Clean)
{
    foreach my $Target (keys(%Targets), keys(%ClientTargets))
    {
        chdir("$SRC_DIR/$Target") or warn("ERROR: cannot chdir '$SRC_DIR/$Target': $!");
        system("make -i -f \"$Target.gmk\" clean");     
        system("perl $CURRENTDIR/P4Clean.pl -f -c=$Client -a=$Target");
    }
}
print("perl $CURRENTDIR/Build.pl -i=$Config $BuildParameters -qset=MY_TARGETS:==$TargetFile"); print("\n");
system("perl $CURRENTDIR/Build.pl -i=$Config $BuildParameters -qset=MY_TARGETS:==$TargetFile");

open(LOG, $Log) or die("ERROR: cannot open '$Log': $!");
AREA: while(<LOG>)
{
    my $Area;
    next unless(($Area) = /^=\+=Area:\s*(.+)$/);
    while(<LOG>)
    {
        my $NumberOfErrors;
        next unless(($NumberOfErrors) = /^=\+=Errors detected:\s*(.+)$/);
        $SMTPTOs{$Targets{$Area}} = undef if($NumberOfErrors>0 && exists($Targets{$Area}));
        next AREA;
    }
}
close(LOG);
exit(0) unless(%SMTPTOs);

foreach(@ARGV)
{
    last if(($Config) = /-i[nit]{0,3}=([^\s]+)/);
}
print("perl Build.pl -i=$Config -M -qset=SMTPTO:".(join(";", sort(keys(%SMTPTOs))))); print("\n");
system("perl Build.pl -i=$Config -M -qset=SMTPTO:".(join(";", sort(keys(%SMTPTOs)))));
exit(1);

END { $p4->Final() if($p4) }

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : RollingBuild.pl -b -c -i -o -f -a
             RollingBuild.pl -h.elp|?
   Example : RollingBuild.pl -c=a41_cons_lubango -o=output.log -f="//product/*;//tp/*;\.context\.xml$" -b="-i=a41_cons.ini -B" 
    
   [options]
   -help|?     argument displays helpful information about builtin commands.
   -b.uild     specifies the build paramaters. See Build.pl -help.
   -c.lient    specifies the perforce client name.
   -i.ni       specifies the configuration file.
   -o.utput    specifies the output log file path.
   -f.ilters   specifies a list of excluding perl regular expressions (separator is ;).
   -a.ll       specifies whether the client must be compiled (-a.ll) or not (-noa.ll), default is -noall.
   -f.clean    force the impacted areas clean (-fc.lean) or not (-nofc.lean), default is -nofclean.
USAGE
    exit;
}