#!/usr/bin/perl -w
package Dependencies;

use FindBin qw($Bin);
use lib ("$Bin", "$Bin/site_perl");

# core
use XML::DOM;
require Tie::CPHash;

# local
use Build;

use constant PARENTS  => 1;
use constant CHILDREN => 0;         

use constant 
{
    OR=>0,
    AND=>1
};
use constant
{
    COMPUTING=>1
};

no warnings 'recursion';

################################################################################################################
# Methods declaration
#########################################################################################################################
sub FindFinalDelivrableDependencies($$$$$$$;$$$$$);
sub _FindFinalDelivrableDependencies($$$$$$$$$;$$$$$$);

################################################################################################################
# Functions
################################################################################################################
#---------------------------------------------------------------------------------------------------------------
#	InitializeDependencies()
#		Return a reference to the content of <project.process.read.dat) 
#	arg1: is the outbin_dir value content of the directory containing dependencies .dat(string)
#	arg2: project/Makefile name(string)
#	arg3: SRC_DIR directory containing all the source code(string)
#	arg4: OUTPUT_DIR directory containing all the build outputs(string)
#	arg5: Case sensitive or not(boolean)
#	arg6: dependencies type (read or write) (string)
#---------------------------------------------------------------------------------------------------------------
sub ReadDataFile($$$$$;$)
{
	my $szOutBinDir=shift;
	my $szMakefileName=shift;
	my $SRC_DIR=shift;
	my $OUTPUT_DIR=shift;
	my $szFileType=shift;
	my $bCaseSensitive=shift;
	
	
	my %hData;
	tie %hData, 'Tie::CPHash' if(!defined $bCaseSensitive || $bCaseSensitive==0);

	while (defined($next = <$szOutBinDir/depends/*.dependencies.$szFileType.dat>))  # scan .dat files in this directory
	{
    	return undef if(!open(PROCESSDAT, $next)) ;
    
    	while(<PROCESSDAT>)
    	{
    		eval $_;
    		die("Errors in DAT file ($next) : ".$@."\n") if($@); # evaluate file content to transform it into real PERL variables
    	}
    	close(PROCESSDAT);
	}
	
	return \%hData;
}
sub LoadDependenciesData($$$$$;$$)
{
	my $DependenciesLinks=shift;
	my $szOutBinDir=shift;
	my $szMakefileName=shift;
	my $SRC_DIR=shift;
	my $OUTPUT_DIR=shift;
	
	my $bCaseSensitive=shift;
	my $Type=shift;
		
	return undef if(!defined $DependenciesLinks || (defined $Type && $Type!=CHILDREN && $Type!=PARENTS));
	
	delete $DependenciesLinks->{'Dependencies'} if(exists $DependenciesLinks->{'Dependencies'});
	return undef if(defined $Type && !defined ($DependenciesLinks->{'Dependencies'}=ReadDataFile($szOutBinDir,$szMakefileName,$SRC_DIR,$OUTPUT_DIR,$Type==CHILDREN?'read':'write',1)));	
	$DependenciesLinks->{'Type'}=(!defined $Type?CHILDREN:$Type);
	return $DependenciesLinks;
}
sub UnloadDependenciesData($)
{
	my $DependenciesLinks=shift;
	delete $DependenciesLinks->{'Dependencies'} if(defined $DependenciesLinks && exists $DependenciesLinks->{'Dependencies'});
}
#---------------------------------------------------------------------------------------------------------------
#	SetOption()
#		used to define new options
#	arg1: must be different at each call, used internaly to flag links already analyzed 
#	arg2: Option name
#	arg3: Option value
#---------------------------------------------------------------------------------------------------------------
sub SetOption($$;$)
{
	my $DependenciesLinks=shift;
	my $Option=shift;
	my $Value=shift;
	
	$DependenciesLinks->{'Options'}{$Option}=$Value;
}

sub InitializeDependencies($$$$;$$)
{
	my $szOutBinDir=shift;
	my $szMakefileName=shift;
	my $SRC_DIR=shift;
	my $OUTPUT_DIR=shift;
	
	my $bCaseSensitive=shift;
	my $Type=shift;
	
	my %DependenciesLinks;
	
	return undef if(defined $Type && $Type!=CHILDREN && $Type!=PARENTS);
	
	return undef if(defined $Type && !defined (LoadDependenciesData(\%DependenciesLinks,$szOutBinDir,$szMakefileName, $SRC_DIR, $OUTPUT_DIR, $bCaseSensitive, $Type)));	
	return undef if(!defined ($DependenciesLinks{'FileNames'}=ReadDataFile($szOutBinDir,$szMakefileName,$SRC_DIR,$OUTPUT_DIR,'filename',$bCaseSensitive)));
	return undef if(!defined ($DependenciesLinks{'FileIDs'}=ReadDataFile($szOutBinDir,$szMakefileName,$SRC_DIR,$OUTPUT_DIR,'fileid',1)));
	return undef if(!defined ($DependenciesLinks{'BuildUnitIDs'}=ReadDataFile($szOutBinDir,$szMakefileName,$SRC_DIR,$OUTPUT_DIR,'buildunitid',1)));
	$DependenciesLinks{'Type'}=(!defined $Type?CHILDREN:$Type);
	SetOption(\%DependenciesLinks,Dependencies::COMPUTING,Dependencies::OR);
	return \%DependenciesLinks;
}
#---------------------------------------------------------------------------------------------------------------
#	GetAllDelivrableFiles()
#		Return a hashtable reference with all delivrables as keys found in idcards, returns undef if no delivrables or idcards)
#	arg1: is the OUTPUT_DIR value where are stored idcards (string)
#	arg2: Case sensitive or not(boolean)
#---------------------------------------------------------------------------------------------------------------
sub GetAllDelivrableFiles($;$)
{
	my $szOutputDir=shift;
	my $bCaseSensitive=shift;
	
	my $ReturnValue=undef;
	
	return undef if(!opendir(XML, "$szOutputDir/logs/packages")) ;
	
	my @IdCards;
	while(defined(my $Folder = readdir(XML)))
	{
		push(@IdCards, "$szOutputDir/logs/packages/$Folder/setup.info.xml") if(-e "$szOutputDir/logs/packages/$Folder/setup.info.xml");
	}
	closedir(XML);
	
	my %DelivrableFiles;
	tie %DelivrableFiles , 'Tie::CPHash' if(!defined $bCaseSensitive || $bCaseSensitive==0);

	foreach my $XMLFile (@IdCards)
	{
		my $parser = new XML::DOM::Parser;
		my $IDCARD = $parser->parsefile ($XMLFile);

		for my $PACKAGE (@{$IDCARD->getElementsByTagName("package")})
		{
		    my $defaultSourceDirectory = $PACKAGE->getAttribute("defaultSourceDirectory");
		    for my $IMPORT (@{$PACKAGE->getElementsByTagName("file")})
		    {
		        my $sourceDirectory = $IMPORT->getAttribute("sourceDirectory") || $defaultSourceDirectory;
		        (my $SrcFile = $sourceDirectory.$IMPORT->getAttribute("fileName")) =~ s/\\/\//g;
		        (my $DstFile = $PACKAGE->getAttribute("installDirectory").$IMPORT->getAttribute("fileName")) =~ s/\\/\//g;
		        $ReturnValue=\%DelivrableFiles if(!defined $ReturnValue);
		        $ReturnValue->{$SrcFile} = $DstFile;
		    }
		}

		# From the official doc : http://search.cpan.org/~tjmather/XML-DOM-1.44/lib/XML/DOM.pm
		# Avoid memory leaks - cleanup circular references for garbage collection
		$IDCARD->dispose;
	}
	return $ReturnValue;
}
#---------------------------------------------------------------------------------------------------------------
#	FindFinalDelivrableDependencies()
#		Return a hashtable reference with found delivrables as keys for file arg4
#	arg1: must be different at each call, used internaly to flag links already analyzed 
#	arg2: hashtable reference containing dependencies : {"read file"}{'process id'}{"written file"}=[0,'Done by this buildunit']
#	arg3: hashtable reference containing delivrable files as keys
#	arg4: File to analyze(string), it will returns its dependencies as described above (it is a file id for the _FindFinalDelivrableDependencies method
#	arg5: buildunits dependencies hashtable reference, Tie::IxHash type is recomanded to keep the dependencies order(optional, can be undef)
#	arg6: substitution table, example : {'$SRC_DIR'=>"^".$Slashed_SRC_DIR, '$OUTPUT_DIR'=>"^".$OutputDir }
#	arg7: is case sensitive for the substitution table ?
#	arg8: handle to flush datas into an xml file
#	arg9: Max recursivity for example, to only recover input files used to create the $CurrentFile....
#	arg10: Callback to compare the file, must return 1 if equal
#	arg11: Private user data passed to the callback
#	arg12: Does all the parent or child files equals ?, reference to a return value (1 if yes)
#	arg13: Process ID of the file to analyze... If child file is from the same process don't analyze the child one to reduce unneeded recursivities
#	arg14: SequenceNumber of of the current file
#	arg15: internal used, for recursivity, it is the return result which is internaly given to fill it
#	arg16: Internal counter for recursivity level,also used to indent xml datas...
#---------------------------------------------------------------------------------------------------------------
sub FindFinalDelivrableDependencies($$$$$$$;$$$$$)
{
	my $RunID=shift;
	my $DependenciesLinks=shift;
	my $DeliverableFiles=shift;
	my $CurrentFile=shift;
	my $BuildUnitsPath=shift;
	my $SubstitutionTable = shift;
	my $bCaseSensitive=shift;
	
	my $hXMLFile=shift;
	my $nMaxRecursivity=shift;
	my $rCallback=shift;
	my $rPrivateData=shift;
	my $rReturnedValue=shift;
	
	$CurrentFile=~ s/\\/\//g;
	return undef unless(exists $DependenciesLinks->{'FileNames'}->{$CurrentFile});
	
	my %FoundDelivrablesDependenciesForThisFile;

	my $ReturnedValue=_FindFinalDelivrableDependencies($RunID,$DependenciesLinks,$DeliverableFiles,$DependenciesLinks->{'FileNames'}->{$CurrentFile},$BuildUnitsPath,$SubstitutionTable,$bCaseSensitive,$hXMLFile, $nMaxRecursivity, $rCallback, $rPrivateData, undef, undef, \%FoundDelivrablesDependenciesForThisFile, 0);
	${$rReturnedValue}=$ReturnedValue if($rReturnedValue);
	return \%FoundDelivrablesDependenciesForThisFile;
}

sub _FindFinalDelivrableDependencies($$$$$$$$$;$$$$$$)
{
	my($RunID, $DependenciesLinks, $DeliverableFiles, $CurrentFileID, $BuildUnitsPath, $SubstitutionTable, $bCaseSensitive, $hXMLFile, $nMaxRecursivity, $rCallback, $rPrivateData, $CurrentProcessID, $CurrentFileSequenceNumber, $HashResult, $nRecursivity) = @_;
		
	my $bAddXMLClosing=undef;		
	my $ReturnValue=undef;
		
	return $ReturnValue unless(defined $CurrentFileID);
		
	# Does this fileid mapped to a string filename ?
	if(exists $DependenciesLinks->{'FileIDs'}->{$CurrentFileID})
	{
		my $CurrentFile=$DependenciesLinks->{'FileIDs'}->{$CurrentFileID};
		# If file equal, so do not look into childs & return
		$ReturnValue=&{$rCallback}($rPrivateData, $CurrentFile, $CurrentFileID) if(defined $rCallback);

		if(defined $hXMLFile && defined $nRecursivity && $nRecursivity>0) { print $hXMLFile ((" "x($nRecursivity+1))."<file name='$CurrentFile' type='".(exists $DependenciesLinks->{"Type"}?($DependenciesLinks->{"Type"}==CHILDREN?"child":"parent"):"unknown")."' processid='".(defined $CurrentProcessID?$CurrentProcessID:"")."'>\n"); $bAddXMLClosing=1; } 
		if(exists $DeliverableFiles->{$CurrentFile} && defined $HashResult) # found in idcards, add it in our table
		{
			my $PrefixedFilename=(defined $SubstitutionTable?Build::ConvertLogicalFilenameToPrefixedFilename($CurrentFile,$SubstitutionTable,$bCaseSensitive):$CurrentFile);
			$HashResult->{$PrefixedFilename}=[$CurrentFileID, $CurrentProcessID, $CurrentFileSequenceNumber, $nRecursivity];
		}
	}
	
	if((!defined $ReturnValue || $ReturnValue==0) && (!defined $nMaxRecursivity || !defined $nRecursivity || $nRecursivity<$nMaxRecursivity) &&  # do we are authorized to go & drill to this recursivity level ?
		exists $DependenciesLinks->{'Dependencies'}->{$CurrentFileID}) # Is this file mapped in the read entries of the Dependencies DAT datas...
	{
	    	my $raCurrentFile = \@{$DependenciesLinks->{'Dependencies'}->{$CurrentFileID}};

		if(defined $raCurrentFile->[2][0] && defined $rCallback) # If used to compare files & estimate modified tree/branch & not yet estimated, do it, otherwise returns the previous estimation as already done
		{
			$ReturnValue=$raCurrentFile->[2][1];
		}
		else
		{
			if($raCurrentFile->[0]!=$RunID) # already done ? to break infinite recursivity
			{
				$raCurrentFile->[0]=$RunID; # mark as already done
				my $tmpReturnValue=0;
				foreach my $raEntry(@{$raCurrentFile->[1]})
				{
					# If next node is on the same process id, don't take care of it & find a child element which generate a file coming from another process
					next if(defined $CurrentProcessID && $CurrentProcessID==$raEntry->[0]);
					foreach my $WrittenFileID(keys %{$raEntry->[2]})
					{
						my $ChildFileSequenceNumber=$raEntry->[2]->{$WrittenFileID};
						next if(defined $CurrentProcessID && $CurrentProcessID!=$raEntry->[0] && 
						
							defined $CurrentFileSequenceNumber && 
							(
								($CurrentFileSequenceNumber>$ChildFileSequenceNumber && $DependenciesLinks->{'Type'}==CHILDREN) || # if read file has been read after written file, this written file is not its child, don't analyze this entry
								($CurrentFileSequenceNumber<$ChildFileSequenceNumber && $DependenciesLinks->{'Type'}==PARENTS) # if the write file has been written before the read file, this read file is not its parent
							)
						);
						# This file sequency is ok, when searching parent file, the written file is older than the read one, ect...
						# Store in the $BuildUnitsPath, the list of build units to be recompiled
						$BuildUnitsPath->{$DependenciesLinks->{'BuildUnitIDs'}->{$raEntry->[1]}}=undef if(
							defined $BuildUnitsPath &&
							defined $DependenciesLinks->{'BuildUnitIDs'} && 
							defined $raEntry->[1]
							
						);
						# Transivity, search this written file in the read table to find its childrens...
						if($WrittenFileID!=$CurrentFileID)
						{
							$tmpReturnValue=_FindFinalDelivrableDependencies($RunID, $DependenciesLinks, $DeliverableFiles, $WrittenFileID, undef, $SubstitutionTable, $bCaseSensitive, $hXMLFile, $nMaxRecursivity, $rCallback, $rPrivateData, $raEntry->[0], $ChildFileSequenceNumber, $HashResult, defined $nRecursivity?($nRecursivity+1):1);
							if($DependenciesLinks->{'Options'}{Dependencies::COMPUTING}==Dependencies::OR)
							{
							    if(defined $tmpReturnValue)
							    {
							        $ReturnValue=defined $ReturnValue?($ReturnValue|$tmpReturnValue):$tmpReturnValue;
							    }
							}
							elsif($DependenciesLinks->{'Options'}{Dependencies::COMPUTING}==Dependencies::AND)
							{
							        $ReturnValue=defined $ReturnValue?($ReturnValue&$tmpReturnValue):$tmpReturnValue;
							}
						}
					}
				}
				# Store if the three is still the same or not when a comparaison was requested
				@{$raCurrentFile->[2]}=(0,$ReturnValue) if(defined $rCallback);
			}
		}
	}

	print $hXMLFile ((" "x(defined $nRecursivity?($nRecursivity+1):0))."</file>\n") if($bAddXMLClosing);
	return $ReturnValue;
}

1;
