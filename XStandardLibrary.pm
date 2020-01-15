# NAME:
#   XStandardLibrary.pm
# PURPOSE:
#   standard subroutines go in here
# FUTURE:

package               XStandardLibrary;

use                   Exporter ();
use vars qw( $VERSION @ISA @EXPORT $PROGRAM);
$VERSION        = 1.000;
@ISA            = qw(Exporter);
@EXPORT         = qw(
  CheckDiskSpace
  CheckForExternalPrograms
  CheckNetworkStatus
  CheckSystemLoad
  SendMail
  Size2GB
);

# core modules
use Data::Dumper;
use Cwd 'abs_path';
use File::Path;
use File::Spec;
use File::Basename;
use Sys::Hostname;
use Socket;
use Mail::Sendmail;
use Net::Time qw(inet_time);
use Net::FTP;
use Sys::Hostname;
# use our stuff
use XLogging;
use Site;
# perl pragmas
use strict;
$^W = 1;  # use warnings

# declare subroutines
sub CheckDiskSpace(;$);
sub CheckForExternalPrograms(;\%);
sub CheckNetworkStatus(;@);
sub CheckSystemLoad();
sub SendMail($$);
sub Size2GB($);

my $LoginName = getlogin() || getpwuid($<) || 'unknown';
$LoginName = lc($LoginName);
(my $Host = lc(hostname())) =~ s<\..*$><>;

###=============================================================================

$PROGRAM = defined $main::PROGRAM ? $main::PROGRAM : basename("$main::0", ".pl");

our $MAIL = 1; # send mail on error?
if($XLog::xgLogDebug) {
  $Mail::Sendmail::mailcfg{debug} = 4;
}

###=============================================================================

