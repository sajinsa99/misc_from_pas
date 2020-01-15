#########################################################################################################################
# WARNING: Please read carefully ! 
# 	Targets structure format is :
# 		[Command line, Priority in text, Execution time, array of dependencies, Area, Parent path, Status, Order, Priority in internal value]
#########################################################################################################################
use POSIX;
use Switch;
use Tie::IxHash;
use Data::Dumper;
use File::Copy;
use Cwd;
use File::Basename;
use Perforce;

use Depends::Common;

package Build;

($WAITING, $INPROGRESS, $FINISHED) = (1..3);

$NULLDEVICE = "";
$PLATFORM = "";
$OS_TYPE="";
$PATH_SEPARATOR=":"; 
$OBJECT_MODEL="";

$ENV{OS_FAMILY}  = $^O eq "MSWin32" ? "windows" : "unix";
#########################################################################################################################
# Methods declaration
#########################################################################################################################
sub RecursiveExecuteTargets($$$$$$$$$$);

sub InitializeVariables($)
{
	my $Model=shift;
	
	$OS_TYPE = $ENV{OBJECT_MODEL} = $OBJECT_MODEL = $Model ? "64" : ($ENV{OBJECT_MODEL} || "32"); 
	if($^O eq "MSWin32")    { if($OS_TYPE eq "32") { $PLATFORM = "win32_x86"; } else { $PLATFORM = "win64_x64"; }; $PATH_SEPARATOR=";"; }
	elsif($^O eq "solaris") { $PLATFORM = "solaris_sparc" }
	elsif($^O eq "aix")     { $PLATFORM = "aix_rs6000" }
	elsif($^O eq "hpux")    { $PLATFORM = "hpux_pa-risc" }
	elsif($^O eq "linux")   { if($OS_TYPE eq "32") { $PLATFORM = "linux_x86"; } else { $PLATFORM = "linux_x64"; } }
	$NULLDEVICE = $^O eq "MSWin32" ? "nul" : "/dev/null";
}
#########################################################################################################################
# ret = sub GetMakeVariable(arg1,arg2,arg3)
#	returns the list of values contained in a gmk variable (like Units or Areas)
#########################################################################################################################
#		arg1[in] name of the value to read
#		arg2[in] Make file to read
#		arg3[in] boolean, if true, result is cached in a file if does not exists otherwise it reads this file. if false: nocache
#	ret reference on a array containing all values for arg1
#########################################################################################################################
sub GetMakeVariableContent($$$)
{
	my $VariableName=shift;
	my $handle=shift;
	my $handleCache=shift;
	
	my $Result;

	while(<$handle>)
	{
		print $handleCache $_  if(defined $handleCache);
		next unless(($_) = /^\s*$VariableName\s*:?=\s*(.+)$/);
		do
		{
			my($Units,$OnNextLine) = /^\s*([^#\\]*)\s*(.?).*$/;
			foreach my $Unit (split(/\s+/, $Units))
			{
				next if($Unit eq "");
				push(@{$Result},$Unit);
			}
			last if(!$OnNextLine || $OnNextLine ne "\\" );
		} while(<$handle>);
		last;
	}
	return $Result;
}

sub GetMakeVariable($$$)
{
	my $VariableName=shift;
	my $Make=shift;
	my $bCachedResult=shift;

	my $Result;

    my $CurrentDir = Cwd::getcwd();
    $Make=Cwd::abs_path($Make);
    my($DirName) = $Make =~ /^(.+)[\\\/]/;
    my $handleWriteCache=undef;
    my $fileToOpen="make -f $Make display_\L$VariableName INIT_PHASE=1 2>$NULLDEVICE |";
    
    if(defined $DirName)
    {
    	chdir($DirName) or warn("WARNING: cannot chdir '$DirName': $!");
    }
    
    if(defined $bCachedResult && $bCachedResult==1)
    {
    	if(-e "$Make.$VariableName.cache"){$fileToOpen="$Make.$VariableName.cache";}
    	else {open($handleWriteCache, ">$Make.$VariableName.cache") ; }
	}
	else
	{
		unlink("$Make.$VariableName.cache") if(-e "$Make.$VariableName.cache");
	}
		
	if(open(my $handle, $fileToOpen))
	{
		$Result=GetMakeVariableContent($VariableName,$handle,$handleWriteCache);
		$handle->close();
	}
	if(!defined $Result)
	{
		if(open(my $handle, $Make))
		{
			$Result=GetMakeVariableContent($VariableName,$handle,$handleWriteCache) ;
			$handle->close();
		}
	}
	$handleWriteCache->close() if(defined $handleWriteCache);
    chdir($CurrentDir) or die("ERROR: cannot chdir '$CurrentDir': $!");
	return $Result;
}

#########################################################################################################################
# ret = sub GetDependenciesList(arg1,arg2,arg3,arg4,arg5)
#	returns the content of the dep file stored in a hash table with the target name as key
#########################################################################################################################
#		arg1[in] Dependency filename
#		arg2[in] Prefix to add before the TargetName with the ":" char separator to allow target of the same name but contained in versionned parent
#		arg3[in/out] hash table containg alreay loaded target & their dependencies you want to complete (OPTIONAL can be undef)
#       arg4[in] test if target already exists in arg2, if =1 & does not already exist, don't add it. This is used when only wanting targets defined in gmk & if not defined in gmk as target, don't add the dependency entry as it does not have to be build
#		arg5[in] contains the parent path/owner of this targets & dependencies
#	ret hash table of array, containing targets, their dependencies, & other parameters contained in a .dep file
# 		${$Deps{TargetName}}[?] where [] is
#########################################################################################################################
sub GetDependenciesList($;$$$$)
{
	my $DepFilename=shift;
	my $Prefix=shift;
	my $Deps=shift;
	my $OnlyIfAlreadyExists=shift;
	my $ParentPath=shift;

	tie my %H, "Tie::IxHash";
	$Deps=\%H if(!$Deps);

	if(open(my $depFileHandle, $DepFilename))
	{
		while(<$depFileHandle>)
		{
			# Dependencies found, fill the Third element of the target array containing it
			my $Target=undef;
			if(/^\s*(.+)_deps\s*=\s*\$\(.+,\s*([^,]*?)\s*\)\s*(?:[#](.*))?/)
			{
				$Target=(defined $Prefix?($Prefix.":"):"").$1;
				
				if((!defined($OnlyIfAlreadyExists) || !$OnlyIfAlreadyExists) || exists $Deps->{$Target})
				{
					$Deps->{".KEYS_WITHOUT_PREFIX"}[0]{$1}{$Prefix}=undef if (defined $Prefix);
	
					my @Depends = split(/\s+/, $2);
					@{$Deps->{$Target}}[3] = @Depends ? \@Depends : undef ;
					if(defined $3) { $_=$3; @{%{$Deps->{$Target}[4]}}{/\s*([^\s]+)\s*/g}=undef; }
					else { %{$Deps->{$Target}[4]} = (); }
					$Deps->{$Target}[5]=$ParentPath if(defined $ParentPath);
				}
			}
			elsif(/^\s*(.+)_prio\s*=\s*(.+)\s*,\s*(\d+)/) # if priority field, fill elements 1 & 2 of the array containing priority & time
			{ 
				$Target=(defined $Prefix?($Prefix.":"):"").$1;
				
				if((!defined($OnlyIfAlreadyExists) || !$OnlyIfAlreadyExists) || exists $Deps->{$Target})
				{
					$Deps->{".KEYS_WITHOUT_PREFIX"}[0]{$1}{$Prefix}=undef if (defined $Prefix);
			
					@{$Deps->{$Target}}[1..2] = ($2, $3);

    				$Deps->{$Target}[8] = $Deps->{$Target}[1] =~/^DEFAULT$/i ? 0 : ($Deps->{$Target}[1]=~/^LOW$/i ? -4 : ($Deps->{$Target}[1]=~/^BELOWNORMAL$/i ? -3 : ($Deps->{$Target}[1]=~/^NORMAL$/i ? -2 : ($Deps->{$Target}[1]=~/^HIGH$/i ? -1: 0))));
					$Deps->{$Target}[5] = $ParentPath if(defined $ParentPath);
				}
			}  
			elsif(/^\s*\.PHONY\s*:\s*(.+)\s*/i) # if Phony, fill first level of array
			{
				my @Values = split(/\s+/, $1);
				if(exists $Deps->{".PHONY"} && exists $Deps->{".PHONY"}[3])
				{ @{$Deps->{".PHONY"}[3]}=(@{$Deps->{".PHONY"}[3]}, @Values) if(@Values); }
				else { @{$Deps->{".PHONY"}[3]}=@Values; }
			}
			if(defined $Target && exists $Deps->{$Target}) # Initializing state with default value...
			{
				$Deps->{$Target}[6]=$WAITING  unless(defined $Deps->{$Target}[6]);
				$Deps->{$Target}[2]=0 unless(defined $Deps->{$Target}[2]);
			}
		}
		close($depFileHandle);
		$Deps->{".KEYS_WITHOUT_PREFIX"}[6]=$Deps->{".PHONY"}[6]=$FINISHED;
		$Deps->{".KEYS_WITHOUT_PREFIX"}[7]=$Deps->{".KEYS_WITHOUT_PREFIX"}[8]=$Deps->{".PHONY"}[7]=$Deps->{".PHONY"}[8]=0;
	}
	return $Deps;
}

#########################################################################################################################
# ret = sub GetAreasList(arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9)
#	returns the list of areas requested in a makefile (by the AREAS:?= makefile variable
#########################################################################################################################
#		arg1[in] project name
#		arg2[in] makefile filename with its directory if needed
#		arg3[in] Dep directory
#		arg4[out] Area circular dependencies
#		arg5[out] hash table of array, containing targets, their dependencies, & other parameters contained in a .dep file
#		arg6[in] Load also all dependencies even if the target does not exist anymore in the gmk
#		arg7[in] Don't initialize arg5 with GMK
#		arg8[in] .dep files suffix extension (will be concated after .dep)
#		arg9[in] If true, first time .mak files are executed to retrieve list && results are cached for next read
#	ret array containing areas list
#########################################################################################################################
sub GetAreasList($$;$$$$$$$)
{
	my $ProjectName=shift;
	my $Makefile=shift;
	my $DepDirectory=shift;
	my $CircularDependencies=shift;
	my $ReturnedDeps=shift;
	my $bAlsoDependencies=shift;
	my $bDontLoadFromMakeFile=shift;
	my $Suffix=shift;
	my $bCachedResult=shift;

	# Get Areas value content
	$AreasList=GetMakeVariable("AREAS",$Makefile,$bCachedResult) or return undef;

	$Makefile=Cwd::abs_path($Makefile); # First, get the absolute path to the current make file
	my($MakefileName,$MakefilePath,$MakefileExtension)=File::Basename::fileparse($Makefile,'\..*'); # get directory, & basename of the makefile
	
	# now, we are going to read the target order in dep file, so replace .gmk extension by .dep
	my $OrgDepMake = $DepDirectory?$DepDirectory:$MakefilePath;
	$OrgDepMake =~ s/[\/\\]$//; my $DepMake;
	#$DepMake = $OrgDepMake."/".$MakefileName.".".$ENV{OS_FAMILY}.$OS_TYPE.".dep";
	#if(defined $Suffix && -e "$DepMake$Suffix")
	#{
	#	$DepMake .= $Suffix;
	#}
	#else
	#{
	#	unless(-e "$DepMake")
	#	{
			$DepMake = $OrgDepMake."/".$MakefileName.".".$ENV{OS_FAMILY}.".dep";
			if(defined $Suffix && -e "$DepMake$Suffix")
			{
				$DepMake .= $Suffix;
			}
			else
			{
				unless(-e "$DepMake")
				{			
					$DepMake = $OrgDepMake."/".$MakefileName.".dep";
					# Ensure backward compatibility (Main/Stable/Build must work for both PI and Stable):
					unless(-e "$DepMake") 
					{ 
						$DepMake =~ s/\.dep$/.$PLATFORM.dep/ ; 
						$DepMake .=$Suffix if(defined $Suffix && -e "$DepMake$Suffix"); 
					}
				}
			}
	#	}
	#}

	{
		tie my %H, "Tie::IxHash";
		my $Deps=\%H;
		# Just initialize an empty $Deps for next computations
		unless(defined $bDontLoadFromMakeFile && $bDontLoadFromMakeFile==1)
		{
			foreach my $Area(@$AreasList)
			{
				$Deps->{$Area} = [undef,undef,undef,undef];
			}
		}
		${$ReturnedDeps}=$Deps if(defined $ReturnedDeps);
		GetDependenciesList($DepMake, undef, $Deps,(!defined $bAlsoDependencies || $bAlsoDependencies==0)?1:undef,$ProjectName); # Get dependencies from dep file if exists
		$AreasList=ExecuteTargets(1, 1, undef, $Deps, 1, $CircularDependencies); # Simulate a run to get execution order & create the final ordered areas list
	}
	return $AreasList;
}
#########################################################################################################################
# ret = sub GetTargetsListForArea(arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9)
#	returns the list of build units requested in each areas makefiles (by the UNITS= makefile variable
#########################################################################################################################
#		arg1[in] Project name
#		arg2[in] Area to read
#		arg3[in] area directory
#		arg4[in] Dep directory
#		arg5[in/out] hash table containg alreay loaded target & their dependencies you want to complete (OPTIONAL can be undef)
#		arg6[in] Load also all dependencies even if the target does not exist anymore in the gmk
#		arg7[in] Don't initialize arg5 with GMK
#		arg8[in] .dep files suffix extension (will be concated after .dep)
#		arg9[in] If true, first time .mak files are executed to retrieve list && results are cached for next read
#	ret hash table of array, containing targets, their dependencies, & other parameters contained in a .dep file
# 		${$Deps{TargetName}}[?] where [] is
# 		[Command line, Priority, Execution time, array of dependencies, Area]
#########################################################################################################################
sub GetTargetsListForArea($$$;$$$$$$)
{
	my $ProjectName=shift;
	my $Area=shift;
	my $AreaDirectory=shift;
	my $DepDirectory=shift;
	my $Deps=shift;
	my $bAlsoDependencies=shift;
	my $bDontLoadFromMakeFile=shift;
	my $Suffix=shift;
	my $bCachedResult=shift;
	
	my $EffectiveDepDirectory=$DepDirectory?$DepDirectory:$AreaDirectory;

	tie my %H, "Tie::IxHash";
	$Deps=\%H if(!$Deps);

	my($AreaName,$AreaVersion) = $Area =~ /^(.+)[\\\/](.+)$/;
	$AreaName=$Area if(!defined $AreaName);

	if( -e "$AreaDirectory/$AreaName.gmk")
	{
		if((my $Units=GetMakeVariable("UNITS","$AreaDirectory/$AreaName.gmk",$bCachedResult)))
			{
				unless(defined $bDontLoadFromMakeFile && $bDontLoadFromMakeFile==1)
				{
					foreach my $Unit(@{$Units})
					{
						(my $PlatformDependantPath=$AreaDirectory) =~ s/[\/\\]/${\Depends::get_path_separator()}/g ; 
						$Deps->{$Area.":".$Unit} = [(["cd ".($^O eq "MSWin32"?"/D ":"").$PlatformDependantPath,"make -i -f $AreaName.gmk $Unit nodeps=1"]), "DEFAULT", 1, undef, $Area, undef, $WAITING, undef, 0];
						$Deps->{".KEYS_WITHOUT_PREFIX"}[0]{$Unit}{$Area}=undef;
					}
				}
				undef $Units;
				
				my $DepMake = "";
				# $DepMake = "$EffectiveDepDirectory/$AreaName.".$ENV{OS_FAMILY}.$OS_TYPE.".dep";
				#if(defined $Suffix && -e "$DepMake$Suffix")
				#{
				#	$DepMake .= $Suffix;
				#}
				#else
				#{
				#	unless(-e "$DepMake")
				#	{
						$DepMake = "$EffectiveDepDirectory/$AreaName.".$ENV{OS_FAMILY}.".dep";
						if(defined $Suffix && -e "$DepMake$Suffix")
						{
							$DepMake .= $Suffix;
						}
						else
						{
							unless(-e "$DepMake")
							{
								$DepMake =  "$EffectiveDepDirectory/$AreaName.dep";
								unless(-e "$EffectiveDepDirectory/$AreaName.dep")
								{
									$DepMake =  "$EffectiveDepDirectory/$AreaName.$PLATFORM.dep";
									if(defined $Suffix && -e "$DepMake$Suffix")
									{
										$DepMake .= $Suffix;
									}		
								}
							}
						}
				#	}
				#}
				GetDependenciesList($DepMake, $Area, $Deps, (!defined $bAlsoDependencies || $bAlsoDependencies==0)?1:undef, (defined $ProjectName?($ProjectName.":".$Area):undef));
			}
	} else {
		print "WARNING : makefile '$AreaDirectory/$AreaName.gmk' not found\n";
	}
	return $Deps;
}

#########################################################################################################################
# ret = sub GetTargetsList(arg1,arg2,arg3,arg4,arg5,arg6)
#	returns the list of build units requested in each areas makefiles (by the UNITS= makefile variable
#########################################################################################################################
#		arg1[in] project name
#		arg2[in] Array of areas names returned by GetAreasList()
#		arg3[in] Source directory where to find areas dirs containing area make files
#		arg4[in] Dep directory
#		arg5[in/out] hash table containg alreay loaded target & their dependencies you want to complete (OPTIONAL can be undef)
#		arg6[in] .dep files suffix extension (will be concated after .dep)
#		arg7[in] If true, first time .mak files are executed to retrieve list && results are cached for next read
#	ret hash table of array, containing targets, their dependencies, & other parameters contained in a .dep file
# 		${$Deps{TargetName}}[?] where [] is
# 		[Command line, Priority, Execution time, array of dependencies, Area]
#########################################################################################################################
sub GetTargetsList($$$;$$$$)
{
	my $ProjectName=shift;
	my $Areas=shift;
	my $SrcDirectory=shift;
	my $DepDirectory=shift;
	my $Deps=shift;
	my $Suffix=shift;
	my $bCachedResult=shift;

	foreach my $Area (@$Areas) # Build Unit List
	{
		$Deps=GetTargetsListForArea($ProjectName,$Area,$SrcDirectory."/".$Area,$DepDirectory?($DepDirectory."/".$Area):undef,$Deps,undef,undef,$Suffix, $bCachedResult);
	}
	return $Deps;
}

#########################################################################################################################
# ret = sub RemoveUnwanteds(arg1,arg2)
#	Remove unwanted from arg1 if not requested arg2 list
#########################################################################################################################
#		arg1[in] Official areas/buildunits list read from files
#		arg2[in] wanted areas/buildunits
#	ret is the official requested existing areas/buildunits
#########################################################################################################################
sub RemoveUnwanteds($$)
{
	my $Areas=shift;
	my $RequestedAreas=shift;

	my @Result;	
	my %SelectedList;

	if($RequestedAreas && @$RequestedAreas) # is there a requested choice from the user, if no, get all default system areas
	{
		# First loop is only to compute wanted areas
		foreach $AreaChoice(@$RequestedAreas)
		{
			$_=$AreaChoice;
			if(my($Mode,$Area)=/^\s*([\+\-\*]?)\s*([^\s]*)\s*/) # format is +<area> for adding, -<area> for removing <area>, * for all system areas
			{ 
				if($Mode eq "*" && $Area eq "") # if * all areas were requested by the user
				{
					@SelectedList{@$Areas}=undef;
					next;
				}
				elsif(defined $Area)
				{
	                $Area=~s/\./\\./g; $Area=~s/\*/.*/g; $Area=~s/\?/./g; # add joker management for example to select core.* targets

					foreach my $OfficialArea(@$Areas) # no joker, so it is a + or a - plus the area name to remove or to add
					{
						if($OfficialArea=~ /^$Area$/) # The requested area really exits in the system areas list
						{
							if(!defined $Mode || $Mode eq "" || $Mode eq "+") # add it in the selected area list
							{
								$SelectedList{$OfficialArea}=undef;
							}
							elsif($Mode eq "-" && exists $SelectedList{$OfficialArea}) # remove it from the selected area list
							{
								delete $SelectedList{$OfficialArea};
							}
						}
					}
				}
			}				
		}	
		# but we have now to re-order area sequencing regarding the one defined in $Areas !
		foreach my $OfficialArea(@$Areas)
		{
			push(@Result, $OfficialArea) if(exists $SelectedList{$OfficialArea}) ;
		}
	}
	else { @Result=@$Areas; }
	return(@Result?\@Result:undef);
}
#########################################################################################################################
# ret = sub IsWantedAreas(arg1,arg2)
#	return true if the areas is wanted
#########################################################################################################################
#		arg1[in] Requested areas list
#		arg2[in] Area to test
#	ret is the official requested existing areas
#########################################################################################################################
sub IsWantedAreas($$)
{
	my $RequestedAreas=shift;
	my $OfficialArea=shift;
	
	if($RequestedAreas && @$RequestedAreas)
	{
		foreach $Area(@$RequestedAreas)
		{
			return 1 if($OfficialArea eq $Area);
		}				
	}
	else { return 1; }
	
	return 0;
}

#########################################################################################################################
# ret = sub GetPhysicalCircularDependenciesFromFiles(arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,arg10)
#	returns Execute the list of targetsc contained in arg4 & returns the list of built targets
#########################################################################################################################
#		arg1[in] Project name
#		arg2[in] Makefile path
#		arg3[in] Makefile Name
#		arg4[in] Full Makefile path & name
#		arg5[in] Source directory
#		arg6[in] Dep directory
#		arg7[in] List of requested areas
#		arg8[out] Will contain detected circular dependencies for areas
#		arg9[out] Optional, Will contain detected circular dependencies for build units, if undef, arg8 will be filled for backward compatibility
#		arg10[in] .dep files suffix extension (will be concated after .dep)
#		arg11[in] If true, first time .mak files are executed to retrieve list && results are cached for next read
#	ret undef if error otherwise 1
#########################################################################################################################
sub GetPhysicalCircularDependenciesFromFiles($$$$$$$$;$$$)
{
	my $ProjectName=shift;
	my $MakefilePath=shift;
	my $MakefileName=shift;
	my $Makefile=shift;
	my $SrcDirectory=shift;
	my $DepDirectory=shift;
	my $RequestedAreas=shift;
	my $AreaCircularDependencies=shift;
	
	my $BuildUnitCircularDependencies=shift;
	my $Suffix=shift;
	my $bCachedResult=shift;

	## Read Makefile & DEP files to analyze indirect independencies ##
	{
		my $Targets; # will be used by the dependencies checker

		# Area List #
		my $AreasGmksToTest;
		my $AllAreasGmksToTest=Build::GetAreasList($ProjectName,$Makefile,$DepDirectory,$AreaCircularDependencies,undef,undef,undef,$Suffix,$bCachedResult);
		$AreasGmksToTest=Build::RemoveUnwanteds($AllAreasGmksToTest,$RequestedAreas) if($AllAreasGmksToTest); # Exclude unwanted areas
		# Build units list, if no area read from makefile, assuming that current makefile is an area
		if($AllAreasGmksToTest) { $Targets=Build::GetTargetsList($ProjectName,$AreasGmksToTest,$SrcDirectory, $DepDirectory,undef,$Suffix,$bCachedResult) if($AreasGmksToTest); }
		else { $Targets=Build::GetTargetsListForArea($ProjectName, $MakefileName, $MakefilePath,$DepDirectory,undef,undef,undef,$Suffix,$bCachedResult); }
		return undef if(!$Targets);
		
		# Calculate dependencies/targets building order
		ExecuteTargets(1, 1, undef, $Targets, 1, defined $BuildUnitCircularDependencies?$BuildUnitCircularDependencies:$AreaCircularDependencies);

	}
	return 1;
}

#########################################################################################################################
# ret = sub GetFullTargetName(arg1,arg2)
#	Runs recursively depedencies if multi process=1 so in sequential mode to simulate make otherwise all will be start in the same loop
#########################################################################################################################
#		arg1[in] Ref Hash of Targets returning an array for each target (pass the result returned by GetTargetsList())
#		arg2[in] Name to test & to reconstruct
#	ret The full name
#########################################################################################################################
sub GetFullTargetName($$)
{
	my $Deps=shift;
	my $Target=shift;

	return $Target if($Target =~ /^(.+)[\:](.+)$/);
	
	# for backward compatibility when the dependencies does not contain prefix, search for a default one (area:buildunit)
	foreach my $Prefix(keys %{$Deps->{".KEYS_WITHOUT_PREFIX"}[0]{$Target}})
	{
		if(exists $Deps->{$Prefix.":".$Target})
		{
			$Target=$Prefix.":".$Target;
			last;
		}
	}
	return $Target;
}

#########################################################################################################################
# ret = sub ConcatenateTargets(arg1,arg2)
#	Concataenate all targets from arg2 into arg1
#########################################################################################################################
#		arg1[in/out] destination
#		arg2[in] source
#	ret arg1 or arg2 if arg1 is null
#########################################################################################################################
sub ConcatenateTargets($$)
{
	my $Targets=shift;
	my $tmpTargets=shift;
	
	return $tmpTargets if(!defined $Targets);
	
	foreach my $entryToCopy(keys %{$tmpTargets})
	{
		if($entryToCopy eq ".KEYS_WITHOUT_PREFIX")
		{
			foreach my $buildUnit(keys %{$tmpTargets->{$entryToCopy}[0]})
			{
				foreach my $prefix(keys %{$tmpTargets->{$entryToCopy}[0]{$buildUnit}})
				{
					$Targets->{$entryToCopy}[0]{$buildUnit}{$prefix}=$tmpTargets->{$entryToCopy}[0]{$buildUnit}{$prefix};
				}
			}
			$Targets->{$entryToCopy}[6]=$FINISHED;
			$Targets->{$entryToCopy}[7]=$Targets->{$entryToCopy}[8]=0;
		}
		elsif($entryToCopy eq ".PHONY")
		{
			if(defined $tmpTargets->{$entryToCopy}[3])
			{
				if(defined $Targets->{$entryToCopy}[3])
				{
					@{$Targets->{$entryToCopy}[3]}=(@{$Targets->{$entryToCopy}[3]}, @{$tmpTargets->{$entryToCopy}[3]})  ;
				}
				else
				{
					@{$Targets->{$entryToCopy}[3]}=@{$tmpTargets->{$entryToCopy}[3]};
				}
			}
			$Targets->{$entryToCopy}[6]=$FINISHED;
			$Targets->{$entryToCopy}[7]=$Targets->{$entryToCopy}[8]=0;
		}
		else
		{
			$Targets->{$entryToCopy}=$tmpTargets->{$entryToCopy};
		}
	}
	return $Targets;
}
#########################################################################################################################
# ret = sub ComputeCriticalPath(arg1,arg2)
#	Compute & return an hash of all computed critical path
#########################################################################################################################
#		arg1[in] Critical paths of already computed critical paths
#		arg2[in] Build unit for which critical path must be computed
#		arg3[in] number of recursive loops
#		arg4[in] level
#		arg5[in] Targets hash list
#		arg6[in] Excluded targets
#	ret return an hash of all computed critical path
#########################################################################################################################
# Critical Path #
sub _CriticalPath($$$$$$);
sub _CriticalPath($$$$$$)
{
    my($CriticalPaths, $Unit, $rhLoops, $Level, $Targets, $ExcludeDeps) = @_;    

    return $CriticalPaths->{$Unit} if(exists($CriticalPaths->{$Unit}));
    
    my($Weight, $raDepends, $Status) = @{$Targets->{$Unit}}[2,3,6];
    my @CriticalPath; 
    $CriticalPath[0]  = (defined $ExcludeDeps && exists($ExcludeDeps->{$Unit})) || $Status==$FINISHED ? 0 : $Weight;
    $CriticalPath[1]  = $Unit;
    return \@CriticalPath if(!$raDepends || !@{$raDepends} || (defined $ExcludeDeps && exists($ExcludeDeps->{$Unit})) || $Status==$FINISHED);

    my @ParentCriticalPath = (0);
    foreach my $Depend (@{$raDepends})
    {
        $Depend=Build::GetFullTargetName($Targets, $Depend);
        next unless exists $Targets->{$Depend};
        next if((defined $ExcludeDeps && exists($ExcludeDeps->{$Depend})) || $Targets->{$Depend}[6]==$FINISHED);
        if(exists(${$rhLoops}{$Depend})) { print("ERROR: a dependency loop exists in $Targets->{$Depend}[4]:$Depend\n"); next }
        my %DependLoops = %{$rhLoops};
        $DependLoops{$Depend}=undef;
        $CriticalPaths->{$Depend} = _CriticalPath($CriticalPaths, $Depend, \%DependLoops, $Level+1, $Targets, $ExcludeDeps);
        @ParentCriticalPath = @{$CriticalPaths->{$Depend}} if(${$CriticalPaths->{$Depend}}[0] > $ParentCriticalPath[0]);    
    }
    $CriticalPath[0] += $ParentCriticalPath[0];
    push(@CriticalPath, splice(@ParentCriticalPath, 1));
    return \@CriticalPath;
}

sub ComputeCriticalPath($$)
{
	my $Targets=shift;
	my $ExcludeDeps=shift;
	
	my %CriticalPaths;
	foreach my $Unit (keys(%{$Targets}))
	{
	    next if($Unit =~ /^[\.#].*/);
	    next if((defined $ExcludeDeps && exists($ExcludeDeps->{$Unit})) || $Targets->{$Unit}[6]==$FINISHED || $Targets->{$Unit}[8]);
	    my %Loops;
	    $CriticalPaths{$Unit} = _CriticalPath(\%CriticalPaths, $Unit, \%Loops, 0, $Targets, $ExcludeDeps);
	}
	return \%CriticalPaths;
}
#########################################################################################################################
# ret = sub ComputeTargetsOrderField(arg1,arg2)
#	Compute the order field of the target hash list
#########################################################################################################################
#		arg1[in] Targets hash list
#		arg2[in] array containing targets in the correct order
#	ret no return 
#########################################################################################################################
sub ComputeTargetsOrderField($$)
{
	my $Targets=shift;
	my $raTargetsToBuild=shift;
	
	my $Order=0;
	foreach my $BuildUnitFullName (@{$raTargetsToBuild})
	{
		next if(!exists $Targets->{$BuildUnitFullName});
		$Targets->{$BuildUnitFullName}[7]=++$Order;
	}	
}
#########################################################################################################################
# ret = sub ComputeCompileOrder(arg1)
#	returns an array containing the targets in the correct compilation order
#########################################################################################################################
#		arg1[in] Targets hash list
#	ret an array containing the targets in the correct compilation order
#########################################################################################################################
sub ComputeCompileOrder($$)
{
	my $Targets=shift;
	my $MAX_NUMBER_OF_PROCESSES=shift;

	return 
		$MAX_NUMBER_OF_PROCESSES==1
			? sort({ $Targets->{$a}[7]<=>$Targets->{$b}[7] } (keys(%{$Targets})))
			: sort({ $Targets->{$b}[8]<=>$Targets->{$a}[8] || $Targets->{$a}[7]<=>$Targets->{$b}[7] } (keys(%{$Targets})));
}

#########################################################################################################################
# ret = sub IsTargetOrdered(arg1,arg2)
#	returns 1 if arg2 execution as been ordered in arg1, if not the target must not be executed
#########################################################################################################################
#		arg1[in] Targets hash list
#		arg2[in] Targets hash list
#	ret true if the target has been ordered otherwise 0
#########################################################################################################################
sub IsTargetOrdered($$)
{
	my $Targets=shift;
	my $BuildUnitFullName=shift;
	
    return 1 if(defined $Targets && defined $BuildUnitFullName && defined $Targets->{$BuildUnitFullName} && defined $Targets->{$BuildUnitFullName}[7] && $Targets->{$BuildUnitFullName}[7]>0);
    return 0;
}

#########################################################################################################################
# ret = sub SetCriticalPathPriority(arg1,arg2,arg3[,arg4])
#	Compute & return an hash of all computed critical path
#########################################################################################################################
#		arg1[in] Targets hash list
#		arg2[in] Excluded targets
#		arg3[in] Number of parallel processes 
#		arg4[in] Display infos
#	ret return an hash of all computed critical path
#########################################################################################################################
sub _HHMMSS
{
    my($Difference) = @_;
    my $s = $Difference % 60;
    $Difference = ($Difference - $s)/60;
    my $m = $Difference % 60;
    my $h = ($Difference - $m)/60;
    return sprintf("%02u h %02u mn %02u s", $h, $m, $s);
}

sub SetCriticalPathPriority($$$;$)
{
	my $CriticalPaths=shift;
	my $Targets=shift;
	my $MAX_NUMBER_OF_PROCESSES=shift;
	my $bLog=shift;
	
	my @CriticalPaths = sort({ ${$b}[0] <=> ${$a}[0] } values(%{$CriticalPaths}));
	for(my $i=0; $i<$MAX_NUMBER_OF_PROCESSES && $i<@CriticalPaths; $i++)
	{
	    print("### Critical Path $i ###\n") if(defined $bLog && $bLog==1);
	    my $raCriticalPath = $CriticalPaths[$i];
	    for(my $j=1; $j<@{$raCriticalPath}; $j++)
	    { 
	        my $Unit = ${$raCriticalPath}[$j];
	        $Targets->{$Unit}[8] = 2 if($Targets->{$Unit}[8] >= 0); # priority
	        print("\t$Unit: ", _HHMMSS($Targets->{$Unit}[2]), "\n") if(defined $bLog && $bLog==1);
	    }
	    print("Total: ", _HHMMSS(${$raCriticalPath}[0]), "\n") if(defined $bLog && $bLog==1);
	}
}

#########################################################################################################################
# ret = sub RecursiveExecuteTargets(arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,arg10)
#	Runs recursively depedencies if multi process=1 so in sequential mode to simulate make otherwise all will be start in the same loop
#########################################################################################################################
#		arg1[in] Ref on an array of targets to run
#		arg2[in/out] Ref Hash of Targets returning an array for each target (pass the result returned by GetTargetsList())
#		arg3[in/out] Ref Hash table for targets assigned to their PID
#		arg4[in] Maximum number of process (multi processor) to create
#		arg5[in/out] Current number of processes running
#		arg6[out] Ref on an array containining compilation order of each targets
#		arg7[in] Dry run, if 1 does not run the build, only analyze dependencies & simulate, used by depends.pl
#		arg8[in] Recursivity deep
#		arg9[out]map containing circular dependenices list as keys (& undef as value)
#		arg10[out] String containing the actual deep recursivity path
#	ret No return value
#########################################################################################################################
sub RecursiveExecuteTargets($$$$$$$$$$)
{
	my $Targets=shift;
	my $Deps=shift;
	my $PIDs=shift;
	my $MaxNumberOfProcess=shift;
	my $NumberOfProcess=shift;
	my $ExecutedTargets=shift;
	my $DryRun=shift;
	my $Recursivity=shift;
	my $CircularDependencies=shift;
	my $DependencyPath=shift;

	return if(!$Targets);
	
	my $NewFork = 0;
	my $pid = -1;

	WAITFORK: do
	{
		$pid = waitpid(-1, POSIX::WNOHANG);

		# -1=no more process, so reset the NumberOfProcess, 0=nothing to do, others=deleted process
		switch($pid)
		{
			case -1 { ${$NumberOfProcess}=0 }
			case 0  { }
			else
			{
				{
					foreach my $Target (keys(%$PIDs))
					{
						my($Status, $PID) = @{$PIDs->{$Target}};
						if($Status==$INPROGRESS && $PID==$pid)
						{
							${$NumberOfProcess}--;
							${$PIDs->{$Target}}[0] = $FINISHED;		# Status
							last;
						}
					}
				}
			}
		}

		$NewFork = 0;
		COMMAND: foreach my $Target (@{$Targets})
		{

			$Target=GetFullTargetName($Deps,$Target);
			last if(${$NumberOfProcess} >= $MaxNumberOfProcess);
			next if(!exists $PIDs->{$Target});
			my($Status, $PID, $Deep) = @{$PIDs->{$Target}};
			# if not in a waiting state, currently compiled (inprogress)
			next if($Status != $WAITING || !exists $Deps->{$Target});

			#or already compiled... Or an auto recursivity to break......
			if(defined($Deep) && $Deep!=0 && $Deep<$Recursivity)
			{
				$CircularDependencies->{($DependencyPath?($DependencyPath.";"):"").($Deps->{$Target}[5]?($Deps->{$Target}[5].":"):"").$Target}=undef if($CircularDependencies);
				next;
			}

			$Deep=${$PIDs->{$Target}}[2]=$Recursivity if(!defined($Deep) || !$Deep);
			my($Command, $Priority, $Weight, $raDepends) = @{$Deps->{$Target}};

			# First try to build dependencies
			if($raDepends)
			{
				if($MaxNumberOfProcess>1) # if multi process, load all in the same loop & don't take care of the make order
				{
					foreach my $Depend (@{$raDepends}) { next COMMAND if(${$PIDs{$Depend}}[0] != $FINISHED) }

				}
				else # if only one process simulate sequential make order
				{
					RecursiveExecuteTargets($raDepends, $Deps, $PIDs,$MaxNumberOfProcess,$NumberOfProcess, $ExecutedTargets, $DryRun, $Recursivity+1, $CircularDependencies, ($DependencyPath?($DependencyPath.";"):"").($Deps->{$Target}[5]?($Deps->{$Target}[5].":"):"").$Target);
				}
			}

			push(@{$ExecutedTargets},$Target);
			$PIDs->{$Target} = CreateFork($Command, $Priority, $Target,$NumberOfProcess,$DryRun, $Recursivity);
			$NewFork = 1;
		}

	} until $pid == -1 && $NewFork == 0;
}

#########################################################################################################################
# ret = sub ExecuteTargets(arg1,arg2,arg3,arg4,arg5,arg6)
#	returns Execute the list of targetsc contained in arg4 & returns the list of built targets
#########################################################################################################################
#		arg1[in] Maximum number of computers used to compile
#		arg2[in] Maximum number of process (multi processor) to create
#		arg3[in] Hash containing the list of targets attributed to each computers
#		arg4[in] Hash of Targets returning an array for each target (pass the result returned by GetTargetsList())
#		arg5[in] Dry run, if 1 does not run the build, only analyze dependencies & simulate, used by depends.pl
#		arg6[out]map containing circular dependenices list as keys (& undef as value)
#	ret arrary containing the list of targets built
#########################################################################################################################
sub ExecuteTargets($$$$$;$)
{
	my $NumberOfComputers=shift;
	my $MaxNumberOfProcess=shift;
	my $Machines=shift;
	my $Deps=shift;
	my $DryRun=shift;
	my $CircularDependencies=shift;

	my @ExecutedTargets;
	my $NumberOfProcess=0;

	tie my %PIDs, "Tie::IxHash";

	foreach my $Target (keys(%$Deps))
	{
		next if ($Target =~ /^[\.#].*/); # Do not try to compile targets starting with # or . chars
		if($NumberOfComputers>1 && !exists(${${$Machines->[$Rank]}[1]}{$Target})) { $PIDs{$Target}=[$FINISHED, undef, 0]; next }

		my($Command, $Priority, $Weight, $raDepends) = @{$Deps->{$Target}};

		if($raDepends || $NumberOfProcess>=$MaxNumberOfProcess || $MaxNumberOfProcess==1) { $PIDs{$Target} = [$WAITING, undef, 0] }
		else { push(@ExecutedTargets,$Target); $PIDs{$Target} = CreateFork($Command, $Priority, $Target,\$NumberOfProcess,$DryRun, 1) }
	}

	my @Targets=keys(%PIDs);
	RecursiveExecuteTargets(\@Targets, $Deps, \%PIDs,$MaxNumberOfProcess,\$NumberOfProcess, \@ExecutedTargets, $DryRun, 1, $CircularDependencies, undef);

	return \@ExecutedTargets;
}
sub CreateFork($$$$$;$)
{
	my($Command, $Priority, $Name, $NumberOfProcess, $DryRun, $Deep) = @_;

	if(!defined($pid=fork())) { die("ERROR: cannot fork '$Command': $!") }
	elsif($pid)
	{
		${$NumberOfProcess}++;
		return [$INPROGRESS, $pid, $Deep];
	}
	else
	{
		if(!$DryRun)
		{
			$CommandLine=join("&",@{$Command});
			exec("start \"$Name ($Priority)\" /MIN /WAIT cmd /c \"$CommandLine >$OUTLOGDIR/$Name.log 2>&1\"") ;
		}
		exit(0);
	}
}
#########################################################################################################################
# ret = sub DashboardGet(arg1,arg2)
#	returns an array containing each line of the dashboard, & arg2 receives the list of build units stored in the dashboard
#########################################################################################################################
#		arg1[in] Dashboard filename to open (with path)
#		arg2[out] Will contain all build units stored in the dashboard
#	ret arrary containing each line of the dashboard
#########################################################################################################################
sub DashboardGet($;$)
{
	my $Dashboard=shift;
	my $Units=shift;
	
	my $ErrorsRef=undef;
	if($Dashboard)
	{
	    my @Errors;
	    $Errors[0]=0;
	    if(open(my $dashboardHandle, $Dashboard))
	    {
	        local $/ = undef; 
	        eval <$dashboardHandle>;
	        close($dashboardHandle);
	        for(my $i=1; $i<@Errors; $i++)
	        {
	            my($NumberOfErrors, $LogFile, $SummaryFile, $Area, $Start, $Stop) = @{$Errors[$i]};
	            if($LogFile)
	            {
		            my($Unit) = $LogFile =~ /^.*?([^\\\/]+?)=/;
		            $Units->{$Unit} = undef if($Units);
		        }
	        }   
	    }
            $ErrorsRef=\@Errors;
	}
	return $ErrorsRef;
}
#########################################################################################################################
# ret = sub DashboardAddEntry(arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8)
#	Add an entry in the dashboard array
#########################################################################################################################
#		arg1[in] Dashboard path
#		arg2[in/out] receive the return value of DashboardGet(), this one contains all the actual content of the 
#			dashboard & the new build unit will be added
#		arg3[in] Will contain all build units stored in the dashboard & returned from the arg2 of DashboardGet()
#		arg4[in] will contain rank value
#		arg5[in] will contain platform type
#		arg6[in] will contain build mode
#		arg7[in] will contain area mode
#		arg8[in] will contain unit mode
#	ret no return
#########################################################################################################################
sub DashboardAddEntry($$$$$$$$)
{
	my $Dashboard=shift;
	my $Errors=shift;
	my $Units=shift;
	my $Rank=shift;
	my $Platform=shift;
	my $BuildMode=shift;
	my $Area=shift;
	my $Unit=shift;

	return if(!defined $Dashboard || !defined $Errors);
	my($Phase) = $Dashboard =~ /([^_]+?)_\d+.dat$/;
	
	push(@{$Errors}, [undef, "Host_".($Rank+1)."/$Unit=${Platform}_${BuildMode}_$Phase.log", "Host_".($Rank+1)."/$Unit=${Platform}_${BuildMode}_summary_$Phase.txt", $Area]) unless(exists($Units->{$Unit}));
}
#########################################################################################################################
# ret = sub DashboardUpdateEntry(arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,arg10,arg11)
#	Update an entry in the dashboard array
#########################################################################################################################
#		arg1[in] Dashboard path
#		arg2[in/out] receive the return value of DashboardGet(), this one contains all the actual content of the 
#			dashboard & the new build unit will be added
#		arg3[in] log output directory
#		arg4[in] will contain rank value
#		arg5[in] will contain platform type
#		arg6[in] will contain build mode
#		arg7[in] will contain area mode
#		arg8[in] will contain unit mode
#		arg9[in] number of errors of the current build unit
#		arg10[in] start date time
#		arg11[in] end date time
#	ret no return
#########################################################################################################################
sub DashboardUpdateEntry($$$$$$$$$$$)
{
	my $Dashboard=shift;
	my $Errors=shift;
	my $OutLogDir=shift;
	my $Rank=shift;
	my $Platform=shift;
	my $BuildMode=shift;
	my $Area=shift;
	my $Unit=shift;
	my $NumberOfErrors=shift;
	my $Start=shift;
	my $Stop=shift;

	return if(!defined $Dashboard || !defined $Errors);
	my($Phase) = $Dashboard =~ /([^_]+?)_\d+.dat$/;
	my($HTTPDIR) = $Dashboard =~ /^(.+)[\\\/].+$/;

	
	$Errors->[0]=0;
	for(my $i=1; $i<@{$Errors}; $i++)
	{
		my($OldErrors, $LogFile) = @{$Errors->[$i]}[0,1];
		my($BuildUnit) = $LogFile =~ /^.*?([^\\\/]+?)=/ if($LogFile);
		if($BuildUnit && $Unit eq $BuildUnit)
		{
			$Errors->[$i] = [$NumberOfErrors, "Host_".($Rank+1)."/$Unit=${Platform}_${BuildMode}_$Phase.log", "Host_".($Rank+1)."/$Unit=${Platform}_${BuildMode}_summary_$Phase.txt", $Area, $Start, $Stop];            
			File::Copy::copy("$OutLogDir/$Area/$Unit.log", "$HTTPDIR/Host_".($Rank+1)."/$Unit=${Platform}_${BuildMode}_$Phase.log") or warn("ERROR: cannot copy '$OutLogDir/$Area/$Unit.log': $!");
			File::Copy::copy("$OutLogDir/$Area/$Unit.summary.txt", "$HTTPDIR/Host_".($Rank+1)."/$Unit=${Platform}_${BuildMode}_summary_$Phase.txt") or warn("ERROR: cannot copy '$OutLogDir/$Area/$Unit.summary.txt': $!");
			$Errors->[0] += $NumberOfErrors;
		} else { $Errors->[0] += $OldErrors if($OldErrors) } 
	}   	
}
#########################################################################################################################
# ret = sub DashboardUpdate(arg1,arg2)
#	Update the dashboard file with its new content given in parameter
#########################################################################################################################
#		arg1[in] Dashboard path
#		arg2[in/out] receive the return value of DashboardGet(), this one contains all the actual content of the 
#			dashboard & the new build unit will be added
#	ret no return
#########################################################################################################################
sub DashboardWrite($$)
{
	my $Dashboard=shift;
	my $Errors=shift;
	
	return if(!defined $Dashboard || !defined $Errors);
	
	my $dashboardHandle;
	unless(open($dashboardHandle, ">$Dashboard")) { warn("ERROR: cannot open '$Dashboard': $!"); return; }
	$Data::Dumper::Indent = 0;
	print $dashboardHandle Data::Dumper->Dump([$Errors], ["*Errors"]);
	close($dashboardHandle);
}

#########################################################################################################################
# ret = sub DeleteChange(arg1,arg2,arg3)
#	Delete a P4 change based on its number & a regex for the description
#########################################################################################################################
#		arg1[in] P4 Handle
#		arg2[in] Change number id
#		arg3[in] RegEx to delete a change specificaly on its description
#	ret 1 if ok otherwise undef
#########################################################################################################################
sub DeleteChange($$;$)
{
	my $p4=shift;
	my $ChangeNumber=shift;
	my $RegEx=shift;
	
	my $rhChange = $p4->Change("-o $ChangeNumber");
	return undef if($p4->ErrorCount());
        
        if (!defined $RegEx || $rhChange->{"Description"}[0] =~ /$RegEx/ ) {
		foreach my $Line (@{$rhChange->{"Files"}})
		{
			my($FileName,$Status)=($Line =~ /^(.*?)\s*\#\s*(.*)$/);
			next if(!defined $FileName || $FileName eq "");
			
			$p4->Revert("-c $ChangeNumber $FileName");
			return undef if($p4->ErrorCount());
		}
		$p4->Change("-d $ChangeNumber");
		return undef if($p4->ErrorCount());
	}
	return 1;
}

#########################################################################################################################
# ret = sub DeleteChanges(arg1,arg2,arg3,arg4)
#	Delete all P4 changes based on their statis, on the client name & on a regex for the description
#########################################################################################################################
#		arg1[in] P4 Handle
#		arg2[in] Client name
#		arg3[in] change status to delete
#		arg4[in] RegEx to delete a change specificaly on its description
#	ret 1 if ok otherwise undef
#########################################################################################################################
sub DeleteChanges($$$;$)
{
	my $p4=shift;
	my $Client=shift;
	my $Status=shift;
	my $RegEx=shift;

	my $rhChanges = $p4->Changes("-s $Status -c $Client");
	return undef if($p4->ErrorCount());
	foreach my $Line(@{$rhChanges})
	{
		my($ChangeNumber)=($Line=~/^Change\s*(\d*)\s*.*/);
		return undef if(!DeleteChange($p4, $ChangeNumber, $RegEx ));
	}
	return 1;
}

#########################################################################################################################
# ret = sub ConvertLogicalFilenameToPrefixedFilename(arg1,arg2,arg3,arg4)
#########################################################################################################################
#		arg1 is the string to modify
#		arg2 is a substitution array for replacing a path part by a tag
#		arg3 is case sensitive regarding arg2 substitution
#		arg4 is a regex to filter files & ignore some of them if requested like in a specific directory
#########################################################################################################################
sub ConvertLogicalFilenameToPrefixedFilename($$;$$)
{
	my $ReadFile= shift;
	my $SubstitutionTable = shift;
	my $CaseSensitive = shift;
	my $RegExArrayToIgnore = shift;
	
	return $ReadFile if(!defined $ReadFile || $ReadFile eq "");
	
	$ReadFile=~ s/\\/\//g; # Force slash format
	if(defined $SubstitutionTable)
	{
		foreach $CurrentKey(keys %$SubstitutionTable)
		{
			if(((!defined $CaseSensitive || $CaseSensitive==0) && $ReadFile=~ /$SubstitutionTable->{$CurrentKey}/i) || $ReadFile=~ /$SubstitutionTable->{$CurrentKey}/)
			{
				$ReadFile=~ s/$SubstitutionTable->{$CurrentKey}/$CurrentKey/i;
				last;
			}
		}
	}

	if(defined $RegExArrayToIgnore)
	{
		foreach my $regEx(@{$RegExArrayToIgnore})
		{
			return undef if(defined $regEx && $ReadFile =~ /$regEx/);
		}
	}

	return $ReadFile;
}

1;
