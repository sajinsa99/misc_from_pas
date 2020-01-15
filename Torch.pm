#!/usr/bin/perl
#
# Name:     Torch.pm
# Purpose:  Functions for recording events in Torch.
# Notes:    
# Future:   
#
package Torch;
use HTTP::Cookies;
use File::Path;
use File::stat;
use Data::Dumper;
use IO::File;
use Time::HiRes;

our $bSoapInstalled=0;
our $opSys           = $^O;
our $true;
our $false;
eval { require "SOAP/Lite.pm" };
unless($@)
{
    $bSoapInstalled = 1;
    eval 
    {
	    $true  = SOAP::Data->value('1')->type('boolean');
	    $false = SOAP::Data->value('0')->type('boolean');
    };
} else { warn("ERROR: can't locate SOAP::Lite module.") }

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
    return $toConvert unless($bSoapInstalled==1);
    return  SOAP::Data->type(string => $toConvert );
}

sub new {
	
	my $szProto=shift;
	my $szURL=shift;
	my $FileName=shift;

	return undef unless($bSoapInstalled==1 && defined $szURL && defined $ENV{BUILD_DASHBOARD_ENABLE} && $ENV{BUILD_DASHBOARD_ENABLE}!=0);
	
	my $self  = {};
	$self->{PROTO}=$szProto;
	$self->{ERROR}=undef;
    $self->{COUNT}=0;
    
	eval
	{
		$self->{TORCH_PROXY} = SOAP::Lite->proxy($szURL);
	};
	return undef if($@ || !defined $self->{TORCH_PROXY});
	if($SOAP::Lite::VERSION eq "0.60")
	{
		$self->{TORCH_PROXY}->uri('http://ws.torch.rmtools.businessobjects.com/');
	}	
	else
	{
		$self->{TORCH_PROXY}->ns('http://ws.torch.rmtools.businessobjects.com/','namesp1');
		$self->{TORCH_PROXY}->autotype(0);
	}
	
	$self->{ISPARENT}=1 if(defined $ENV{BUILD_DASHBOARD_SESSION});
	$ENV{BUILD_DASHBOARD_SESSION}||=time()."_".$$;
    
    if(defined $ENV{TEMP})
    {
        eval { File::Path::mkpath("$ENV{TEMP}") } unless(-e "$ENV{TEMP}");
    }
	if($FileName) { $self->{FILE_NAME_DONTDELETE}=1; $self->{FILE_NAME}=$FileName; }
	else { $self->{FILE_NAME}=(defined $ENV{TEMP}?$ENV{TEMP}:".")."/".$ENV{BUILD_DASHBOARD_SESSION} }

	$self->{COOKIE_FILE}=$self->{FILE_NAME}.".cookie";
	$self->{COOKIE_HANDLE} = HTTP::Cookies->new(ignore_discard => 1,
                                        file => $self->{COOKIE_FILE},
                                        autosave=>1);
    $self->{TORCH_PROXY}->transport->cookie_jar($self->{COOKIE_HANDLE});

	
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
	$self->closeBuildSession(@_);
	$self->_destroy();
}

###=============================================================================
# Internal methods
sub _save_failing_call_timestamp()
{
	my $self = shift;
    my $lfh=new IO::File(">".$self->{FILE_NAME}.".failed") ;
    $lfh->close if($lfh);
}

sub _save_call()
{
	my $self = shift;
	my $fh = shift;
	my $stamp = shift;
	my $cmd = shift;
    
    my $lfh=$fh;
    $lfh=new IO::File(">>".$self->{FILE_NAME}.".queue") if(!$fh);
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

    $self->{TORCH_PROXY}->transport->cookie_jar(undef);
    delete $self->{COOKIE_HANDLE};
	unlink($self->{COOKIE_FILE});
}
 
sub _execute()
{
	my $self = shift;
	my $stamp = shift;
	my $cmd = shift;
    
	my $returnValue=undef;
	my $donePosition=0;
	my $previousCallDuration=0;

	my $lastDoneCall = stat($self->{FILE_NAME}.".done");	# last call is equal is the modification time of the .done file
	my $lastFailedCall = stat($self->{FILE_NAME}.".failed");	# last modification date/time of this file is the time of the last request failure

    # Put current call at the end of the list to flush
    $self->_save_call(undef,$stamp,$cmd,@_) if($cmd);

    # Read the position of already done calls in the queue to start after
    {
        my $fhDone=new IO::File("<".$self->{FILE_NAME}.".done");
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
    my $lfh=new IO::File("<".$self->{FILE_NAME}.".queue");
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
                	eval
                	{
                		$returnValue=$self->{TORCH_PROXY}->$cmdToReplay(@$entry) unless(defined $self->{TEST});
                	};
                	$self->{ERROR}=$@;
	                $callDuration=Time::HiRes::time()-$callDuration;
                	
                	$self->{COOKIE_HANDLE}->save() if(defined $self->{COOKIE_HANDLE}); # Force cookie session backup in the $self->{COOKIE_FILE}
                	
                	if($self->{ERROR} || (defined $returnValue && !defined $returnValue->result))
                	{
                	    $self->_save_failing_call_timestamp(); # Save the time of the last failed call by modiying the .failed mtime stat value
                	    return $returnValue;
                    }
            	    my $fhDone=new IO::File(">".$self->{FILE_NAME}.".done");
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
    unless(defined $self->{FILE_NAME_DONTDELETE})
    {
        unlink($self->{FILE_NAME}.".queue") if(-e $self->{FILE_NAME}.".queue");
        unlink($self->{FILE_NAME}.".done") if(-e $self->{FILE_NAME}.".done");
        unlink($self->{FILE_NAME}.".failed") if(-e $self->{FILE_NAME}.".failed");
    }
		
	return $returnValue;
}

sub AUTOLOAD
{
	my $self = shift;

   	return if $AUTOLOAD =~ /::DESTROY$/;
	(my $cmd = $AUTOLOAD ) =~ s/.*:://;
	
	my @compatibleParameters; my $counter=0;
	foreach my $parameter(@_)
	{
		push(@compatibleParameters,SOAP::Data->name(("arg".($counter++)) => $parameter))
	}
	return $self->_execute(time()."-".$$."-".$self->{COUNT}++,$cmd,@compatibleParameters);
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

#my $test=new Torch("http://localhost","./test");
#$test->request("Param1","Param2","Param3",123);
#$test->delete_build_session();
#undef $test;
