#
# Usage:
#
#   use XLogging;
#
#   $xgLogDebug = 1;              # 1 means always to both
#   $xgLogVerboseLevel = 0;       # 0 means never to console, always to logfile
#                                       #    * only applies to "info:" lines
#   $xgLogStackTrace = -1;        # -1 means never
#   $xgLogConsoleOutput = 0;      # 0 means never

package               XLogging;

use strict;
use warnings;

BEGIN {
    use                   Exporter ();
    use vars qw(
    $VERSION
    @ISA
    @EXPORT
    @EXPORT_OK
    @EXPORT_FAIL
    %EXPORT_TAGS
    );
$VERSION        = 1.001;
@ISA            = qw(Exporter);
@EXPORT         = qw(
    &xLogClose
    &xLogOpen
    &xLogPause
    &xLogResume
    &xLogCloseAndLego
    &xLogDbg
    &xLogErr
    &xLogFatal
    &xLogFile
    &xLogFileErr
    &xLogFileInf1
    &xLogFileInf2
    &xLogFileInf3
    &xLogFileWrn
    &xLogFlush
    &xLogH1
    &xLogH2
    &xLogInf1
    &xLogInf2
    &xLogInf3
    &xLogRun
    &xLogRunDetached
    &xLogRunBg
    &xLogRunAbort
    &xLogRunHarvest
    &xLogSummarize
    &xLogWrn
    &xNow
    $hLogout
    $xgLogBackgroundJobMax
    $xgLogConsoleOutput
    $xgLogDebug
    $xgLogErrCount
    $xgLogLastError
    $xgLogStackTrace
    $xgLogVerboseLevel
    *TTYERR
    *TTYOUT
    );
@EXPORT_FAIL    = qw(
    &dosummarize
    &print_output
    &xLog
    &xLogH
    &xLogInf
    );
}

# uses (must keep to bare mimumum)
use File::Basename;
use File::Path;
use File::Spec;
use Sys::Hostname;
use POSIX;

# forward declare all functions
# so they can be referenced even before they are defined

# public
sub xLogOpen($;$$);
sub xLogClose(;$$);
sub xLogPause(;$);
sub xLogResume(;$);
sub xLogCloseAndLego(;$);
sub xLogDbg(@);
sub xLogErr(@);
sub xLogFatal(@);
sub xLogFile($$$);
sub xLogFileErr($);
sub xLogFileInf1($);
sub xLogFileInf2($);
sub xLogFileInf3($);
sub xLogFileWrn($);
sub xLogFlush(;$);
sub xLogH1($);
sub xLogH2($);
sub xLogInf1(@);
sub xLogInf2(@);
sub xLogInf3(@);
sub xLogRaw(@);
sub xLogRun($;\@\@$);
sub xLogRunDetached($);
sub xLogRunBg($;\@\@\$$$);
sub xLogRunAbort();
sub xLogRunHarvest(;$$);
sub xLogSummarize($$;$\@\@$$);
sub xLogWrn(@);
sub xNow();
# private
sub dosummarize($$$$);
sub print_output($$$$$);
sub xLog(@);
sub xLogH($$);
sub xLogInf(@);
sub split_command($$;$);
sub send_mail($$);

# exported package global vars
use vars qw(
  $hLogout
  $xgLogVerboseLevel
  $xgLogDebug
  $xgLogStackTrace
  $xgLogConsoleOutput
  $xgLogErrCount
  $xgLogLastError
  $xgLogBackgroundJobMax
);
$xgLogVerboseLevel  = 3;
$xgLogDebug = 0;
$xgLogStackTrace = 1;
$xgLogConsoleOutput = 1;
$xgLogErrCount = 0; # count the number of calls to xLogErr
$xgLogLastError = "";
$xgLogBackgroundJobMax     = 10;    # maximum simultaneous bg jobs

# NOT exported package global vars
local *LOG;                       # log filehandle
my $BackgroundJobCntr    = 0;     # part of unique job id
my $Tmpdir  = $^O eq 'MSWin32' ? $ENV{TEMP} || 'c:/temp' : $ENV{TMPDIR} || '/tmp';
my $To_console = 1;               # use with $xgLogVerboseLevel for STDOUT output
my $log_index  = 0;               # log stack index
my $pid;                          # process id
my %BackgroundJobInpg = ();       # to store inprogress job info
my @Backlog;                      # used to store output when no log open
my @log = ();                     # log stack logfile name
my @log_console = (1);            # log stack console flag

###=============================================================================

