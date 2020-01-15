#!/usr/bin/perl -w

# set @INC array
use FindBin qw($Bin);
use lib ("$Bin", "$Bin/site_perl");

# core
use Getopt::Long;

# local
use Torch;

##############
# Parameters #
##############

Usage() unless(@ARGV);
$Getopt::Long::ignorecase = 0;
GetOptions("help|?"=>\$Help,
"directory=s"	=>\$szDirectory,
"site=s"	=>\$szSite
);
Usage() if($Help);

$ENV{SITE} ||= $szSite if($szSite); 


eval { require "Site.pm" }; 

Usage() if($Help || !$ENV{PROJECT});

Torch::delete_all_build_session($ENV{BUILD_DASHBOARD_WS}, 1, $szDirectory);


sub Usage
{
	print <<USAGE;
	Usage   : FlushWSRecords.pl [option]+
	Example : FlushWSRecords.pl -h
	FlushDBRecords.pl -d=/temp/build -s=Levallois

	[option]
	-help|?  argument displays helpful information about builtin commands.
	-d.irectory  must contain the directory containing *.failed & other WebService records (mandatory)
	-s.ite		 must contain the build site from, where this script is launched (optional if stored in the environment)
USAGE
	exit;
}
