package Exec;
use strict;

sub getDefault(){
	return $ENV{BUILD_EXEC_LIB} || ($^O eq 'MSWin32'?'MSWin32':'Default');
}

##################################################
## the object constructor (simplistic version)  ##
##################################################
sub new {
	my $Proto=shift;
	my $execPlatform=shift;
	
	$execPlatform||=getDefault();
	
	require "Exec-".$execPlatform.".pl";

	my $self  = new { $Proto."::".$execPlatform }(@_);
	
	bless($self,$Proto."::".$execPlatform);           # but see below
	return $self;

}

1;
