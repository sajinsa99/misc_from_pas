#!/usr/bin/perl -w

# set @INC array
use Data::Dumper;
use FindBin qw($Bin);
use lib ("$Bin", "$Bin/site_perl");
# core
use Sys::Hostname;
use Getopt::Long;
use File::Copy;
use File::Path;
use File::Basename;
use FindBin;
use Fcntl;
use POSIX;
use IO::Socket;
use IO::Select;
use IO::File;
use Socket;
use threads;
use Cwd 'abs_path';
# used for linux systems receiving broken pipe randomly on certains tcp client connections
use sigtrap;

# used for packets coming from WinXX drivers to convert unicode filename to ansi
use Unicode::Normalize;
use Encode;

# Use DB on disk storage for memory optimisation
BEGIN
{
	my $package = "DB_File";
	eval {
		(my $pkg = $package) =~ s|::|/|g; # require need a path
		require "$pkg.pm";
		$package->import;
	}
}


# site
use Date::Calc(qw(Today_and_Now Delta_DHMS));
# local
use Site;
use Perforce;
use Build;
# Required for multi-platform Depends, each Depends-(MSWin32,...).pl will contain platform specific code...
use Depends;
use Depends::Common;
use Torch;

#
#  Define the access mask as a longword sized structure divided up as
#  follows:
#
#       3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1
#       1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
#      +---------------+---------------+-------------------------------+
#      |G|G|G|G|Res'd|A| StandardRights|         SpecificRights        |
#      |R|W|E|A|     |S|               |                               |
#      +-+-------------+---------------+-------------------------------+
#
#      typedef struct _ACCESS_MASK {
#          WORD   SpecificRights;
#          BYTE  StandardRights;
#          BYTE  AccessSystemAcl : 1;
#          BYTE  Reserved : 3;
#          BYTE  GenericAll : 1;
#          BYTE  GenericExecute : 1;
#          BYTE  GenericWrite : 1;
#          BYTE  GenericRead : 1;
#      } ACCESS_MASK;
#      typedef ACCESS_MASK *PACCESS_MASK;
#
#WRITE= 1000000 00000000 00000000 00000000
#READ= 10000000 00000000 00000000 00000000
#
#DELETE=						    1 00000000 00000000
#READ_CONTROL=				   10 00000000 00000000
#WRITE_OWNER=				 1000 00000000 00000000
#SYNCHRONIZE=				10000 00000000 00000000
#FILE_WRITE_ATTRIBUTES=					 1 00000000
#FILE_READ_ATTRIBUTES=					   10000000
#FILE_WRITE_EA=						          10000
#FILE_READ_EA=							       1000
#FILE_APPEND_DATA=						        100
#FILE_WRITE_DATA=						         10
#FILE_READ_DATA=							      1
#
#Creation:		00120196	10010 00000001 10010110
#Modification:	0012019f	10010 00000001 10011111
#Lecture:		00120089	10010 00000000 10001001
#Destruction:	00010080	    1 00000000 10000000

my $szUnpackString="SCCLLLLLLLQQQQQQlLLLCCCCCCCCQQQQQQLL";

sub GetEndOfStringPos
{

	my $iStartPos=shift;
	my $arrayString=shift;
	my $stringSize=scalar @{$arrayString};

	my $posToDelete=0; 
	{
		my $numberOfZero=0;
		for($posToDelete=$iStartPos;$posToDelete<$stringSize && $numberOfZero!=2;$posToDelete++)
		{
			if($arrayString->[$posToDelete]==0) {$numberOfZero++;} else { $numberOfZero=0; }
		}
	}
	return $posToDelete;
}

sub ExpandPackString
{
	my $string=shift;

	my $szCurrentProcessor=Depends::Common::GetProcessor();

	if(defined $szCurrentProcessor && $szCurrentProcessor eq "x86_64" )
	{
		$string=~ s/Q/b64/g;
	}
	else
	{
		$string=~ s/Q/b32/g;
	}
	return $string;
}
my $szExpandedUnpackString=ExpandPackString($szUnpackString);
my $iNumberOfElements=length $szUnpackString;

use constant {
	FILE_READ 	=>1,
	FILE_WRITE	=>2,
	FILE_APPEND =>4,
};

use constant {
	FILE_SUPERSEDED		=>0,
	FILE_OPENED			=>1,
	FILE_CREATED        =>2,
	FILE_OVERWRITTEN	=>3,
};

use constant {
	TRUE =>1,
	FALSE =>0
};

use constant
{
	RECORD_TYPE_NORMAL =>0,
	RECORD_TYPE_PROCESSEVENT =>2,
	RECORD_TYPE_MESSAGE		=>8,
};

use constant STATUS_SUCCESS =>0;

require "Depends/Depends-".$^O.".pl";
# End required for multi-platform Depends...
################################################################################################################
# Methods declaration
#########################################################################################################################
# first is mode returned by filelog, file sub extension, variable name
$CURRENTDIR = "$FindBin::Bin";
$BOOTSTRAPDIR=abs_path($CURRENTDIR."/../..");

$PROCESSOR=Depends::Common::GetProcessor();

$FIELD_SEPARATOR='$';

$READ_MODE  = 1;
$WRITE_MODE = 2;
$CREATE_MODE = 4;

%DAT_FILE_LIST = (
$READ_MODE => ["r","g_read"],
$WRITE_MODE => ["w","g_write"],
$CREATE_MODE => ["c","g_create"],
);

use constant FILELOG_CLIENT_DEFAULT_PORT    => 1234;
use constant FILELOG_CLIENT_BUFSIZE_RECV    => 2048;

$DEPENDS_PORT=$ENV{FILELOG_PORT} || FILELOG_CLIENT_DEFAULT_PORT;
$DEPENDS_PORT=int($DEPENDS_PORT); # convert it into integer if spaces have been stored in the command line


$SIG{PIPE}='IGNORE' if($^O ne "MSWin32");# forcing broken pipes to be ignored & not to generate a hang stopping the script, ONLY under Unix because it works well under Windows

sub HierarchicalDependenciesToDependencyFile($$$$$$$$$$$$$$$$$$;$$$);
sub FlatToHierarchicalDependency($$$$$$;$);
sub __FlatToHierarchicalDependency($$$$$$$$$;$);
sub ExtractDependencies($$$;$);
sub FindLastSequenceNumber($);
sub GetFileListInDirectory($$$;$$);

#############
# Functions #
#############

