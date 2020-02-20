package sm_velocity;
##############################################################################
##############################################################################
##### declare uses
## ensure code quality
use strict;
use warnings;
use diagnostics;
use Carp qw(cluck confess); # to use instead of (warn die)

## for the script itself
use charnames ':full';
use JSON;
use Exporter;
use File::Path;
use File::stat;
use Time::Local;
use Data::Dumper;
use File::Basename;
use Store::CouchDB;
use Sort::Versions;
use Tie::Hash::Indexed;
## for jira
use JIRA::REST;
use JIRA::Client::Automated;

## custom perl modules
use sm_queries;
use sm_html;



##############################################################################
##############################################################################
##### declare subs
sub sm_sprint($);
sub sm_velocity();



##############################################################################
##############################################################################
##### functions
sub sm_sprint($) {

}

sub sm_velocity() {
    
}

##############################################################################
##############################################################################
##############################################################################
1;
