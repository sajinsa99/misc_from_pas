#!/usr/bin/perl -w
use strict;
use File::Path;
use File::Copy;

my %srcDestPlatform = (
        "win32_x86"			=> "win64_x64",
        "win64_x64"			=> "win32_x86", 
        "linux_x86"			=> "linux_x64", 
        "linux_x64"			=> "linux_x86", 
        "solaris_sparc"		=> "solaris_sparcv9", 
        "solaris_sparcv9"	=> "solaris_sparc", 
        "aix_rs6000"		=> "aix_rs6000_64", 
        "aix_rs6000_64"		=> "aix_rs6000" 
    );
my %srcDestModel = (
        "win32_x86"			=> "64",
        "win64_x64"			=> "32", 
        "linux_x86"			=> "64", 
        "linux_x64"			=> "32", 
        "solaris_sparc"		=> "64", 
        "solaris_sparcv9"	=> "32", 
        "aix_rs6000"		=> "64", 
        "aix_rs6000_64"		=> "32" 
    );

#check environment
die ("ERROR: DROP_DIR not set")		unless($ENV{DROP_DIR});
die ("ERROR: PLATFORM not set")		unless($ENV{PLATFORM});
die ("ERROR: BUILD_MODE not set")	unless($ENV{BUILD_MODE});
die ("ERROR: OUTPUT_DIR not set")	unless($ENV{OUTPUT_DIR});

if ($ENV{PLATFORM} eq "hpux_ia64") {
	print "\nnothing to do for $ENV{PLATFORM}\n";
	exit;
}

if (($ENV{PLATFORM} eq "win32_x86")  or  ($ENV{PLATFORM} eq "win64_x64")) {
	die ("ERROR: CONTEXT not set")		unless($ENV{CONTEXT});
	die ("ERROR: BUILD_NUMBER not set")	unless($ENV{BUILD_NUMBER});
} else {
	die ("ERROR: CONTEXT not set")		unless($ENV{context});
	die ("ERROR: BUILD_NUMBER not set")	unless($ENV{build_number});
}
my $buildNumber = $ENV{BUILD_NUMBER} || $ENV{build_number};
my $duSrcDIR = $ENV{DUSRC_DIR} || "$ENV{DROP_DIR}/$ENV{context}/$buildNumber/$srcDestPlatform{$ENV{PLATFORM}}/$ENV{BUILD_MODE}/deploymentunits";
$duSrcDIR =~ s-\/\/-\\\\-g;

print "\nbegin of $0";
print " at ",scalar(localtime()),"\n";
print "COPY_DU_SYNC=$ENV{COPY_DU_SYNC}\n" if(defined($ENV{COPY_DU_SYNC}));
print "dusrcdir = $duSrcDIR\n";
print "dropdir $ENV{DROP_DIR}\n";
print "output_dir $ENV{OUTPUT_DIR}\n";
print "OBJECT_MODEL=$ENV{OBJECT_MODEL}\n";
my $otherModel = $srcDestModel{$ENV{PLATFORM}};
print "other  model=$otherModel\n";

if (($ENV{COPY_DU_SYNC}) && ($ENV{COPY_DU_SYNC} != 0)) { #if COPY_DU_SYNC is setted and not equal 0
    my $exportfinished = "$duSrcDIR/deploymentunits_copy_done";
    print "
looking for $duSrcDIR/deploymentunits_copy_done
waiting for $exportfinished\n";
    while ( ! -e "$exportfinished" ) {
      print ".\n";
      sleep(10);
    }
    print "\nfound $exportfinished\n";
} else {
	#needed if $duSrcDIR should be on local build machine, but something wrong happened (not built or cleaned or ...)
	print "
search $duSrcDIR\n";
	if( ! -e "$duSrcDIR" ) {
	    print "waiting for $duSrcDIR\n";
	    while ( ! -e "$duSrcDIR" ) {
	      print ".\n";
	      sleep(10);
	    }
	    print "\nfound $duSrcDIR\n";
	}
}

print "\n\nStart at ",scalar(localtime()),"\n";

my $duDestDIR = "$ENV{OUTPUT_DIR}/deploymentunits";
print "Copying DU's from $duSrcDIR to $duDestDIR\n";
mkpath("$duDestDIR") or warn("ERROR: cannot mkpath '$duDestDIR': $!") unless(-e "$duDestDIR");

my $NULLDEVICE = ($^O eq "MSWin32") ? "nul" : "/dev/null";
system("chmod -R 777 $duDestDIR > $NULLDEVICE 2>&1") if ( $^O eq "MSWin32" );

my $IsRobocopy = ($^O eq "MSWin32") ? ((`which robocopy.exe 2>&1`=~/robocopy.exe$/i) ? 1 : 0) : 0;

my @DUs;
if ($^O eq "MSWin32") {
	my $duSrcDIR2 = $duSrcDIR; #need like an unix path for ls under windows
	($duSrcDIR2) =~ s-\\-\/-g;
	print "\nParsing $duSrcDIR2\n";
	if(opendir(AREAS, "$duSrcDIR2")) {
		while(defined(my $area = readdir(AREAS))) {
			next if($area =~ /^\./);
			next if($area =~ /^deploymentunits_copy_done$/i);
			next unless( -d "$duSrcDIR2/$area");
			if(opendir(DUS, "$duSrcDIR2/$area")) {
				while(defined(my $du = readdir(DUS))) {
					next if($du =~ /^\./);
					next unless( -d "$duSrcDIR2/$area/$du");
					push(@DUs,"$area/$du");
				}
				closedir(DUS);
			} #end of if(opendir(DUS
		}
		closedir(AREAS);
	}
} else {
	print "\nParsing $duSrcDIR\n";
	@DUs = <$duSrcDIR/*/*>;
}

print "\nStart Copying ...\n\n";
foreach my $du (@DUs) {
    my $dupath = $du;
    $dupath =~s/$duSrcDIR\///;
    my $copyneeded = 0;
    $copyneeded = 1 if ( $dupath =~ m/-$otherModel$/ );
    $copyneeded = 1 if ( $dupath =~ m/-nu$/i and $otherModel eq 32  );
    unless( -e "$duDestDIR/$dupath") {
		mkpath("$duDestDIR/$dupath") or warn("ERROR: cannot mkpath '$duDestDIR': $!") unless ( -f $du) ;
		$copyneeded = 1;
    }
	
    next unless ($copyneeded);

	if($IsRobocopy) {
		print "\n";
		print ("\t","#" x (length("#### $dupath ####")),"\n");
    	print ("\t#### $dupath ####\n");
    	print ("\t","#" x (length("#### $dupath ####")),"\n");
    } else {
    	print $dupath . "\n";
    }

    if (($ENV{PLATFORM} eq "win32_x86")  or  ($ENV{PLATFORM} eq "win64_x64")) {
        if($IsRobocopy) {
	    	system("robocopy /R:3 /XO /XN /S /NP /NFL \"$duSrcDIR/$dupath\" \"$duDestDIR/$dupath\"");
        } else {
	    	system("xcopy \"$duSrcDIR/$dupath\" \"$duDestDIR/$dupath\" /ECIQHRYD");
		}
    } else {
		system("cd $duSrcDIR; find $dupath -print | cpio -pdvm $duDestDIR 2>/dev/null");
    }
}
print "\n\nEnd Copying at ",scalar(localtime()),"\n";
