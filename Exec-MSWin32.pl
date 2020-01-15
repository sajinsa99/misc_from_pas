package Exec::MSWin32;

use strict;
use Win32::Process qw(IDLE_PRIORITY_CLASS NORMAL_PRIORITY_CLASS HIGH_PRIORITY_CLASS);
use Win32::Event 1.00 qw(wait_any);

# Defining here instead of importing from Win32::Process to be compatible with all Win32::Process library versions 
# even more if not defined in this library
sub BELOW_NORMAL_PRIORITY_CLASS { 0x00004000 } 

our @PRIORITIES = (IDLE_PRIORITY_CLASS,BELOW_NORMAL_PRIORITY_CLASS,NORMAL_PRIORITY_CLASS,HIGH_PRIORITY_CLASS);
our @DESKTOP_PRIORITIES = qw(LOW BELOWNORMAL NORMAL HIGH);

sub new 
{
	my $self  = {};
	$self->{processObjects}=[];
	bless($self);
	return $self;	
}

sub start($$$$)
{
	my($self, $srcDir, $cmd, $priority)=@_;
	my $processObj;
	
	$priority||=2;
    my $desktopDisabled=(!$srcDir ||  !-f "$srcDir/Build/export/win32_x86/desktop.exe" || exists $ENV{BUILD_DESKTOP_DISABLE});
    
    return undef if(
    	!Win32::Process::Create(
    		$processObj, 
    		($desktopDisabled?$ENV{COMSPEC}:"$srcDir/Build/export/win32_x86/desktop.exe"),
    		($desktopDisabled?"":"/$DESKTOP_PRIORITIES[$priority] cmd ")."/c \"$cmd\"", 0, $PRIORITIES[$priority], 
    		 '.'));
	push(@{$self->{processObjects}},$processObj);
	return $processObj->GetProcessID();
}

sub wait($;$)
{
	my($self,$nowait)=@_;
	
	return -1 unless(@{$self->{processObjects}});
	
	my $x = (defined $nowait?wait_any(@{$self->{processObjects}},$nowait):wait_any(@{$self->{processObjects}}));
	return splice(@{$self->{processObjects}}, abs($x) - 1, 1)->GetProcessID() if($x);
	return 0;
}

1;
