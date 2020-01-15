#!/usr/bin/perl
#
# Name:     Torch.pm
# Purpose:  Functions for recording events in Torch.
# Notes:    
# Future:   
#

package ScorchResult;
sub new(){
	my $self={};
	$self->{RESULT}=$_[1];
	 
	bless($self);           # but see below	
	return $self;
}

sub result() {
	my $self=shift;	
	return $self->{RESULT};
}

package Scorch;
use HTTP::Cookies;
use File::Path;
use File::stat;
use Data::Dumper;
use IO::File;
use Time::HiRes;

our $bSoapInstalled=0;
our $opSys           = $^O;
our $true=1;
our $false=0;

#Scorch (POC)
use LWP::UserAgent;
use HTTP::Request::Common qw( POST );

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    # set the version for version checking
    $VERSION = sprintf "%d.000", q$Revision: #3 $ =~ /(\d+)/g;
    
    @ISA         = qw(Exporter);

    # your exported package globals go here,
    #@EXPORT      = qw(&processlog);

    # collections of exported globals go here
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    
    # any optionally exported functions go here
    @EXPORT_OK   = qw();
}
our @EXPORT_OK;

sub ToSoapString
{
    my $toConvert=shift;
    return $toConvert;
}

sub new {
	
	my $szProto=shift;
	my $szURL=shift;
	my $FileName=shift;

	return undef unless(defined $szURL && defined $ENV{BUILD_SCORCH_ENABLE} && $ENV{BUILD_SCORCH_ENABLE}!=0);

	my $self  = {};
	$self->{PROTO}=$szProto;
	$self->{ERROR}=undef;
    $self->{COUNT}=0;
    $self->{SCORCH_URL}=$szURL;
    
	eval
	{
		$self->{TORCH_PROXY} = LWP::UserAgent->new;
	};
	return undef if($@ || !defined $self->{TORCH_PROXY});
	
	$self->{ISPARENT}=1 if(defined $ENV{BUILD_DASHBOARD_SESSION});
	$ENV{BUILD_DASHBOARD_SESSION}||=time()."_".$$;
    
    if(defined $ENV{TEMP})
    {
        eval { File::Path::mkpath("$ENV{TEMP}") } unless(-e "$ENV{TEMP}");
    }
	if($FileName) { $self->{FILE_NAME_DONTDELETE}=1; $self->{FILE_NAME}=$FileName; }
	else { $self->{FILE_NAME}=(defined $ENV{TEMP}?$ENV{TEMP}:".")."/".$ENV{BUILD_DASHBOARD_SESSION} }

	$self->{COOKIE_FILE}=$self->{FILE_NAME}.".cookie.scorch";
	$self->{COOKIE_HANDLE} = HTTP::Cookies->new(ignore_discard => 1,
                                        file => $self->{COOKIE_FILE},
                                        autosave=>1);
    # $self->{TORCH_PROXY}->transport->cookie_jar($self->{COOKIE_HANDLE});

	
	$self->{BUILD_CONTACT_NAME}=(!defined $ENV{BUILD_CONTACT_NAME})?"":$ENV{BUILD_CONTACT_NAME};
	$self->{BUILD_CONTACT_EMAIL}=(!defined $ENV{BUILD_CONTACT_EMAIL})?"":$ENV{BUILD_CONTACT_EMAIL};	
	$self->{BUILD_TORCH_ACCEPTABLE_DURATION}=defined $ENV{BUILD_TORCH_ACCEPTABLE_DURATION}?int($ENV{BUILD_TORCH_ACCEPTABLE_DURATION}):0;	# Acceptable duration is in  milliseconds
	$self->{BUILD_TORCH_FAILURE_PAUSE}=defined $ENV{BUILD_TORCH_FAILURE_PAUSE}?int($ENV{BUILD_TORCH_FAILURE_PAUSE}):0;	 # FAILURE PAUSE is in seconds
		
	{
		my @splittedString=split(/\@/, $self->{BUILD_CONTACT_EMAIL});
		$self->{BUILD_CONTACT_EMAIL}="" if(scalar @splittedString>2) ; # Must contain only one email addr so one @
	}

	bless($self);           # but see below	
	return $self;

}

