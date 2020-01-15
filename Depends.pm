package Depends;
use strict;

##################################################
## the object constructor (simplistic version)  ##
##################################################
sub new {
	my $Proto=shift;
	my $Platform=$^O;

	my $self  = new { $Proto."::".$Platform }(@_);
	
	bless($self,$Proto."::".$Platform);           # but see below
	return $self;

}

sub get_path_separator()
{
	my $PathSeparator;
	eval "\$PathSeparator=\$Depends::".$^O."::PATH_SEPARATOR";
	return $PathSeparator;
}
1;