sub CheckForExternalPrograms(;\%)
{
    my($opts) = @_;
    my $have_all = 1;
    
    xLogInf1( "Checking for required programs" );
    
    # <type>|<name>|<default dir>|<close>|<phase>[|<phase>...]
    # <type> is p for programs that should be on path
    # <type> is c for com object servers
    # <name> should be either the filename or the projid
    # <close> is the name of the function that needs to be called
    #         to close the com object server
    # <phase> is a phase that requires the exe or object
    # phases: remove version fetch compile java drop copy postproduction setup
    
    my @ProgramsNeeded;
    
    if ($^O eq 'MSWin32') {
        
        my $javahome = defined $ENV{JAVA_HOME} ? $ENV{JAVA_HOME} : 'C:\\j2sdk14';
        
        @ProgramsNeeded = (
        # Cygwin tools
        "p|make.exe|c:\\cygwin\\bin||cygwin",
        # Native tools
        "p|devenv.exe|c:\\Program Files\\Microsoft Visual Studio .NET\\Common7\\IDE||dotnet",
        "p|jar.exe|$javahome\\bin||java",
        "p|javac.exe|$javahome\\bin||java",
        "p|p4.exe|c:\\program files\\perforce||version",
        );
        
    }
    elsif ($^O eq 'aix') {
        
        @ProgramsNeeded = (
        # Mainwin tools
        "p|nmake|/home2/mainwin/Saturn/sdk/502sp1/mw/bin-aix4_optimized||mainwin",
        "p|cl.exe|/home2/mainwin/Saturn/sdk/502sp1/mw/bin||mainwin",
        # Native tools
        "p|bison|/home4/thirdparty/Saturn/AIX/5.1/bin||compile",
        "p|gmake|/usr/local/bin||compile",
        "p|p4|/usr/bin||version",
        "p|slibclean|/usr/sbin||compile",
        "p|xlC_r|/usr/vacpp/bin||compile",
        );

    }
    elsif ($^O eq 'hpux') {
        
        @ProgramsNeeded = (
        # Mainwin tools
        "p|cl.exe|/home2/mainwin/Saturn/sdk/502sp1/mw/bin||mainwin",
        "p|nmake|/home2/mainwin/Saturn/sdk/502sp1/mw/bin-ux11_optimized||mainwin",
        # Native tools
        "p|aCC|/usr/bin||compile",
        "p|bison|/home4/thirdparty/Saturn/HP-UX/B.11.11/bin||compile",
        "p|gmake|/usr/local/bin||compile",
        "p|p4|/usr/bin||version",
        );
        
    }
    elsif ($^O eq 'linux') {
        
        @ProgramsNeeded = (
        # Mainwin tools
        "p|cl.exe|/home2/mainwin/Saturn/sdk/502sp1/mw/bin||mainwin",
        "p|nmake|/home2/mainwin/Saturn/sdk/502sp1/mw/bin-linux_optimized||mainwin",
        # Native tools
        "p|bison|/home4/thirdparty/Saturn/Linux/AS3.0/bin||compile",
        "p|g++|/usr/bin||compile",
        "p|gmake|/usr/local/bin||compile",
        "p|p4|/usr/bin||version",
        );
        
    }
    elsif ($^O eq 'solaris') {
        
        @ProgramsNeeded = (
        # Mainwin tools
        "p|cl.exe|/home2/mainwin/Saturn/sdk/502sp1/mw/bin||mainwin",
        "p|nmake|/home2/mainwin/Saturn/sdk/502sp1/mw/bin-sunos5_optimized||mainwin",
        # Native tools
        "p|CC|/usr/bin||compile",
        "p|bison|/home4/thirdparty/Saturn/SunOS/5.8/bin||compile",
        "p|dmake|/usr/bin||compile",
        "p|gmake|/usr/local/bin||compile",
        "p|p4|/usr/bin||version",
        );

    }
    else {
        @ProgramsNeeded = ();
        xLogErr("external programs - FATAL: ", "Unsupported platform: $^O");
        return(0);
    }
    
    my %opts;
    my $all_phases = 0;
    if( (defined $opts) and 
    (ref $opts eq 'HASH')
    ) {
        %opts = %$opts;
    }
    else {
        xLogInf1( "Assuming all phases required" );
        $all_phases = 1;
    }
    
    my $dsep = $^O eq 'MSWin32' ? '\\' : '/';  # dir element seperator
    my $psep = $^O eq 'MSWin32' ? ';' : ':';   # PATH seperator
    my @paths = split( /$psep/, $ENV{PATH} );
    my $index;
    for ( $index=0;  $index<=$#paths;  ++$index ) {
        if ( $paths[$index] =~ /^\s*"(.+)"\s*$/ ) {
            $paths[$index] = $1;
        }
    }
    
    my $entry;
    foreach $entry ( @ProgramsNeeded ) {
        
        my( $type, $name, $defaultdir, $close, @phases ) = split( /\|/, $entry );
        
        if ( $type ne "p" and $type ne "c" ) {
            xLogErr( "external programs - FATAL: ", "Programming error: bad type in ProgramsNeeded table, $entry" );
            $have_all = 0;
            next;
        }
        
        my $needed_this_run = 0;
        my $phase;
        foreach $phase ( @phases ) {
            if ( !$all_phases and ! defined( $opts{$phase} ) ) {
                xLogErr( "external programs - FATAL: ", "Programming error: bad phase $phase in ProgramsNeeded table, $entry" );
                $needed_this_run = 1;
                next;
            }
            if ( $all_phases or $opts{$phase} eq "yes" ) {
                if ( 
                  $phase eq 'mainwin'
                ) {
                    $needed_this_run = 0;
                    #xLogInf1("Ignoring $phase for Solution Kit Project");
                }
                else {
                    $needed_this_run = 1;
                }
            }
        }
        
        if ( $needed_this_run ) {
            
            if ( $type eq "p" ) {
                my $found = 0;
                my $path;
                
                foreach $path ( @paths ) {
                    if ( -f "$path$dsep$name" ) {
                        $found = 1;
                        xLogInf1( "found: $path$dsep$name" );
                        last;
                    }
                }
                if ( ! $found ) {
                    if ( -f "$defaultdir$dsep$name" ) {
                        $found = 1;
                        xLogInf1( "found in default directory: $defaultdir$dsep$name" );
                        $ENV{PATH} = $ENV{PATH} . ';' . $defaultdir;
                    }
                    else {
                        xLogErr( "external programs - FATAL: ", "Missing $name" );
                        $have_all = 0;
                    }
                }    
            }
            else {
                # unknown type
                1;
            }
            
        }
    }
    
    # *** stub out until all tools are on all machines and
    # coordtool sources the buildpath.{sh,cmd} file
    return(1) if($PROGRAM eq "coordtool");
    
    return($have_all);
}

