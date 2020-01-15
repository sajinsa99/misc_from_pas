#!/usr/bin/perl -w

use Getopt::Long;

##############
# Parameters #
##############

if($^O eq "MSWin32")
{ 
	die("ERROR: $Result Please download psexec.exe from http://technet.microsoft.com/fr-fr/sysinternals/hh223554")       if(($Result=`psexec.exe 2>&1`) =~ /not recognized/);
	die("ERROR: $Result Please download plink.exe from http://www.smuxi.org/issues/show/218")                            if(($Result=`plink.exe 2>&1`)  =~ /not recognized/);
	die("ERROR: $Result Please download pscp.exe from http://www.chiark.greenend.org.uk/~sgtatham/putty/download.html")  if(($Result=`pscp.exe 2>&1`)   =~ /not recognized/);
}
die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/[\\\/]\d+$//;

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "commands=s@"=>\@Commands, "files=s@"=>\@Files, "machines=s@"=>\@Hosts, "password=s"=>\$Password, "user=s"=>\$User); 
Usage() if($Help);
unless(@Commands) { print(STDERR "the -c parameter is mandatory\n"); Usage() }
unless(@Hosts)    { print(STDERR "the -m parameter is mandatory\n"); Usage() }

# expand @Hosts
@Hosts = map({split('\s*,\s*')} @Hosts);
$NumberOfHosts = @Hosts;
for(my$i=0; $i<$NumberOfHosts; $i++)
{
	if(-f $Hosts[$i])
	{
		my $File = splice(@Hosts, $i, 1);
		open(IN, $File) or die("ERROR: cannot open '$File': $!");
		while(<IN>)
		{
			next if(/^\s*#/);
			chomp;
			splice(@Hosts, $i++, 0, $_);
		}
		close(IN);
		$NumberOfHosts = @Hosts; $i=0;
	}
}
HOST: for(my $i=0; $i<@Hosts; $i++)
{
	next if($Hosts[$i] =~ /\:/);
	
	my $Cmd = "psexec \\\\$Hosts[$i]";
	$Cmd .= " -u $User" if($User);
	$Cmd .= " -p $Password" if($Password);
	$Cmd .= " -n 5 echo 2>&1";
	open(PSEXEC, "$Cmd |") or die("ERROR: cannot execute '$Cmd': $!");
	while(<PSEXEC>)
	{
		if(/with error code 0\./)
		{ 
			warn("WARNING: the platform of $Hosts[$i] is not specified. We assume it is 'windows'.");
			$Hosts[$i] = "windows:$Hosts[$i]";
			next HOST
		}
	}
	close(PSEXEC);

	my($UnixUser) = $User =~ /([^\\]+$)/;
	$Cmd = "plink -auto_store_key_in_cache $UnixUser\@$Hosts[$i]";
	$Cmd .= " -pw $Password" if($Password);
	$Cmd .= " echo plink is OK 2>&1";
	open(PLINK, "$Cmd |") or die("ERROR: cannot execute '$Cmd': $!");
	while(<PLINK>)
	{
		if(/plink is OK/)
		{ 
			warn("WARNING: the platform of $Hosts[$i] is not specified. We assume it is 'unix'.");
			$Hosts[$i] = "unix:$Hosts[$i]";
			next HOST
		}
	}
	close(PLINK);
	
	warn("ERROR: cannot connect to '$Hosts[$i]'."); 	
	$Hosts[$i] = undef;
}
@Hosts = grep({$_} @Hosts);
die("ERROR: no host found.") unless(@Hosts);
 
## expand @Commands
$NumberOfCommands = @Commands;
for(my$i=0; $i<$NumberOfCommands; $i++)
{
	if(-f $Commands[$i])
	{
		my $File = splice(@Commands, $i, 1);
		open(IN, $File) or die("ERROR: cannot open '$File': $!");
		while(<IN>)
		{
			next if(/^\s*#/);
			chomp;
			splice(@Commands, $i++, 0, $_);
		}
		close(IN);
		$NumberOfCommands = @Commands; $i=0;
	}
}

########
# Main #
########

foreach(@Hosts)
{
	my($Platform, $Host) = split('\s*:\s*', $_);
	if($Platform eq "windows")
	{
		my $CmdHead = "psexec \\\\$Host";
		$CmdHead .= " -u $User" if($User);
		$CmdHead .= " -p $Password" if($Password);
		foreach my $File (@Files)
		{
			my($FileName) = $File =~ /([^\\\/]*)$/;
			open(IN, $File) or die("ERROR: cannot open '$File': $!");
			open(OUT, ">$TEMPDIR\\rcmd.bat") or die("ERROR: cannot open '$TEMPDIR\\rcmd.bat': $!");
			print(OUT "\@echo off\n");
			print(OUT "IF EXIST \%TEMP\%\\$FileName DEL /F \%TEMP\%\\$FileName\n");
			while(<IN>)
			{
				chomp;
				s/\^/\^\^/g;
				print(OUT "echo", $_?" $_":"." ," >> \%TEMP\%/$FileName\n");
			}
			close(IN);
			close(OUT);
			system("$CmdHead -c -f $TEMPDIR\\rcmd.bat >nul 2>nul") && warn("ERROR: cannot remote copy file '$File'.");
		}
		for my $Command (@Commands)
		{
			my $Cmd = $CmdHead;
			$Cmd = "$CmdHead cmd /c cd /d ^\%TEMP^\% ^& $Command 2>nul";
			print("\n# Connecting to $Host to execute '$Command'...\n\n");
			system($Cmd) && warn("ERROR: cannot execute remote command '$Command'."); 
		}
	}
	elsif($Platform eq "unix")
	{
		my($UnixUser) = $User =~ /([^\\]+$)/;
		foreach my $File (@Files)
		{
			my($FileName) = $File =~ /([^\\\/]*)$/;
			my $Cmd = "pscp.exe";
			$Cmd .= " -pw $Password" if($Password);
			$Cmd .= " $File $UnixUser\@$Host:$FileName";
			system("$Cmd 1>nul 2>nul") && warn("ERROR: cannot remote copy file '$File'.");
		}
		my $CmdHead = "plink -auto_store_key_in_cache $UnixUser\@$Host";
		$CmdHead .= " -pw $Password" if($Password);
		for my $Command (@Commands)
		{
			my $Cmd = $CmdHead;
			$Cmd = "$CmdHead $Command 2>nul";
			print("\n# Connecting to $Host to execute '$Command'...\n\n");
			system($Cmd) && warn("ERROR: cannot execute remote command '$Command'."); 
		}
	}
	else { warn("ERROR: platform '$Platform' is unknown for $Host") }
	

}

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : rcmd.pl -m -j -u -p -c
   Example : rcmd.pl -h
             rcmd.pl -m=windows:dewdfth04095m,unix:dewdfth0425am -u=SAP_ALL\builder -p=blabla -c=ls
             rcmd.pl -m=dewdfth04095m,dewdfth0425am -j=c:\\jobs -u=SAP_ALL\builder -p=blabla -c=ls

   -help|?      argument displays helpful information about builtin commands.
   -c.ommands   list of commands or a file containing a list of commands.
   -f.iles      copy the specified files to the remote system. 
   -m.achines   list of machines. Syntax is [platform:]name,[platform:]name,....
                or a file containing a list of machines
   -password    specify the password for the remote user
   -user        specify the user for the remote command
USAGE
    exit;
}