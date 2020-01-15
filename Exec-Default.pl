package Exec::Default;

use POSIX ":sys_wait_h";
use POSIX qw( WNOHANG );
 
sub new 
{
	my $self  = {};
	bless($self);
	return $self;	
}

sub start($$$$)
{
	my($self, $srcDir, $cmd, $priority)=@_;
	$priority||=2;

    my $pid;
    if(!defined($pid=fork())) { return undef }
    elsif($pid) { return $pid }
    else 
    {
        exec("nice -".(5*(2-$priority))." bash -c \"$cmd\"");
        exit(0);
    }
}

sub wait($;$)
{
    my($self,$nowait)=@_;
	return waitpid(-1, (!defined $nowait?0:WNOHANG));
}

1;