###=============================================================================

sub CheckNetworkStatus(;@)
{
  my(@what) = @_;
  my $what;
  my $cmd;
  my @tokens;
  my @output;
  my $msg;
  
  # check p4, ftp, license, & clock drift by default
  if(! @what) {
    $what = "p4, mount, license, clock";
  }
  else {
    $what = lc join(',', @what);
  }
  
  # 1. check p4
  if( $what =~ m<\bp4\b> ) {
    $cmd    = "p4 depots";
    @tokens = (
      '^Depot \w+ .*',
    );
    if( !xLogRun($cmd , @tokens, @output, 1) ) {
      {
        local $" = "\n";
        $msg = "unable to connect with perforce server: $ENV{P4PORT}\n@output";
      }
      xLogErr('p4 - WARN: ', $msg);
      return(0);
    }
  }
  
  # 2. check $ENV{DROP_DIR} status
  if( $what =~ m<\bmount\b> ) {
      if( ! -d $ENV{DROP_DIR} ) {
          xLogErr('mount - WARN: ', "cannot read drop dir: $ENV{DROP_DIR}");
          return(0);
      }
  }
  
  # 3. check license servers
  if( $what =~ m<\blicense\b> ) {
    1;
  }

  # 4. check clock
  # a) drift
  if( $what =~ m<\bclock\b> ) {
    my $time = time();
    # We expect the $ENV{DROP_SERVER} to be running these servers
    # * nfsd  (ie: unix network file system)                 <-- not tested
    # * smb   (ie: windows folder sharing)                   <-- not tested
    # * ftpd  (eg: "ServUDaemon" http://www.serv-u.com/)     <-- tested above
    # * timed (eg: "ats" http://www.adjusttime.com/atcs.php) <-- tested here
    # * smtpd (ie: simple mail transport protocol)           <-- used
    my $inet_time = inet_time($ENV{DROP_SERVER}, "udp");
    if (! $inet_time) {
      xLogErr('clock - WARN: ', "cannot get inet_time from $ENV{DROP_SERVER}");
      # this is just an info message, do not return fail
    } elsif(abs($time - $inet_time) > 60*5) {
      xLogErr('clock - WARN: ', "clock drift " . ($time - $inet_time)/60 . " minutes");    
      # this is just an info message, do not return fail
    }
  }
  # b) timezone (including daylight-savings check)
  if( $what =~ m<\btimezone\b> ) {
    #my $real = GetTZ('real');
    #my $exp  = GetTZ('expected');
    #if( $real ne $exp ) {
    #  xLogErr('clock - WARN: ', "timezone is ($real) but expected ($exp)");    
    #  # this is just an info message, do not return fail
    #}
  }
  
  # return success
  return(1);
}

###=============================================================================

