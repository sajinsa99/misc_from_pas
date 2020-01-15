#!/usr/bin/perl
#========================================================================================
# Module: XDepDB.pm
# For   : Saturn dependency tool to interact with the Jupiter dependency tool db
#========================================================================================
package XDepDB;
use strict;
use warnings;

use Exporter();
use vars qw(
    $VERSION
    @ISA
    @EXPORT_OK
);
$VERSION = 1.0;
@ISA     = qw(Exporter);
@EXPORT_OK = (
'$G_DPSR_Host',
'$G_DPSR_Port',
'$G_DPSR_Sid',
'$G_DPSR_User',
'$G_DPSR_Passwd',
'$G_DPSR_Commit_Limit',
'$G_DPSR_P4_Format',
'$G_DPSR_MAX_MSG_LENGTH',
'$G_DPSR_Mapping_Format',
'$G_DPSR_Param_Format',
'%G_DPSR_Params',
'$G_DPSR_Param_Section',
'$G_DPSR_Mapping_Section'
);

# if use testing server
my $Test_Server = 0;
#========================================================================================
our $G_DPSR_Host           = undef;
our $G_DPSR_Port           = undef;         
our $G_DPSR_Sid            = undef;       
our $G_DPSR_User           = undef;  
our $G_DPSR_Passwd         = undef; 

if($Test_Server){
    $G_DPSR_Host           = 'vanpgrmapps01.product.businessobjects.com';
    $G_DPSR_Port           = 1521;         
    $G_DPSR_Sid            = 'orcl';       
    $G_DPSR_User           = 'dependency';  
    $G_DPSR_Passwd         = 'depends321'; 
}
else{
    $G_DPSR_Host           = 'vanpgprodb03.product.businessobjects.com';
    $G_DPSR_Port           = 1521;         
    $G_DPSR_Sid            = 'pro10u03';       
    $G_DPSR_User           = 'dependency';  
    $G_DPSR_Passwd         = 'd1p2nd3ncy'; 
}

our $G_DPSR_Commit_Limit   = 200000;
our $G_DPSR_MAX_MSG_LENGTH = 4000;

# dependency mapping text file line format
our $G_DPSR_Mapping_Format = qr!^\s*(//.+?)\s*->\s*(.+?)\s*$!;
our $G_DPSR_Param_Format   = qr!^\s*([^=]+?)\s*=\s*([^=]+?)\s*$!;
our %G_DPSR_Params=(
'project'  => qr!^.+$!,
'stream'   => qr!^.+$!,
'platform' => qr!^.+$!,
'revision' => qr!^\d+$!,
'datetime' => qr!^\w{3}\s\w{3}\s{1,2}\d{1,2}\s\d{1,2}:\d{2}:\d{2}\s\d{4}$!
);
our $G_DPSR_Param_Section   = qr!^\s*\[Params\]\s*$!i;
our $G_DPSR_Mapping_Section = qr!^\s*\[Mapping\]\s*$!i;

# //depot2/project/stream/area/rest
our $G_DPSR_P4_Format = qr!^//(depot2)/([^\/]+)/([^\/]+)/([^\/]+)/(.+)$!;
#========================================================================================
1;
