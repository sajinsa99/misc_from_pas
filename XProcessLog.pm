#!/usr/bin/perl
#
# Name:     XProcessLog.pm
# Purpose:  Functions for processing build log files. This includes summarization and submitting the results to
#           reporting system.
# Notes:
# Future:   Add infrastructure and package support
#
package XProcessLog;

use Date::Calc(qw(Today_and_Now Delta_DHMS));

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION = sprintf "%d.000", q$Revision: #3 $ =~ /(\d+)/g;

    @ISA         = qw(Exporter);

    # your exported package globals go here,
    @EXPORT      = qw(&processlog);

    # collections of exported globals go here
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

    # any optionally exported functions go here
    @EXPORT_OK   = qw();
    
	my $REModule = $ENV{RE_MODULE} || "XProcessLogRE.pm";
	die("ERROR: coulldn't load '$REModule': $@") unless(eval(require $REModule));	
}
our @EXPORT_OK;

# base
use File::Basename;
use File::Spec;
use File::Path;
use File::Copy;
use Sys::Hostname;
use FindBin ();
use Net::SMTP;

# site
use LWP::UserAgent;
# local
use XLogging;

# pragmas
use strict;
use warnings;

# global variables
my $CURRENTDIR = "$FindBin::Bin";
my $BUILD_BEGIN;
my $BUILD_END;
my $BUILD_START;
my $BUILD_STOP;
my ($HOSTNAME) = split( /\./, hostname() );
my $SMTP_SERVER = $ENV{SMTP_SERVER} || "mail.sap.corp";
my $SMTP_FROM = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
my $CIS_HOST="cis-dashboard.wdf.sap.corp";

# sub declarations
sub processlog($$;$$);
sub summarizelog($$;$$);
sub updatebuildreporting($$$);
sub copylogtoserver(%);
sub createserverlogpath(%);
sub detectheadingline($$);
sub detecterrorline($$);
sub trim($);

###=============================================================================
# This is the entry point to the module from the .pl wrapper
# Arguments:
# - array containing the command line arguments
#
sub main(@) {
    my $submit = 0;
    my $bRealErrorCount=0;
    my $log_file=undef;

    if (! @_ ) {
        usage();
    }
    foreach my $CurrentArg(@_)
    {
	    if ( $CurrentArg eq '-submit' )
	    {
	        $submit = 1;
	    }
	    elsif($CurrentArg eq '-real')
	    {
	    	$bRealErrorCount = 1;
	    }
	    else
	    {
	        $log_file = $CurrentArg;
	    }
    }

    # check log file
    if (! defined $log_file ) {
        usage();
    }
    if (! -f $log_file ) {
        print "Unable to open log file: $log_file \n";
        usage();
    }

    processlog($submit, $log_file, $bRealErrorCount);
}

###=============================================================================
# Display usage information
#
sub usage() {
    print "Usage:\n";
    print "$0 [-submit] [-real] <logfile path>/<build unit name>.log \n";
    exit 1;
}

