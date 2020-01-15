package Exec::Queue;

use IO::Select;
use IO::Socket;
use Symbol qw(qualify_to_ref);
use threads;
use Data::Dumper;

sub at_eol($) { $_[0] =~ /\n\z/ }

sub sysreadline(*;$) {
    my($handle, $timeout) = @_;
    $handle = qualify_to_ref($handle, caller( ));
    my $infinitely_patient = (@_ == 1 || $timeout < 0);
    my $start_time = time( );
    my $selector = IO::Select->new( );
    $selector->add($handle);
    my $line = "";
SLEEP:
    until (at_eol($line)) {
		threads->yield();
        unless ($infinitely_patient) {
            return $line if time( ) > ($start_time + $timeout);
        }
        # sleep only 1 second before checking again
        # next SLEEP unless $selector->can_read(1.0);
INPUT_READY:
        while ($selector->can_read(0.0)) {
			threads->yield();
            my $was_blocking;
            $was_blocking=$handle->blocking(0) if(exists &IO::Handle::blocking) ;
CHAR:       
			while (sysread($handle, my $nextbyte, 1)) {
				threads->yield();
                $line .= $nextbyte;
                last CHAR if $nextbyte eq "\n";
            }
            $handle->blocking($was_blocking) if(exists &IO::Handle::blocking && defined $was_blocking);
            # if incomplete line, keep trying
            next SLEEP unless at_eol($line);
            last INPUT_READY;
        }
    }
	threads->yield();
	return $line;
}


sub reset($)
{
	my $self=shift;
	
	$self->{DATA}{$self->{HANDLE}}{CODE}=undef;
	%{$self->{DATA}{$self->{HANDLE}}{HEADER}}=();
}

sub new 
{
	# my $s = Net::HTTP::NB->new(Host => "localhost:".$self->{PORT}, KeepAlive => TRUE, PeerHTTPVersion => "1.1");
	
	 
	my $host = '127.0.0.1'; # an example obviously
	my $sock = IO::Socket::INET->new( 
	   Proto     => "tcp",
	   PeerAddr  => $host,
	   PeerPort  => ($ENV{BUILD_EXEC_PORT} || 8082),
	) or return undef;
		 
	$sock->autoflush(1);	

	my $self  = {		
		CONNECTION => {},
		HANDLE => $sock,
		COUNTER =>0,		
		
	};
	return undef if(!$self->{HANDLE});
	bless($self);
	return $self;	
}

sub start($$$$)
{
	my($self, $srcDir, $cmd, $priority)=@_;
	$priority||=2;
		
	my $content=Dumper({ cmd =>$cmd, env=> { %ENV } });

	syswrite ${$self->{HANDLE}},
	(
		'POST /?mode=START&user=Exec-Queue&blocking=1&priority='.$priority.'&_eq_handle='.(++$self->{COUNTER}).' HTTP/1.1'.Socket::CRLF.
		'Content-Type: text/xml; charset=utf-8'.Socket::CRLF.
		'Connection: Keep-Alive'.Socket::CRLF.
		'Content-Length: '.length($content).Socket::CRLF.
		Socket::CRLF.$content
	);
	$self->{CONNECTION}{$self->{COUNTER}}=undef;
	return $self->{COUNTER};
}

sub wait($;$)
{
    my($self,$nowait)=@_;
    unless(keys %{$self->{CONNECTION}}) {
    	return -1 ;
    }
    
    my %request;
    my $timeout=8;
    
    my $selector = IO::Select->new( ${$self->{HANDLE}} );
    do {
		threads->yield();

    	if(my($fh) = $selector->can_read($nowait)) {
    		unless($self->{DATA}{$self->{HANDLE}}{HEADER}{HEADER_DONE}) 	{
				while(my $line=sysreadline($fh,$timeout)){
					threads->yield();
		            chomp $line; # Main http request
		            if ($line =~ /^\s*HTTP\/(\d.\d)\s*(\d+)\s*(.*)/) {
		                $self->{DATA}{$self->{HANDLE}}{HEADER}{HTTP_VERSION} = $1;
		                $self->{DATA}{$self->{HANDLE}}{HEADER}{ERROR_CODE} = uc $2;
		                $self->{DATA}{$self->{HANDLE}}{HEADER}{MESSAGE} = $3;
		            } # Standard headers
		            elsif ($line =~ /:/) {
		                (my $type, my $val) = split /:/, $line, 2;
		                $type =~ s/^\s+//;
		                foreach ($type, $val) {
	                        s/^\s+//;
	                        s/\s+$//;
							threads->yield();
		                }
		                $self->{DATA}{$self->{HANDLE}}{HEADER}{lc $type} = $val;
		            } # POST data
		            elsif ($line =~ /^\s*$/) {
		            	$self->{DATA}{$self->{HANDLE}}{HEADER}{HEADER_DONE}=1;
		            	unless(defined $self->{DATA}{$self->{HANDLE}}{HEADER}{'content-length'}) {
		            		$self->{DATA}{$self->{HANDLE}}{HEADER}{CONTENT}="";
		            		$self->{DATA}{$self->{HANDLE}}{HEADER}{'CONTENT-COUNTER'}=0;
		            	} else {
		            		$self->{DATA}{$self->{HANDLE}}{HEADER}{'CONTENT-COUNTER'}=$self->{DATA}{$self->{HANDLE}}{HEADER}{'content-length'};
		            	}
		            	last;
		            }
				}
    		}
    		elsif($self->{DATA}{$self->{HANDLE}}{HEADER}{'CONTENT-COUNTER'}) {
    			my $buf;
                my $n=sysread($fh, $buf, $self->{DATA}{$self->{HANDLE}}{HEADER}{'CONTENT-COUNTER'})
                    if $self->{DATA}{$self->{HANDLE}}{HEADER}{'CONTENT-COUNTER'};
                if($n) {
                	$self->{DATA}{$self->{HANDLE}}{HEADER}{CONTENT}.= $buf;
                	$self->{DATA}{$self->{HANDLE}}{HEADER}{'CONTENT-COUNTER'} -= $n;
                }
    		}
    	}
    } while(!defined $nowait && (!$self->{DATA}{$self->{HANDLE}}{HEADER}{HEADER_DONE} || $self->{DATA}{$self->{HANDLE}}{HEADER}{'CONTENT-COUNTER'}));
    
    return 0 if(!$self->{DATA}{$self->{HANDLE}}{HEADER}{HEADER_DONE} || $self->{DATA}{$self->{HANDLE}}{HEADER}{'CONTENT-COUNTER'});
    
    if(exists $self->{DATA}{$self->{HANDLE}}{HEADER}{ERROR_CODE} && $self->{DATA}{$self->{HANDLE}}{HEADER}{ERROR_CODE}!=200) {
    	$self->reset();
    	return -1;    	
    }
        
    if(!$self->{DATA}{$self->{HANDLE}}{HEADER}{'CONTENT-COUNTER'} && exists $self->{DATA}{$self->{HANDLE}}{HEADER}{CONTENT}) {

    	my $VAR1;
    	eval $self->{DATA}{$self->{HANDLE}}{HEADER}{CONTENT};
    	if($VAR1->{query_param}{_eq_handle}) {
    		delete $self->{CONNECTION}{$VAR1->{query_param}{_eq_handle}};
    		$self->reset(); 
    		return $VAR1->{query_param}{_eq_handle};
    	} 
    }
    return 0;
}

1;