###=============================================================================
# Public methods
sub error
{
	my $self=shift;
	return $self->{ERROR};
}

sub display_error()
{
	
}

sub get_contact_name()
{
	my $self = shift;
	return $self->{BUILD_CONTACT_NAME};
}

sub get_contact_email()
{
	my $self = shift;
	return $self->{BUILD_CONTACT_EMAIL};
}

sub delete_build_session()
{
	my $self = shift;
	my ($group, $project, $contact_name, $contact_email, $context, $version, $mode, $platform, $session_start) = @_;	
	my $session_end = time();		
	$scorchMethod = defined $ENV{SCORCH_METHOD}?$ENV{SCORCH_METHOD}:"RESTFulHttpToHttps";
	$self->$scorchMethod({
		ACTION => 'closeBuildSession',
		GROUP_NAME => $group,
		PROJECT_NAME =>$project,
		CONTACT_NAME => $contact_name,
		CONTACT_EMAIL => $contact_email,
		BRANCH_NAME => $context,
		VERSION_NAME => $version,
		MODE_NAME => $mode,
		PLATFORM_NAME => $platform,
		SESSION_START => $session_start,
		SESSION_END => $session_end
	});	
	$self->_destroy();
}

sub set_version_property()
{
	my $self = shift;
	my ($group, $project, $context, $version, $site, $name, $value) = @_;	
	my $session_end = time();		
	$scorchMethod = defined $ENV{SCORCH_METHOD}?$ENV{SCORCH_METHOD}:"RESTFulHttpToHttps";
	$self->$scorchMethod({
		ACTION => 'logVersionProperty',
		GROUP_NAME => $group,
		PROJECT_NAME =>$project,
		BRANCH_NAME => $context,
		VERSION_NAME => $version,
		SITE => $site,
		VERSION_PROPERTY_NAME => $name,
		VERSION_PROPERTY_VALUE => $value	
	});	
	$self->_destroy();
}

sub set_activity()
{
	my $self = shift;
	my ($group, $project, $context, $version, $site, $activity_name, $activity_r_user, $activity_history, $activity_r_date, $activity_readonly, $activity_issues, $activity_description) = @_;	
	my $session_end = time();		
	$scorchMethod = defined $ENV{SCORCH_METHOD}?$ENV{SCORCH_METHOD}:"RESTFulHttpToHttps";
	$self->$scorchMethod({
		ACTION => 'logActivity',
		GROUP_NAME => $group,
		PROJECT_NAME =>$project,
		BRANCH_NAME => $context,
		VERSION_NAME => $version,
		SITE => $site,
		ACTIVITY_NAME => $activity_name,
		ACTIVITY_R_USER => $activity_r_user,
		ACTIVITY_HISTORY => $activity_history,
		ACTIVITY_R_DATE => $activity_r_date,
		ACTIVITY_READONLY => $activity_readonly,
		ACTIVITY_ISSUE => $activity_issues,
		ACTIVITY_DESCRIPTION => $activity_description		
	});	
	$self->_destroy();
}

###=============================================================================
# Internal methods
sub _save_failing_call_timestamp()
{
	my $self = shift;
    my $lfh=new IO::File(">".$self->{FILE_NAME}.".failed.scorch") ;
    $lfh->close if($lfh);
}

sub _save_call()
{
	my $self = shift;
	my $fh = shift;
	my $stamp = shift;
	my $cmd = shift;
    
    my $lfh=$fh;
    $lfh=new IO::File(">>".$self->{FILE_NAME}.".queue.scorch") if(!$fh);
    return unless(defined $lfh);
    
    local $Data::Dumper::Purity = 1;
	$lfh->print("\n# SAVED CALL : $stamp\n");
	$lfh->print("{\nmy ");
	$lfh->print(Data::Dumper->Dump([\@_], [qw(*args)])."\n");
	$lfh->print("push(\@{\$self->{SAVED_CALLS}}, ['$stamp', '$cmd', \@args] );\n");
	$lfh->print("}\n");
 	$lfh->print("\n# END SAVED CALL : $stamp\n");
    $lfh->close if(!$fh);
}