#########################################################################################################################
# ret = sub GetFileListInDirectory(arg1,arg2,arg3,arg4,arg5)
#    Returns the list of files contained in all subdir recursively of arg1 suffixed with arg2 & which must be ok with the regex  arg3
#    returns an array
#########################################################################################################################
#		arg1 is the directory to scan
#		arg2 is the suffix to add under each directory
#		arg3 if undef, does not search in the root dir (root dir is directory/suffix when arg4=undef)
#		arg3 is the regex
#		arg4 must not be set or to undef by the caller
#########################################################################################################################
sub GetFileListInDirectory($$$;$$)
{
	my ($directory,$suffix,$searchInRootDirectory,$regEx,$array)=@_;
	
	my @Result;
	
	$array=\@Result unless(defined $array);
	
	if((defined $searchInRootDirectory && $searchInRootDirectory==1) && opendir(my $files, $directory.$suffix))
	{
		while (my $file = readdir $files)
		{
			next if($file eq '.' || $file eq '..');
			next unless($file =~ $regEx && -f $directory.$suffix."/".$file);
			push(@$array,$directory.$suffix."/".$file);
		}
		closedir($files);
	}

	if(opendir(my $dh, $directory))
	{
		while (my $file = readdir $dh)
		{
			next if $file eq '.' || $file eq '..';
			next unless (-d $directory."/".$file);
			$array=GetFileListInDirectory($directory."/".$file, $suffix, 1, $regEx, $array);
		}
		closedir($dh);	
	}
	return $array;
}
#########################################################################################################################
# ret = sub FindLastSequenceNumber(arg1,arg2)
#    Returns the biggest number stored in a sample of depends.seq stored under some subdirs....
#    Used to return a starting number bigger than the one previous in the build if restarted or dirs imported
#########################################################################################################################
#		arg1 is the directory to scan
#########################################################################################################################
sub FindLastSequenceNumber($)
{
	my $directory=shift;
	
	my $list=GetFileListInDirectory($directory."/depends", "", undef ,qr/depends\.seq$/);
	my $lastBigger=0;
	my $lastNLoadedProcess=0;
	foreach my $file(@$list)
	{
		if(open(my $dependsNumberFileHandle, $file))
		{
			foreach my $Line(<$dependsNumberFileHandle>)
			{
				my $SequenceNumberFromFile; my $nLoadedProcessFromFile;
				if(($SequenceNumberFromFile, $nLoadedProcessFromFile) = $Line =~ /^(\d+)(?:,(\d+))?$/)
				{
					$lastBigger=$SequenceNumberFromFile if(!defined $lastBigger || $SequenceNumberFromFile>$lastBigger);
					$lastNLoadedProcess=$nLoadedProcessFromFile if(!defined $lastNLoadedProcess || $nLoadedProcessFromFile>$lastNLoadedProcess);
				}
			}
			close($dependsNumberFileHandle);
		}			
	}
	return ($lastBigger,$lastNLoadedProcess);
}
#########################################################################################################################
# ret = sub DatToFilteredPerlFile(arg1,arg2,arg3,arg4,arg5,arg6)
#########################################################################################################################
#		arg1 is the system dependent object used for retreiving system infos
#		arg2 is the INPUT DAT handle which will be filtered & convert into arg2 perl file
#		arg3 is the OUTPUT DAT HANDLE
#		arg4 is a substitution array for replacing a path part by a tag
#		arg5 is an array of files to ignore
#		arg6 is the exclude array not to convert some specific files & to retun null instead
#########################################################################################################################
sub DatToFilteredPerlFile($$$$$$)
{
	# Retrieve parameters
	my ($DependsPlatform,$InputFile,$OutputFile,$SubstitutionTable,$regexOnFileToIgnore, $rHashExcludedFiles) = @_;

	my %OpenedFilesList;

	while(<$InputFile>)
	{
		# read something like :
		# "/device/harddisk/volumeX/toto.txt",
		# "/device/harddisk/volumeX/toto2.txt",
		# only get /device/harddisk/volumeX/toto2.txt  & remove double quote & coma, so only this group : (.+)
		next unless(my($ReadFile,$SequenceNumber) = /^[ \t]*\'(.+)\'[ \t]*,[ \t]*(.+)[ \t]*,[ \t]*$/);
		# TODO : Check now on disk if this read entry is a file or a directory... if a directory or already openeed
		# end in the map, continue to the next line.... We are not interrested by directories (only tracking files dependencies
		# end we do not need to have duplicate keys in the final output
		$ReadFile=Build::ConvertLogicalFilenameToPrefixedFilename($DependsPlatform->get_unique_file_name($ReadFile),$SubstitutionTable,undef,$regexOnFileToIgnore);

		if($ReadFile && $ReadFile ne "" && !exists $rHashExcludedFiles->{$ReadFile})
		{
			$ReadFile=~ s/\'/\\\'/g;
			$OpenedFilesList{"\t"."'".$ReadFile."',"."\n"}=$SequenceNumber if(!exists($OpenedFilesList{"\t"."'".$ReadFile."',"."\n"}) || $SequenceNumber<$OpenedFilesList{"\t"."'".$ReadFile."',"."\n"});
		}
	}

	print ($OutputFile join("",keys(%OpenedFilesList)));
	print ($OutputFile "\t'',\n}=(\n".join(",\n",values(%OpenedFilesList))."\n);\n\n");
}

#########################################################################################################################
# ret = sub FilterBuildUnitDATFiles(arg0,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9) 
#	Convert temporary da0 files into final DAT files
#########################################################################################################################
#		arg0 is the specific platform class
#		arg1 is the project name
#		arg2 is the source directory
#		arg3 is the principal output directory
#		arg4 is the binary output directory
#		arg5 is the root directory containing sometimes sources & outputs
#		arg6 is the Temporary directory where da0 file are stored
#		arg7 is the current area name
#		arg8 is the current build unit name
#		arg9 is a list of regex to ignore some files
#########################################################################################################################
sub FilterBuildUnitDATFiles($$$$$$$$$$)
{
	my ($DependsPlatform,$ProjectName,$SrcDir,$OutputDir,$OutBinDir,$RootDir,$TempDir,$Area,$BuildUnit,$regexOnFileToIgnore)=@_;
	
	my($AreaName,$AreaVersion) = $Area =~ /^(.+)[\\\/](.+)$/;
	$AreaName=$Area if(!defined $AreaName);

	my $OutputFilePathName=$TempDir."${\Depends::get_path_separator()}".$Build::OBJECT_MODEL."${\Depends::get_path_separator()}".$SHORT_MODE."${\Depends::get_path_separator()}depends${\Depends::get_path_separator()}deps${\Depends::get_path_separator()}".$ProjectName.$FIELD_SEPARATOR.$AreaName.(defined $AreaVersion?'@'.$AreaVersion:"").$FIELD_SEPARATOR.$BuildUnit;
	my $CurrentDataOutputPath=$OutputDir."/depends/".$Area;
	mkpath($CurrentDataOutputPath) unless(-e "$CurrentDataOutputPath");
	my $FinalDATOutputFilePathName=$CurrentDataOutputPath."/".$ProjectName.$FIELD_SEPARATOR.$AreaName.(defined $AreaVersion?'@'.$AreaVersion:"").$FIELD_SEPARATOR.$BuildUnit;

	(my $Slashed_SRC_DIR=$SrcDir)=~ s/\\/\//g; # Force slash format
	(my $Slashed_ROOT_DIR=$RootDir)=~ s/\\/\//g; # Force slash format
	tie(my %substitutionArray, Tie::IxHash, '$SRC_DIR'=>"^".$Slashed_SRC_DIR, '$OUTPUT_DIR'=>"^".$OutputDir, '$ROOT_DIR'=>"^".$Slashed_ROOT_DIR ); # Substition array to put variable & generate relative path instead of physical absolute path
	
			# transfert & convert (filter : remove paths & duplicate entries) _filelog.*.dat files into build unit.*.pl files
	# UNIX_PORT : If you need to port this file to Unix, you will have to save your outputs under two files :
	#		ProjectName.AreaName.BuildUnit.r.dat or ProjectName.AreaName.BuildUnit.w.dat
	#		.r.dat is for read files list in the executed build command, & .w.dat the written files
	#		.r.da0 & .w.da0 were some intermediate files
	#	DatToFilteredPerlFile() is used to filter intermediate files & to generate the real final files which will be analyzed by our algo
	#		This method will remove filenames duplicated many times & remove also if it is a directory (we only need files). This will optimize memory usage due to the big big big
	#		big big big size of  the .dat files !
	foreach my $CurrentLogFile(values(%DAT_FILE_LIST))
	{
		open(my $FILELOG_DAT, $OutputFilePathName.".".$CurrentLogFile->[0].".da0") or return undef;
		my $FH; my %hashExcludedFiles;
		unless(open($FH, ">".$FinalDATOutputFilePathName.".".$CurrentLogFile->[0].".dat")) { close ($FILELOG_DAT); return undef; }
		print($FH 'delete $'.$CurrentLogFile->[1].'{"'.$ProjectName.":".$Area.":".$BuildUnit.'"} if(exists $'.$CurrentLogFile->[1].'{"'.$ProjectName.":".$Area.":".$BuildUnit.'"});'."\n");
		print($FH '@{$'.$CurrentLogFile->[1].'{"'.$ProjectName.":".$Area.":".$BuildUnit.'"}}{'."\n");
		if(open(my $EXCLUDE_FILE, $SrcDir."${\Depends::get_path_separator()}".$Area."${\Depends::get_path_separator()}export${\Depends::get_path_separator()}Depends${\Depends::get_path_separator()}".$BuildUnit.".".$CurrentLogFile->[0].".exclude")) # Open exclude files
		{
			while(<$EXCLUDE_FILE>)
			{
				chomp;
				$hashExcludedFiles{$_}=undef;
			}
			close ($EXCLUDE_FILE);
		}

		DatToFilteredPerlFile($DependsPlatform, $FILELOG_DAT, $FH,  \%substitutionArray, $regexOnFileToIgnore, \%hashExcludedFiles );
		close ($FH);
		close ($FILELOG_DAT);
	}

	if(open(my $FILELOG_DAT, $OutputFilePathName.".fmap")) # as this file is optional, does not return an error if it cannot be opened
	{
		my $FH;
		unless(open($FH, ">".$FinalDATOutputFilePathName.".fmap")) { warn("ERROR: cannot open '$FinalDATOutputFilePathName.fmap': $!"); close ($FILELOG_DAT); return undef; }
		while(<$FILELOG_DAT>)
		{
			next unless(my($ProcessID,$SequenceNumber,$Mode,$File) = /^([^\*]+)\*(\d+)\.(\d+)\.(.*)$/);
			$File=Build::ConvertLogicalFilenameToPrefixedFilename($DependsPlatform->get_unique_file_name($File),\%substitutionArray, undef,$regexOnFileToIgnore );
			if($File && $File ne "")
			{
				$File=~ s/\'/\\\'/g;
				print($FH "\@{\$g_fmap{'$SequenceNumber'}}=('$File','$Mode','$ProcessID');\n");
			}
		}
		close ($FH);
		close ($FILELOG_DAT);
	}
	return 1;
}
#########################################################################################################################
# ret = sub CompareDeepPath(arg1, arg2, arg3)
#	Compare targets arg1 & arg2 stored in a array form (Saturn._External._icuc is stored in arg1 as arg1[0]=Saturn, arg1[2]=_External, arg3[_icuc]=_icuc)
#########################################################################################################################
#		arg1[in] First string to compare to arg2
#		arg2[in] Second string to be compared
#		arg3[in] Max deep level to compare
#	ret returns the deep level differing between arg1 & arg2
#########################################################################################################################
sub CompareDeepPath($$$)
{
	my ($PathOne,$PathTwo,$MaxDeep)=@_;
	my $DeepOk=0;

	for(my $DeepLevel=0;$DeepLevel<$MaxDeep && $PathOne->[$DeepLevel] eq $PathTwo->[$DeepLevel]; $DeepLevel++) { $DeepOk++; }
	return $DeepOk;
}
#########################################################################################################################
# ret = sub SaveTargetDependencies(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12,arg13,arg14)
#	Construct dependencies, phony & other lists & flush into dep/log files
#########################################################################################################################
#		arg1[in] Current DEP output filehandle
#		arg2[in] Current LOG output filehandle
#		arg3[in] defined if clean .dep without unused targets must be generated, otherwise undef
#		arg4[in] Full target name
#		arg5[in] All Targets hash table
#		arg6[in] Current target [key to read in hierarchical data, key to read in dependencies/Targets]
#		arg7[in] Target compilation errors & duration;
#		arg8[in] Current deep name in array form ([0]=Saturn, [1]=Area,..., regarding the current level ($arg2)
#		arg9[in] Current deep level
#		arg10[in] Receive the current node
#		arg11[in] Update even if build failed
#		arg12[in] Time range change for updating compilation
#		arg13[in/out] incremented during each call to retrieve the number of changes, should be used for exemple to know if a change has been performed & if we need to submit it in perforce
#		arg14[in] Do we have to version the targets output
#	ret 0 if saved because node exists otherwise 1 if saved correctly
#########################################################################################################################
sub SaveTargetDependencies($$$$$$$$$$$$$$)
{
	my $rDepMakeDest=shift;
	my $rDepLog=shift;
	my $Wash=shift;
	my $TargetFullName=shift;
	my $Targets=shift;
	my $Target=shift;
	my $BuildInfos=shift;
	my $PathArray=shift;
	my $Deep=shift;
	my $HierarchicalDependencies=shift;
	my $bIgnoreError=shift;
	my $TimeRange=shift;
	my $nNumberOfChanges=shift;
	my $Versioned=shift;

	my %Depends;
	my %RealDepends;
	my %Phony;
	my $Priority=$DEFAULT_PRIORITY; # Default priority if no sub branch of this node, so no dependencies
	my $iDepencencyDeepName=$Deep+1; # Will be used to construct the dependency name regarding the deep (if in Saturn(Deep=0), & depencny is Saturn.External, depencency true name will be External(Deep+1)
	my $BuildErrors=($BuildInfos && exists $BuildInfos->[0])?$BuildInfos->[0]:0;
	my $nDuration=($BuildInfos && exists $BuildInfos->[1])?$BuildInfos->[1]:0;
	my($Dummy,$TargetShortName) = $TargetFullName =~ /^(.+)[\:](.+)$/;
	$TargetShortName=$TargetFullName if(!defined $TargetShortName);

	return 0 if(!defined($BuildInfos) && defined($Wash)); # if no error in target && not found, suppress it
	# & also if wanting an unclean/unwashed clean dep file with old unused targets, so continue

	# if errors when building this target, no cleaned dep files requested,  or target has been removed in destination, just rewrite the old target content by using original data contained in $Targets
	# Only if target exists in original data
	if($Targets && defined $Target->[1] && exists $Targets->{$Target->[1]})
	{
		$Priority=$Targets->{$Target->[1]}[1] if(exists $Targets->{$Target->[1]}[1] && defined $Targets->{$Target->[1]}[1]);
		if(!defined($BuildInfos) || ($BuildErrors!=0 && (!defined $bIgnoreError || $bIgnoreError==0)) || !defined($Wash))
		{
			if(($BuildErrors!=0 && (!defined $bIgnoreError || $bIgnoreError==0))|| !defined($BuildInfos) || !$BuildInfos || !exists $BuildInfos->[1]) # Just overwrite build time when a build failed even if in wash/clean mode !
			{
				if(exists $Targets->{$Target->[1]}[2]) { $nDuration=$Targets->{$Target->[1]}[2]; } else { $nDuration=0; }
			}
			%RealDepends=%{$Targets->{$Target->[1]}[4]} if(defined %{$Targets->{$Target->[1]}[4]});

			foreach my $TargetDependency(@{$Targets->{$Target->[1]}[3]}) # Reconstruct original dependencies
			{
				$Depends{$TargetDependency}=undef;
				if(exists $Targets->{".PHONY"})
				{
					foreach my $PhonyEntry(@{$Targets->{".PHONY"}[3]}) # Reconstuct phony line
					{
						if($TargetDependency eq $PhonyEntry)
						{
							$Phony{$TargetDependency}=undef;
							last;
						}
					}
				}
			}
		}
	}
	# No errors & target compiled, complete dependencies
	if(defined($BuildInfos) && ($BuildErrors==0 || (defined $bIgnoreError && $bIgnoreError!=0)) && defined $HierarchicalDependencies->[1] && defined $Target->[0] && exists $HierarchicalDependencies->[1]->{$Target->[0]})
	{
		foreach my $TargetDependency (keys %{$HierarchicalDependencies->[1]->{$Target->[0]}->[0]}) # Get new dependencies & update the list
		{
			my @TargetDependencyArray = split(/[\:]+/, $TargetDependency);
			$TargetDependencyDeepName=$TargetDependencyArray[$iDepencencyDeepName];
			$Depends{$TargetDependencyDeepName}=undef;
			$Phony{$TargetDependencyDeepName}=undef if(CompareDeepPath($PathArray,\@TargetDependencyArray,$Deep+1)<=$Deep); # if upper level differs, add a phony not to compile a dependency in another non related node
			# Show real expended full target name when not in the final deep for more clarity
			# This helps to for example when Common has External as dependency, to know which target in external is needed for Common
			foreach my $TargetDependencyFullName (keys %{$HierarchicalDependencies->[1]->{$Target->[0]}->[0]->{$TargetDependency}})
			{
				my @TargetDependencyFullNameArray = split(/[\:]+/, $TargetDependencyFullName);
				if($iDepencencyDeepName<=$#TargetDependencyFullNameArray)
				{
					# but do not store the root path (so don't want Saturn.* but only *)
					shift @TargetDependencyFullNameArray;
					$RealDepends{join(":",@TargetDependencyFullNameArray)}=undef;
				}
			}
		}
	}
	# flush it on disk
	if((defined($BuildInfos) && ($BuildErrors==0 || (defined $bIgnoreError && $bIgnoreError!=0))) || ($Targets && (defined $Target->[1] && exists $Targets->{$Target->[1]}))) # but only if no errors, or if the target was already existing to write old target datas if errors
	{
		$rDepMakeDest->print (".PHONY: ".join(" ", sort(keys %Phony))."\n") if(keys(%Phony));
		$rDepMakeDest->print ($TargetShortName.'_deps=$(if $(nodeps),,'.join(" ", sort(keys %Depends)).")");
		# Do we have some full expanded depency names to show in comment for more clarity ?
		$rDepMakeDest->print (" # ".join(" ", sort(keys %RealDepends))) if(keys %RealDepends);
		$rDepMakeDest->print ("\n");
		$rDepMakeDest->print ($TargetShortName."_prio=".$Priority.",".(defined $nDuration?$nDuration:0)."\n\n");
	}

	# (1)Target(2)! means was built but there were some compilation errors, so this a warning (! symbole) saying that this is the value of the previous .dep file
	# 1 is + means this is a new target added in the DEP file, no compilation error
	# 1 is ? means this is a new target but its compilation failed & so was not added in the DEP file
	# 1 is ! means this target has not been compiled & maybe removed, target name & dependencies were retrieved from the old value
	# 1 is = means was rebuilt (this is an already known old target just rebuilt)
	# 2 is : means no error during the build
	# 2 is ! means was built but there were some compilation errors, so this a warning (! symbole) saying that this is the value of the previous .dep file
	if($Targets && (defined $Target->[1] && exists $Targets->{$Target->[1]})) # if key exists in the past
	{
		$rDepLog->print($TargetShortName.(defined($BuildInfos)?($BuildErrors!=0?(!defined $bIgnoreError || $bIgnoreError==0?"(WARNING : Already exists but generation failed, values retrieved from previous DEP file)":"(WARNING : Generation failed but updated because errors are ignored)"):""):"(WARNING : Maybe removed or not executed, values retrieved from previous DEP file)")."= ") if($rDepLog);
		# Output removed targets
		foreach my $CurrentDependency (@{$Targets->{$Target->[1]}[3]})
		{
			if(!exists $Depends{$CurrentDependency})
			{
				${$nNumberOfChanges}++;
				$rDepLog->print("".$CurrentDependency."(removed) ") if($rDepLog);
			}
		}
		# Output added targets
		%HashedDepends=(); 
		if(defined $Target->[1]) 
		{ 
			foreach my $CurrentDependency (@{$Targets->{$Target->[1]}[3]}) 
			{ 
				$HashedDepends{$CurrentDependency}++ 
			}
		}
		foreach my $CurrentDependency (keys %Depends)
		{
			if(!exists $HashedDepends{$CurrentDependency})
			{
				${$nNumberOfChanges}++;
				$rDepLog->print("".$CurrentDependency."(added) ") if($rDepLog);
			}
		}
		# output if we have an old value & a new value, calculate if we have to consider it as a change or not
		$rDepLog->print("# ") if($rDepLog);
		if(defined($BuildInfos) && ($BuildErrors==0 || (defined $bIgnoreError && $bIgnoreError!=0)))
		{
			# for build duration
			if(exists $BuildInfos->[1] && defined $Target->[1] && exists $Targets->{$Target->[1]}[2] && $nDuration!=$Targets->{$Target->[1]}[2] && abs($nDuration-$Targets->{$Target->[1]}[2])>$TimeRange)
			{
				${$nNumberOfChanges}++;
				$rDepLog->print("(Duration change : ".($nDuration-$Targets->{$Target->[1]}[2]).") ") if($rDepLog);
				
			}
		}
		$rDepLog->print("\n") if($rDepLog);
	}
	else
	{
			${$nNumberOfChanges}++ if(defined($BuildInfos) && ($BuildErrors==0 || (defined $bIgnoreError && $bIgnoreError!=0)));
			$rDepLog->print($TargetShortName.((defined($BuildInfos) && $BuildErrors==0)?"(added)":(defined($BuildInfos)?(!defined $bIgnoreError || $bIgnoreError==0?"(WARNING : New but not added because generation failed)":"(WARNING : New but generation failed, added because errors are ignored)" ):"(WARNING : New but not added because generation information was missing)"))."= ".join(" ", keys %Depends)."\n") if($rDepLog);
	}

	return 1;
}
#########################################################################################################################
# ret = sub FindBackupFileSlot(arg1)
#########################################################################################################################
#		arg1 is the complete filename which will be backuped
#	ret will contain the numbered extension which should be concated to arg1 by the caller.
#########################################################################################################################
sub FindBackupFileSlot($)
{
	# Retrieve parameters
	my $FilePrefix = shift;
	my $Slot=0; #initialize return value
	while (defined($next = <$FilePrefix.*>))  # scan .dat files in this directory
	{
		$_=$next;
		next unless(($next) = /\.(\d+)$/ && $next =~ /\d/); # only threat files name.dep.#number
		$next=int($next);
		$Slot=$next if($next>$Slot);
	}
	$Slot = sprintf("%d", ++$Slot);
	return $Slot;
}

#########################################################################################################################
# ret = sub FlushHierarchicalEntryToDependencyFile(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19, arg20, arg21)
#	Convert only one node data created by FlatToHierarchicalDependency into one file
#		For example, if having a componenent Saturn._External._icuc having dependencies, where arg2 is 1 as current deep level, it will create :
#			- a second file in arg1 dir\Saturn\External\External.dep
#	This method is called by HierarchicalDependenciesToDependencyFile to flush each node on disk
#########################################################################################################################
#		arg1[in] P4 handle to Perforce object for submitting DEP file if needed
#		arg2[in] P4 Changelist number where must be submit modified files
#		arg3[in] Starting submitting dependencies files only from node level arg3 (for example not to submit root dep file)
#		arg4[in] Log file name cotaining all dependencies change, if eq "" so will be created using the .gmk filename with .log extension
#		arg5[in] Path for the project central dep file
#		arg6[in] Root node number where the project really starts
#		arg7[in] Origin root dir for accessing original .dep files
#		arg8[in] root destination dir, will contains the root node .dep files & all sublevel dependencies as described above
#		arg9[in] defined if clean .dep without unused targets must be generated, otherwise undef
#		arg10[in] Update even if build failed
#		arg11[in] Time range change for updating compilation
#		arg12[in/out] Build errors for each target & computed build errors number for current level
#		arg13[in] Current deep path at recursivity level 0, will only contains "Saturn", at level 1, will contains "Saturn._External"
#		arg14[in] Max deep generation, for exemple 1 if you want only the root level (Saturn.dep)
#		arg15[in/out] Is the starting hierarchical node to flush to disk & if done, subdir is deleted
#		arg16[in] Excluded target not to save
#		arg17[in] Current Deep recursivity level
#		arg18[in] New Dep files suffix
#		arg19[in] even if no change save the new file (boolean)
#		arg20[in] Do we have to version the targets output
#		arg21[in] If true, first time .mak files are executed to retrieve list && results are cached for next read
#	ret return total number of modifications done
#########################################################################################################################
sub FlushHierarchicalEntryToDependencyFile($$$$$$$$$$$$$$$$$;$$$$)
{
	my $p4=shift;
	my $iChangelist=shift;
	my $StartSubmittingFromNodeLevel=shift;
	my $LogFile=shift;
	my $ProjectDepFilePath=shift;
	my $RootNode=shift;
	my $OrgRootDir=shift;
	my $DestRootDir=shift;
	my $Wash=shift;
	my $bIgnoreError=shift;
	my $TimeRange=shift;
	my $BuildInfos=shift;
	my $Path=shift;
	my $MaxDeep=shift;
	my $HierarchicalDependencies=shift;
	my $ExcludedTargets=shift;
	my $Deep=shift;
	
	my $Suffix=shift;
	my $ForcedCheckin=shift;
	my $Versioned=shift;
	my $bCachedResult=shift;

	my @PathArray = split(/[\:]+/, $Path);
	my $OutputFileName=undef;
	my $OrgDependenciesDirectory=undef;
	my $nNumberOfChanges=0;
	my $LeafErrors=0;
	my $DepMake="";
	my $DepMakeTmpName="";
	my $UnversionedOutputFileName="";
	my $OutputFileNameVersion="";

	return 0 if($Deep<$RootNode); # if root node not set at zero, & current deep lower, ignoring current node
	
	{
		my @tmpPathArray = @PathArray;
		$OutputFileName=$tmpPathArray[$Deep]; # Get the real output file name regarding the deep
		($UnversionedOutputFileName,$OutputFileNameVersion) = $OutputFileName =~ /^(.+)[\\\/](.+)$/;
		$UnversionedOutputFileName=$OutputFileName if(!defined $UnversionedOutputFileName);

		shift @tmpPathArray; # remove the root as the root is normaly also a filename when deep=0 & is located directly in $DestRootDir
		$OrgDependenciesDirectory=($Deep==$RootNode && defined($ProjectDepFilePath) && $ProjectDepFilePath ne ""?$ProjectDepFilePath:$OrgRootDir).($Deep>$RootNode?("/".join("/",@tmpPathArray)):"");
				
		# First search for windows.dep or unix.dep, next for backward compatibility with .dep & finally with win32_x86|... . dep
		#$DepMake=$OrgDependenciesDirectory."/".$UnversionedOutputFileName.".".$ENV{OS_FAMILY}.$Build::OS_TYPE.".dep";
		#$DepMake.=(defined $Suffix?$Suffix:"");
		#unless(-e $DepMake)
		#{
			# Next search for windows.dep or unix.dep, next for backward compatibility with .dep & finally with win32_x86|... . dep
			$DepMake=$OrgDependenciesDirectory."/".$UnversionedOutputFileName.".".$ENV{OS_FAMILY}.".dep";
			$DepMake.=(defined $Suffix?$Suffix:"");
			#unless(-e $DepMake)
			#{
			#	$DepMake=$OrgDependenciesDirectory."/".$UnversionedOutputFileName.".dep";
			#	# Ensure backward compatibility (Main/Stable/Build must work for both PI and Stable):
			#	unless(-e "$DepMake") { $DepMake =~ s/\.dep$/.$Build::PLATFORM.dep/; $DepMake.=(defined $Suffix?$Suffix:""); };
			#}
		#}
				
		my $ReelDestOutDir=($Deep==$RootNode && defined($ProjectDepFilePath) && $ProjectDepFilePath ne "" && (!defined($DestRootDir) || $DestRootDir eq $OrgRootDir)?$ProjectDepFilePath:(defined($DestRootDir)?$DestRootDir:$OrgRootDir)).($Deep>$RootNode?("/".join("/",@tmpPathArray)):"");
		mkpath("$ReelDestOutDir") or die("ERROR: cannot mkpath '$ReelDestOutDir': $!") unless(-e "$ReelDestOutDir");
		$DepMakeTmpName=$ReelDestOutDir."/".$UnversionedOutputFileName.(!defined($DestRootDir) || $OrgRootDir eq $DestRootDir?".dep.tmp":(".".$ENV{OS_FAMILY}.".dep"));
	}

	my $depLogHandle;
	if($Log)
	{
		open($depLogHandle, ">>".($LogFile && $LogFile ne ""?$LogFile:($UnversionedOutputFileName.".log"))) or die("ERROR: cannot open log file '".($LogFile && $LogFile ne ""?$LogFile:($UnversionedOutputFileName.".log"))."': $!");
		print $depLogHandle "\n#Dependencies update for path '".$Path."' done at ".scalar(localtime())."\n";
	}

	$p4->Sync("-f ".$DepMake."#head") if($p4 && -e "$DepMake"); # Before force file refresh to take care of developers modifications since the build start other they will be removed

	my $ReadDeps=undef;
	if(!defined $Deep || $Deep==0) 
	{ 
		Build::GetAreasList(undef, $OrgDependenciesDirectory."/".$UnversionedOutputFileName.".gmk", undef, undef, \$ReadDeps, 1, 1, undef, $bCachedResult); 
	} 
	else 
	{ 
		$ReadDeps=Build::GetTargetsListForArea(undef, $OutputFileName, $OrgDependenciesDirectory, undef, undef, 1, 1, undef, $bCachedResult); 
	}
	if(open(my $depHandle, ">$DepMakeTmpName"))
	{

		my %Targets;
		foreach my $Target(keys %{$HierarchicalDependencies->[1]}) { $Targets{$Path.":".$Target}[0]=$Target;} # Create a unique table which will be sorted containing existing & new targets
		foreach my $Target(keys %{$ReadDeps}) 
		{ 
			next if ($Target =~ /^[\.#].*/); # Do not try to save targets starting with # or . chars

			my($Dummy,$TargetShortName) = $Target =~ /^(.+)[\:](.+)$/;
			$TargetShortName=$Target if(!defined $TargetShortName);
			$Targets{$Path.":".$TargetShortName}[1]=$Target; 
		} # Create a unique table which will be sorted containing existing & new targets

		foreach my $Target (sort keys %Targets) # Get new dependencies & update the list
		{
			next if(defined $ExcludedTargets && exists $ExcludedTargets->{$Target}); # is an excluded target ?

			# Increase current path errors
			$LeafErrors+=$BuildInfos->{$Target}[0] if($BuildInfos && exists $BuildInfos->{$Target} && exists $BuildInfos->{$Target}[0]);

			# If old target not executed, do not added in the new dep & go to the next one
			if(SaveTargetDependencies($depHandle,$depLogHandle,$Wash,$Target,$ReadDeps,\@{$Targets{$Target}},($BuildInfos && exists $BuildInfos->{$Target})?(\@{$BuildInfos->{$Target}}):undef,\@PathArray,$Deep,$HierarchicalDependencies, $bIgnoreError, $TimeRange ,\$nNumberOfChanges, $Versioned)==0)
			{ 
				# node not saved, inform it has been removed in log files
				if($ReadDeps && defined $Targets{$Target}[1] && exists $ReadDeps->{$Targets{$Target}[1]}) 
				{	
					#log to inform that this target has been removed in the new dep file
					$nNumberOfChanges++;
					# if no error information putting "-targetname? buildunit?..." instead of : to indicate this is a supposition
					my($Dummy,$TargetShortName) = $Targets{$Target}[1] =~ /^(.+)[\:](.+)$/;
					$TargetShortName=$Targets{$Target}[1] if(!defined $TargetShortName);

					$depLogHandle->print($TargetShortName."(removed)".(($BuildInfos && exists $BuildInfos->{$Target} && exists $BuildInfos->{$Target}[0] && $BuildInfos->{$Target}[0]!=0)?"?":"=")." \n") if($Log) ;
				}
			}
		}
		$depHandle->flush(); $depHandle->close();
	}
	else
	{
		print "    WARNING : Dependency file '".($DepMakeTmpName)."' not saved because : ".($!)."\n";
	}

	$depLogHandle->close() if($Log && $depLogHandle);

	# Update current path errors
	if($BuildInfos && exists $BuildInfos->{$Path} && $BuildInfos->{$Path}[0]) { $BuildInfos->{$Path}[0]+=$LeafErrors; }
	else { $BuildInfos->{$Path}[0]=$LeafErrors; }

	if(!$nNumberOfChanges && !defined($ForcedCheckin) && (!defined($DestRootDir) || $OrgRootDir eq $DestRootDir)) # no change, only delete the temporary file if DestDir is the original dir (so it is a temp file)
	{
		unlink($DepMakeTmpName) if(-e $DepMakeTmpName);
	}
	else # else rename it & submit it to perforce
	{
		my $bAddFile=0;
		# P4PERL : Code for editing perforce file (DEP) must be added here
		if($p4 && $Deep>=$StartSubmittingFromNodeLevel) # undef if no submit option in perforce has been set
		{
			chmod(0666,$DepMake); unlink($DepMake);
			$p4->Sync("-f ".$DepMake."#head"); # Before force file refresh for reducing conflicts
			if(-e "$DepMake") { $p4->Edit(!$iChangelist?$DepMake:("-c ".$iChangelist." ".$DepMake)); }
			else { $bAddFile=1; }
			print("WARNING: '$DepMake' cannot be edited or added in Perforce, you will have to submit it manually : ",@{$p4->Errors()}) if($p4->ErrorCount());
		}

		# Original DEP file now opened in edit mode, replace it by the new version & rename the old into .???
		if(!defined($DestRootDir) || $OrgRootDir eq $DestRootDir)
		{
			if(-f $DepMake)
			{
				my $BackupDepName=$DepMake.".".FindBackupFileSlot($DepMake);
				chmod(0666,$DepMake); rename($DepMake, $BackupDepName);
			}
			rename($DepMakeTmpName, $DepMake) or die("ERROR: cannot replace dependencies file '$DepMake' by '$DepMakeTmpName' : $!");
		}
		$p4->Add(!$iChangelist?$DepMake:("-c ".$iChangelist." ".$DepMake)) if($p4 && $bAddFile==1);
	}
	return $nNumberOfChanges;
}
#########################################################################################################################
# ret = sub HierarchicalDependenciesToDependencyFile(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19, arg20)
#	Convert data created by FlatToHierarchicalDependency into many files named regarding to the recurvivity
#		if having a componenent Saturn._External._icuc having dependencies, it will create :
#			- a file in arg1 dir\Saturn.dep
#			- a second file in arg1 dir\Saturn\External\External.dep
#########################################################################################################################
#		arg1[in] P4 handle to Perforce object for submitting DEP file if needed
#		arg2[in] P4 Changelist number where must be submit modified files
#		arg3[in] Starting submitting dependencies files only from node level arg3 (for example not to submit root dep file)
#		arg4[in] Optional, if undef, the log fille will be named with dep filename & location but with .log extension
#		arg5[in] Path for the project central dep file
#		arg6[in] Root node number where the project really starts
#		arg7[in] Origin root dir for accessing original .dep files
#		arg8[in] root destination dir, will contains the root node .dep files & all sublevel dependencies as described above
#		arg9[in] defined if clean .dep without unused targets must be generated, otherwise undef
#		arg10[in] Update even if build failed
#		arg11[in] Build errors for each target
#		arg12[in] Time range change for updating compilation
#		arg13[in] Max deep generation, for exemple 1 if you want only the root level (Saturn.dep)
#		arg14[in] Current deep path at recursivity level 0, will only contains "Saturn", at level 1, will contains "Saturn._External"
#		arg15[in/out] Is the starting hierarchical node to flush to disk & if done, subdir is deleted
#		arg16[in] Excluded target not to save
#		arg17[in] Current Deep recursivity level
#		arg18[in] Do we have to version the targets output
#		arg19[in] New Dep files suffix
#		arg20[in] even if no change save the new file (boolean)
#		arg21[in] If true, first time .mak files are executed to retrieve list && results are cached for next read
#	ret return total number of modifications done
#########################################################################################################################
sub HierarchicalDependenciesToDependencyFile($$$$$$$$$$$$$$$$$$;$$$)
{
	my $p4=shift;
	my $iChangelist=shift;
	my $StartSubmittingFromNodeLevel=shift;
	my $LogFile=shift;
	my $ProjectDepFilePath=shift;
	my $RootNode=shift;
	my $OrgRootDir=shift;
	my $DestRootDir=shift;
	my $Wash=shift;
	my $bIgnoreError=shift;
	my $TimeRange=shift;
	my $BuildInfos=shift;
	my $MaxDeep=shift;
	my $Path=shift;
	my $HierarchicalDependencies=shift;
	my $ExcludedTargets=shift;
	my $Deep=shift;
	my $Versioned=shift;

	my $Suffix=shift;
	my $ForcedCheckin=shift;
	my $bCachedResult=shift;

	my $nNumberOfChanges=0;

	return 0 if($Deep>=$MaxDeep);

	foreach my $SubElement (keys %{$HierarchicalDependencies->[1]}) # Get new dependencies & update the list
	{
		$nNumberOfChanges+=HierarchicalDependenciesToDependencyFile($p4, $iChangelist, $StartSubmittingFromNodeLevel, $LogFile, $ProjectDepFilePath, $RootNode, $OrgRootDir, $DestRootDir, $Wash, $bIgnoreError, $TimeRange, $BuildInfos, $MaxDeep,$Path.":".$SubElement,$HierarchicalDependencies->[1]->{$SubElement}, $ExcludedTargets, $Deep+1, $Versioned, $Suffix, $ForcedCheckin, $bCachedResult);
	}

	$nNumberOfChanges+=FlushHierarchicalEntryToDependencyFile($p4, $iChangelist, $StartSubmittingFromNodeLevel, $LogFile, $ProjectDepFilePath, $RootNode, $OrgRootDir, $DestRootDir, $Wash, $bIgnoreError, $TimeRange, $BuildInfos, $Path, $MaxDeep, $HierarchicalDependencies, $ExcludedTargets, $Deep, $Suffix, $ForcedCheckin, $Versioned, $bCachedResult);

	return $nNumberOfChanges;
}
#########################################################################################################################
# ret = sub __FlatToHierarchicalDependency(arg1, arg2, arg3, arg4, arg5, arg6, arg7)
#	Internal method called by FlatToHierarchicalDependency & used to convert flat dependencies to hierarchical dependencies
#########################################################################################################################
#		arg1[in/out] is a two element size array, first will contain a hash of hash containing dependencies,
#			second will contain a hash of arg1 array contanining d string containing sub levels
#		arg2[in] Original target
#		arg3[in] Original target name but in array format
#		arg4[in] its arg1's Depenceny target
#		arg5[in] its arg1's Depenceny target in array format
#		arg6[in] Difference deep level between original & dependency target
#		arg7[in] the file generating the dependency
#		arg8[in] Current deep level used in recursivity to create the deep tree
#		arg9[in] Max deep to analyze
#		arg10[in] boolean, save all dependencies details like the filename in the hierarchical hash table returned in arg1
#	ret No return value
#########################################################################################################################
sub __FlatToHierarchicalDependency($$$$$$$$$;$)
{
	# HierarchicalDependencies, arg1[in/out] is a two element array tree node containing two elements :
	#	Sample based on arg2="Saturn._Common.cxlib" & arg3="Saturn._External._icuc"
	#		arg4 is 0, so current node is Saturn which will have External as deeep level
	# 	[0] contains a hash of hash, first hash, is its dependent target name [0]{"Saturn._External"},
	#		next hask key is the componenent ($CurrentDepencency) name which is need for this node to be compiled : [0]{"_External"}{"Saturn._External._icuc"}
	#		Value of the hash of hash, is undef
	#	[1] contains sublevels stored through a hash, each sublevel is new HierarchicalDependency node :
	#		[1]{"_Saturn.Common"}=HierarchicalDependency
	#			this new entry will have as [0] entry : [0]{"Saturn._External._icuc"} because Saturn._Common needs Saturn._External._icuc sublevel to be compiled
	#	Taking the root node(so Saturn), it will contains all dependencies at the saturn level & sublevel for Common will contains all its sublevel dependencies
	#		(Saturn._Common has Saturn._External._icuc as depencency).
	
	my ($HierarchicalDependencies, $CurrentTarget, $TargetLeef, $CurrentDependency, $DependencyLeef, $DeepDifferenceLevel, $FileDependency,$CurrentDeepLevel,$TotalDeep,$bAllDetails)=@_;

	return if ($CurrentDeepLevel>=$TotalDeep); # Do not continue if we have reach the max deep

	my $LeefDeepLevel=0;
	$LeefDeepLevel=1 if(($CurrentDeepLevel+1)<$TotalDeep); # Is there another deep level, if yes, keys will be the sublevel

	# Thank's to CompareDeepPath allowing different type of dependencies management
	if($DeepDifferenceLevel<=$CurrentDeepLevel) # Generate dependencies even if not in the same level
	{
		my $SubTargetDependency=join(":",@{$DependencyLeef}[0...($CurrentDeepLevel>$DeepDifferenceLevel?($CurrentDeepLevel+$LeefDeepLevel):$DeepDifferenceLevel)]);
		unless(defined $HierarchicalDependencies->[0])
		{
			my $HoH=(); # Create a reference hash of hash entry (see comment above on args for its usage)
			$HierarchicalDependencies->[0]=$HoH;
		}
		unless(exists $HierarchicalDependencies->[0]->{$SubTargetDependency})
		{
			my $HoH=(); # Create a reference hash of hash entry (see comment above on args for its usage)
			$HierarchicalDependencies->[0]->{$SubTargetDependency}=$HoH;
		}
	 	
		
		if(defined $bAllDetails && $bAllDetails==1) { $HierarchicalDependencies->[0]->{$SubTargetDependency}->{$CurrentDependency}{$CurrentTarget}{$FileDependency}=undef if($FileDependency); }
		else { $HierarchicalDependencies->[0]->{$SubTargetDependency}->{$CurrentDependency}=undef; }
	}

	if(($CurrentDeepLevel+1)<$TotalDeep) # do we have still a sublevel to analyze ?
	{
		my $H=();
		$HierarchicalDependencies->[1]=$H unless($HierarchicalDependencies->[1]);
		my $A=[undef,undef]; # Allocate a new HierarchicalDepencencies two element array to store sublevel
		$HierarchicalDependencies->[1]->{$TargetLeef->[$CurrentDeepLevel+1]}=$A unless(exists $HierarchicalDependencies->[1]->{$TargetLeef->[$CurrentDeepLevel+1]});

		# New level to analyze do a recursive call
		__FlatToHierarchicalDependency(
			$HierarchicalDependencies->[1]->{$TargetLeef->[$CurrentDeepLevel+1]},
			$CurrentTarget,
			$TargetLeef, 
			$CurrentDependency,
			$DependencyLeef,
			$DeepDifferenceLevel,
			$FileDependency,
			$CurrentDeepLevel+1, 
			$TotalDeep,
			$bAllDetails
		) if (($CurrentDeepLevel+1)<$TotalDeep);
	}
	return;
}

sub FlatToHierarchicalDependency($$$$$$;$)
{
	my ($HierarchicalDependencies, $CurrentTarget, $CurrentDependency,$FileDependency,$CurrentDeepLevel,$TotalDeep,$bAllDetails)=@_;

	my @TargetLeef = split(/[\:]+/, $CurrentTarget);
	my @DependencyLeef=split(/[\:]+/, $CurrentDependency);

	# Do not use a string comparing but this function returning the deep level where differs the two targets
	# this will allow by a if comparator to define the type of dependency (see below)
	my $DeepDifferenceLevel=$CurrentTarget eq $CurrentDependency?$TotalDeep:CompareDeepPath(\@TargetLeef,\@DependencyLeef,$TotalDeep);
	
	return __FlatToHierarchicalDependency(
			$HierarchicalDependencies,
			$CurrentTarget,
			\@TargetLeef,
			$CurrentDependency,
			\@DependencyLeef,
			$DeepDifferenceLevel,
			$FileDependency,
			$CurrentDeepLevel, 
			$TotalDeep,
			$bAllDetails);
}

#########################################################################################################################
# ret = sub AnalyzeAllDependencies(arg1, arg2, arg3, arg4, arg5, arg6)
#	Create a flat hash of hash table containing components as arg1 hask key & arg2 as its dependency second hash key
#########################################################################################################################
#		arg1[in] is a hash table with target names as key & hash tables (read file name, undef) as associated values.
#		arg2[in] is a hash table with target names as key & hash tables (write file name, undef) as associated values.
#		arg3[in] is a hash table with target names as key & hash tables (create file name, undef) as associated values.
#		arg4[in/out] is the number of circular dependencies detected
#		arg5[in/out] is the number of files generated twice by different build units
#		arg6[in] is the database log file handle to flush all the database data in it.
#	ret is a hash table with target names as key & their dependencies (flat table) as associated values
#########################################################################################################################
sub AnalyzeAllDependencies($$$;$$$)
{
	# Retrieve parameters
	my $read=shift;
	my $write=shift;
	my $create=shift;
	my $nCircularDependencies=shift;
	my $nGeneratedTwice=shift;
	my $DatabaseLogHandle=shift;

	my %AllDependencies;

	# Generate a map of all files as key & corresponding writers as data
	my %AllCreatedAndWrittenFiles;
	foreach my $Target(keys(%{$write}))
	{
		next if($Target eq '');
		foreach $file(keys (%{$write->{$Target}})) # now look for each read files of this dependency
		{
			next if($file eq '');
			$AllCreatedAndWrittenFiles{$file}{$Target}=[$write->{$Target}{$file},0] if(!exists $AllCreatedAndWrittenFiles{$file} || !exists $AllCreatedAndWrittenFiles{$file}{$Target} || $write->{$Target}{$file}<$AllCreatedAndWrittenFiles{$file}{$Target}[0]);
		}
	}
	foreach my $Target(keys(%{$create}))
	{
		next if($Target eq '');
		foreach $file(keys (%{$create->{$Target}})) # now look for each read files of this dependency
		{
			next if($file eq '');
			$AllCreatedAndWrittenFiles{$file}{$Target}=[$create->{$Target}{$file},1] if(!exists $AllCreatedAndWrittenFiles{$file} || !exists $AllCreatedAndWrittenFiles{$file}{$Target} || $create->{$Target}{$file}<=$AllCreatedAndWrittenFiles{$file}{$Target}[0]);
		}
	}
	# Now flush on screen multiple write accesses to a file
	foreach my $file (keys(%AllCreatedAndWrittenFiles))
	{
		next if($file eq '');
		if(keys(%{$AllCreatedAndWrittenFiles{$file}})>1)
		{
			my $cCreationSeqNumber=0;
			my $cWrittenSeqNumber=0;
			my $Content="";
			foreach my $TargetWriter (keys(%{$AllCreatedAndWrittenFiles{$file}}))
			{
				next if($TargetWriter eq '');
				if($AllCreatedAndWrittenFiles{$file}{$TargetWriter}[1]) 
				{
					$cCreationSeqNumber=$AllCreatedAndWrittenFiles{$file}{$TargetWriter}[0] if($cCreationSeqNumber==0 || $AllCreatedAndWrittenFiles{$file}{$TargetWriter}[0]<$cCreationSeqNumber);
				}
				else
				{
					$cWrittenSeqNumber=$AllCreatedAndWrittenFiles{$file}{$TargetWriter}[0] if($cWrittenSeqNumber==0 || $AllCreatedAndWrittenFiles{$file}{$TargetWriter}[0]<$cWrittenSeqNumber);
				}
				$Content.="          ".($AllCreatedAndWrittenFiles{$file}{$TargetWriter}[1]?"c":"w").",$TargetWriter\n";
				${$nGeneratedTwice}++ if($nGeneratedTwice);
			}
			print "      ".($cCreationSeqNumber!=0 && $cWrittenSeqNumber>$cCreationSeqNumber?"WARNING":"Warning").": Multiple write accesses in \"".$file."\" by :\n".$Content;
		}
	}
	# Generate a map of all files as key & corresponding readers as data
	my %AllAlreadyExistingFiles;
	foreach my $Target(keys(%{$read}))
	{
		next if($Target eq '');
		foreach $file(keys (%{$read->{$Target}})) # now look for each read files of this dependency
		{
			next if($file eq '' || (exists $AllCreatedAndWrittenFiles{$file} && exists $AllCreatedAndWrittenFiles{$file}{$Target} && $AllCreatedAndWrittenFiles{$file}{$Target}[1]==1 && $AllCreatedAndWrittenFiles{$file}{$Target}[0]<=$read->{$Target}{$file}));
			$AllAlreadyExistingFiles{$file}{$Target}=[$read->{$Target}{$file},0] if(!exists $AllAlreadyExistingFiles{$file} || !exists $AllAlreadyExistingFiles{$file}{$Target} || $read->{$Target}{$file}<$AllAlreadyExistingFiles{$file}{$Target}[0]);
		}
	}
	foreach my $Target(keys(%{$write}))
	{
		next if($Target eq '');
		foreach $file(keys (%{$write->{$Target}})) # now look for each read files of this dependency
		{
			next if($file eq '' || (exists $AllCreatedAndWrittenFiles{$file} && exists $AllCreatedAndWrittenFiles{$file}{$Target} && $AllCreatedAndWrittenFiles{$file}{$Target}[1]==1 && $AllCreatedAndWrittenFiles{$file}{$Target}[0]<=$write->{$Target}{$file}));
			$AllAlreadyExistingFiles{$file}{$Target}=[$write->{$Target}{$file},1] if(!exists $AllAlreadyExistingFiles{$file} || !exists $AllAlreadyExistingFiles{$file}{$Target} || $write->{$Target}{$file}<=$AllAlreadyExistingFiles{$file}{$Target}[0]);
		}
	}


	# reading all targets which have opened some files in read or write mode only (so not created) to find dependencies
	# dependencies can be found if the same file has been created in another target...
	# So, files opened in read mode create the tagert dependency if they have been opened in another target in write mode
	foreach my $file(keys(%AllAlreadyExistingFiles))
	{
		next if($file eq '');

		foreach $AccessingTarget(keys (%{$AllAlreadyExistingFiles{$file}})) # now look for each read files of this dependency
		{
			next if($AccessingTarget eq '');

			# if current this file has been created by this build unit, go to the next & read after, go to the next
			next if(!exists $AllCreatedAndWrittenFiles{$file} || (exists $AllCreatedAndWrittenFiles{$file}{$AccessingTarget} && $AllCreatedAndWrittenFiles{$file}{$AccessingTarget}[1]==1 && $AllCreatedAndWrittenFiles{$file}{$AccessingTarget}[0]<=$AllAlreadyExistingFiles{$file}{$AccessingTarget}));

			# Now check who read it
			NEXT_CREATOR: foreach my $WritingTarget (keys(%{$AllCreatedAndWrittenFiles{$file}})) # look in each target were files have been read
			{
				# build units must be different & written build unit must be generated before the reader one
				next if($WritingTarget eq '' || $WritingTarget eq $AccessingTarget || $AllCreatedAndWrittenFiles{$file}{$WritingTarget}[0]>$AllAlreadyExistingFiles{$file}{$AccessingTarget}[0]);

				# if this already existing file has been opened in write mode & dependency has been also accessed in write mode or existing before being re-created, so also modified
				if($AllAlreadyExistingFiles{$file}{$AccessingTarget}[1] && (!$AllCreatedAndWrittenFiles{$file}{$WritingTarget}[1] || (exists $read->{$WritingTarget} && exists $read->{$WritingTarget}{$file} && $read->{$WritingTarget}{$file}<$AllCreatedAndWrittenFiles{$file}{$WritingTarget}[0])))
				{
					print "      WARNING : Ambiguous relation, $AccessingTarget and $WritingTarget not creators of this file but modified it together : $file\n";
					if($AllAlreadyExistingFiles{$file}{$AccessingTarget}[0]<$AllCreatedAndWrittenFiles{$file}{$WritingTarget}[0])
					{
						print "        Because $WritingTarget modified it after $AccessingTarget, assuming $WritingTarget is depending on $AccessingTarget.\n";
						next NEXT_CREATOR;
					}
				}
				if(exists $AllDependencies{$WritingTarget} && exists $AllDependencies{$WritingTarget}{$AccessingTarget})
				{
					print "      ERROR: Ambiguous relation, potential direct implicit or explicit circular dependency detected between :\n";
					print "        -\"$WritingTarget\" acessed this(ese) file(s) written by $AccessingTarget : \n";
					foreach my $CircularFile (keys(%{$AllDependencies{$WritingTarget}{$AccessingTarget}}))
					{
						print "          ".$CircularFile."\n";
					}
					print "        -\"$AccessingTarget\" acessed this file written by $WritingTarget : \n";
					print "          ".$file."\n";
					${$nCircularDependencies}++ if($nCircularDependencies);
				}
				$AllDependencies{$AccessingTarget}{$WritingTarget}{$file}=undef;
				print ($DatabaseLogHandle $AccessingTarget."|".$WritingTarget."|".$file."\n") if($DatabaseLogHandle);
			}
		}
	}

	return \%AllDependencies;
}

#########################################################################################################################
# ret = sub ExtractDependencies(arg1, arg2, arg3, arg4)
#	returns all the dependencies details between arg2 & arg3 (arg2 is the client, arg3 its provider, so arg2 depends
#		on arg3)
#########################################################################################################################
#		arg1[in] Is the starting hierarchical node to flush to disk & if done, subdir is deleted
#		arg2[in] Is the target client name
#		arg3[in] Is the dependency of arg2, so its provider
#		arg4[in] current node level in arg1
#	ret is a hash of hash of hash table containing dependencies details between two dependencies
#		{Client}{Provider}{File}
#########################################################################################################################
sub ExtractDependencies($$$;$)
{
	my $HierarchicalDependencies=shift;
	my $CurrentTarget=shift;
	my $CurrentDependency=shift;
	my $CurrentDeep=shift;
	
	$CurrentDeep=0 if(!defined $CurrentDeep);
		
	my @CurrentTargetArray = split(/[\:]+/, $CurrentTarget);
	return if($CurrentDeep>=(scalar @CurrentTargetArray));
		
	my $CurrentTargetLevel=$CurrentTargetArray[$CurrentDeep];
	
	my @CurrentDependencyArray = split(/[\:]+/, $CurrentDependency);
	$#CurrentDependencyArray=$CurrentDeep;
	my $CurrentDependencyLevel=join(":",@CurrentDependencyArray);

	$#CurrentDependencyArray=$CurrentDeep;
		
	if(exists $HierarchicalDependencies->[1]->{$CurrentTargetLevel})
	{
		if( ($CurrentDeep+1==scalar @CurrentTargetArray) && exists $HierarchicalDependencies->[1]->{$CurrentTargetLevel}->[0]{$CurrentDependencyLevel})
		{
			my %DependenciesDescriptionArray;
			foreach my $FullProviderName(keys %{$HierarchicalDependencies->[1]->{$CurrentTargetLevel}->[0]{$CurrentDependencyLevel}})
			{
				foreach my $FullClientName(keys %{$HierarchicalDependencies->[1]->{$CurrentTargetLevel}->[0]{$CurrentDependencyLevel}{$FullProviderName}})
				{
					foreach my $FileName(keys %{$HierarchicalDependencies->[1]->{$CurrentTargetLevel}->[0]{$CurrentDependencyLevel}{$FullProviderName}{$FullClientName}})
					{
						$DependenciesDescriptionArray{$FullClientName}{$FullProviderName}{$FileName}=undef;
					}
				}
			}
			return \%DependenciesDescriptionArray
		}
		return ExtractDependencies($HierarchicalDependencies->[1]->{$CurrentTargetLevel},$CurrentTarget,$CurrentDependency,$CurrentDeep+1);
	}
	return undef;
}

#########################################################################################################################
# ret = sub PrintCircularDependencies()
#	prints the full details of a circular dependencies path
#########################################################################################################################
#		arg1[in] xml file handle to save result
#		arg2[in] directory name where are stored .fmap & .ptree files.....
#		arg3[in] Is the starting hierarchical node to flush to disk & if done, subdir is deleted
#		arg4[in] Is the complete circular dependency path
#		arg5[in] when a circular path cannot be explained, print an error or a warning ?
#	ret is undef
#########################################################################################################################
sub _DumpProcessTree($$$;$);
sub _DumpProcessTree($$$;$)
{
	my $hXMLFile=shift;
	my $g_ptree=shift;
	my $ProcessID=shift;
	
	my $Recursivity=shift;
	
	return if(!defined $g_ptree || !exists $g_ptree->{$ProcessID});
	return if(!defined $hXMLFile);
	
	$Recursivity=0 if(!defined $Recursivity);
	
	$hXMLFile->print("        ".(" "x$Recursivity)."<Process id='$ProcessID'>\n");
	if(exists $g_ptree->{$ProcessID}->[0] && defined $g_ptree->{$ProcessID}->[0])
	{
		$hXMLFile->print("        ".(" "x$Recursivity)." <CommandLine>\n");
		$hXMLFile->print("        ".(" "x$Recursivity)."  ".$g_ptree->{$ProcessID}->[0]."\n");
		$hXMLFile->print("        ".(" "x$Recursivity)." </CommandLine>\n");
	}
	#_DumpProcessTree($hXMLFile, $g_ptree, $g_ptree->{$ProcessID}->[1], $Recursivity+1) if(exists $g_ptree->{$ProcessID}->[1] && defined $g_ptree->{$ProcessID}->[1]);
	$hXMLFile->print("        ".(" "x$Recursivity)."</Process>\n");
}
sub _DumpFileDependencies($$$$$)
{
	my $hXMLFile=shift;
	my $OutBinDir=shift;
	my $raListOfFiles=shift;
	my $Target=shift;
	my $bSaveProcessTree=shift;

	return if(!defined $hXMLFile);
	return if(!(my ($ProjectName, $Area, $BuildUnit) = $Target =~ /^(.+?)\.(.+?)\.(.+?)$/));
	my($AreaName,$AreaVersion) = $Area =~ /^(.+)[\\\/](.+)$/;
	$AreaName=$Area if(!defined $AreaName);
	
	my %g_fmap;
	my %g_ptree;
	my $CurrentDataOutputPath=$ENV{OUTPUT_DIR}."/depends/".$Area;
	my $FinalDATOutputFilePathName=$CurrentDataOutputPath."/".$ProjectName.$FIELD_SEPARATOR.$AreaName.(defined $AreaVersion?'@'.$AreaVersion:"").$FIELD_SEPARATOR.$BuildUnit;
		
	if(defined $bSaveProcessTree && $bSaveProcessTree==1 && (my $hFMAPFile=new IO::File "$FinalDATOutputFilePathName.fmap"))
	{ 
		while (defined(my $Line = <$hFMAPFile>))  
		{
			eval $Line;  
		}
		$hFMAPFile->close(); 
		undef($hFMAPFile);
	}
	if(defined $bSaveProcessTree && $bSaveProcessTree==1 && (my $hPTREEFile=new IO::File "$FinalDATOutputFilePathName.ptree"))
	{ 
		my $szFullPTreeContent="";
		while (defined(my $Line = <$hPTREEFile>))  
		{
			$szFullPTreeContent.=$Line;  
		}
		$hPTREEFile->close(); 
		eval $szFullPTreeContent;
		undef($szFullPTreeContent);
	}

	$hXMLFile->print("      <Target name='$Target'>\n");
	foreach my $File(@{$raListOfFiles})
	{
		$hXMLFile->print("       <File name='$File'>\n");
		foreach $FileNumber(keys %g_fmap)
		{
			my($FileName, $Mode, $PrcssID) = @{$g_fmap{$FileNumber}};
			if($FileName eq $File)
			{
				_DumpProcessTree($hXMLFile, \%g_ptree, $PrcssID);
			}
			
		}
		$hXMLFile->print("       </File>\n");
	}
	$hXMLFile->print("      </Target>\n");
	undef(%g_fmap);
	undef(%g_ptree);
}
sub PrintCircularDependencies($$$$$)
{
	my $hXMLFile=shift;
	my $OutBinDir=shift;
	my $HierarchicalDependenciesRoot=shift;
	my $CircularDependencyPath=shift;
	my $bError=shift;
	
	print "        Warning: Circular dependency path detected : \"".$CircularDependencyPath."\"\n";						
	$hXMLFile->print("  <Path name='$CircularDependencyPath'>\n") if(defined $hXMLFile);
	
	my @CircularDependencyPathArray = split(/\;+/, $CircularDependencyPath);
	for(my $nCurrentDependency=0;$nCurrentDependency<((scalar @CircularDependencyPathArray)-1);$nCurrentDependency++)
	{
		my $CurrentDependency=$CircularDependencyPathArray[$nCurrentDependency];
		my $NextInThePath=$CircularDependencyPathArray[$nCurrentDependency+1];
		
		print "          Links between $CurrentDependency;$NextInThePath\n";
		$hXMLFile->print("   <Node name='$CurrentDependency;$NextInThePath'>\n") if(defined $hXMLFile);

		my $DependenciesDetails=ExtractDependencies($HierarchicalDependenciesRoot, $CurrentDependency, $NextInThePath, 1);
		if(!defined $DependenciesDetails)
		{
			print "            ".(!defined $bError || $bError!=1?"WARNING : ":"ERROR: ")."There is no more link between this dependency, path details canceled !. Please, verify cleaned dependencies\n";
			next;
		}
		else
		{
			foreach my $OriginalTarget(keys %{$DependenciesDetails})
			{
				foreach my $OriginalDependency(keys %{$DependenciesDetails->{$OriginalTarget}})
				{					
					$hXMLFile->print("    <Dependency name='$OriginalTarget;$OriginalDependency'>\n") if(defined $hXMLFile);
					my @Files=keys %{$DependenciesDetails->{$OriginalTarget}{$OriginalDependency}};					
					print "            $OriginalTarget;$OriginalDependency\n";
					foreach my $File(@Files)
					{
						print "              $File\n";
					}
					_DumpFileDependencies($hXMLFile, $OutBinDir, \@Files, $OriginalTarget,undef);
					_DumpFileDependencies($hXMLFile, $OutBinDir, \@Files, $OriginalDependency,undef);
					$hXMLFile->print("    </Dependency>\n") if(defined $hXMLFile);
				}
			}
		}
		$hXMLFile->print("   </Node>\n") if(defined $hXMLFile);
	}
	$hXMLFile->print("  </Path>\n") if(defined $hXMLFile);
}

#########################################################################################################################
# ret = sub SavePTreeEntryDb()
#	Save a ptree entry in Saturn.dependencies.read or write.dat & manage temporary data on disk
#########################################################################################################################
#		arg1[in] global g_ptree with original keys as value 
#		arg2[in] global processTreeDb reference hash pointer
#		arg3[in] global g_fmap with original keys as value 
#		arg4[in] global g_fmap reference hash pointer
#		arg5[in/out] hash reference on process id dictionary
#		arg6[in/out] hash reference on buildunits id dictionary
#		arg7[in/out] number of of ids in the hash reference arg4 array, used to create a unique key
#		arg8[in/out] hash reference on fileids id dictionary
#		arg9[in] current build unit name
#		arg10[in] process id to flush
#		arg11[in] File handler where to flush data
#		arg12[in] Type of the source (read or write/create)
#		arg13[in] Type of the destination (read or write/create)
#	ret : error is undef otherwise 1 if ok
#########################################################################################################################
sub SavePTreeEntryDb($$$$$$$$$$$$$)
{
	my ($hProcessKeyTableDb,$processTreeDb,$hFileKeyTableDb,$g_fmapDb,$hProcessIDTableDb,$hBuildUnitIDTable,$nBuildUnitID,$hFileIDTableDb,$FullBuildUnitName,$ProcessID,$hProcessDAT,$OriginMode,$DestinationMode)=@_;
	
	return 1 if(!defined $processTreeDb || $processTreeDb->get_dup($ProcessID)==0);
	my @raFiles = $processTreeDb->get_dup($ProcessID);
	return 1 if(!(@raFiles));
			
	my $szDestinationFilesToFlush="";
	my $szOriginFilesToFlush="";
	
	my %AllNewFilesToAdd;
	{
		# AlreadyDoneDestinationFiles & AlreadyDoneOriginFiles are used not to create a new entry for an already file done
		my %AlreadyDoneDestinationFiles;
		my %AlreadyDoneOriginFiles;
		foreach my $DestinationFileID (@raFiles)
		{
			my $value=0;
			next unless($g_fmapDb->get($DestinationFileID,$value)==0);
			next unless( (my ($Mode, $File) = $value =~ /^(\d+)\.([^\.]+)$/));
			next unless($Mode & $OriginMode || $Mode & $DestinationMode);
			
			$AllNewFilesToAdd{$File}=undef unless(exists $AllNewFilesToAdd{$File});

			if($Mode & $DestinationMode && !exists $AlreadyDoneDestinationFiles{$File})
			{
				$szDestinationFilesToFlush.=$File."=>$DestinationFileID," ;
				$AlreadyDoneDestinationFiles{$File}=undef;
			}
			if($Mode & $OriginMode && !exists $AlreadyDoneOriginFiles{$File})
			{
				$szOriginFilesToFlush.='$hData{'.$File.'}[0]=0;push(@{$hData{'.$File.'}[1]},$A);';
				$AlreadyDoneOriginFiles{$File}=undef;
			}
		}				
	}
		
	return 1 if($szOriginFilesToFlush eq "" || $szDestinationFilesToFlush eq ""); # no file written loop to the next processid

	{
		my $value=0;
		$hProcessIDTableDb->put($value,$ProcessID) if($hProcessKeyTableDb->get($ProcessID,$value)==0);
	}

	$hBuildUnitIDTable->{$FullBuildUnitName}||=(++${$nBuildUnitID});
	
	foreach my $nCurrentFileID(keys %AllNewFilesToAdd)
	{
		my $value=0;
		$hFileIDTableDb->put($value,$nCurrentFileID) if($hFileKeyTableDb->get($nCurrentFileID,$value)==0);
	}

	my $szEntryToFlush= 'my $A=[];';
	$szEntryToFlush.= '$A->[0]='.$ProcessID.';'; # ProcessID
	$szEntryToFlush.= '$A->[1]='.$hBuildUnitIDTable->{$FullBuildUnitName}.';'; # BuildUnitID

	$szEntryToFlush.= '$A->[2]={'.$szDestinationFilesToFlush.'};'; 
	print($hProcessDAT $szEntryToFlush.$szOriginFilesToFlush."\n") ; 
	
	return 1;
}	

#########################################################################################################################

die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/^(.+?)[\\\/]?\d*$/$1/;
$ENV{TEMP} = $TEMPDIR;

$HOST       = hostname();
$DEFAULT_PRIORITY = "DEFAULT";

##############
# Parameters #
##############

Usage() unless(@ARGV);
$Getopt::Long::ignorecase = 0;
GetOptions("help|?"=>\$Help,
"areadependenciesonly!"   =>\$NOGNUMakeDependencyMode,
"build:s"	=>\$Build,
"checkin:s"	=>\$Checkin,
"Checkin:s"	=>\$ForcedCheckin,
"database!"	=>\$Database,
"Dependencies!"   =>\$DependenciesDATFiles,
"extended!"   	=>\$Extended,
"force!"        =>\$Force,
"gmake=s"	=>\$Makefile,
"ini=s"		=>\$Config,
"Ignore=s@"     => \@regexOnFileToIgnore,
"log!"		=>\$Log,
"mode=s"	=>\$BUILD_MODE,
"Monitor!" =>\$Monitor,
"output=s" 	=>\$Output,
"predictive!"   =>\$Predictive,
"Plugins!"   =>\$Plugins,
"reporting=s" 	=>\$Dashboard,
"Recovery"		=> \$Troubleshooting,
"source=s"	=>\$SRC_DIR,
"Suffix=s"	=>\$Suffix,
"timerange=i"	=>\$TimeRange,
"Thread=i"     => \$MAX_NUMBER_OF_PROCESSES,
"update!"	=>\$Update,
"versioned!"		=>\$Versioned,
"washed!"	=>\$Wash,
"64!"          => \$Model
);

Build::InitializeVariables($Model);
$Build::NULDEVICE       = $Build::PLATFORM eq "win32_x86" ? "nul" : "/dev/null";

$Checkin=$ForcedCheckin if(defined($ForcedCheckin));
$DependenciesDATFiles=1 unless(defined $DependenciesDATFiles);

if($DependenciesDATFiles==1)# now starting global dependencies files generation (by processes)
{ 		
	unless(defined $DB_File::VERSION)
	{
		die("ERROR: Option '-Dependencies' enabled but 'DB_File' Perl module not installed!");
	}
}

$NOGNUMakeDependencyMode=1 if(!defined $NOGNUMakeDependencyMode);
$Extended=0 if(!defined $Extended);
$Plugins=0 if(!defined $Plugins);
$Force=1 if(!defined $Force);
$Monitor=1 if(!defined $Monitor);
$Predictive=1 if(!defined $Predictive);
$TimeRange=60 if(!defined $TimeRange);
$MAX_NUMBER_OF_PROCESSES ||= 1;

Usage() if($Help);
unless($Makefile) { print(STDERR "the -g parameter is mandatory\n\n"); Usage() }
$BUILD_MODE ||= $ENV{BUILD_MODE} || "release";
if("debug"=~/^$BUILD_MODE/i) { $BUILD_MODE="debug" } elsif("release"=~/^$BUILD_MODE/i) { $BUILD_MODE="release" }
else { print(STDERR "ERROR: compilation mode '$BUILD_MODE' is unknown [d.ebug|r.elease]\n"); Usage() }

($SHORT_MODE = $BUILD_MODE) =~ s/^(.).*(.)$/$1$2/;


$CURRENTDIR = $FindBin::Bin;

ReadIni() if($Config) ;

$SRC_DIR    ||= $ENV{SRC_DIR};
unless($SRC_DIR) { print(STDERR "the SRC_DIR environment variable (or -s option) is mandatory\n\n"); Usage() }
$SRC_DIR =~ s/[\/\\]/\//g;

my $StartSubmittingFromNodeLevel=0;

if(defined $Checkin && Checkin ne "")
{
	$_=$Checkin;
	($Checkin, $StartSubmittingFromNodeLevel)= /([^,]*)(?:,(\d+))?/ ;
	$StartSubmittingFromNodeLevel=0 if(!defined $StartSubmittingFromNodeLevel);
}

$Checkin=$ForcedCheckin=undef if(!defined $Monitor || $Monitor==0);

$Client ||= (defined($Checkin) && $Checkin ne "")?$Checkin:$ENV{Client};
# if checkin requested the $Client parameter must be set throught environment variable or -c option argument
if(defined($Checkin) && (!defined($Client) || $Client eq "")) { print(STDERR "the Client environment variable (or -c argument) is mandatory\n\n"); Usage() }

($ROOT_DIR) = $ENV{ROOT_DIR} || ($SRC_DIR=~/^(.*)[\/\\]/);
$ROOT_DIR   =~ s/[\/\\]/${\Depends::get_path_separator()}/g;
$ENV{SRC_DIR}      = $SRC_DIR;
$ENV{PATH}="$BOOTSTRAPDIR/export/${Build::PLATFORM}${Build::PATH_SEPARATOR}".$ENV{PATH};
$ENV{PATH}="$BOOTSTRAPDIR/export/win64_x86".$Build::PATH_SEPARATOR.$ENV{PATH} if($Build::PLATFORM eq "win32_x86" && $PROCESSOR eq "x86_64" );
$ENV{LD_LIBRARY_PATH}="$BOOTSTRAPDIR/export/${Build::PLATFORM}".(exists $ENV{LD_LIBRARY_PATH} && defined $ENV{LD_LIBRARY_PATH}?"${Build::PATH_SEPARATOR}$ENV{LD_LIBRARY_PATH}":"") if($Build::PLATFORM ne "win32_x86");
if($Extended==1 && $Plugins==1)
{
	$ENV{NANT_ARGS}	||= " -listener:Filelog.NAnt.FilelogBuildListener -extension:\"$BOOTSTRAPDIR/export/win32_x86/Filelog.NAnt.dll\"" if($Build::PLATFORM eq "win32_x86");	
	$ENV{ANT_ARGS}	||= " -lib $BOOTSTRAPDIR/export/java -listener com.businessobjects.RMTools.Ant.FilelogBuildListener" ;
}
$ENV{ROOT_DIR}    ||= $ROOT_DIR;
$ENV{build_mode}  = $ENV{BUILD_MODE}  = $BUILD_MODE;
($ENV{OUTPUT_DIR} ||= ($ENV{OUT_DIR} || ($SRC_DIR=~/^(.*)[\\\/]/, "$1/$Build::PLATFORM"))."/$BUILD_MODE")=~ s/[\/\\]/\//g;
$OUTPUT_DIR = $ENV{OUTPUT_DIR};
$ENV{OUTBIN_DIR} ||= $ENV{OUTPUT_DIR}."/bin";
$OUTLOGDIR = "$ENV{OUTPUT_DIR}/logs".($Output?"/$Output":"");
$SRC_DIR =~ s/[\/\\]/${\Depends::get_path_separator()}/g;
$Submit    = $ENV{SUBMIT_LOG} ? "-submit" : "";
$BuildName = ((exists $ENV{context} && defined $ENV{context})?($ENV{context}):"").((exists $ENV{build_number} && defined $ENV{build_number})?("_".$ENV{build_number}):"");

## Read Makefile ##
my @RequestedAreas;
my $MakefilePath;
my $MakefileName;
my $MakefileExtension;
{
	my $RequestedAreasString;
	($Makefile, $RequestedAreasString) = split('=', $Makefile);
	$Makefile=abs_path($Makefile); # First, get the absolute path to the current make file
	($MakefileName,$MakefilePath,$MakefileExtension)=fileparse($Makefile,'\..*'); # get directory, & basename of the makefile
	$MakefilePath=~ s/[\/\\]$//;

	@RequestedAreas=split(',', $RequestedAreasString) if($RequestedAreasString);
}

mkpath("$OUTLOGDIR") or die("ERROR: cannot mkpath '$OUTLOGDIR': $!") unless(-e "$OUTLOGDIR");
# This is for putting all logs inside
mkpath("$OUTLOGDIR/depends") or die("ERROR: cannot create '$OUTLOGDIR/depends': $!") unless(-e "$OUTLOGDIR/depends");

########
# Main #
########

my @Start = Today_and_Now();
$ENV{build_parentstepname}=$ENV{build_stepname} if(exists $ENV{build_stepname});
$ENV{build_steptype}="build_unit";
$ENV{TORCH_METHOD}="logAndGetID"; # Enable specific process_log method for reporting in Torch not in oneway & to get the result id !
$ENV{BUILD_DATE_EPOCH}||=time();

## Clean and Fetch ##
chdir($CURRENTDIR) or die("ERROR: cannot chdir '$CURRENTDIR': $!");

# Area List #
my $Areas=undef;
my $AllAreas=Build::GetAreasList($MakefileName, $Makefile,undef,undef,undef,undef,undef,undef,$Troubleshooting);
$Areas=Build::RemoveUnwanteds($AllAreas,\@RequestedAreas) if($AllAreas);

# Buildunits result id table

# Code for running targets &/| converting log files into perl files if no build requested
if(defined $Build) # if in building mode, initialize socket & select for receiving tracked name files
{
	if($Config)
	{
		print("Update $SRC_DIR...\n");
		system("perl Build.pl -i=$Config -nodashboard -nolabeling -C -F > ".$Build::NULDEVICE);
	}

	my $raTargetsToBuild; # Array containing build units/targets to build regarding their depencencies order
	my $Targets; # will be used by the dependencies computer


	# Build units list
	if($AllAreas) 
	{ 
		# do we have to re-order targets exactly in the area order & just take care of build units dependencies coming from the same area 
		# & ignore build units dependencies coming from other areas
		if(defined $NOGNUMakeDependencyMode && $NOGNUMakeDependencyMode==1) 
		{
			my $A=[]; # Allocate an empty array
			$raTargetsToBuild=$A;
			# instead of calling GetTargetsList() with all the area lists which will load first all build units & their dependencies & after this
			# calculate the compilation order by taking care of dependencies coming from another area,
			# read each area by area & calculate their order inside this area
			# because no other area are loaded during the order computing, no link is etablished with a dependency coming from another area !
			foreach my $CurrentArea(@{$Areas})
			{
				my $tmpTargets=Build::GetTargetsListForArea($MakefileName,$CurrentArea,$SRC_DIR."/".$CurrentArea,undef,undef,undef,undef,undef,$Troubleshooting);
				if($tmpTargets)
				{
					my $tmpTargetsToBuild=Build::ExecuteTargets(1, 1, undef, $tmpTargets, 1);
					if($tmpTargetsToBuild)
					{
						push(@${raTargetsToBuild},@{$tmpTargetsToBuild});
						$Targets=Build::ConcatenateTargets($Targets, $tmpTargets);
					}
				}
			}
		}
		# or do we have to work in the GNU Make mode : compute areas dependencies, 
		# & drill into the build units level & take care also of build units dependencies 
		# even if some onf them contain some dependencies not coming from the same area
		else 
		{
			$Targets=Build::GetTargetsList($MakefileName,$Areas,$SRC_DIR,undef,undef,undef,$Troubleshooting) if($Areas); 
		}
	}
	else { $Targets=Build::GetTargetsListForArea($MakefileName,$MakefileName,$MakefilePath,undef,undef,undef,undef,undef,$Troubleshooting); }
	die("ERROR: Cannot retrieve dependencies : $!") if(!$Targets);
	
	# Calculate dependencies/targets building order only if only area was requested or if the GNU Make mode is available, so no $GNUMakeDependencyMode set

	$raTargetsToBuild=Build::ExecuteTargets(1, 1, undef, $Targets, 1) if(!defined $raTargetsToBuild || !defined $NOGNUMakeDependencyMode || $NOGNUMakeDependencyMode==0);
	$raTargetsToBuild=Build::RemoveUnwanteds($raTargetsToBuild,\@RequestedAreas) unless($AllAreas) ;

	my @RequestedBuildUnits=split(',', $Build);
	$raTargetsToBuild=Build::RemoveUnwanteds($raTargetsToBuild,\@RequestedBuildUnits);
	
	if(!defined $Troubleshooting || $Troubleshooting==0)
	{
		rmtree("$TEMPDIR/".$Build::OBJECT_MODEL."/".$SHORT_MODE."/depends/deps") if(-e "$TEMPDIR/".$Build::OBJECT_MODEL."/".$SHORT_MODE."/depends/deps"); # reset this directory & refill it again
	}
	mkpath("$TEMPDIR/".$Build::OBJECT_MODEL."/".$SHORT_MODE."/depends/deps") or die("ERROR: cannot mkpath '$TEMPDIR/".$Build::OBJECT_MODEL."/".$SHORT_MODE."/depends/deps': $!") unless(-e "$TEMPDIR/".$Build::OBJECT_MODEL."/".$SHORT_MODE."/depends/deps");


	# Create dashboard if requested
	if(defined $Dashboard)
	{ 
		my %UnitsActuallyInDashboard;
		my $DashboardContent=Build::DashboardGet($Dashboard,\%UnitsActuallyInDashboard); # open it or create it
		if($DashboardContent)
		{
			foreach my $BuildUnitFullName (@{$raTargetsToBuild})
			{
				my($Dummy,$BuildUnit) = $BuildUnitFullName =~ /^(.+)[\:](.+)$/;
				$BuildUnit=$BuildUnitFullName unless(defined $BuildUnit);
				next if(!exists $Targets->{$BuildUnitFullName});
				my($Command, $Area) = @{$Targets->{$BuildUnitFullName}}[0,4];
				Build::DashboardAddEntry($Dashboard, $DashboardContent, \%UnitsActuallyInDashboard, 0, $Build::PLATFORM, $BUILD_MODE, $Area, $BuildUnit);  # add new entries if need
			}
			Build::DashboardWrite($Dashboard, $DashboardContent); # update it
		}
	}

	print("Getting the last file sequence number...\n");
	my($SequenceNumber,$nLoadedProcess)=FindLastSequenceNumber($ENV{OUTPUT_DIR}); # used for undertanding files sequencies (when a file B has been read for exemple before it is re-open in written mode)
	$SequenceNumber=1 unless(defined $SequenceNumber);
	print("Build starting with sequence number: $SequenceNumber...\n");
	
	my $StartedSequenceNumber=$SequenceNumber;
	my $StartednLoadedProcess=$nLoadedProcess;
	my $NumberOfProcess=0;
	
	my %DependsPlatformByPid;
	my %FILELOG_W_NET;
	my %FILELOG_W_PTREE;
	my %FILELOG_W_FMAP;
	my %LogFileHandles;
	my %DurationTime;
	my %StartTime;
    my $NewFork = 0;    
    my $killedpid=-1;
    my %TcpServersByPid;
    my %PidBySocket;
	my %Tasks;
	my $TaskScopeNumber=0;
	my %uniqueProcessIds;

	my $read_set = IO::Select->new(); # create handle set for reading 	# handle for select for sequentially checking incoming data in the tcp server without blocking

	Build::SetCriticalPathPriority(Build::ComputeCriticalPath($Targets, \%ExcludeDeps),$Targets,$MAX_NUMBER_OF_PROCESSES,1);
	Build::ComputeTargetsOrderField($Targets,$raTargetsToBuild);
	my @BuildUnitInCompileOrder=Build::ComputeCompileOrder($Targets,$MAX_NUMBER_OF_PROCESSES);
	
	do
	{
		$NewFork = 0;    
		do
		{
			foreach my $rh ($read_set->can_read(1)) {
				# if it is the main socket then we have an incoming connection and
				# we should accept() it and then add the new socket to the $read_set
				foreach my $currentPid(keys %TcpServersByPid)
				{
					next unless($rh == $TcpServersByPid{$currentPid});
					my $ns = $rh->accept();
					$PidBySocket{$ns}=$currentPid;
					$read_set->add($ns);
					$rh=undef;
					last;
				}
				# otherwise it is an ordinary socket and we should read and process the request
				if(defined $rh) {
					my $szPacket="";
					my $nTotalReceivedBytes=0;
					my $RecvResult=undef;
					my $Signature=undef;
					my $iBufferPos=0;
					my $pid=$PidBySocket{$rh};

					binmode($rh);
					if(defined ($RecvResult=sysread($rh, $szPacket,FILELOG_CLIENT_BUFSIZE_RECV,0)) && $RecvResult>0)
					{
						my $iGlobalPacketSize=0;
						do
						{
							$nTotalReceivedBytes+=$RecvResult; $iBufferPos+=$RecvResult;
							if($iGlobalPacketSize==0)
							{
								($Signature)=unpack("S",$szPacket);
								if(defined $Signature && int($Signature)==64) # This is a binary data, new format as the first char is directly the separator without any string size
								{
									if($nTotalReceivedBytes>=8)  # Is it the new format sent by the WinXX drivers
									{
										($Signature, my $SpyRequestType, my $iFoundGlobalPacketSize)=unpack("SSL",$szPacket);
										$iGlobalPacketSize=$iFoundGlobalPacketSize;
									}
								}
								else # Old string format
								{
									$Signature=undef;
									if((my ($iFoundGlobalPacketSize,$szTrace)= $szPacket =~ /^(\d+)\@(.*)$/ms))
									{
										$iGlobalPacketSize=int($iFoundGlobalPacketSize)+length($iFoundGlobalPacketSize)+1;
										$szPacket=$szTrace;
										$iBufferPos=length($szPacket);
									}
								}
							}
						} while(($iGlobalPacketSize==0 || $nTotalReceivedBytes<$iGlobalPacketSize) && defined ($RecvResult=sysread($rh, $szPacket, $iGlobalPacketSize?($iGlobalPacketSize-$nTotalReceivedBytes):FILELOG_CLIENT_BUFSIZE_RECV,$iBufferPos)) && $RecvResult>0);

						unless(defined $RecvResult && $RecvResult>0)
						{
							# the client has closed the socket
							# remove the socket from the $read_set and close it
							$read_set->remove($rh);
							delete $PidBySocket{$rh};
							close($rh); 
							undef $rh;
							$rh=undef;
						}
						# ... process $buf ...
						if($iGlobalPacketSize && defined $szPacket)
						{
							if(defined $Signature && int($Signature)==64) # New data format sent by WinXX drivers
							{
									my @elements;
									@elements=unpack($szExpandedUnpackString."C*",$szPacket);
		
									(my $Signature, my $Architecture, my $SpyRequestType, my $length, my $SequenceNumber, my $RecordType, my $OriginatingTimePart1, my $OriginatingTimePart2, my $CompletionTimePart1, my $CompletionTimePart2, my $DeviceObject, my $FileObject, my $Transaction, my $ProcessId, my $ThreadId , my $Information, my $Status, my $AccessMask, my $IrpFlags, my $Flags, my $CallbackMajorId, my $CallbackMinorId, my $Reserved1, my $Reserved2, my $Reserved3, my $Reserved4, my $Reserved5, my $Reserved6, my $Arg1, my $Arg2, my $Arg3, my $Arg4, my $Arg5, my $Arg6Part1, my $Arg6Part2)=@elements[0..($iNumberOfElements-1)];
			 					    
									my $posToDelete=GetEndOfStringPos($iNumberOfElements,\@elements);
									my $UnicodedFilenameString=pack("C*",@elements[$iNumberOfElements..$posToDelete-1]);
									my $string = decode("UTF-16LE", $UnicodedFilenameString);
									$string = NFD($string);
									$string =~ s/\pM//og;
									
									($Information)=unpack("L",pack("b32",$Information));
									
									if($RecordType & RECORD_TYPE_MESSAGE)
									{
										$szPacket="".$ProcessId.".16.0.1.".$string;
									}
									elsif($RecordType & RECORD_TYPE_PROCESSEVENT)
									{
										$szPacket="".
											($Status==1?$Arg1:$ProcessId).".".
										 	(int($READ_MODE)|16).
										 	".0.1.".
											($Status==1?("[Child process created] ".$ProcessId):"[Child process ended] 0");
									}
									else
									{
										$szPacket="".
											 $ProcessId.".".
											 	(
											 		(($AccessMask&FILE_READ)?int($READ_MODE):0)|
											 		(($AccessMask&FILE_WRITE)?int($WRITE_MODE):0)|
											 		($Status==STATUS_SUCCESS && ($Information==FILE_SUPERSEDED || $Information==FILE_CREATED || $Information==FILE_OVERWRITTEN )?int($CREATE_MODE):0)
											 	).".".
											 	"0".".".
											 ($Status == STATUS_SUCCESS?1:0).".".
											 $string
											;
									}

							}
							
							if( (my ($ProcessID, $Mode, $Handle, $Success, $File) = $szPacket =~ /^([^\.]+).(\d+)\.([^\.]+).(\d+)\.(.*)$/ms)) # Received format is normaly : a.b values (with \n at the end), where a is 1 for writen file 0 for read file, & b its name
							{
								$ProcessID="".$ProcessID.$uniqueProcessIds{$ProcessID} if(defined $ProcessID && exists $uniqueProcessIds{$ProcessID});

								if($Mode==255) # if mode is 255, this is the process cpu usage time sent by the forked perl thread
								{
									$DurationTime{$pid}=int($File);
								}
								else
								{
									if($File =~ /^UNC\\.*/i || $File =~ /^\\Device\\LANMANREDIRECTOR\\.*/i ) # This is for tracking network file accesses
									{
										$FILELOG_W_NET{$pid}->print($Mode.",".$File."\n");
									}
									elsif ($Success==1 || ($Predictive && $Predictive!=0))
									{
										if(($Mode&16) && (my($InfoType, $InfoDetail) = $File =~ /^\[(.*?)\]\s(.*)$/ms))
										{
											# just save child process infos in logs
											if($InfoType eq "Child process created") 
											{ 
												$nLoadedProcess++;										
												$uniqueProcessIds{$InfoDetail}=$nLoadedProcess;
												$InfoDetail="".$InfoDetail.$nLoadedProcess;
												
												# This process should not contain Ant/Nant scopes as it was just created !
												delete $Tasks{$InfoDetail} if(exists $Tasks{$InfoDetail});
												if($Extended==1)
												{
													# are we working in a ant & nant scope, if yes reconstruct the pid linked to the scope level
													my $tmpProcessID=$ProcessID;
													if(exists $Tasks{$ProcessID} && defined $Tasks{$ProcessID}[0] && $Tasks{$ProcessID}[0]->Length())
													{
														$tmpProcessID=$ProcessID."@".join("@",$Tasks{$ProcessID}[0]->Keys())."@".$Tasks{$ProcessID}[0]->Values($Tasks{$ProcessID}[0]->Length()-1);
													}

													$FILELOG_W_PTREE{$pid}->print("\${\$g_ptree{'$InfoDetail'}}[1]='$tmpProcessID';\n"); 
													$FILELOG_W_PTREE{$pid}->print("push(\@{\${\$g_ptree{'$tmpProcessID'}}[2]},'$InfoDetail');\n"); 
												}
											}
											elsif($InfoType eq "Child process ended") 
											{
												delete $uniqueProcessIds{$ProcessID} if(defined $ProcessID && exists $uniqueProcessIds{$ProcessID});
											}
											elsif($InfoType eq "Child process started") 
											{ 
												my $tmpInfoDetail=$InfoDetail; $tmpInfoDetail=~ s/(['\\])/\\$1/g; 
												$FILELOG_W_PTREE{$pid}->print("\$g_ptree{\"$ProcessID\"}[0]='$tmpInfoDetail';\n") if($Extended==1); 
											}
											# save in memory scope traces level to reproduce a unique pid linked to the level of scope
											# scopes are returned by ant & nant listeners
											elsif($InfoType eq "Listener processing started")
											{
												$Tasks{$ProcessID}[0]=Tie::IxHash->new() if(!defined $Tasks{$ProcessID}[0]);
												my $tmpProcessID=$ProcessID;
												$tmpProcessID=$ProcessID."@".join("@",$Tasks{$ProcessID}[0]->Keys())."@".$Tasks{$ProcessID}[0]->Values($Tasks{$ProcessID}[0]->Length()-1) if($Tasks{$ProcessID}[0]->Length()>0);
												$Tasks{$ProcessID}[0]->Push($InfoDetail => (++$TaskScopeNumber));
												
												my $tmpInfoDetail=$ProcessID."@".join("@",$Tasks{$ProcessID}[0]->Keys())."@".$Tasks{$ProcessID}[0]->Values($Tasks{$ProcessID}[0]->Length()-1);
												if($Extended==1)
												{
													$FILELOG_W_PTREE{$pid}->print("\${\$g_ptree{'".$tmpInfoDetail."'}}[1]='".$tmpProcessID."';\n"); 
													$FILELOG_W_PTREE{$pid}->print("push(\@{\${\$g_ptree{'".$tmpProcessID."'}}[2]},'".$tmpInfoDetail."');\n"); 
												}
											}
											elsif($InfoType eq "Listener processing ended" && exists $Tasks{$ProcessID})
											{
												# not poping the key but deleting it with all keys added after, will help to 
												# resynchronize the tree If a previous pushed key which was not poped
												if(defined $Tasks{$ProcessID}[0] && defined (my $TaskPos=$Tasks{$ProcessID}[0]->Indices($InfoDetail))) { $Tasks{$ProcessID}[0]->Splice($TaskPos) ; }

												if(defined $Tasks{$ProcessID}[0] && !$Tasks{$ProcessID}[0]->Length()) { delete $Tasks{$ProcessID}[0]; $Tasks{$ProcessID}[0]=undef; } 
												delete $Tasks{$ProcessID} if(!defined $Tasks{$ProcessID}[0]);
											}
										}
										else
										{
											# are we working in a ant & nant scope, if yes reconstruct the pid linked to the scope level
											my $tmpProcessID=$ProcessID;
											if(exists $Tasks{$ProcessID} && defined $Tasks{$ProcessID}[0] && $Tasks{$ProcessID}[0]->Length())
											{
												$tmpProcessID=$ProcessID."@".join("@",$Tasks{$ProcessID}[0]->Keys())."@".$Tasks{$ProcessID}[0]->Values($Tasks{$ProcessID}[0]->Length()-1);
											}
											if($Extended==1)
											{
												$FILELOG_W_PTREE{$pid}->print("push(\@{\${\$g_ptree{'".$tmpProcessID."'}}[3]},\"$SequenceNumber\");\n");
												$FILELOG_W_FMAP{$pid}->print("$tmpProcessID*$SequenceNumber.$Mode.$File\n");
											}

											$File="\t'".$File."',".$SequenceNumber.",\n";
											foreach my $AccessMode(keys %{$LogFileHandles{$pid}}) # dispatch each file to the corresponding file regarding its access mode
											{
												if($AccessMode&$Mode) { my $fh=$LogFileHandles{$pid}{int($AccessMode)}; print $fh $File; }
											}
											$SequenceNumber++;
										}
									}
								}
								syswrite($rh,"1",1) if(defined $rh); # Acknowledge unlocking the client until the flush of the log request is not done
							}
							else
							{
								print("\nERROR: Unable to decode received packet [".$szPacket."]\n");
							}
						}
					}
					else
					{ 
						# the client has closed the socket
						# remove the socket from the $read_set and close it
						$read_set->remove($rh);
						delete $PidBySocket{$rh};
						close($rh);
						undef $rh;
						$rh=undef;
					}

				}
				threads->yield();
			}
			threads->yield();
			
		} while(!($killedpid = waitpid(-1, WNOHANG)));
		if($killedpid!=-1)
		{
			my %deletedPIDs=( $killedpid==-1?%PIDs:($killedpid => $PIDs{$killedpid}) );
			foreach my $pid(keys %deletedPIDs)
			{
			    my($Command, $Priority, $Weight, $raDepends, $Area, $ParentPath, $Status) = @{$Targets->{$deletedPIDs{$pid}}};
				my($AreaName,$AreaVersion) = $Area =~ /^(.+)[\\\/](.+)$/;
				my $BuildUnitFullName=$PIDs{$pid};
				print "---".$BuildUnitFullName." at ".scalar(localtime())."\n";
				${$Targets->{$BuildUnitFullName}}[6] = $Build::FINISHED;
	
				$AreaName=$Area if(!defined $AreaName);
	
				my($Dummy,$BuildUnit) = $BuildUnitFullName =~ /^(.+)[\:](.+)$/;
				$BuildUnit=$BuildUnitFullName unless(defined $BuildUnit);
				
				my $OutputFilePathName=$TEMPDIR."${\Depends::get_path_separator()}".$Build::OBJECT_MODEL."${\Depends::get_path_separator()}".$SHORT_MODE."${\Depends::get_path_separator()}depends${\Depends::get_path_separator()}deps${\Depends::get_path_separator()}".$MakefileName.$FIELD_SEPARATOR.$AreaName.(defined $AreaVersion?'@'.$AreaVersion:"").$FIELD_SEPARATOR.$BuildUnit;
				my $CurrentDataOutputPath=$ENV{OUTPUT_DIR}."/depends/".$Area;
			
				my $FinalDATOutputFilePathName=$CurrentDataOutputPath."/".$MakefileName.$FIELD_SEPARATOR.$AreaName.(defined $AreaVersion?'@'.$AreaVersion:"").$FIELD_SEPARATOR.$BuildUnit;
	
	
				my $EndTime=time();
				my $Errors;
				my $BuildUnitResultIDs;
	
				$DurationTime{$pid}=$EndTime-$StartTime{$pid} if(!defined $DurationTime{$pid});
		
				system("echo === Build stop: ".$EndTime." >>$OUTLOGDIR/$Area/$BuildUnit.log");
				foreach my $fh(values(%{$LogFileHandles{$pid}})) 
				{ 
					$fh->close; 
					undef $fh; 
				}
				delete $LogFileHandles{$pid}; 
				
				if($Extended==1)
				{ 
					$FILELOG_W_PTREE{$pid}->close; undef $FILELOG_W_PTREE{$pid}; delete $FILELOG_W_PTREE{$pid}; 
					$FILELOG_W_FMAP{$pid}->close; undef $FILELOG_W_FMAP{$pid}; delete $FILELOG_W_FMAP{$pid}; 
				}
				$FILELOG_W_NET{$pid}->close; undef $FILELOG_W_NET{$pid}; delete $FILELOG_W_NET{$pid}; 
				${$Targets->{$BuildUnitFullName}}[2]=$DurationTime{$pid}; # Save execution time in table
		
				# Send log to process log for retrieving error analyzing & return it to build.pl
				$ENV{AREA} = $Area;
			   	$ENV{UNIT} = $BuildUnitFullName;
				$ENV{order}= $Targets->{$BuildUnitFullName}[7] ;
	
		        open(my $PROCESSLOG, "perl $CURRENTDIR/process_log.pl $Submit -real $OUTLOGDIR/$Area/$BuildUnit.log 2>&1 |");
		        while(<$PROCESSLOG>)
		        { 
		            print;
		            if(/^=\+=Errors detected: (\d+)/i) { $Errors = $1 }
		            elsif(/^=\+=Start: (.+)$/i)        { $StartTime{$pid} = $1 }
		            elsif(/^=\+=Stop: (.+)$/i)         { $EndTime = $1 }
		            elsif(/^=\+=Torch: (.+)$/i)         { $BuildUnitResultIDs = int($1) if(defined $1 && $1>0); }
		        }
		        close($PROCESSLOG);
		
				if(defined $Dashboard)
				{ 
					my %UnitsActuallyInDashboard;
					my $DashboardContent=Build::DashboardGet($Dashboard); # open it or create it
					if($DashboardContent)
					{
						Build::DashboardUpdateEntry($Dashboard, $DashboardContent, $OUTLOGDIR, 0, $Build::PLATFORM, $BUILD_MODE, $Area, $BuildUnit, $Errors, $StartTime{$pid}, $EndTime);  # add new entries if need
						Build::DashboardWrite($Dashboard, $DashboardContent); # update it
					}
				}
		
				# Record also errors to determine during analyzis if depencencies of this target must be updated (no if errors)
				# It also contains build time for filling correctly the time value in unit_prio if only started with option -u
				{
					open(my $FH, ">".$FinalDATOutputFilePathName.".build") or die("ERROR: cannot open '".$FinalDATOutputFilePathName.".build"."': $!");
					print($FH '@{$g_buildinfos{"'.$MakefileName.":".$Area.":".$BuildUnit.'"}}=('.(defined($Errors)?int($Errors):-1).",".${$Targets->{$BuildUnitFullName}}[2].");\n");
					print($FH '$g_targets{"'.$MakefileName.":".$Area.":".$BuildUnit.'"}=undef;'."\n");
					close ($FH);
				}
		
				# Record actual sequence number if current datas imported later
				if(open(my $DEPENDSNUMBERFILE, ">".$ENV{OUTPUT_DIR}."/depends/".$Area."/depends.seq"))
				{
					print($DEPENDSNUMBERFILE "".$SequenceNumber.",".$nLoadedProcess);
					close($DEPENDSNUMBERFILE);
				}
				# Record buildunit result_id		
				if(open(my $DEPENDSNUMBERFILE, ">>".$ENV{OUTPUT_DIR}."/depends/".$Area."/depends.rid"))
				{ 			
					print($DEPENDSNUMBERFILE '$hashBuildUnitResultIDs{'."'".$BuildUnit."'".'}='.(defined $BuildUnitResultIDs && $BuildUnitResultIDs>0?$BuildUnitResultIDs:"undef").";\n"); 
					close($DEPENDSNUMBERFILE); 
				}
				
				# TODO : ne pas faire si en multiproc !
				unless($Predictive && $Predictive!=0) # not in preditive mode, clean/removed missing files & convert da0 files into dat files now
				{
					FilterBuildUnitDATFiles($DependsPlatformByPid{$pid}, $MakefileName, $SRC_DIR, $OUTPUT_DIR, $ENV{OUTBIN_DIR}, $ROOT_DIR, $TEMPDIR, $Area, $BuildUnit,\@regexOnFileToIgnore) or die("ERROR: cannot filter da0 file for build unit '".$MakefileName.":".$AreaName.(defined $AreaVersion?'@'.$AreaVersion:"").":".$BuildUnit."': $!");
				}
				
				delete $StartTime{$pid};
				delete $DurationTime{$pid};
				$read_set->remove($TcpServersByPid{$pid});
				delete $PidBySocket{$TcpServersByPid{$pid}};
				close($TcpServersByPid{$pid}); delete $TcpServersByPid{$pid};
				delete $DependsPlatformByPid{pid};
				$NumberOfProcess--;
	
				if(defined $Troubleshooting && $Troubleshooting==1 && defined $Errors && $Errors>0)
				{
					die("Troubleshooting mode, stopping due to build unit: ".$BuildUnitFullName." failing...");
				}
			} # for 
		} # if($waitpid!=-1)
		
		if($NumberOfProcess<$MAX_NUMBER_OF_PROCESSES)
		{
			UNT: foreach my $BuildUnitFullName (@BuildUnitInCompileOrder)
			{
			    next if($BuildUnitFullName =~ /^[\.#].*/);
			    if(exists($ExcludeDeps{$BuildUnitFullName})) { ${$Targets->{$BuildUnitFullName}}[6] = $Build::FINISHED; next }
			    my($Command, $Priority, $Weight, $raDepends, $Area, $ParentPath, $Status) = @{$Targets->{$BuildUnitFullName}};
			    next if($Status != $Build::WAITING);
			    next if(Build::IsTargetOrdered($Targets,$BuildUnitFullName)==0);
			    if($raDepends) 
			    { 
			    	foreach my $Depend (@{$raDepends}) 
			    	{ 
				    	my $FullDependencyName=Build::GetFullTargetName($Targets, $Depend);
			    		next UNT if(exists($Targets->{$FullDependencyName}) && $Targets->{$FullDependencyName}[6] != $Build::FINISHED) 
			    	} 
			    }
			    
				my($AreaName,$AreaVersion) = $Area =~ /^(.+)[\\\/](.+)$/;
				$AreaName=$Area if(!defined $AreaName);
	
				my($Dummy,$BuildUnit) = $BuildUnitFullName =~ /^(.+)[\:](.+)$/;
				$BuildUnit=$BuildUnitFullName unless(defined $BuildUnit);

	        	if(defined $Troubleshooting && $Troubleshooting==1 && -e "$OUTLOGDIR/$Area/$BuildUnit.summary.txt")
	        	{
			        my $Errors=0;
			        open(my $PROCESSLOG, "$OUTLOGDIR/$Area/$BuildUnit.summary.txt");
			        while(<$PROCESSLOG>)
			        { 
			            $Errors += $1 if(/^== Sections with errors: (\d+)/i);
			        }
					close($PROCESSLOG);

			        if($Errors==0) 
			        	{ ${$Targets->{$BuildUnitFullName}}[6] = $Build::FINISHED; next }

			    }

						
				my $server; # server connection socket handle (for accepting incoming connection requests
				my $localDEPENDS_PORT=$DEPENDS_PORT;
				$localDEPENDS_PORT++ while(!defined ($server = IO::Socket::INET->new(LocalPort => $localDEPENDS_PORT, Type => SOCK_STREAM, Reuse => 0, Listen => 32)) && !$ENV{FILELOG_PORT});
				die("ERROR: Cannot open socket for buildunit '$BuildUnitFullName': $@\n") if(!defined $server);
				my $DependsPlatform=new Depends($localDEPENDS_PORT, $ROOT_DIR, $SRC_DIR, $BOOTSTRAPDIR);

				$ENV{UNIT} = $BuildUnitFullName;
				$ENV{area} = $Area;
				$Targets->{$BuildUnitFullName}[6] = $Build::INPROGRESS;
				mkpath($OUTLOGDIR."/".$Area) unless(-d $OUTLOGDIR."/".$Area);
				mkpath($ENV{OUTPUT_DIR}."/depends/".$Area) or die("ERROR: cannot open '".$ENV{OUTPUT_DIR}."/depends/".$Area."': $!") unless(-d $ENV{OUTPUT_DIR}."/depends/".$Area);
				
				print "+++".$BuildUnitFullName." at ".scalar(localtime())."\n";
	   			my $kidpid = fork();
	   			my $LocalStartTime=time();
				if (!defined($kidpid))  # Start in background the target to compile & let the cygwin make through LD_PRELOAD, injecting our filelog.dll hook tracker
				{
					# fork returned undef, so failed
					die "cannot fork: $!";
				} elsif ($kidpid == 0)
				{
					# Start the program to run
					my @CommandsToStart=("echo === Build start: ".$LocalStartTime." >$OUTLOGDIR/$Area/$BuildUnit.log");
					foreach my $CurrentCommand(@{$Command})
					{
						push(@CommandsToStart,$CurrentCommand." >> $OUTLOGDIR/$Area/$BuildUnit.log 2>&1");
					}
					$DependsPlatform->system_trace($Monitor,@CommandsToStart);
					exit(0);
				}
			    $DependsPlatformByPid{$kidpid}=$DependsPlatform;
			    $PIDs{$kidpid} = $BuildUnitFullName;
			    $TcpServersByPid{$kidpid} = $server;
			    $PidBySocket{$server}=$kidpid;
			    $read_set->add($server);
			    
				$DurationTime{$kidpid} = undef;
				$StartTime{$kidpid} = $LocalStartTime;
	
			    
				my $OutputFilePathName=$TEMPDIR."${\Depends::get_path_separator()}".$Build::OBJECT_MODEL."${\Depends::get_path_separator()}".$SHORT_MODE."${\Depends::get_path_separator()}depends${\Depends::get_path_separator()}deps${\Depends::get_path_separator()}".$MakefileName.$FIELD_SEPARATOR.$AreaName.(defined $AreaVersion?'@'.$AreaVersion:"").$FIELD_SEPARATOR.$BuildUnit;
				my $CurrentDataOutputPath=$ENV{OUTPUT_DIR}."/depends/".$Area;
			
				my $FinalDATOutputFilePathName=$CurrentDataOutputPath."/".$MakefileName.$FIELD_SEPARATOR.$AreaName.(defined $AreaVersion?'@'.$AreaVersion:"").$FIELD_SEPARATOR.$BuildUnit;
		
				$FILELOG_W_NET{$kidpid}=new IO::File ">".$FinalDATOutputFilePathName.".net-detection" or die("ERROR: cannot open '".$OutputFilePathName.".net-detection"."': $!"); # This is for tracking network file accesses
				$FILELOG_W_PTREE{$kidpid}=new IO::File ">".$FinalDATOutputFilePathName.".ptree" or die("ERROR: cannot open '".$OutputFilePathName.".ptree"."': $!") if($Extended==1); # This is for tracking & reconstruct process tree
				$FILELOG_W_FMAP{$kidpid}=new IO::File ">".$OutputFilePathName.".fmap" or die("ERROR: cannot open '".$OutputFilePathName.".fmap"."': $!") if($Extended==1); # This is for tracking & reconstruct file to process mapping
				foreach my $CurrentLogFile(keys(%DAT_FILE_LIST))
				{
					$LogFileHandles{$kidpid}{$CurrentLogFile}=new IO::File ">".$OutputFilePathName.".".$DAT_FILE_LIST{$CurrentLogFile}[0].".da0" or die("ERROR: cannot open '".$OutputFilePathName.".".$DAT_FILE_LIST{$CurrentLogFile}[0].".da0"."': $!");
				}
				
				$NumberOfProcess++;
		        $NewFork = 1;
			    last if($NumberOfProcess>=$MAX_NUMBER_OF_PROCESSES);
			}
		}
	} until $killedpid == -1 && $NewFork == 0;
	print "".($SequenceNumber-$StartedSequenceNumber)." file access(es) catched.\n";
	print "".($nLoadedProcess-$StartednLoadedProcess)." process loading catched.\n";
	print "".($TaskScopeNumber)." process scopes created.\n";
	
	if($Predictive && $Predictive!=0 && defined $Monitor && $Monitor==1)
	{
		print "Predictive mode, post filtering, filtering catched files at ".scalar(localtime())."\n";
		my $DependsPlatform=new Depends($DEPENDS_PORT, $ROOT_DIR, $SRC_DIR, $BOOTSTRAPDIR);
		foreach my $BuildUnitFullName (@BuildUnitInCompileOrder)
		{
			my($Dummy,$BuildUnit) = $BuildUnitFullName =~ /^(.+)[\:](.+)$/;
			$BuildUnit=$BuildUnitFullName unless(defined $BuildUnit);

	    	next if(!exists $Targets->{$BuildUnitFullName} 
		    	|| $BuildUnitFullName =~ /^[\.#].*/ 
		    	|| exists($ExcludeDeps{$BuildUnitFullName}) 
		    	|| Build::IsTargetOrdered($Targets,$BuildUnitFullName)==0);
				
			my($Command, $Area) = @{$Targets->{$BuildUnitFullName}}[0,4];
			my($AreaName,$AreaVersion) = $Area =~ /^(.+)[\\\/](.+)$/;
			$AreaName=$Area if(!defined $AreaName);

			FilterBuildUnitDATFiles($DependsPlatform, $MakefileName, $SRC_DIR, $OUTPUT_DIR, $ENV{OUTBIN_DIR}, $ROOT_DIR, $TEMPDIR, $Area, $BuildUnit,\@regexOnFileToIgnore) or die("ERROR: cannot filter da0 file for build unit '".$MakefileName.":".$AreaName.(defined $AreaVersion?'@'.$AreaVersion:"").":".$BuildUnit."': $!");
		} # end filtering loop
	}
	{ # now starting global dependencies files generation (by units)
		
		# read dat files area by area #
		print "Global unit dependencies generation step at ".scalar(localtime())."\n";
		my $list=GetFileListInDirectory($ENV{OUTPUT_DIR}."/depends", "", undef ,qr/\.[crw]\.dat$/);
		# write dat files by type #
		mkpath("$ENV{OUTBIN_DIR}/depends") or die("ERROR: cannot mkpath '$ENV{OUTBIN_DIR}/depends': $!") unless(-e "$ENV{OUTBIN_DIR}/depends");

		
		foreach my $Type (qw(read write create))
		{
			if(open(my $datFile, ">$ENV{OUTBIN_DIR}/depends/$MakefileName.$Type.dat"))
			{ 		
				$datFile->print("(");
			        foreach my $file(@$list)
				{
					my $prefix=substr($Type, 0, 1);
					next unless( $file =~ /\.$prefix\.dat$/ );

					my %g_write;
					my %g_read;
					my %g_create;

					my $rhData;
					eval "\$rhData=\\\%g_$Type\;";

					local $/ = undef;
					if(open(my $inputFile, $file))
			      		{
						eval <$inputFile>;
						close($inputFile);

						my @ret=map
						(
							{
								my($AreaUnit)=/\:(.+?\:.+?)$/;
								"\@\{\$g_$Type\{'$AreaUnit'\}\}\n\{\n".
									join
									(
										",\n", 
										map
										(
											{
												"\t'$_'"
											} 
											grep({$_} keys(%{$rhData->{$_}}))
										)
									)
									."\n}"
							} 
							keys(%$rhData)
						);
						$datFile->print(join(",\n", @ret)); $datFile->print(",\n");
					}
					else
					{
						warn("ERROR: cannot open '$file': $!");
					}
				}
				$datFile->print(")=();");
				$datFile->close();
			}
			else
			{
				warn("ERROR: cannot open '$ENV{OUTBIN_DIR}/depends/$MakefileName.$Type.dat': $!");
			}
		}
	}
}

if($DependenciesDATFiles==1)# now starting global dependencies files generation (by processes)
{ 		
	# Use IDs dictionary instead of full names to optimize memory usage & redundant texts
	my %hFileIDTable;
	my $hFileIDTableDb=tie %hFileIDTable,  "DB_File", "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filename.db", O_RDWR|O_CREAT, 0644, $DB_HASH;

	my %hProcessIDTable;
	my $hProcessIDTableDb=tie %hProcessIDTable,  "DB_File", "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processid.db", O_RDWR|O_CREAT, 0644, $DB_HASH;

	my %hBuildUnitIDTable;
	
	my $nCurrentFileID=0;
	my $nCurrentProcessID=0;
	my $nBuildUnitID=0;
	# End of variable used to manage dictionary
	
	# read dat files area by area ptree and fmap #
	print "Global process dependencies generation step at ".scalar(localtime())."\n";

	# write dat files by type #
	mkpath("$ENV{OUTBIN_DIR}/depends") or die("ERROR: cannot mkpath '$ENV{OUTBIN_DIR}/depends': $!") unless(-e "$ENV{OUTBIN_DIR}/depends");

	open(my $PROCESSDATREAD, ">$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.read.dat") or warn("ERROR: cannot open '$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.read.dat': $!");
	open(my $PROCESSDATWRITE, ">$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.write.dat") or warn("ERROR: cannot open '$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.write.dat': $!");

	my %hTmpFileIDTable;
	my $hTmpFileIDTableDb=tie %hTmpFileIDTable,  "DB_File", "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filename.tmp.db", O_RDWR|O_CREAT, 0644, $DB_HASH;

	{
		my %hFileKeyTable;
		my $hFileKeyTableDb=tie %hFileKeyTable,  "DB_File", "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filekeytable.db", O_RDWR|O_CREAT, 0644, $DB_HASH;


		my $list=GetFileListInDirectory($ENV{OUTPUT_DIR}."/depends", "", undef ,qr/\.ptree$/);
        foreach my $File(@$list)
		{		
			if(open(my $ptreeFileHandle, $File))
			{
			    # Enable duplicate records
			    $DB_BTREE->{'flags'} = R_DUP ;

				my %processTree;
				my $processTreeDb=tie %processTree,  "DB_File", "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processtree.db", O_RDWR|O_CREAT, 0644, $DB_BTREE;

				my %hProcessKeyTable;
				my $hProcessKeyTableDb=tie %hProcessKeyTable,  "DB_File", "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processkeytable.db", O_RDWR|O_CREAT, 0644, $DB_HASH;

				{
					my %hTmpProcessIDTable;										
					my $hTmpProcessIDTableDb=tie %hTmpProcessIDTable,  "DB_File", "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processkeytable.tmp.db", O_RDWR|O_CREAT, 0644, $DB_HASH;
					while (defined(my $Line = <$ptreeFileHandle>))  
					{
						# Removing unused data to optimize memory usage, only keep the fourth element of the hash table key array (so, only fileid access)
						my $szProcessID=undef;
						my $Match=q/push\(@{\${\$g_ptree{'(.*:?)'}}\[3\]},"(.*:?)"\);/;
						next unless(($szProcessID)=$Line =~ /^$Match$/);
	
						my %g_ptree;
						eval $Line;  
						
						my $hTmpProcessID=undef;
	
						unless($hTmpProcessIDTableDb->get($szProcessID,$hTmpProcessID)==0)
						{
							$hTmpProcessID = ++$nCurrentProcessID;
							$hTmpProcessIDTableDb->put($szProcessID,$hTmpProcessID);
							$hProcessKeyTableDb->put($hTmpProcessID,$szProcessID);
						}
						
						foreach my $value(@{$g_ptree{$szProcessID}[3]})
						{
							$processTreeDb->put($hTmpProcessID, $value);
						}
					}
					undef $hTmpProcessIDTableDb;
					untie %hTmpProcessIDTable;
				}
				unlink("$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processkeytable.tmp.db") if(-f "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processkeytable.tmp.db");
				$ptreeFileHandle->close();

				my $FullBuildUnitName="";
				{
					local $/ = undef;
					my %g_buildinfos;
					my %g_targets;

					(my $buildFile=$File) =~ s/\.ptree$/\.build/;
					if(open(my $buildFileHandle, $buildFile))
					{
						eval <$buildFileHandle>; 
						$buildFileHandle->close();
					}
					else
					{
						warn("ERROR: cannot open '$buildFile': $!");
					}
					$FullBuildUnitName=join("",keys(%g_targets));
				}
				
				my %fileMap;
				my $fileMapDb=tie %processTree,  "DB_File", "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filemap.db", O_RDWR|O_CREAT, 0644, $DB_HASH;
				
				{
					local $/ = undef;
					{
						(my $fmapFile=$File) =~ s/\.ptree$/\.fmap/;
						if(open(my $fmapFileHandle, $fmapFile))
						{
							# One line contains the data below
							# print($FH "\@{\$g_fmap{'$SequenceNumber'}}=('$File','$Mode','$ProcessID');\n");
							while (defined(my $Line = <$fmapFileHandle>))  
							{
								my %g_fmap;
								eval $Line;
								  
								foreach my $DestinationFileID(keys %g_fmap)
								{
									my($File, $Mode, $PrcssID) = @{$g_fmap{$DestinationFileID}};
									$File =~ s/([\@\$\\])/\\$1/g; $File =~ s/^\\\$/\$/; # Dont escape the first $ chars as it can be $SRC_DIR & dont have to be escaped

									{
										my $hTmpFileID=0;
										unless($hTmpFileIDTableDb->get($File,$hTmpFileID)==0)
										{
											$hTmpFileID = ++$nCurrentFileID;
											$hTmpFileIDTableDb->put($File,$hTmpFileID);
											$hFileKeyTableDb->put($hTmpFileID,$File);
										}
										$fileMapDb->put($DestinationFileID, $Mode.".".$hTmpFileID);
									}
								}	
								undef %g_fmap;
							}
							$fmapFileHandle->close();
						}
						else
						{
							 warn("ERROR: cannot open '$fmapFile': $!");
					    }
					}	
				}
			    {
				    my($status, $ProcessID, $PreviousProcessID, $value)=(0, undef, 0, 0);
					for (
						$status = $processTreeDb->seq($ProcessID, $value, R_FIRST) ;
						$status == 0 ;
						$status = $processTreeDb->seq($ProcessID, $value, R_NEXT) )
					{  
			      		next if(defined $PreviousProcessID && $PreviousProcessID eq $ProcessID); # Go to the next different key
			      		$PreviousProcessID=$ProcessID;
			      		
						SavePTreeEntryDb($hProcessKeyTableDb, $processTreeDb, $hFileKeyTableDb, $fileMapDb, $hProcessIDTableDb, \%hBuildUnitIDTable, \$nBuildUnitID, $hFileIDTableDb, $FullBuildUnitName, $ProcessID, $PROCESSDATREAD, $READ_MODE, $WRITE_MODE | $CREATE_MODE) or die("ERROR: cannot save data in  '$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.read.dat'!");
						SavePTreeEntryDb($hProcessKeyTableDb, $processTreeDb, $hFileKeyTableDb, $fileMapDb, $hProcessIDTableDb, \%hBuildUnitIDTable, \$nBuildUnitID, $hFileIDTableDb, $FullBuildUnitName, $ProcessID, $PROCESSDATWRITE, $WRITE_MODE | $CREATE_MODE, $READ_MODE) or die("ERROR: cannot save data in  '$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.write.dat'!");
	
						$status=$processTreeDb->find_dup($ProcessID,$value); # Set back the cursor to the previous position as it can be changed by get_dup() in SavePTreeEntryDb()
					}
				}
				undef $fileMapDb;
				untie %fileMap;
				unlink("$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filemap.db") if(-f "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filemap.db");

				undef $hProcessKeyTableDb;
				untie %hProcessKeyTable;
				unlink("$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processkeytable.db") if(-f "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processkeytable.db");
				
				undef $processTreeDb;
				untie %processTree;
				unlink("$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processtree.db") if(-f "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processtree.db");
			}
			else
			{
				warn("ERROR: cannot open '$File': $!");
			}
		}
		undef $hFileKeyTableDb;
		untie %hFileKeyTable;
		unlink("$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filekeytable.db") if(-f "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filekeytable.db");		
	}
	undef $hTmpFileIDTableDb;
	untie %hTmpFileIDTable;
	unlink("$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filename.tmp.db") if(-f "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filename.tmp.db");

	$PROCESSDATWRITE->close();				
	$PROCESSDATREAD->close();				
	# Flush now dictionaries
	if(open(my $hFile, ">$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processid.dat"))
	{
		my($status,$szProcessID,$value)=(0,0,0);
		for (
			$status = $hProcessIDTableDb->seq($szProcessID, $value, R_FIRST) ;
			$status == 0 ;
			$status = $hProcessIDTableDb->seq($szProcessID, $value, R_NEXT) )
		{  

			$hFile->print( "\$hData{".$value."}='".$szProcessID."';\n"); 
		}
		$hFile->close();

	} else { warn("ERROR: cannot open '$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processid.dat': $!"); }
	undef $hProcessIDTableDb;
	untie %hProcessIDTable;
	unlink("$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processid.db") if(-f "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.processid.db");
	
	if(open(my $hFile, ">$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filename.dat"))
	{
		my($status,$szFileID,$value)=(0,0,0);
		for (
			$status = $hFileIDTableDb->seq($szFileID, $value, R_FIRST) ;
			$status == 0 ;
			$status = $hFileIDTableDb->seq($szFileID, $value, R_NEXT) )
		{  

			$hFile->print("\$hData{\"${szFileID}\"}=".$value.";\n");
		}
		$hFile->close();
	} else { warn("ERROR: cannot open '$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filename.dat': $!");	}
	if(open(my $hFile, ">$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.fileid.dat"))
	{
		my($status,$szFileID,$value)=(0,0,0);
		for (
			$status = $hFileIDTableDb->seq($szFileID, $value, R_FIRST) ;
			$status == 0 ;
			$status = $hFileIDTableDb->seq($szFileID, $value, R_NEXT) )
		{  

			$hFile->print( "\$hData{".$value."}=\"".$szFileID."\";\n"); 
		}
		$hFile->close();
	} else { warn("ERROR: cannot open '$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.fileid.dat': $!"); }
	undef $hFileIDTableDb;
	untie %hFileIDTable;
	unlink("$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filename.db") if(-f "$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.filename.db");
	
	if(open(my $hFile, ">$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.buildunitid.dat"))
	{
		foreach my $szBuildUnitID(keys %hBuildUnitIDTable) { $hFile->print(  "\$hData{".$hBuildUnitIDTable{$szBuildUnitID}."}='".$szBuildUnitID."';\n"); }
		$hFile->close();
	} else { warn("ERROR: cannot open '$ENV{OUTBIN_DIR}/depends/$MakefileName.dependencies.buildunitid.dat': $!"); }
}
# All dependencies buildunit.r.dat & .w.dat files now created, we can now calculate dependencies
if($Update)
{
	my %hashBuildUnitResultIDs;
	print "Reading BuildUnit results(.rid) step at ".scalar(localtime())."\n";
	{
		my $list=GetFileListInDirectory($ENV{OUTPUT_DIR}."/depends", "", undef ,qr/depends\.rid$/);
	    foreach my $file(@$list)
		{
			if(open(DEPENDSNUMBERFILE, $file))
			{ 
				eval $_ while(<DEPENDSNUMBERFILE>); 
				close(DEPENDSNUMBERFILE); 
			}			
		}
	}

	print "Dependencies update step at ".scalar(localtime())."\n";
	my $p4;
	if(defined($Checkin)) ## Perforce Initialization only if submission of new dep files has been requested ##
	{
		$p4 = new Perforce;
		$p4->SetClient($Client);
		die("ERROR: cannot set client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount());
	}

	print "  Reading dependencies data files (".$ENV{OUTBIN_DIR}.") at ".scalar(localtime())."\n";
	my $AllDependencies;
	my $nCircularDependencies=0;
	my $nGeneratedTwice=0;
	my %g_buildinfos;
	my %g_targets;
	my $ReelAllAreas=$AllAreas?($AllAreas):([$MakefileName]);
	{ # I really like scoping code to define variable limit when not used outside of a scope
		my %g_write;
		my %g_read;
		my %g_create;
		
		foreach my $Area (@$ReelAllAreas) # Load all data 
		{
			{
				my $list=GetFileListInDirectory($ENV{OUTPUT_DIR}."/depends/$Area", "", 1, qr/\.dat$/);
			    foreach my $next(@$list)
				{
                	local $/ = undef;
                	open (my $datFileHandle, $next);
					eval <$datFileHandle>;
					close($datFileHandle);
					die("Errors in DAT file (".$next.") : ".$@."\n") if($@); # evaluate file content to transform it into real PERL variables
				}
			}
			if($AllAreas && !Build::IsWantedAreas($Areas,$Area))
			{
				my $list=GetFileListInDirectory($ENV{OUTPUT_DIR}."/depends/$Area", "", 1, qr/\.build$/);
			    foreach my $next(@$list)
				{
                	local $/ = undef;
					open (my $datFileHandle, $next);
					eval <$datFileHandle>;
					close($datFileHandle);
					die("Errors in BUILD file (".$next.") : ".$@."\n") if($@); # evaluate file content to transform it into real PERL variables
				}				
			}
		}
		
		print "  Analyzing dependencies at ".scalar(localtime())."\n";
		my $DatabaseLogHandle=undef;
		$DatabaseLogHandle=new IO::File ">".$OUTLOGDIR."/depends/$MakefileName.database.log" or die("ERROR: cannot open log file '".$OUTLOGDIR."/depends/database.log"."': $!");
		$AllDependencies=AnalyzeAllDependencies(\%g_read,\%g_write,\%g_create,\$nCircularDependencies,\$nGeneratedTwice,$DatabaseLogHandle); # analyze all dependencies in a flat model
		$DatabaseLogHandle->close if($DatabaseLogHandle);
		if(open( my $dbLog, $OUTLOGDIR."/depends/$MakefileName.database.log"))
		{
			my $dependencies_list="";
			my %Dependencies;
			while(<$dbLog>)
			{
				my @arrayDependency=split /\|/; pop(@arrayDependency);
				for(my $pos=0;$pos<=$#arrayDependency;$pos++)
					{ my @arrayResult=split(/\:/, $arrayDependency[$pos]); $arrayDependency[$pos]= pop(@arrayResult); } 
				$Dependencies{$hashBuildUnitResultIDs{$arrayDependency[0]}}{$hashBuildUnitResultIDs{$arrayDependency[1]}}=undef if(defined $hashBuildUnitResultIDs{$arrayDependency[0]} && defined $hashBuildUnitResultIDs{$arrayDependency[1]});
			}
			close ($dbLog); 
			$dependencies_list .= "".$_."=".join(" ",keys %{$Dependencies{$_}}).";" foreach(keys  %Dependencies);
			
			if($dependencies_list ne "")
			{
				my $reporterProxy   = new Torch($ENV{BUILD_DASHBOARD_WS});

				if(defined $reporterProxy)
				{
					$reporterProxy->logDependencies($dependencies_list);
					if ($reporterProxy->error()) { 
						warn("ERROR: ".$reporterProxy->error()) 
					}
				}
			}

		}
		undef %g_create; undef %g_read; undef %g_write; # We do not need any more these variables, remove them from memory, at this time, the memory usage is reduced ! cool !
		print "    Direct circular dependencies detected in the internal database : ".$nCircularDependencies."\n";
		print "    Multiple write accesses to identical filenames by some different build units : ".$nGeneratedTwice."\n";
	}
	if($AllDependencies)
	{
		print "  Converting flat to hierarchical dependencies at ".scalar(localtime())."\n";
		my $HierarchicalDependenciesRoot=[undef,undef]; # Allocate empty root entry (Saturn) which will contains all sublevels (dependencies for exemple=External, Common & sublevels=also External & Common
		my $Deep=0;
		foreach my $Target (keys %{$AllDependencies}) # Show each attached dependencies
		{
			unless($Deep)
			{
				my @TargetArray=split(/[\:]+/, $Target);
				$Deep=scalar @TargetArray;
			}
			# each target is dependent from itself !
			FlatToHierarchicalDependency($HierarchicalDependenciesRoot, $Target, $Target, undef, 0, $Deep, 1);
			# take all dependencies & send them in the hierarchical structure
			foreach my $TargetDependency (keys (%{$AllDependencies->{$Target}})) # Show each attached dependencies
			{
				foreach my $File (keys (%{$AllDependencies->{$Target}{$TargetDependency}})) # Show each attached dependencies
				{
					FlatToHierarchicalDependency($HierarchicalDependenciesRoot, $Target,$TargetDependency, $File, 0, $Deep, 1);
					delete $AllDependencies->{$Target}{$TargetDependency}{$File}; # remove already flushed items to optimize memory
				}
				delete $AllDependencies->{$Target}{$TargetDependency}; # remove already flushed items to optimize memory
			}
			delete $AllDependencies->{$Target}; # remove already flushed items to otpimize memory
		}
		undef($AllDependencies); $AllDependencies=undef;
		
		if($Deep)
		{
			my $iChangelist=0;
			if($p4) # if submit in perforce requested, create a specific changelist for this run
			{
				print "  Cleaning/Deleting previous Depends changelist at ".scalar(localtime())."\n";
				die("", @{$p4->Errors()}) if(!Build::DeleteChanges($p4, $Client, "pending", qr/^Summary[\*]?\s*:\s*Dependencies Analyzer Tool - DEP Files modified by Depends.pl\s\|\s.*/i));

				print "  Creating a Perforce changelist for saving modifications at ".scalar(localtime())."\n";
				my $rhChange = $p4->FetchChange();
				die("ERROR: Cannot create Changelist in Perforce : ",@{$p4->Errors()}) if($p4->ErrorCount());
				${$rhChange}{Description}=["Summary*:Dependencies Analyzer Tool - DEP Files modified by Depends.pl | $BuildName on $Build::PLATFORM platform", "What and how:", "Reviewed by*:xding"];
				my $Result=$p4->SaveChange($rhChange);
				die("ERROR: Cannot save new Changelist in Perforce : ",@{$p4->Errors()}) if($p4->ErrorCount());
				$iChangelist=int($1) if($Result && ($Result=join("",@{$Result})) && $Result=~/^\s*[^\s]*\s*(\d*)\s*.*$/);
				print "    Modification details will be saved in Changelist #".$iChangelist."\n";
			}
	
			print "  Building list of excluded areas at ".scalar(localtime())."\n";
			my %ExcludedTargets=%g_targets; # First imported must be excluded from .dep generation as it was not really built 
		
			foreach my $Area (@$ReelAllAreas) # Load all data 
			{
				if(!$AllAreas || Build::IsWantedAreas($Areas,$Area))
				{
					my $list=GetFileListInDirectory($ENV{OUTPUT_DIR}."/depends/$Area", "", 1, qr/\.build$/);
				    foreach my $next(@$list)
					{
					    local $/ = undef;
						open (DATFILE, $next);
						eval <DATFILE>;
						close(DATFILE);
						die("Errors in BUILD file (".$next.") : ".$@."\n") if($@); # evaluate file content to transform it into real PERL variables
					}
				}
			}
		
			# Before converting hierarchies to files, create an entry for each buildunit otherwise,as each buildunit depends on itself
			# This is for retrieving correct hierarchies informations/error calculation not to obtain this message (WARNING : Maybe removed or not executed, values retrieved from previous DEP file)
			foreach my $Target(keys %g_buildinfos)
			{
				FlatToHierarchicalDependency($HierarchicalDependenciesRoot, $Target, $Target, undef, 0, $Deep, 1);
			}

			if(!defined $Wash || $Wash!=1)
			{
				print "  Dumping Clean hierarchical dependencies in log directory at ".scalar(localtime())."\n" ;
				# Deep 3 only contains final targets, do not need them, need only direct parent of the most deep target to generate makefiles
				my $nTotalChanges=HierarchicalDependenciesToDependencyFile(undef, $iChangelist, $StartSubmittingFromNodeLevel, $OUTLOGDIR."/depends/depends.log.clean", $MakefilePath, !$AllAreas, $SRC_DIR, $OUTLOGDIR, 1, $Force, $TimeRange, \%g_buildinfos, $Deep-1,$MakefileName,$HierarchicalDependenciesRoot, \%ExcludedTargets, 0, $Versioned, undef, undef, $Troubleshooting);
				print "    Testing new DEP files for direct and indirect circular dependencies at ".scalar(localtime())."\n";
				my %AreasCircularDependencies;
				my %BuildUnitsCircularDependencies;
				Build::GetPhysicalCircularDependenciesFromFiles($MakefileName, $MakefilePath, $MakefileName, $Makefile, $SRC_DIR, $OUTLOGDIR, \@RequestedAreas, \%AreasCircularDependencies, \%BuildUnitsCircularDependencies,undef,$Troubleshooting) or die("ERROR: Cannot retrieve dependencies : $!");
				if(keys(%AreasCircularDependencies) || keys(%BuildUnitsCircularDependencies))
				{
					my $hXMLFile=new IO::File ">".$OUTLOGDIR."/depends/$MakefileName.circular.clean.xml"  or die("ERROR: cannot open '".$OUTLOGDIR."/depends/$MakefileName.circular.clean.xml"."': $!");
					$hXMLFile->print('<?xml version="1.0" encoding="UTF-8"?>'."\n");
					$hXMLFile->print("<CircularDependencies>\n");
				        print "      Areas circular dependencies:\n";
					foreach my $CircularDependencyPath(keys(%AreasCircularDependencies))
					{
						PrintCircularDependencies($hXMLFile, $ENV{OUTBIN_DIR}, $HierarchicalDependenciesRoot, $CircularDependencyPath, 1);
					}
				        print "      Buildunits circular dependencies:\n";
					foreach my $CircularDependencyPath(keys(%BuildUnitsCircularDependencies))
					{
						PrintCircularDependencies($hXMLFile, $ENV{OUTBIN_DIR}, $HierarchicalDependenciesRoot, $CircularDependencyPath, 1);
					}
					$hXMLFile->print("</CircularDependencies>\n");
					$hXMLFile->close();
					undef($hXMLFile);
				}
				print "      Total changes in DEP files : ".$nTotalChanges."\n";
				print "      Direct and indirect circular dependencies in DEP files : ".(keys(%AreasCircularDependencies)+keys(%BuildUnitsCircularDependencies))."\n";
			}

			{
				print "  Dumping Hierarchical dependencies into DEP files at ".scalar(localtime())."\n";
				# Deep 3 only contains final targets, do not need them, need only direct parent of the most deep target to generate makefiles
				my $nTotalChanges=HierarchicalDependenciesToDependencyFile($p4, $iChangelist, $StartSubmittingFromNodeLevel, $OUTLOGDIR."/depends/depends.log", $MakefilePath, !$AllAreas, $SRC_DIR, undef, $Wash, $Force, $TimeRange, \%g_buildinfos, $Deep-1,$MakefileName,$HierarchicalDependenciesRoot, \%ExcludedTargets, 0, $Versioned, $Suffix, $ForcedCheckin, $Troubleshooting);
		
				print "    Testing new DEP files for direct and indirect circular dependencies at ".scalar(localtime())."\n";
				my %AreasCircularDependencies;
				my %BuildUnitsCircularDependencies;
				Build::GetPhysicalCircularDependenciesFromFiles($MakefileName, $MakefilePath, $MakefileName, $Makefile, $SRC_DIR, undef, \@RequestedAreas, \%AreasCircularDependencies, \%BuildUnitsCircularDependencies,$Suffix,$Troubleshooting) or die("ERROR: Cannot retrieve dependencies : $!");
	
				if(keys(%AreasCircularDependencies) || keys(%BuildUnitsCircularDependencies))
				{
					my $hXMLFile=new IO::File ">".$OUTLOGDIR."/depends/$MakefileName.circular.xml"  or die("ERROR: cannot open '".$OUTLOGDIR."/depends/$MakefileName.circular.xml"."': $!");
					$hXMLFile->print('<?xml version="1.0" encoding="UTF-8"?>'."\n");
					$hXMLFile->print("<CircularDependencies>\n");
				        print "      Areas circular dependencies:\n";
					foreach my $CircularDependencyPath(keys(%AreasCircularDependencies))
					{
						PrintCircularDependencies($hXMLFile, $ENV{OUTBIN_DIR}, $HierarchicalDependenciesRoot, $CircularDependencyPath, undef);
					}
				        print "      Buildunits circular dependencies:\n";
					foreach my $CircularDependencyPath(keys(%BuildUnitsCircularDependencies))
					{
						PrintCircularDependencies($hXMLFile, $ENV{OUTBIN_DIR}, $HierarchicalDependenciesRoot, $CircularDependencyPath, undef);
					}
					$hXMLFile->print("</CircularDependencies>\n");
					$hXMLFile->close();
					undef($hXMLFile);
				}
		
				print "      Total changes in DEP files : ".$nTotalChanges."\n";
				print "      Direct and indirect circular dependencies in DEP files : ".(keys(%AreasCircularDependencies)+keys(%BuildUnitsCircularDependencies))."\n";
				print "    WARNING : new DEP files will not be submitted in Perforce because it contains no change or Buildunits circular dependencies!\n" if($p4 && (!$nTotalChanges || keys(%BuildUnitsCircularDependencies) )); # no change reverting changelist as no more needed
		
				if($p4)
				{
					if(!$nTotalChanges && !defined($ForcedCheckin))# no change reverting changelist as no more needed
					{
						print "  No modified file(s), discarding Changelist at ".scalar(localtime())."\n";
						$p4->Change("-d ".$iChangelist);
						die("ERROR: Cannot discard Changelist in Perforce : ",@{$p4->Errors()}) if($p4->ErrorCount());
					}
					elsif(keys(%BuildUnitsCircularDependencies))
					{
						print "  FATAL ERROR: Buildunits circular dependencies found, Changelist not submitted & pending !\n";
					}
					else
					{
						print "  Modified file(s) to save, submiting Changelist at ".scalar(localtime())."\n";
						$p4->Submit("-c ".$iChangelist);
						die("ERROR: Cannot submit Changelist in Perforce : ",@{$p4->Errors()}) if($p4->ErrorCount());
					}
				}			
			}
		}
		else
		{
			print "  WARNING : No dependency was found, dependencies files were not modified at all !\n";
		}	
		
	}
	else
	{
		print "  WARNING : No dependency was found, dependencies files were not modified at all !\n";
	}	
}
if($Log)
{
 	if(-e $OUTLOGDIR."/depends/depends.log")
	{
		print "  Printing dependency changes from '".$OUTLOGDIR."/depends/depends.log"."' :\n";
	 	my $DependsLog=new IO::File "<".$OUTLOGDIR."/depends/depends.log";
		if($DependsLog)
		{
			while(<$DependsLog>)
			{
				print "    ".$_;
			}
			$DependsLog->close;
		}
		else
		{
			print "    Error when opening depends.log : $!\n";
		}
	}
}


printf("execution took: %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

#############
# Functions #
#############
sub ParseErrors
{
	my($LogFile) = @_;

	if(open(LOG, $LogFile))
	{
		my $Errors = 0;
		while(<LOG>) { $Errors++ if(/^make.*: \[.+\] Error/) }
		close(LOG);
		return $Errors;
	}
	else { warn("ERROR: cannot open '$LogFile': $!") }

	return undef;
}

sub Monitor
{
	my($rsVariable) = @_;
	return tie ${$rsVariable}, 'main', ${$rsVariable}
}

sub TIESCALAR
{
	my($Pkg, $Variable) = @_;
	return bless(\$Variable);
}

sub FETCH
{
	my($rsVariable) = @_;

	my $Variable = ${$rsVariable};
	return "" unless(defined($Variable));
	while($Variable =~ /\${(.*?)}/g)
	{
		my $Name = $1;
		$Variable =~ s/\${$Name}/${$Name}/ if(${$Name} ne "");
	}
	return $Variable;
}

sub ReadIni
{
	open(INI, $Config) or die("ERROR: cannot open '$Config': $!");
	SECTION: while(<INI>)
	{
		next unless(my($Section) = /^\[(.+)\]/);
		while(<INI>)
		{
			redo SECTION if(/^\[(.+)\]/);
			next if(/^\s*$/ || /^\s*#/);
			s/\s*$//;
			chomp;
			if($Section eq "context")  { $Context = $_; Monitor(\$Context) }
			elsif($Section eq "client")   { $Client = $_; Monitor(\$Client) }
			elsif($Section eq "root")
			{
				my($Platform, $Root) = split('\s*\|\s*', $_);
				next unless($Platform=~/^all$/i || $Platform eq $Build::PLATFORM || ($Build::PLATFORM ne "win32_x86" && $Platform=~/^unix$/i));
				$Root =~ s/\${(.+?)}/${$1}/g;
				($SRC_DIR = $Root) =~ s/\\/\//g;
			}
		}
	}
	close(INI);
}

sub Usage
{
	print <<USAGE;
	Usage   : depends.pl [option]+
	Example : depends.pl -h
	depends.pl -g=Saturn.gmk -i=saturn_stable.ini

	[option]
	-help|?  argument displays helpful information about builtin commands.
	-a.readependenciesonly Used with -b, compile without taking care of build unit dependencies coming from another area, disable the GNU Make mode compilation order, set by default
	-b.uild      Build target & so, calculate execution time (-b[=*,buildunit1,-buildunit2])
	-c.heckin    Submit new updated dependency files (.DEP) from node level n (-c=[P4 Client name][,node level(default is zero)])
	-C.heckin    Force submisison of new updated dependency files (.DEP) from node level n (-c=[P4 Client name][,node level(default is zero)])
	-d.atabase   Print dependencies database content in database.log.
	-D.ependencies Generate .dependence.*.dat files used by fix packs & rolling builds. Enabled by default for backward compatibility, add noD not to generate them
	-e.xtended   Save extended information (.fmap & .ptree) to be able to analyse dependencies & drill to the process level instead of the build unit, not set by default
	-f.orce      Force dependencies update on build units which failed to compile or not (-nof.orce), default is -f
	-g.make      specifies the makefile name (-g=project.gmk[=*,area1,-area2]= or -g=area.gmk).
	-i.ni        specifies the configuration file (not mandatory, will force a build.pl call).
	-I.gnore     Ignore some files in the detection based on a regex (-I=file1 -I=file2 ...)
	-l.og        Create a log file associated to the .dep
	-m.ode       debug or release, default is release.
	-Monitor     Monitor the build for dependencies analyzis or not(-noM), default is -M
	-o.utput     Specifies the output directory relative to OUTPUT_DIR/logs.
	-p.redictive Generate DAT files also on failed file accesses for predicting dependencies (used with -b) or not (-nop.redictive), default is -p
	-P.lugins	 Load ANT, NANT, ... & other language specific plugins (works only with -extended also enabled)
	-r.eporting  Realtime reporting update of the dashboard (-r=path to dat dashboard file), not set by default
	-R.ecovery   Stop on error and restart at the last failed build unit, default is -noR
	-s.ource     Specifies the root source dir, default is \$ENV{SRC_DIR}.
	-S.uffix     Add a .dep suffix after the .dep file extension, no suffix after .dep by default
	-t.imerange  Specify a time range for updating .dep files when compilation durations changed more than x seconds (-t=x), default is 60
	-T.thread    specifies the maximum number of simultaneous threads, default is 1.
	-u.pdate     Update dependencies
	-v.ersioned	 When using versioned targets, the area name & its version number is stored in dependencies (Area?/?.?:Buildunit?)
	-w.ashed     Create cleaned dependencies files with unused targets removed.
	-64          Forces the 64 bits (-64) or not (-no64), default is -no64 i.e 32 bits.
USAGE
	exit;
}
