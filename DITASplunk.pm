package DITASplunk;

use File::Temp;
use File::Basename;
#use strict;

my @Values;
my $ApplicationList=";replication;backup;png_creation;cms_scheduler;outputgenerator;deltafetch;deltastructure;";
my $DomainList=";production;test;sandbox;feat;automatedtest;";
my $OutputFolder="\\\\derotvi0355\\volume9\$\\DITASplunk\\Data";
my $Application;
my $Domain;

sub CheckSplunkInfo
{
	my ($ApplicationIn,$DomainIn)=@_;
	my $ret=1;
	if(!($ApplicationList=~/;$ApplicationIn;/i))
	{
		$rest=0;
		print "ERROR: The Application $Application is not defined in the List\n";
		return $ret;
	}
	if(!($DomainList=~/;$DomainIn;/i))
	{
		$rest=0;
		print "ERROR: The Domain $Domain is not defined in the List\n";
		return $ret;
	}
	$Application=lc $ApplicationIn;
	$Domain= lc $DomainIn;
	@Values=();
	return $ret;
}

sub AddValue
{
	my ($Data)=@_;
	if($Data=~/=/)
	{
	  my ($name, $val) = split("=", $Data);
	  if ($val=~/Start/i || $val=~/End/i)
	  {
		if (!($name=~/Event/i))
		{
			print "ERROR: Variable name should be \"Event\" for $Data.\n";
		}
	  }
	  
	  push(@Values,$Data);
	}
	else
	{
		print "ERROR: Format requested Variable=Value\n";
	}
}

sub SaveSplunkInfo
{
	my $tmp = new File::Temp();
	$filename = $tmp->filename;
	my $tempfile=basename($filename);
	my $FileName="$ENV{COMPUTERNAME}_$tempfile.log";
	my $Path="$OutputFolder\\$FileName";
	#print "$Path\n";
	if(open(FILESPLUNK,">$Path"))
	{
		my $timestamp=FormatDateTimeForSplunk();
		my $Event="$timestamp Host=$ENV{COMPUTERNAME}, Application=$Application, Domain=$Domain, ";
		foreach(@Values)
		{
			$Event.="$_, ";
		}
		$Event=~s/, $//;
		print FILESPLUNK "$Event";
		close(FILESPLUNK);
		print "SendToSplunk -> [$Event]\n";
	}
	else
	{
		print "ERROR: Can't create $Path:  $!\n";
	}
}

sub FormatDateTimeForSplunk
{
	my($ss, $mn, $hh, $dd, $mm, $yy, $wd, $yd, $isdst) = localtime ();
	
	return sprintf("%04u-%02u-%02u %02u:%02u:%02u", $yy+1900, $mm+1, $dd,$hh,$mn,$ss);
}

1;