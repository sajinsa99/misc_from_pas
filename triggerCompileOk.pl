use strict;
use Getopt::Long;
use Sys::Hostname;


my ($context,$platform,$mode) = @ARGV;
$mode = "release" unless $mode ;
#$platform="win32_x86" unless $platform;
usage("no context specified") unless ($context);
usage("no platform specified") unless ($platform);

#print "context = $context\n";
my $HOST = hostname();
my $P4CLIENT = "${context}_$HOST"  ;

my $root_dir = `p4 client -o $P4CLIENT|grep "^Root:"` ;
$root_dir =~ s/^Root:\s*//;
chomp($root_dir) ;
#print "$root_dir\n";
my $build_result_file = "${root_dir}/../$platform/$mode/logs/Build/build_step.log" ;

if ( -f $build_result_file )
{
	if ( open LOG_FILE , "$build_result_file" )
	{
		my $good_section = 0;
		while (<LOG_FILE>)
		{
			#if ( $good_section && $_ =~ /^====(\d+) e\.rror/ )
			if ( $good_section && $_ =~ /^====(\d+) e\.rror\(s\) / )
			{
				print "$platform Compile errors = $1\n";
				if ( $1 eq "0" )
				{
					print "$platform greatest=yes\n" 
				}
				else
				{
					print "$platform greatest=no\n" 
				}
			}
			elsif ( $_ =~ /=\+=Area: (.+)/ )
			{
				$good_section = 1 if ( $1 ne "init" ) ;
			}
				
		}
		close (LOG_FILE);
	}
	else
  {
		print "can't open build summary log file $build_result_file : $!\n";
  }
}
else
{
	print "build summary log file $build_result_file doesn't exist\n";
}

sub usage()
{
	if ( @_ )
	{
		print "ERROR: @_\n\n";
  }
	print "Usage: triggerCompileOk.pl context platform [mode]\n\n"; 
	
	print "Context and platform are mandatory\n" ;
	print "by default mode is release\n\n";
	
	die "sample : triggerCompileOk.pl df_4.0 win32_x86\n\n";
}