sub CheckSystemLoad()
{
    my @output;
    my @parts;
    my $load;

    return(1); ### stub out for now ###
        
    # Windows
    if ( $^O eq 'MSWin32' ) {
        # TOTAL  K 0:00:04.343 (10.9%)  U 0:00:00.187 ( 0.5%)  I 0:00:35.468 (88.7%)  DPC
        # 0:00:00.031 ( 0.1%)  Interrupt 0:00:00.171 ( 0.4%)
        @output = `kernrate -a -s 2`;
        xLogDbg(@output);
        chomp(@output);
        for my $line ( @output ) {
            if($line =~ m<^TOTAL  K >) {
                $line =~ s<[()%]><>g;
                @parts = split(m<\s+>, $line);
                $load = 100 - $parts[9];
            }
        }
    }
    # Solaris
    elsif( $^O eq 'solaris' ) {
        @output = `rup localhost`;
        xLogDbg(@output);
        chomp(@output);
        for my $line ( @output ) {
            if($line =~ m<^>) {
                $line =~ s<[()%]><>g;
                @parts = split(m<\s+>, $line);
                $load = 100 - $parts[9];
            }
        }
    }
    # AIX, HPUX, Linux
    else {
        @output = `uptime`;      
        xLogDbg(@output);
        chomp(@output);
        for my $line ( @output ) {
            if($line =~ m<^TOTAL  K >) {
                $line =~ s<[()%]><>g;
                @parts = split(m<\s+>, $line);
                $load = 100 - $parts[9];
            }
        }
    }
    
    return(1);
}

###=============================================================================

sub CheckDiskSpace(;$)
{
  my( $wanted_path ) = @_;
  my %paths;
  my $threshhold;
  
  if(defined $wanted_path) {
    %paths = ($wanted_path => "0GB");
  }
  else {
    if ( $^O eq 'MSWin32' ) {
      %paths = (
        'c:\\' => '2GB', 
        'd:\\' => '6GB',
      );
    }
    else {
      my $build = abs_path("$ENV{HOME}/.");
      
      %paths = (
        $build    => '10GB',
        '/var'    => '15%',
        '/tmp'    => '15%', 
        '/'       => '15%',
      );
    }
  }
  
  # check disk space
  my @output;
  
  # Windows
  if ( $^O eq 'MSWin32' ) {
    for my $path (sort keys %paths) {
      @output = `c:\\Build\\tools\\win32_x86\\zdu.exe /i $path`;
      xLogDbg(@output);
      chomp(@output);
      # Total: 78 066 098 176 [73G] - Free: 24 179 589 120 [23G]
      if ( $output[-1] =~ m<\[([\d.]+[a-z])\].*\[([\d.]+[a-z])\]>i ) {
        my $size  = Size2GB($1);
        my $avail = Size2GB($2);
        my $percent = 100 - ( ( ($size - $avail) / $size) * 100);
        
        xLogDbg("$path has $avail GB left ($percent\% left)");
        if (defined $wanted_path) {
          return($avail);
        }
        $threshhold = $paths{$path};
        # percent
        if ($threshhold =~ s<\%$><>) {
          if ( $percent < $threshhold ) {
            my $err_msg = "$path has $percent\% left"; 
            xLogErr("disk - FATAL: ", $err_msg);
            return 0;
          }
        }
        # GB
        else {
          $threshhold =~ s<GB$><>;
          if ( $avail < $threshhold ) {
            my $err_msg = "$path has $avail GB left"; 
            xLogErr("disk - FATAL: ", $err_msg);
            return 0;
          }
        }
      }
      else {
        xLogErr("disk - FATAL: ", "failed to get disk space info");
        return 0;
      }
    }
  }
  
  # Unix
  else {
    my $extra_flag = ($^O ne "solaris") ? 'P' : '';
    @output = `df -k$extra_flag`;
    xLogDbg(@output);
    chomp(@output);
    my $output = join("~",@output);
    $output =~ s/~\s+/ /g;
    @output = split( /~/, $output );
    shift(@output) if($output[0] =~ m<^\s*Filesystem\s+>i);
    if(! @output) {
      xLogErr("disk - FATAL: ", "failed to get disk space info");
      return 0;
    }
    
    # grep out interesting partitions
    # ex: "/dev/hd3          1048576     32992   1015584       4% /tmp"
    my $match = 0;
    foreach my $line (@output) {
      my $path;
      my ( $filesys, $total, $used, $avail, $percent, $mount ) = split(/\s+/, $line);
      # only look at interesting partitions
      unless (
           ( defined $mount ) and 
           ( ($path) = grep(m<^$mount(/|$)>, keys %paths) )
      ) {
        next;
      }
      # make sure output is sane
      if($percent !~ m<^\d+\%?$> or $mount !~ m<^/[\w/]*$>) {
        xLogErr("disk - FATAL: ", "failed to get disk space info: $line");
        return 0;
      }
      #
      $match++;
      $percent =~ s/\%//;
      $percent = 100 - $percent;
      $avail = sprintf( "%.1f", ($avail/1024**2) ); # convert to GB
      xLogDbg("$mount has $avail GB left ($percent\% left)");
      if (defined $wanted_path) {
          return($avail);
      }
      $threshhold = $paths{$path};
      # percent
      if ($threshhold =~ s<\%$><>) {
        if ( $percent < $threshhold ) {
          my $err_msg = "$path has $percent\% left"; 
          xLogErr("disk - FATAL: ", $err_msg);
          return 0;
        }
      }
      # GB
      else {
        $threshhold =~ s<GB$><>;
        if ( $avail < $threshhold ) {
          my $err_msg = "$path has $avail GB left"; 
          xLogErr("disk - FATAL: ", $err_msg);
          return 0;
        }
      }
    }
    if (defined $wanted_path) {
      xLogErr("disk - ERROR: ", "no match found from 'df' for '$wanted_path'");
      return(-1);
    }
    if(scalar(keys %paths) != $match) {
      xLogErr("disk - FATAL: ", "failed to get disk space info");
      return 0;
    }

  }
  
  return 1;
}