sub _destroy()
{
	my $self = shift;

	delete $ENV{BUILD_DASHBOARD_SESSION} if(!defined $self->{ISPARENT} || $self->{ISPARENT}!=1);

    # $self->{TORCH_PROXY}->transport->cookie_jar(undef);
    delete $self->{COOKIE_HANDLE};
	unlink($self->{COOKIE_FILE});
}
 
sub _execute()
{
	my $self = shift;
	my $stamp = shift;
	my $cmd = shift;
    
	my $donePosition=0;
	my $previousCallDuration=0;

	my $lastDoneCall = stat($self->{FILE_NAME}.".done.scorch");	# last call is equal is the modification time of the .done file
	my $lastFailedCall = stat($self->{FILE_NAME}.".failed.scorch");	# last modification date/time of this file is the time of the last request failure

    # Put current call at the end of the list to flush
    $self->_save_call(undef,$stamp,$cmd,@_) if($cmd);

    # Read the position of already done calls in the queue to start after
    {
        my $fhDone=new IO::File("<".$self->{FILE_NAME}.".done.scorch");
        if(defined $fhDone)
        {
        	($donePosition, $previousCallDuration)= join("",<$fhDone>) =~ /(\d+(?:\.\d+)?\w*)/g;
    	    $fhDone->close;
        }
    }
    
    # if no $cmd or if $cmd equals "closeBuildSession" assuming that all calls must be flush, so force sending
    if(defined $cmd && $cmd ne "closeBuildSession") 
    {
	    # if last call duration was unaccceptable(BUILD_TORCH_ACCEPTABLE_DURATION)
    	if(defined $previousCallDuration && $self->{BUILD_TORCH_ACCEPTABLE_DURATION}>0 && $previousCallDuration>($self->{BUILD_TORCH_ACCEPTABLE_DURATION}/1000.0))
    	{
	    	#  so don't send any new request since this call until next BUILD_TORCH_ACCEPTABLE_DURATION
	    	return undef if(defined $lastDoneCall && $self->{BUILD_TORCH_FAILURE_PAUSE}>(time()-$lastDoneCall->mtime));
	    }
	    # if last failure was generated there less than BUILD_TORCH_FAILURE_PAUSE seconds.... so exit !
	    return undef if(defined $lastFailedCall && $self->{BUILD_TORCH_FAILURE_PAUSE}>time()-$lastFailedCall->mtime);
    }

	# Before replay saved calls
    my $lfh=new IO::File("<".$self->{FILE_NAME}.".queue.scorch");
    if($lfh)
    {
        $lfh->seek($donePosition,0);
        my $currentCall="";
        while(<$lfh>)
        {
            $currentCall.=$_;
            next unless(/^\# END SAVED CALL : (.*)/) ;

            eval $currentCall;
            if(!$@)
            {
                while(my $entry=shift(@{$self->{SAVED_CALLS}}))
                {
                    my $stampToReplay=shift(@$entry);
                    my $cmdToReplay=shift(@$entry);

                	$self->{ERROR}=undef;
                	
 	                # If a queue was existing when entering in _execute, that means that some calls were already pushed in the queue because they fails previously
 	                # In this case, instead of replaying the original command, check if a re-routing to another command was requested througth the environment
 	                # This allow for example, to execute logResultAndGetID to be executed instead of logResult which can generate server issue & as the server is more robust when calling logResultAndGetID
 	                # instead of logResult
 	                $cmdToReplay=$ENV{"torch.route.".$cmdToReplay} if(defined $lastDoneCall && defined $ENV{"torch.route.".$cmdToReplay});
 	                
 	                my $callDuration=Time::HiRes::time();
 	                my $httpRet=undef;
                	eval
                	{
                		unless(defined $self->{TEST}) {
                			$req=POST("$self->{SCORCH_URL}/$cmd",@$entry);
                			$httpRet=$self->{TORCH_PROXY}->request($req);
                		}
                	};
                	$self->{ERROR}=$@;
	                $callDuration=Time::HiRes::time()-$callDuration;
                	
                	## $self->{COOKIE_HANDLE}->save() if(defined $self->{COOKIE_HANDLE}); # Force cookie session backup in the $self->{COOKIE_FILE}
                	
                	if($self->{ERROR} || !defined $httpRet || !$httpRet->is_success)
                	{
                	    $self->{ERROR}= $httpRet->message if(!$self->{ERROR} && defined $httpRet && !$httpRet->is_success); 
                	    $self->_save_failing_call_timestamp(); # Save the time of the last failed call by modiying the .failed mtime stat value
                	    return new ScorchResult(undef);
                    } 
                    
            	    my $fhDone=new IO::File(">".$self->{FILE_NAME}.".done.scorch");
            	    if(defined $fhDone)
            	    {
                    	$fhDone->print("".($lfh->tell)." ".($callDuration));
            		    $fhDone->close;
            	    }
            	    # Call was successfull, saved as done just above but duration was too long !, so leave & don't continue next call 
            	    return undef if((defined $cmd && $cmd ne "closeBuildSession") && $self->{BUILD_TORCH_ACCEPTABLE_DURATION}>0 && $callDuration>($self->{BUILD_TORCH_ACCEPTABLE_DURATION}/1000.0));
                }                  
            }
            $currentCall="";
        }
        $lfh->close;
    }
    unless(defined $self->{FILE_NAME_DONTDELETE} || (defined $ENV{BUILD_SCORCH_KEEP} && $ENV{BUILD_SCORCH_KEEP}==1))
    {
        unlink($self->{FILE_NAME}.".queue.scorch") if(-e $self->{FILE_NAME}.".queue.scorch");
        unlink($self->{FILE_NAME}.".done.scorch") if(-e $self->{FILE_NAME}.".done.scorch");
        unlink($self->{FILE_NAME}.".failed.scorch") if(-e $self->{FILE_NAME}.".failed.scorch");
    }
		
	return undef;
}

sub AUTOLOAD
{
	my $self = shift;

   	return if $AUTOLOAD =~ /::DESTROY$/;
	(my $cmd = $AUTOLOAD ) =~ s/.*:://;
	
	return $self->_execute(time()."-".$$."-".$self->{COUNT}++,$cmd,@_);
}

1;

################################################
# Unmarshalling methods stored in 
#foreach my $entry(@{$self->{sAVED_CALLS}})
#{
#    print "Call number [".shift(@$entry)."]\n";
#    print "\tMethod [".shift(@$entry)."]\n";
#    foreach my $parameter(@$entry)
#    {
#        print "\t\tParameter[".$parameter."]\n";    
#    }
#}


# to record a file
=pod
my $record_test=new Scorch("http://vantgvmlnx296.dhcp.pgdev.sap.corp:8080/RESTfulHttpToHttps","./event");
$record_test->RESTFulHttpToHttps({PARAM1=>"Param1",PARAM2=>"Param2",PARAM3=>"Param3",PARAM4=>123});
$record_test->delete_build_session();
undef $record_test;
=cut


=pod
# to replay an event file
my $replay_test=new Scorch("http://vantgvmlnx296.dhcp.pgdev.sap.corp:8080/RESTfulHttpToHttps","./event");
$replay_test->execute();
# $test->delete_build_session();
undef $replay_test;
=cut

=pod
#to test closeBuildSession
$ENV{BUILD_SCORCH_ENABLE} = 1;
my $test=new Scorch("http://vantgvmlnx296.dhcp.pgdev.sap.corp:8080/RESTfulHttpToHttps");
	my $group = "";
  my $project = "";
  my $contact_name = "tester1";
  my $contact_email ="kittylam@gmail.com";	 		
	my $context = "van_devt_test2";
  my $version = "29";
  my $mode = "release";
  my $platform = "win32_x86";
  my $session_start = "1398713420";
my $result = $test->delete_build_session($group, $project, $contact_name, $contact_email, $context, $version, $mode, $platform, $session_start);
#my $result = $test->delete_build_session();
	if ($test->error()) {
		warn("ERROR: SCORCH: ".$test->error());		
	}
	print "RESULTS: ".$result;
=cut