sub xLogOpen($;$$)
{
    my( $filename, $console, $nostart ) = @_;

    if($filename !~ m<\w>)
    {
      xLogErr("Empty logfile name given, xLogOpen cannot continue");
      return 0;
    }

    $xgLogConsoleOutput = defined $console ? $console : 1;

    # check if log already open
    if(defined $log[$log_index] and length $log[$log_index])
    {
      xLogFlush();
      if($pid == $$)
      {
        xLogWrn("xLog log '$log[$log_index]' reopened as '$filename'");
        xLogClose();
      }
      else
      {
        # must have done a fork()
        close STDOUT;
        open (STDOUT, ">&TTYOUT");
        close STDERR;
        open (STDERR, ">&TTYERR");
        close $hLogout;
        undef $hLogout;
        $log[$log_index]            = "";
      }
    }
    $pid = $$;

    # create directory for log file
    my( $file, $path ) = fileparse( $filename );
		eval { mkpath( "$path" ); };
		warn("$@") 	if($@);

    # empty log file
    if ( -f "$filename" ) {
        unlink( "$filename~") if ( -f "$filename~" );
        unless ( rename( "$filename", "$filename~" ) ) {
            xLogErr("unable to empty file '$filename' or '$filename~' (is it currently in use?)");
            return(0);
        }
    }

    # save stdout, stderr
    # set package vars from XLog.pm. We can't use autovivification, because
    # a) old perl on unix doesn't support this; b) open(STDOUT, ">&ttyout") reports error
    eval {
        close TTYOUT;
        open (TTYOUT, ">&STDOUT") or die "failed to dup stdout: $!";
        close TTYERR;
        open (TTYERR, ">&STDERR") or die "failed to dup stderr: $!";
        select TTYERR; $| = 1;
        select TTYOUT; $| = 1;


        # redirect stdout, stderr
        close STDOUT;
        open (STDOUT, ">$filename") or die "failed to redirect stdout: $!";
        close STDERR;
        open (STDERR, ">&STDOUT") or die "failed to redirect stderr: $!";
        select STDERR; $| = 1;
        select STDOUT; $| = 1;

        $hLogout = *LOG;
        close $hLogout if defined(fileno($hLogout));
        open ($hLogout, "<$filename") or die "failed to open log: $!";
    };

    if ( $@ ) {
        xLogErr( $@ );
        # restore stdout and stderr
        close STDOUT;
        open (STDOUT, ">&TTYOUT");
        close STDERR;
        open (STDERR, ">&TTYERR");
        return 0;
        }

    # stash both versions in our package globals
    $log[$log_index]            = $filename;
    $log_console[$log_index]    = $console;

    # log start time
    xLogH1( "starting ($log[$log_index])" ) if (! defined($nostart));

    # log backlog
    xLogFlush();    # Sadly, pre-xLogOpen() stdout/stderr is lost forever

    # return success
    return(1);
}



###=============================================================================

sub xLogClose(;$$)
{
  my( $quiet, $noend ) = @_;
  if(defined $log[$log_index] and length $log[$log_index])
  {
    # mark end of log
    xLogH1( "end ($log[$log_index])" ) if (! defined($noend));

    # close read handle
    close $hLogout;
    undef $hLogout;

    # restore stdout and stderr
    close STDOUT;
    open (STDOUT, ">&TTYOUT");
    close STDERR;
    open (STDERR, ">&TTYERR");

    # clear log vars
    $log[$log_index]            = "";
  }
  else
  {
    xLogWrn("Log was not open, cannot close") unless($quiet);
  }
}

###=============================================================================

sub xLogResume(;$)
{
    my( $quiet ) = @_;
    
    # retrieve both versions in our package globals
    my $filename           = $log[$log_index -1];
    my $console            = $log_console[$log_index -1];

    if($log_index < 1 or $filename !~ m<\w>)
    {
        xLogErr("Log was not paused, xLogResume cannot continue") unless($quiet);
        return 0;
    }

    $xgLogConsoleOutput = defined $console ? $console : 1;

    # check if log already open
    if(defined $log[$log_index] and length $log[$log_index])
    {
      xLogFlush();
      if($pid == $$)
      {
        xLogWrn("xLog log '$log[$log_index]' reopened as '$filename'");
        xLogClose();
      }
      else
      {
        # must have done a fork()
        close STDOUT;
        open (STDOUT, ">&TTYOUT");
        close STDERR;
        open (STDERR, ">&TTYERR");
        close $hLogout;
        undef $hLogout;
        $log[$log_index]            = "";
      }
    }
    $pid = $$;

    # flush old output before resuming
    xLogFlush();

    # decriment log index
    $log_index--;

    # create directory for log file
    my( $file, $path ) = fileparse( $filename );
    mkpath( "$path" );

    # save stdout, stderr
    # set package vars from XLog.pm. We can't use autovivification, because
    # a) old perl on unix doesn't support this; b) open(STDOUT, ">&ttyout") reports error
    eval {
        close TTYOUT;
        open (TTYOUT, ">&STDOUT") or die "failed to dup stdout: $!";
        close TTYERR;
        open (TTYERR, ">&STDERR") or die "failed to dup stderr: $!";
        select TTYERR; $| = 1;
        select TTYOUT; $| = 1;


        # redirect stdout, stderr
        close STDOUT;
        open (STDOUT, ">>$filename") or die "failed to redirect stdout: $!";
        close STDERR;
        open (STDERR, ">>&STDOUT") or die "failed to redirect stderr: $!";
        select STDERR; $| = 1;
        select STDOUT; $| = 1;

        $hLogout = *LOG;
        close $hLogout if defined(fileno($hLogout));
        open ($hLogout, "<$filename") or die "failed to open log: $!";
        seek($hLogout, 0, 2);
    };

    if ( $@ ) {
        xLogErr( $@ );
        return 0;
        }

    # print info
    xLogH1( "log resumed ($log[$log_index])" ) unless($quiet);
    
    # return success
    return(1);
}



###=============================================================================

