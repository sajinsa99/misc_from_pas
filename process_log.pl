#!/usr/bin/perl
#
# Name:    ProcessLog.pl
# Purpose: calls the ProcessLog.pm module
# Notes:   must be either symlinked or copied before used
# Future:  -
#

# set @INC array
use FindBin qw($Bin);
use lib ("$Bin", "$Bin/site_perl");

# base
use File::Basename;
# site
# local
use XLogging;

# pragmas
use strict;
use warnings;

# global variables
our $Program = basename($0);

# sub declarations
sub main();

# call main
main();

###=============================================================================

sub main() {
    # Turn off output buffering
    #
    select STDERR; $| = 1;
    select STDOUT; $| = 1;
    
    # load correspodning module
    #
    if ($Program eq 'module_wrapper.pl') {
        xLogFatal("Must rename before use");
    }
    my $module = $Program;
    $module =~ s<^(.)(.*)\.pl$><"X" . uc($1) . lc ($2)>e;
    $module =~ s<-(.)><"::" . uc($1)>eg;  # for sub modules
    $module =~ s<_(.)><uc($1)>eg;
    eval "require $module";
    xLogFatal($@) if($@);
    
    # call its main subroutine
    #
    my $code;
    eval "\$code = $module\::main(\@ARGV)";
    xLogFatal($@) if($@);
    
    # exit
    #
    exit($code);
}