###=============================================================================

sub SendMail($$) 
{

    my ($subject, $msg) = @_;
    my %mail;

    $mail{To}   = $ENV{SMTP_TO} || "PgVdcBuildVan\@businessobjects.com,Julian.Oprea\@businessobjects.com,Mei.Tan\@businessobjects.com";
    $mail{From} = $ENV{SMTP_FROM} || "$LoginName\@$Host";
    $mail{Smtp} = $ENV{SMTP_SERVER};
    
    $msg =~ s<^\s+><>;
    if(! defined $subject) {
      if($msg =~ m<^([^:]+):>) {
        $subject = $1;
      }
      elsif($msg =~ m<^(\S+)>) {
        $subject = $1;
      }
      else {
        $subject = "(no subject)";
      }
    }
    $mail{Subject} = "$PROGRAM message: $subject";
    $mail{Message} = $msg;
    if ($subject =~ m<\b(error|fatal|abort|fail):>i) {
      $mail{Importance} = "high";
    }
    if( $MAIL ) {
      xLogInf1("Sending mail: $mail{Subject}");
      xLogDbg( Dumper(\%mail) );
      if (! sendmail %mail) {
        xLogErr( "mail: sendmail failed: $Mail::Sendmail::error" );
        xLogDbg($Mail::Sendmail::log);
      }
    }
    else {
      xLogWrn("Not sending mail: $mail{Subject}\n", $mail{Message});
    }
    
    return(1);
}

###=============================================================================

sub Size2GB($)
{
  my($size) = @_;
  my($value, $units);
  
  $size = lc $size;
  $size =~ s<[,\s]+><>g;
  ($value = $size) =~ s<[^\d.]+><>;
  ($units = $size) =~ s<[\d.]+><>;
  $units =~ s<^(.).*$><$1>;
  
  my %map = (
    't' => 1024**1,
    'g' => 1024**0,
    'm' => 1024**-1,
    'k' => 1024**-2,
    'b' => 1024**-3,
  );
  if ( exists($map{$units}) ) {
    $value *= $map{$units};
  }
  else {
    xLogErr("Unrecognized units: $units");
    $value = -1;
  }
  
  return($value);
}

###=============================================================================

# return success to use
1;

###=============================================================================

__END__