###=============================================================================
# Start processing the logfile
# Arguments:
# - boolean indicating whether to submit results to Lego
# - string containing path of log file
# Return:
# - boolean indicating success
#
sub processlog($$;$$) {
    my($submit, $log_file, $bRealErrorCount, $raBuildresults) = @_;
    my $log_dir;
    my $summary_file;
    my $unit_name;
    my $err_count;

    # init time variables
    $BUILD_START = 0;
    $BUILD_STOP = time();

    # generate summary path
    {
        $unit_name = basename( $log_file );
        $log_dir = dirname( $log_file );
        if ( $unit_name =~ /\.log$/ ) {
            $unit_name =~ s/\.log$//;
        }
        else {
            print "Error: log file name expected to have .log extension";
            return 0;
        }
        $summary_file = File::Spec->catfile( $log_dir, ${unit_name}.'.summary.txt' );
    }

    # call_summarize_log:
    my @buildresults;
    {
        $err_count = summarizelog ( $log_file, $summary_file, $bRealErrorCount, $unit_name);
        if ( $err_count < 0 ) {
            return;
        }
        push (@buildresults, "\n\n=+=Summary log file created: $summary_file\n");
        push (@buildresults, "=+=Area: $ENV{area}\n") if ( defined $ENV{area} );
        push (@buildresults, "=+=Order: $ENV{order}\n") if ( defined $ENV{order} );
        push (@buildresults, "=+=Start: $BUILD_START\n");
        push (@buildresults, "=+=Stop: $BUILD_STOP\n");
        push (@buildresults, "=+=Errors detected: $err_count\n");
        foreach my $buildresult (@buildresults) {print $buildresult};
    }

    #call_update_build_reporting:
    {
        updatebuildreporting($err_count, $unit_name, $log_dir) if ( $submit );
    }

    @$raBuildresults = @buildresults;

	if(defined $ENV{build_steptype} && $ENV{build_steptype} eq "step")
	{
        # RSS feed for each step
        if($ENV{BUILD_CIS_DASHBOARD_ENABLE})
        {
            if(open(XML, ">$ENV{HTTP_DIR}/$ENV{context}/$ENV{context}_$ENV{build_stepname}_$ENV{PLATFORM}_$ENV{BUILD_MODE}.rss.xml"))
            {
                print(XML "<?xml version=\"1.0\" encoding=\"ISO-8859-1\" ?>
                <?xml-stylesheet type=\"text/xsl\" href=\"https://$CIS_HOST/htdocs/rss.xsl\" ?>
                <rss version=\"2.0\">
                  <channel>
                    <title>$ENV{BUILD_NAME} $ENV{build_stepname} $ENV{PLATFORM} $ENV{BUILD_MODE}</title>
                    <link>https://$CIS_HOST/cgi-bin/CIS.pl?tag=$ENV{BUILD_NAME}&amp;streams=$ENV{context}</link>
                    <description>$ENV{context} $ENV{BUILD_NAME} $ENV{build_stepname} $ENV{PLATFORM} $ENV{BUILD_MODE}</description>
                    <item>
                      <title>$ENV{BUILD_NAME} $ENV{build_stepname} $ENV{PLATFORM} $ENV{BUILD_MODE} ", scalar(gmtime(time())), " GMT</title>
                      <link>https://$CIS_HOST/cgi-bin/CISReleaseNotes.pl?tag=$ENV{BUILD_NAME}&amp;project=$ENV{PROJECT}&amp;stream=$ENV{context}</link>
                      <description>The build $ENV{BUILD_NAME} just finished the step $ENV{build_stepname} on $ENV{PLATFORM} platform, more details please refer to Release Notes</description>
                      <pubDate>", scalar(gmtime(time())), " GMT</pubDate>
                    </item>
                  </channel>
                </rss>
                ");
                close(XML);
            }
            else { warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{context}_$ENV{build_stepname}_$ENV{PLATFORM}_$ENV{BUILD_MODE}.rss.xml': $!") }
        }

        # Mailing
		if(exists($ENV{"SMTPTO_$ENV{context}_$ENV{build_stepname}_$ENV{PLATFORM}_$ENV{BUILD_MODE}"}) and (!exists($ENV{SMTPTO_ERROR_ONLY}) or $ENV{SMTPTO_ERROR_ONLY}==0 or $err_count))
		{
			my $SMTPTO = $ENV{"SMTPTO_$ENV{context}_$ENV{build_stepname}_$ENV{PLATFORM}_$ENV{BUILD_MODE}"};
			my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>60) or die("ERROR: SMTP connection impossible: $!");
			$smtp->mail('julian.oprea@sap.com');
			$smtp->to(split('\s*;\s*', $SMTPTO));
			$smtp->data();
			$smtp->datasend("To: $SMTPTO\n");
			$smtp->datasend("Subject: [$ENV{context}] the step $ENV{build_stepname} is finished for $ENV{BUILD_NAME} in $ENV{PLATFORM} $ENV{BUILD_MODE}\n");
			$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
			$smtp->datasend("<html><body>");
			$smtp->datasend(($err_count?"they are $err_count errors":"no issue")."<br/><br/>");
			$smtp->datasend("<a href='https://$CIS_HOST/cgi-bin/CIS.pl?tag=$ENV{BUILD_NAME}&amp;streams=$ENV{context}'>see dashboard</a>"); 
			$smtp->datasend("</body></html>"); 
			$smtp->dataend();
			$smtp->quit();			
		}
	}

    return(1);
}

###=============================================================================
# Summarize log file
# The number of errors reported is: the number of sections containing errors lines.
# Each section is seperated by a detected heading.
# Arguments:
# - path of log file
# - path of summary file
#
sub summarizelog($$;$$)
{
    my ($infile, $outfile, $bRealErrorCount, $unit_name) = @_;
    my @outlines;
    my $curline;
    my $errcount = 0;
    my $nSectionsWithErrors=0;
    my $linenum = 0;
    my $errorafterheading = 0;      # has an error line been detected after the last heading?
    my $currentheading = "";
    # what compiler is this (gcc, javac, cl.exe, ...)
    my $language = "default";  # cwp - this needs to be set somehow
    my %ignoreheadingcount = ( # if $ENV{rmbuild_type} contains one of this entry, so all found errors will be computed, instead of adding only one by head sections
        'Dependencies' => undef
    );
    my(@emailRecipient,@errorLines);

    my @StartSummarize = Today_and_Now();

    # read input log
    if ( ! open( IN, "<$infile" ) ) {
        print "Error: Unable to open file for read: $infile\n";
        return -1;
    }

    # detect lines with error
    while($curline = <IN>)
    {
        $linenum++;

        # detect build start time
        if ( $curline =~ m/=+\s*Build start: (\d+)/i ) {
            $BUILD_START = $1;
            next;
        }

        if ( $curline =~ m/=+\s*Build stop: (\d+)/i ) {
            $BUILD_STOP = $1;
            next;
        }

        if ( my $detectedResult = detecterrorline( $curline, $language ) ) {
            # only increment errcount once per section
            if (! $errorafterheading  || (defined $bRealErrorCount && $bRealErrorCount==1) || (exists $ENV{rmbuild_type} && exists $ignoreheadingcount{$ENV{rmbuild_type}})) {
                $errcount++;
                # only print the heading once for each section with errors
                if (! $errorafterheading  )
                {
                    $nSectionsWithErrors++;
                    push @outlines, "\n";
                    push @outlines, $currentheading;
		        }
                $errorafterheading = 1 unless($curline =~ /\[sapLevel:/);
            }
            push @outlines, '[ERROR @'.$linenum."] $curline";

            if($detectedResult->[1]) {
	            push(@emailRecipient,@{$detectedResult->[1]});
	            push(@errorLines,$curline) if($curline);
            }            
            if($detectedResult->[0])
            {
                while($curline = <IN>)
                {
                    $linenum++;
                    push(@outlines, "[INFO  \@$linenum] $curline");
                    last if($curline =~ $detectedResult->[0]);
                }
            }
        }
        elsif ( detectheadingline( $curline, $language ) ) {
            $currentheading = "$curline";
            $errorafterheading = 0;         # entering new section
        }
    }
    close( IN );
	
	if(@emailRecipient && $ENV{context} && $ENV{build_stepname} && $ENV{BUILD_NAME} && $ENV{PLATFORM} && $ENV{BUILD_MODE})
	{
		my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout=>60) or die("ERROR: SMTP connection impossible: $!");
	    $smtp->mail($SMTP_FROM);
	    
	    my %uniqueList;
	    @uniqueList{@emailRecipient} = (undef);
	    foreach(keys %uniqueList) { 
	    	$smtp->to($_) if($_); 
	    }; 
		$smtp->data();
		$smtp->datasend("To: ".(join(';',keys %uniqueList))."\n");
		unless($unit_name) { $smtp->datasend("Subject: [$ENV{context}] The step ".($ENV{build_parentstepname}?"$ENV{build_parentstepname}/":"")."$ENV{build_stepname} has FATAL errors in build $ENV{BUILD_NAME} on $ENV{PLATFORM} $ENV{BUILD_MODE}\n"); }
		else { $smtp->datasend("Subject: [FATAL ERRORS] The unit '$unit_name' in the step ".($ENV{build_parentstepname}?"$ENV{build_parentstepname}/":"")."$ENV{build_stepname} has FATAL errors in build $ENV{BUILD_NAME} on $ENV{PLATFORM}/$ENV{BUILD_MODE}\n");}
		$smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
		$smtp->datasend("<html><body>");
		$smtp->datasend("<p>");
		$smtp->datasend("FATAL ERRORS found in this build (see email subject): ");
        unless($ENV{MY_DITA_PROJECT}) { $smtp->datasend("<a href='https://$CIS_HOST/cgi-bin/CIS.pl?tag=$ENV{BUILD_NAME}&amp;projects=$ENV{PROJECT}&amp;streams=$ENV{context}'>see dashboard</a>") }
        else { $smtp->datasend("<a href='https://$CIS_HOST/cgi-bin/DAM.pl?tag=$ENV{BUILD_NAME}&phio=$ENV{context}'>see dashboard</a>");  } 
		$smtp->datasend("</p>");

	    if(@errorLines) {
			$smtp->datasend("<p>");
			$smtp->datasend("<b>List of detected error(s) triggering this mail:</b><br/>");
		    %uniqueList=(); @uniqueList{@errorLines} = (undef);
		    foreach(keys %uniqueList) { 
		    	$smtp->datasend("$_<br/>");
		    }; 
			$smtp->datasend("</p>");
	    }

		$smtp->datasend("</body></html>"); 
		$smtp->dataend();
		$smtp->quit();
	}

    # add summary info to output
    my $buildinfo;
    $buildinfo = "== Build Info: machine=$HOSTNAME";
    $buildinfo .= ", area=$ENV{area}" if ( defined $ENV{area} );
    $buildinfo .= ", order=$ENV{order}" if ( defined $ENV{order} );
    $buildinfo .= ", buildmode=$ENV{build_mode}" if ( defined $ENV{build_mode} );
    $buildinfo .= ", platform=$ENV{PLATFORM}" if ( defined $ENV{PLATFORM} );
    $buildinfo .= ", context=$ENV{context}" if ( defined $ENV{context} );
    $buildinfo .= ", revision=$ENV{build_number}" if ( defined $ENV{build_number} );
    $buildinfo .= "\n";
    if ( $BUILD_START > 0 ) {
        unshift @outlines, "\n";
        unshift @outlines, '== Build end  : '.localtime($BUILD_STOP)." ($BUILD_STOP)\n";
        unshift @outlines, '== Build start: '.localtime($BUILD_START)." ($BUILD_START)\n";
    }
    unshift @outlines, "\n";
    unshift @outlines, "== Sections with errors: $nSectionsWithErrors\n";
    unshift @outlines, $buildinfo;

    # write output log
    if ( ! open( OUT, ">$outfile" ) ) {
            print "Error: Unable to open file for write: $outfile\n";
            return -1;
    }
    foreach $curline (@outlines) {
        print OUT $curline;
    }
    
    my($Dh, $Dm, $Ds) = (Delta_DHMS(@StartSummarize, Today_and_Now()))[1..3];
    print(OUT sprintf("Summary took %u s (%u h %02u mn %02u s)\n", $Dh*3600+$Dm*60+$Ds, $Dh, $Dm, $Ds));
    close( OUT );

    return $errcount;
}

###=============================================================================
# Update results in build reporting system
# Arguments:
# - number of errors detected
# - name of build unit
# - string containing local log directory
sub updatebuildreporting($$$)
{
    my ($err_count, $unit_name, $log_path_dir) = @_;
    my %params;
    my $ok = 1;

    # get parameters
    {
        $params{drop_dir}       = "$ENV{DROP_DIR}";
        $params{area}           = "$ENV{area}";
        $params{stream}         = "$ENV{context}";
        $params{build_rev}      = "$ENV{build_number}";
        $params{config}         = "$ENV{BUILD_MODE}";
        $params{platform}       = "$ENV{PLATFORM}";
        $params{type}           = "$ENV{rmbuild_type}";
        $params{local_log_path} = "$log_path_dir";
        $params{component}      = "$unit_name";
        $params{num_of_errors}  = "$err_count";
        $params{build_machine}  = "$HOSTNAME";
        $params{log_path}       = 'set in copylogtoserver()';
        # $params{langcode}     = $ENV{langcode}; # not used anymore for Saturn
    }

    # if not set, use defaults
    {
        if ( $params{type} eq '' ) {
            $params{type} = 'compile';
            print "Warning: type parameter was not set, using default ".$params{type}."\n";
        }
        if ( $params{area} eq '' ) {
            $params{area} = 'Saturn';
            print "Warning: area parameter was not set, using default ".$params{area}."\n";
        }
        if ( $params{config} eq '' ) {
            $params{config} = 'release';
            print "Warning: config parameter was not set, using default ".$params{config}."\n";
        }
    }

    # check parameters
    {
        foreach my $param ( keys %params ) {
            if (! defined $params{$param} ) {
                print "Error: parameter undefined $param \n";
                $ok = 0;
            }
            else {
                $params{$param} = trim( $params{$param} );
                if ( $params{$param} eq '' ) {
                    print "Error: parameter value empty $param \n";
                    $ok = 0;
                }
            }
        }

        if (! $ok) {
            return 0;
        }
    }

    # copy log to fileserver
    copylogtoserver( \%params ) if $ok;
	
    return 1;
}

###=============================================================================
# Copy log files to file server
# Assumption:
# - log file and summary file in same directory, and file name only differs by extension: *.log *.summary.txt
# - log file path on server in this layout:
#   \\vcbinaries\dropzone\Saturn\Multi_PI\22\win32_x86\release\logs\host
# Arguments:
# - reference to hash containing report parameters
# Returns:
# - boolean indicating success
#
sub createserverlogpath(%)
{
    my ($rparams) = @_;
    my $serverpath;
    my $pathsuffix = "";         # part of path after /logs/

    # construct fileserver log directory path
    if ( $$rparams{local_log_path} =~ m#[\\/]logs[\\/](.+)# ) {
        $pathsuffix = $1;
    }

    $serverpath = File::Spec->catfile( $$rparams{drop_dir}, $$rparams{stream}, $$rparams{build_rev}, $$rparams{platform}, $$rparams{config}, 'logs', $HOSTNAME, $pathsuffix );
    if (! -d $serverpath) {
          eval { mkpath ($serverpath) };
          return undef if ($@);
    }

    # set log_path parameter for Lego: file:<path>/<build unit name>
    my $result= File::Spec->catfile( $serverpath, $$rparams{component} );
    $result =~ s#\\#/#g;
    return $result;
}
sub copylogtoserver(%)
{
    my ($rparams) = @_;
    my $serverpath;
    my $pathsuffix = "";         # part of path after /logs/
    my $result;

    # set log_path parameter for Lego: file:<path>/<build unit name>
    my $log_path = createserverlogpath($rparams);
    return 0 if(!defined $log_path);
    $$rparams{log_path} = $log_path;

    # copy log file to fileserver
    $result = copy(File::Spec->catfile( $$rparams{local_log_path}, $$rparams{component}.'.log'), $$rparams{log_path}.'.log');
    if (! $result) {
        print "Error copying log file to file server\n";
        return 0;
    }

    # copy log summary to fileserver
    $result = copy(File::Spec->catfile( $$rparams{local_log_path}, $$rparams{component}.'.summary.txt'), $$rparams{log_path}.'.summary.txt');
    if (! $result) {
        print "Error copying log summary to file server\n";
        return 0;
    }

    return 1;
}

sub detecterrorline($$)
{
    my ($line, $language) = @_;

    # return on project success
    if($line=~/^BUILD SUCCEEDED/ || $line=~/^\[INFO\]/ || $line=~/The following error occurred while executing this line/) {
        return undef;
    }

    # check for error keywords
    # loop over languages
    for my $lang ("all_special", "all_general", "${language}_special", "${language}_general") {
        $lang = 'default' unless(exists $XProcessLogRE::patterns{$lang});
        # loop over patterns
        for my $patref ( @{$XProcessLogRE::patterns{$lang}} ) {
            my($pattern, $except, $EndOfDescription, $emailRecipient, $condition) = @{$patref};
            # match
            if ( $line =~ /$pattern/ ) {
                my $prefix = $`;
                my $suffix = $';
                # match exceptions
                if (
                    # special
                    (
                        $lang =~ m<_special$> and
                        ( !defined ($except) or $line !~ /$except/ )
                    ) or
                    # regular
                    (
                        $lang !~ m<_special$> and
                        ($line =~ /\[sourceanalyzer\]/ or $line =~ /AHFCmd\s+:WARNING:/ or $line =~ /\[sapLevel:/ or $line !~ m<\bwarning\b|\bavertissement\b|\bfuture error\b>i) and
                        $prefix !~ m<\b(?:memo|rem|remark|todo|junit)\b[:]?>i and
                        ( !defined ($except) or $line !~ /$except/ )
                    )
                ) {
                    my $evalutedCondition=$condition?eval $condition:1;
                    return [$EndOfDescription,$evalutedCondition?$emailRecipient:undef] || [undef,$evalutedCondition?$emailRecipient:undef];
                }
            }
        }
    }

    # no error detected
    return undef;
}

###=============================================================================
# Detect log lines containing headings
# Arguments:
# - string containing line to check
# Result:
# - boolean indicating whether heading was detected
#
sub detectheadingline($$)
{
    my ($line, $language) = @_;

    # ** Set the patterns to look for here **
    my %patterns = (
        # applies to all languages
        'all' => [
            [qr/-+ Build started/i              , undef],
            [qr/-+ .*started: Project: .* -+/i  , undef],
            [qr/Buildfile: /i                   , undef],
            [qr/^Running: /i                    , undef],
            [qr/\] ===== \w/i                   , undef],
            [qr/^===+ \w/i                      , undef],
        ],
        # applies to default
        'default' => [
        ],
    );

    # check for heading keywords
    for my $lang ('all', $language) {
        $lang = 'default' unless(exists $patterns{$lang});
        for my $patref ( @{$patterns{$lang}} ) {
            my($pattern,$except) = @{$patref};
            if ( $line =~ /$pattern/ ) {
                if (
                    ( !defined ($except) or $line   !~ /$except/ )
                ) {
                    return 1;
                }
            }
        }
    }

    # no heading detected
    return 0;
}

###=============================================================================
# Trim spaces from beginning and end of line
# Arguments:
# - string containing line to trim
sub trim($)
{
	my ( $string ) = @_;

	$string =~ s/^\s+//;
	$string =~ s/\s+$//;

	return $string;
}

###=============================================================================
# module cleanup

END {
}

###=============================================================================

# return true to the 'use' command
1;
