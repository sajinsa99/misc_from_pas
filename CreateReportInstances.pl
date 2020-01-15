#!/usr/bin/perl -w

#create a Crystal Report instance in the CMS with the given stream and revision number
#parameter : context, build_revision, filelog
#filelog is the output log file

use LWP;
require HTTP::Request;

# set home variable
our $Home = $^O eq 'MSWin32' ? $ENV{SYSTEMDRIVE} : $ENV{HOME};

# pragmas
use strict;
use warnings;

my $result;
my ($context , $build_revision, $filelog) = @ARGV ;

# convert to lower case for db
$context =~ tr/A-Z/a-z/;  

my $boe = "";
my $report1 = "";
my $report2 = "";

my $config = "dev"; #prod/qual/dev

# Report IDs on BOEs
# Report1 - Torch Build Dashboard Report: qualBOE = 844883; PGBOE = 1390136; devBOE= 9283; 
# Report2 - Build Results v3 Report: 	  qualBOE = 30373; PGBOE = 29529142; devBOE= 9282;

if ($config eq "prod") {$boe = "http://vanpgbi002.pgdev.sap.corp:1080"; $report1 = "1390136"; $report2 = "29529142";}
elsif ($config eq "qual") {$boe = "http://vanpgapps02.pgdev.sap.corp:1080"; $report1 = "844883"; $report2 = "30373";}
elsif ($config eq "dev") {$boe = "http://pgboetest-vm2.pgdev.sap.corp:1080"; $report1 = "9283"; $report2 = "9282";}	

my @commands;

# create an array of report(s) to cache
if ($ENV{BUILD_DASHBOARD_ENABLE}) {
	@commands = ("$boe/Torch/scheduleFromBuild.jsp?reportID=$report1&param0=$context&param1=$build_revision",   
		     "$boe/Torch/scheduleFromBuild.jsp?reportID=$report2&param0=$context&param1=$build_revision");
}

my $resultlog = "RESULTS: \n";

foreach my $url (@commands)
{
 
#  my $request = HTTP::Request->new(GET => $url);
#  my $ua = LWP::UserAgent->new;
#  my $response = $ua->request($request);
#
#  if ($response->is_success)
#      {
#      $result = $response->status_line();
#  }
#  else
#  {
#      $result = "Error : ".$response->error_as_HTML;
#  }
#  $resultlog = $resultlog."URL: $url\n"."Result: $result\n";
}


if (open OUT  , ">$filelog" )
{
   print OUT "CreateReportInstances.pl\n" ;
   print OUT "------------------------\n" ;
   print OUT "Context    = $context\n" ;
   print OUT "Build Revision   = $build_revision\n" ;
   print OUT "Log file  = $filelog\n" ;
   print OUT "------------------------\n\n" ;
   print OUT "The Following Report Instance Request has been sent:\n";
   print OUT "$resultlog";
   close OUT ;
}