sub xLogPause(;$)
{
    my( $quiet ) = @_;
    
    if(defined $log[$log_index] and length $log[$log_index])
    {
        # print info
        xLogH1( "log paused ($log[$log_index])" ) unless($quiet);
        
        # close read handle
        close $hLogout;
        undef $hLogout;
        
        # restore stdout and stderr
        close STDOUT;
        open (STDOUT, ">&TTYOUT");
        close STDERR;
        open (STDERR, ">&TTYERR");
        
        # bump index and clear log vars
        $log_index++;
        $log[$log_index]            = "";
        $log_console[$log_index]    = 0;
    }
    else
    {
        xLogErr("Log was not open, xLogPause cannot continue") unless($quiet);
        return 0;
    }
}

###=============================================================================
# we expect the log path to have the following format
#   c:\Build\Log\compile\Reporting\CB2_Dev\185\release\win32_x86\fr

sub xLogCloseAndLego(;$) {
    my( $quiet ) = @_;
    my $log;
    my $logdrop;
    my $summary;
    my %env;
    
    # get log
    unless ($log[$log_index] and -f $log[$log_index]) {
        xLogErr("log does not exist") unless($quiet);
        return(0);
    }
    $log = $log[$log_index];
    $log =~ s<\\></>g;
    $logdrop = dirname($log);
    
    # verify log path
    1;
    # set drop path
    1;
    # set component
    ($env{component} = $log) =~ s<^.*?([^/]+)\.log$><$1>;
    # set summary name
    ($summary = $log) =~ s<\.log$><.summary.txt>;
    # summarize log
    xLogPause();
    $env{num_of_errors} = xLogSummarize($log, $summary);
    xLogResume();
    # copy log and summary
    1;
    # talk to lego
    1;
    # close log
    xLogClose();
    
    return(1);
}

###=============================================================================

sub xLog(@)
{
    my @args = @_;
    my $args;
    my $prefix = undef;
    my $final = "\n";
    local $" = "\n";

    # do we send to console?
    my $to_console = shift @args;

    # We don't want to print messages that happen inside BEGIN blocks
    # when the -c flag is on (syntax check)
    return(1) if($^C == 1);

    # flush any pending logfile stuff so that $xgLogVerboseLevel
    # will actually work properly
    xLogFlush($To_console);
    
    # massage output
    # 1. get prefix
    if(
      defined $args[0] and
      $args[0] =~ m<^\s*(debug|info|warning|error|fatal):>i
    ) {
      $prefix = lc $1;
      unless ($args[0] =~ s<^\s*$prefix:\s*(\S)><$1>i) {
        shift @args;
      }
    }
    # 2. make one long sting
    $args = join("", @args);
    # 3. split into array
    @args = split( m<[\012\015]+>, $args);
    # 4. set prefix and final
    if (
      defined $args[0] and
      $args[0] =~ s/^\^//
    )  {
      $prefix = undef;
    }
    if (
      defined $args[-1] and
      $args[-1] =~ s/\$$//
    )  {
      $final = "";
    }
    # 5. add prefix
    if(defined $prefix) {
      my $lp = "$prefix:";
      for my $arg (@args) {
        my $new = sprintf("    %-9s", $lp);
        $arg =~ s<^><$new>;
      }
    }

    # print to logfile
    #   if we have logfilename, write to logfile
    #   if we dont have logfilename, queue for when we get logfilename
    #   but only keep 1000 lines
    if ( defined($hLogout) ) { # stdout has been redirected to logfile
        print "@args$final";
        }
    else {
        push @Backlog, @args;
        while ( $#Backlog > 999 ) {
            shift @Backlog;
            }
        }

    # print to STDOUT
    xLogFlush($to_console);
    unless ( defined($hLogout) and defined(fileno($hLogout)) ) {
        print "@args$final"
            if($to_console and $xgLogConsoleOutput);
    }
    
}

###=============================================================================

sub xLogFlush(;$)
{
    my($to_console) = @_;
    
    unless( defined $to_console ) {
        # write backlog to file if have filename now
        if ( defined($hLogout) and defined(fileno($hLogout)) ) {
            print "$_\n" foreach ( @Backlog );
        }
        @Backlog = ();
    }

    # flush any pending stdout/stderr in log file
    $to_console = $To_console unless(defined $to_console);
    if ( defined($hLogout) and defined(fileno($hLogout)) ) {
        if($xgLogConsoleOutput and $to_console) {
            print TTYOUT (<$hLogout>);
        }
        else {
            seek($hLogout, 0, 2);
        }
    }

}

###=============================================================================

sub xNow()
{
    my( @n );
    my( $t );
    my( $d );

    # get current date and time
    @n = localtime( time );

    # put together time string
    if ($n[2] < 10) {
        $t = "0" . $n[2] . ":" ;
        }
    else {
        $t = $n[2] . ":" ;
        }

    if ($n[1] < 10) {
        $t = $t . "0" . $n[1] . ":" ;
        }
    else {
        $t = $t. $n[1] . ":" ;
        }

    if ($n[0] < 10) {
        $t = $t . "0" . $n[0];
        }
    else {
        $t = $t . $n[0];
        }

    # put together date string

    # add day
    if ($n[3]<10) {
        $d = "/0" . $n[3];
        }
    else {
        $d = "/" . $n[3];
        }

    # add month
    if ($n[4] < 9) {
        $d = "/0" . ($n[4]+1) . $d;
        }
    else {
        $d = "/" . ($n[4]+1) . $d;
        }

    #add year
    $d = (1900  + $n[5]) . $d;

    # return value
    ( $t, $d );
}



###=============================================================================

sub xLogH($$)
{
    my( $pre, $sz ) = @_;

    $sz =~ s/\s+$//;

    my( $sTime, $sDate ) = xNow();

    xLog( 1, "" );
    xLog( 1, $pre, $sz, " at $sTime on $sDate" );
}



###=============================================================================

sub xLogH1($)
{
    my( $sz ) = @_;
    xLogH( "====", $sz );
}



###=============================================================================

sub xLogH2($)
{
    my( $sz ) = @_;
    xLogH( "  ==", $sz );
}



###=============================================================================

sub xLogFatal(@)
{
    xLog( 1, "    fatal:   ", @_ );

    if($xgLogStackTrace >= 0)
    {
      my $i = 1; # the first call stack will be us... ignore
      my ( $pack, $file, $line, $subname, $hasargs, $wantarray );
      while(( $pack,$file,$line,$subname,$hasargs,$wantarray ) = caller($i++)) {
        xLog( 1, "    fatal:   ","   called by: $subname in file: $file, line: $line" );
      }
    }
    XLogging::xLogClose(1);
    exit(1);
}

###=============================================================================

sub xLogErr(@)
{
    {
      local $" = "";
      $xgLogLastError = "@_";
    }
    $xgLogErrCount++;

    xLog( 1, "    error:   ", @_ );

    if($xgLogStackTrace > 0)
    {
      my $i = 1; # the first call stack will be us... ignore
      my ( $pack, $file, $line, $subname, $hasargs, $wantarray );
      while(( $pack,$file,$line,$subname,$hasargs,$wantarray ) = caller($i++)) {
        xLog( 1, "    error:   ","   called by: $subname in file: $file, line: $line" );
      }
    }
}



###=============================================================================

sub xLogWrn(@)
{
    xLog( 1, "    warning: ", @_ );
}



###=============================================================================

sub xLogInf(@)
{
    my $to_console = shift @_;
    
    # print the output
    #

    if ( ( $#_ == -1 ) ||
         ( ($#_ == 0 ) && ($_[0] eq "") ) ) {
        xLog( $to_console, "" );
        }
    else {
        xLog( $to_console, "    info:    ", @_ );
        }

    $To_console = $to_console;
}



###=============================================================================

sub xLogInf1(@)
{
    my $to_console = ( 1 <=  $xgLogVerboseLevel ) ? 1 : 0;
    xLogInf($to_console, @_ );
}



###=============================================================================

sub xLogInf2(@)
{
    my $to_console = ( 2 <= $xgLogVerboseLevel ) ? 1 : 0;
    xLogInf( $to_console, @_ );
}



###=============================================================================

sub xLogInf3(@)
{
    my $to_console = ( 3 <= $xgLogVerboseLevel ) ? 1 : 0;
    xLogInf( $to_console, @_ );
}

###=============================================================================

sub xLogDbg(@)
{
    return() if(!$xgLogDebug);

    # no args or one arg eq "", print blank line
    if ( ( $#_ == -1 ) ||
         ( ($#_ == 0 ) && ($_[0] eq "") ) ) {
        xLog( 1, "" );
        }
    else {
        xLog( 1, "    debug:    ", @_ );
        }
}

###=============================================================================

# $rFilter the second arg is a reference to a function which is called once
# for each line in the log file.  Its one arg is a reference to the line, so
# the filter function can rearrange it if desired.  The filter func must 
# return one of the following strings err, wrn, inf1, inf2, inf3, raw, or ''.  
# This determines which xLog* func is actually used to write the line to the log.

sub xLogFile($$$)
{
    my( $filename, $rFilter, $rError ) = @_;
    local *IN;

    if ( ! open( IN, $filename ) ) {
#       xLogWrn( "cannot open file to copy to log '$filename'" );
        return;
    }

    if ( 'CODE' ne ref $rFilter ) {
        xLogErr( "invalid filter for log file '$filename'" );
        close( IN );
        return;
    }

    # we set $$rError to 0 or 1
    # 1 indicates that an error was detected in the log file
    # detection is left to the filter function
    $$rError = 0;

    my %sub_table = (
        'err'   =>  \&xLogErr,
        'wrn'   =>  \&xLogWrn,
        'inf1'  =>  \&xLogInf1,
        'inf2'  =>  \&xLogInf2,
        'inf3'  =>  \&xLogInf3,
        'dbg'   =>  \&xLogDbg,
	'raw'   =>  \&xLogRaw,
        );

    while ( defined( my $line = <IN> ) ) {
        chomp( $line );
        my $type = lc &$rFilter( \$line );
        if ( $type ne 'raw' ) {
            next if ( $line =~ /^\s*$/ );
            $line =~ s/^\s+//;
            $line =~ s/\s+$//;
        }
        next if ( '' eq $type );
        if ( 'err' eq $type ) {
            $$rError = 1;
        }
        my $rLogSub = $sub_table{$type};
        if ( ! defined( $rLogSub ) ) {
            $rLogSub = $sub_table{'inf1'};
        }

        &$rLogSub( $line );
    }

    close( IN );

    unlink $filename;
}



###=============================================================================

sub xLogFileErr($)
{
    my( $filename ) = @_;
    my $filter = sub { return 'err'; };
    my $error;
    xLogFile( $filename, $filter, \$error );
}



###=============================================================================

sub xLogFileWrn($)
{
    my( $filename ) = @_;
    my $filter = sub { return 'wrn'; };
    my $error;
    xLogFile( $filename, $filter, \$error );
}



###=============================================================================

sub xLogFileInf1($)
{
    my( $filename ) = @_;
    my $filter = sub { return 'inf1'; };
    my $error;
    xLogFile( $filename, $filter, \$error );
}



###=============================================================================

sub xLogFileInf2($)
{
    my( $filename ) = @_;
    my $filter = sub { return 'inf2'; };
    my $error;
    xLogFile( $filename, $filter, \$error );
}



###=============================================================================

sub xLogFileInf3($)
{
    my( $filename ) = @_;
    my $filter = sub { return 'inf3'; };
    my $error;
    xLogFile( $filename, $filter, \$error );
}

###=============================================================================

sub xLogRunDetached($)
{
    my ($cmd) = @_;
    my $ok = 1; # optimistic
    my $nul = $^O eq 'MSWin32' ? 'NUL:' : '/dev/null';

    require Proc::Background;
    
    xLogInf2("Running as detached process: $cmd");
    $cmd =~ s/~/$ENV{HOME}/g  if ( $^O ne 'MSWin32' );
    $cmd =~ s/&\s*$//; # ignore tailing '&'
    my @cmds;
    split_command($cmd, \@cmds);
    $cmds[0] = Proc::Background::_resolve_path($cmds[0]);
    
    # Windows
    if ( $^O eq 'MSWin32' ) {
        require Win32::Process;
        
        local (*TTYIN, *TTYOUT, *TTYERR);
        # save
        open (TTYIN, "<&STDIN");
        open (TTYOUT, ">&STDOUT");
        open (TTYERR, ">&STDERR");
        # redirect
        close STDIN;
        open (STDIN, "<$nul")     or xLogErr("failed to open $nul");
        close STDOUT;
        open (STDOUT, ">$nul") or xLogErr("failed to open $nul");
        close STDERR;
        open (STDERR, ">&STDOUT");
        # run cmd
        my $os_obj = 0;
        Win32::Process::Create(
            $os_obj,
            $cmds[0],
            "@cmds",
            0,
            Win32::Process::NORMAL_PRIORITY_CLASS() | 
            Win32::Process::CREATE_NEW_PROCESS_GROUP() |
            Win32::Process::DETACHED_PROCESS(),
            'c:\\'
        );
        # restore
        close STDIN;
        open (STDIN, "<&TTYIN");
        close STDOUT;
        open (STDOUT, ">&TTYOUT");
        close STDERR;
        open (STDERR, ">&TTYERR");
    }
    # Unix
    else {
        # Default daemon parameters.
        my $UMASK = 0;
        my $WORKDIR = "/";
        
        my $pid = fork();
        if( !defined $pid ) {
            xLogErr("fork failed");
            return(0);
        }
        elsif ($pid == 0) {        # The first child.
            setsid();
            $SIG{'HUP'} = 'IGNORE';
            my $pid2 = fork();        # Fork a second child.
            if (! defined $pid2) {
                xLogErr("fork failed");
                return(0);
            }
            elsif ($pid2 == 0) {        # The second child.
                chdir($WORKDIR);
                umask($UMASK);
                close(STDIN);
                open (STDIN,  "<", $nul);
                close(STDOUT);
                open (STDOUT, ">", $nul);
                close(STDERR);
                open (STDERR, ">", $nul);
                exec(@cmds);
            }
            else {
                _exit(0);        # Exit parent (the first child) of the second child.
            }
        }
    }
    
    return($ok);
}

###=============================================================================

sub xLogRunBg($;\@\@\$$$)
{
    my ($cmd , $rATestTokens, $rResults, $rOk, $quiet, $timeout) = @_;
    my $ok = 1; # optimistic
    
    require Proc::Background;
    
    # have we reached the max bg job limit?
    if ($xgLogBackgroundJobMax) {
        while(keys(%BackgroundJobInpg) >= $xgLogBackgroundJobMax) {
            xLogInf1("have reached max bg jobs, waiting for a free slot");
            xLogRunHarvest(1);
        }
    }

    # load up %BackgroundJobInpg hash
    $BackgroundJobCntr++;
    my $job = time() . "-$BackgroundJobCntr-$$.job" ; # uniqe id
    my $output = File::Spec->catfile($Tmpdir, $job);
    my $proc_obj;
    unlink($output);
    $BackgroundJobInpg{$job}{cmd} = $cmd;
    $BackgroundJobInpg{$job}{tokens} = $rATestTokens;
    $BackgroundJobInpg{$job}{results} = $rResults;
    $BackgroundJobInpg{$job}{quiet} = $quiet;
    $BackgroundJobInpg{$job}{ok} = $rOk;
    $BackgroundJobInpg{$job}{output} = $output; # log filename
    $BackgroundJobInpg{$job}{start} = time();
    $BackgroundJobInpg{$job}{timeout} = $timeout;
    xLogInf2("Running in background: $cmd") unless(defined $quiet and $quiet > 1);
    #
    $cmd =~ s/~/$ENV{HOME}/g  if ( $^O ne 'MSWin32' );
    $cmd =~ s/&\s*$//; # ignore tailing '&'
    my $die_upon_destroy = {'die_upon_destroy' => 0};
    my @cmds;
    split_command($cmd, \@cmds);
    local (*TTYIN, *TTYOUT, *TTYERR);
    my $nul = $^O eq 'MSWin32' ? 'NUL:' : '/dev/null';
    # save
    open (TTYIN, "<&STDIN");
    open (TTYOUT, ">&STDOUT");
    open (TTYERR, ">&STDERR");
    # redirect
    close STDIN;
    open (STDIN, "<$nul")     or xLogErr("failed to open $nul");
    close STDOUT;
    open (STDOUT, ">$output") or xLogErr("failed to open $output");
    close STDERR;
    open (STDERR, ">&STDOUT");
    # hot pipeing
    select(STDERR); $| = 1;
    select(STDOUT); $| = 1;
    # run cmd
    if ( @cmds == 1 and $^O eq 'MSWin32' ) {
        # run under shell
        @cmds = ($ENV{ComSpec}, "/q", "/d", "/c", "@cmds");
        $proc_obj = Proc::Background->new($die_upon_destroy, @cmds);
    }
    else {
        $proc_obj = Proc::Background->new($die_upon_destroy, @cmds);
    }
    # restore
    close STDIN;
    open (STDIN, "<&TTYIN");
    close STDOUT;
    open (STDOUT, ">&TTYOUT");
    close STDERR;
    open (STDERR, ">&TTYERR");
    if ( ! defined($proc_obj) ) {
        # we will let harvest catch it
        $ok = 0;
    }
    else {
        $BackgroundJobInpg{$job}{obj} = $proc_obj;
    }
    #
    return($ok ? $job : 0);
}

###=============================================================================

sub xLogRunAbort() {
    for my $job (keys %BackgroundJobInpg) {
        my $cmd = $BackgroundJobInpg{$job}{cmd};
        my $job_obj = $BackgroundJobInpg{$job}{obj};
        if ( defined($job_obj) ) {
            next if ( !$job_obj->alive );
            $job_obj->die;
            xLogInf1("aborted bg job : $cmd");
        }
    }
    continue {
        delete $BackgroundJobInpg{$job};
    }
    
    return(1);
}

###=============================================================================

sub print_output($$$$$) {
    my($rFh,  $rTokens, $rResults, $rOk, $quiet) = @_;
    my $line;
    local *FH = *$rFh;
    
    @$rResults = ();
    while($line = <FH>) {
        $line =~ s<[\012\015]+$><>;
        push(@$rResults, $line);
        next if ($line =~ /^\s*$/);
        # all out is ok so we preserve 'error:' from child
        if (@$rTokens == 1 and $$rTokens[0] eq '.') {
            # preformatted, print as is
            if ($line =~ /^    (debug|info|warning|error|fatal): |^(?:  |==)==.* at \d\d:\d\d:\d\d on /) {
                my $level = $1 || "";
                if($quiet) {
                    xLogDbg($line) unless(defined $quiet and $quiet > 1);
                }
                else {
                    print("$line\n");
                    $$rOk = 0 if($level eq 'error' or $level eq 'fatal');
                }
            }
            # unformatted
            else {
                # look for errors
                if ( $line =~ /^\s*(error|fatal|fatal error):/i ) {
                    $$rOk = 0;
                    xLogErr($line) unless(defined $quiet and $quiet > 1);
                }
                # must be ok
                else {
                    if($quiet) {
                        xLogDbg($line) unless(defined $quiet and $quiet > 1);
                    }
                    else {
                        xLogInf3($line);
                    }
                }
            }
        }
        # only certain output is ok
        elsif ( grep { $line =~ /$_/i} @$rTokens ) {
            if($quiet) {
                xLogDbg($line) unless(defined $quiet and $quiet > 1);
            }
            else {
                xLogInf3($line);
            }
        }
        # bad output
        else {
            $$rOk = 0;
            xLogErr($line) unless(defined $quiet and $quiet > 1);
        }
    }
    
    return(1);
}

###=============================================================================

sub xLogRunHarvest(;$$)
{
    my($onlyone, $id) = @_;
    my $ok;
    my $code;
    my (@atesttokens, @results);
    my $deleted = 0;

    # do only one?
    if ($onlyone and !$xgLogBackgroundJobMax) {
        # should never get here
        return(1);
    }
    
    # harvest newly completed jobs
    while (%BackgroundJobInpg) {
        my @jobs;
        # id given
        if($id) {
            @jobs = ($id);
        }
        else {
            @jobs = keys %BackgroundJobInpg;
        }
        # loop over jobs
        foreach my $job ( @jobs ) {
            # look at proc
            $ok = 1; # optimistic
            my $cmd = $BackgroundJobInpg{$job}{cmd};
            my $job_obj = $BackgroundJobInpg{$job}{obj};
            if ( !defined($job_obj) ) {
                $code = 1;
            }
            else {
                if ( $job_obj->alive ) {
                    my $start = $BackgroundJobInpg{$job}{start};
                    my $timeout = $BackgroundJobInpg{$job}{timeout};
                    if( $timeout and ( time - $start > ($timeout * 60) ) ) {
                        xLogErr("timeout on $cmd");
                        $job_obj->die;
                        $code = 1;
                    }
                    else {
                        # let it run some more
                        next;
                    }
                }
                else {
                $code = $job_obj->wait; # we do not >> 8 so that we see singal deaths
                }
            }
            my $rATestTokens = $BackgroundJobInpg{$job}{tokens};
            my $rResults = $BackgroundJobInpg{$job}{results};
            my $quiet = $BackgroundJobInpg{$job}{quiet};
            my $rOk = $BackgroundJobInpg{$job}{ok};
            my $output = $BackgroundJobInpg{$job}{output};
            if (defined $rATestTokens) {
                @atesttokens = @$rATestTokens;
            }
            else {
                # assume all output is good
                @atesttokens = ('.');
            }
            # read output file
            local *BG;
            open(BG, $output);
            $ok = $code == 0 ? 1 : 0;
            xLogInf2("Output from: $cmd") if(@results and !$quiet);
            print_output(\*BG,  \@atesttokens, \@results, \$ok, $quiet);
            close(BG);
            unlink($output);
            @$rResults = @results if(defined $rResults);
            $$rOk = $ok if(defined $rOk);
            if ($ok) {
                xLogInf3("command succeeded (code=$code): $cmd") unless($quiet);
            }
            else {
                xLogErr("command failed (code=$code): $cmd") unless(defined $quiet and $quiet > 1);
            }

            delete $BackgroundJobInpg{$job};
            $deleted++;
        }
        # id given
        if($id and $deleted) {
            last;
        }
        # only one
        if(
            ( defined($onlyone) ) and
            ( $onlyone ) and
            ( $deleted > ($xgLogBackgroundJobMax / 2) )
        ) {
            last;
        }
        # sleep
        sleep(1) if(%BackgroundJobInpg);
    }

    # always return success
    $ok = 1;

    return($ok);
}

###=============================================================================

# $quiet: 0 = verbose, 1 = quiet unless error, 2 = silent

sub xLogRun($;\@\@$)
{
    my ($cmd , $rATestTokens, $rResults, $quiet) = @_;
    my (@atesttokens, @results);
    my $ok = 1; # optimistic
    my $code;
    local(*CMDOUT);

    if (defined $rATestTokens) {
        @atesttokens = @$rATestTokens;
    }
    else {
        # assume all output is good
        @atesttokens = ('.');
    }

    if( $cmd !~ m/\s+2\>\s*\S/ ) {
      $cmd .= " 2>&1";
    }
    xLogInf2("Running: $cmd") unless(defined $quiet and $quiet > 1);
    if ( open(CMDOUT, "$cmd|") ) {
        print_output(\*CMDOUT, \@atesttokens, \@results, \$ok, $quiet);
    }
    else {
        $ok = 0;
    }
    close(CMDOUT) if( defined(fileno(CMDOUT)) );
    $code = $?; # we do not >> 8 so that we see singal deaths
    $ok *= $code == 0 ? 1 : 0;

    if ($ok) {
        xLogInf3("command succeeded (code=$code): $cmd") unless($quiet);
    }
    else {
        xLogErr("command failed (code=$code): $cmd") unless(defined $quiet and $quiet > 1);
    }

    # return
    @$rResults = @results if(defined $rResults);
    return $ok;
}



###=============================================================================

sub xLogRaw(@)
{
    xLog(0, @_);
}



###=============================================================================

# Summarize
# Create a log summary file
# ARGUMENTS:
# - path of input log file
# - path of output summary file
# - minimum error level to include in summary (0 = errors, 1 = warnings)
# - test tokens = strings to ignore
# - results array reference <-- output paramater
# - send mail (0 = never, 1 = on errors, 2 = always)
# - subject for SendMail
# RETURN:
# - number of errors found
#
# FUTURE:
# - talk to lego option
# - post log and summary to $LOGFILES_SERVER option
# - have sSimplePlus.pl just call this subroutine
sub xLogSummarize($$;$\@\@$$)
{
    my ($input, $outfile, $errorlevel, $rATestTokens, $rResults, $mail, $subject)  = @_;
    my @infileList;
    my @atesttokens;
    local *IN;
    local *OUT;

    if (defined $rATestTokens) {
        @atesttokens = @$rATestTokens;
    }
    else {
        # assume all output is good
        @atesttokens = ();
    }

    if (! defined $errorlevel) {
        $errorlevel = 0;
    }
    if (! defined $mail) {
        $mail = 0;
    }
    if (! defined $subject) {
        $subject = basename($input) . " summary";
    }

    if ( -f $input ) {
        push @infileList, $input;
    }
    elsif ( -d $input ) {
        opendir( DIR, $input );
        my $file;
        while( $file = readdir( DIR ) ) {
            if ( -f "$input\\$file" ) {
                push @infileList, "$input\\$file";
            }
        }
        closedir DIR;
    }
    elsif ( $input =~ /\*/ ) {
        if ( $input =~ / / ) {
            $input = "'" . $input . "'";
        }
        push @infileList, glob( $input );
    }
    else {
        print "    error: unable to find file $input\n";
        return 1;
    }

    my @inlines;
    my $inline;
    my @outlines;
    my $outline;

    foreach my $infile ( @infileList ) {

        if ( ! open( IN, $infile ) ) {
            print "    error: unable to open file $infile\n";
            next;
        }
        push @inlines, "--------file: $infile--------";
        while ( $inline = <IN> ) {
            $inline =~ s<\s+$><>;
            push @inlines, $inline;
        }
        close( IN );
    }

    chomp @inlines;

    my $numError = dosummarize( $errorlevel, \@inlines, \@outlines, \@atesttokens );

    if ( ! open( OUT, ">$outfile" ) ) {
        print "    error: unable to open file $outfile\n";
        return 1;
    }

    for my $outline ( @outlines ) {
        print OUT "$outline\n";
    }

    close( OUT );

    # Send mail
    #
    if ( ($mail == 2) or ($mail == 1 and $numError) ) {
        my $message = join ("\n", @outlines);
        send_mail($subject, $message);
    }

    # Return number of errors
    #
    @$rResults = @outlines if(defined $rResults);
    return $numError;
}

###=============================================================================

sub dosummarize($$$$)
{
    my( $errorlevel, $rIn, $rOut, $rATestTokens ) = @_;

    my $numError = 0;

    my $logline;
    my $i = 0;

    my $lastheadingread = "";        # last heading read from log file
    my $lastheadingwrote = "";       # last heading wrote to summary log

    while ( $i <= $#$rIn ) {

        $logline = $rIn->[$i];
        ++ $i;

        if ( $logline =~ /^\s*$/ ) {
            # ignore blank lines
            next;
        }

        if ( $logline =~ /^    info:.*variable computername/i ) {
            # output the computername
            push @$rOut, $logline;
            next;
        }

        if ( $logline =~ /^    info:/i ) {
            # ignore these
            # (even if they have error keyword)
            next;
        }

        if ( $logline =~ /^    error: +called by:/ ) {
            # ignore stack trace message
            next;
        }

        if ( grep { $logline =~ /$_/i} @$rATestTokens ) {
            # ignore test token lines
            next;
        }

        if ( $logline =~ /^--------file:/ ) {
            push @$rOut, $logline;
            next;
        }

        if ( $logline =~ /^\s*==/ ) {
            $lastheadingread = $logline;
            if ( $logline =~ /^\s*====/ ) {
                # always output Heading1's
                push @$rOut, $lastheadingread;
                $lastheadingwrote = $lastheadingread;
            }
            next;
        }

        # error case
        if ( $logline =~ /^\s*(error|fatal|fatal error):/i ) {
            if ( $lastheadingread ne $lastheadingwrote ) {
                push @$rOut, $lastheadingread;
                $lastheadingwrote = $lastheadingread;
            }
            push @$rOut, $logline;
            ++ $numError;
            next;
        }

        # warn case
        if ( ($logline =~ /^    warning:/) && ($errorlevel >= 1)  ) {
            if ( $lastheadingread ne $lastheadingwrote ) {
                push @$rOut, $lastheadingread;
                $lastheadingwrote = $lastheadingread;
            }
            push @$rOut, $logline;
            next;
        }
    }

    unshift @$rOut, "  errors: $numError";

    return $numError;
}

###=============================================================================

sub split_command($$;$) {
    my ($command, $commands, $simple) = @_;
    while (1) {
        if ( $command =~ s/^\s*"(.+?)"\s*// ) { # split on double quote
            push @$commands, $1;
        }
        elsif ( $command =~ s/^\s*(\S+)\s*// ) { # split on space
            push @$commands, $1;
        }
        elsif ( $command =~ /^$/ ) {
            last;
        }
        else {
            xLogErr("program error: command = $command");
            last;
        }
    }
    return 1 if( $simple );
    # Background module doesn't recognize .pl as an executable
    if ( $$commands[0] =~ /\.pl$/i ) {
        unshift @$commands, "perl";
    }
    # Proc::Background::Win32 module's new method split single argument on whitespace
    # This is a workaround to avoid that splitting
    if ( $^O eq 'MSWin32' and @$commands == 1 and $$commands[0] =~ /\s/ ) {
        require Win32;
        my $cmd = Win32::GetShortPathName($$commands[0]);
        $$commands[0] = $cmd if( defined($cmd) and length($cmd) );
    }
    return 1;
}

###=============================================================================

sub send_mail($$) {
    my ($subject, $msg) = @_;
    my %mail;
    my $login_name = getlogin() || getpwuid($<);
    my $host_name = hostname();
    my $program_name = basename($0);
    
    require Mail::Sendmail;
    
    $mail{To}   = $ENV{SMTP_TO} || "pgqosgeormops\@businessobjects.com";
    $mail{From} = $ENV{SMTP_FROM} || "$login_name\@$host_name";
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
    $mail{Subject} = "$program_name message: $subject";
    $mail{Message} = $msg;
    if ($subject =~ m<\b(error|fatal|abort|fail):>i) {
        $mail{Importance} = "high";
    }
    xLogInf1("Sending mail: $mail{Subject}");
    if ( ! Mail::Sendmail::sendmail(%mail) ) {
        xLogErr( "mail: sendmail failed: $Mail::Sendmail::error" );
    }
    
    return(1);
}

###=============================================================================

END {
    for my $job (keys %BackgroundJobInpg) {
        my $cmd = $BackgroundJobInpg{$job}{cmd};
        xLogInf1("job will continue as orphaned process: $cmd");
    }
}

###=============================================================================

# return success for "use"
1;
