#!/usr/bin/perl -w

use strict;
use LWP::UserAgent;
use HTTP::Request::Common;
use Getopt::Long;
use XML::Simple;
use Data::Dumper;

##############
# Parameters #
##############

my($Help,$cwb_url,$cwb_user,$cwb_pass,$cwb_file);
my %Changes;
my @Errors;

GetOptions("help|?"=>\$Help, "address=s"=>\$cwb_url, "user=s"=>\$cwb_user, "password=s"=>\$cwb_pass, "file=s"=>\$cwb_file);
Usage() if($Help);
unless($cwb_url)  { print(STDERR "ERROR: -a.ddress option is mandatory.\n"); Usage() }
unless($cwb_user) { print(STDERR "ERROR: -u.ser option is mandatory.\n"); Usage() }
unless($cwb_pass) { print(STDERR "ERROR: -p.assword option is mandatory.\n"); Usage() }
unless($cwb_file) { print(STDERR "ERROR: -f.ile option is mandatory.\n"); Usage() }
sub add_cwb_memo($$);

########
# Main #
########

open(CWB, $cwb_file) or die("ERROR: cannot open '$cwb_file': $!");
while(<CWB>)
{ 
    chomp();
    my($CWBId, $Change) = split(/\s*;\s*/, $_);
    $CWBId =~ s/^\s+//;
    $Change =~ s/\s+$//;
    push(@{$Changes{$Change}}, $CWBId);
}
close(CWB);
map({add_cwb_memo($Changes{$_}, "Correction Request consumed in build '".$ENV{BUILD_NAME}."' through changelist '".$_."'")} keys(%Changes));
die(join("\n",@Errors)) if(@Errors);

#############
# Functions #
#############

sub add_cwb_memo($$) {
    my( $raCWBIds, $message) = @_;
    my $content=<<CWB_ADD_MEMO_REQUEST_BEGIN;
		<massNewMemo>
			<memo>
				<type key="B"/>
				<content>$message</content>
			</memo>
			<correctionRequests>
CWB_ADD_MEMO_REQUEST_BEGIN
	    
    foreach my $cwb_id(@{$raCWBIds}) {
		$cwb_id =~ s/\s//g;
		$content.=<<CWB_ADD_MEMO_REQUEST_CR;
				<correctionRequest id="$cwb_id" />
CWB_ADD_MEMO_REQUEST_CR

    }
	$content.=<<CWB_ADD_MEMO_REQUEST_END;
			</correctionRequests>
		</massNewMemo>
CWB_ADD_MEMO_REQUEST_END
	
	my $ua = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0 }, );
	
	my $req =
	  POST $cwb_url . "/JCWB_SRV_EXTERN/ADD_MEMO", Content=> $content;

	$req->authorization_basic( $cwb_user, $cwb_pass );

	my $page = $ua->request($req);

	if ( $page->is_success ) {
		my $xml = XMLin( $page->content );
		if (%$xml) {
			if(
				exists $xml->{messages} 
				&& $xml->{messages} 
				&& keys %{$xml->{messages}} 
				&& exists $xml->{messages}{message}
				&& $xml->{messages}{message}
				&& exists $xml->{messages}{message}{type}
				&& $xml->{messages}{message}{type}
				&& $xml->{messages}{message}{type} ne 'SUCCESS'
				&& $xml->{messages}{message}{type} ne 'WARNING'
				) {
			    my $cwb_ids = join( ",", @{$raCWBIds} );

				push @Errors,
					"FATAL ERROR adding a memo on one of these correction Requests '"
					. $cwb_ids
					. "', please contact your administrators";				
			}
		}
	}
	else {
		push @Errors,
		  "FATAL ERROR contacting '"
		  . $cwb_url
		  . "', please contact your administrators: '"
		  . $page->message . "'";

	}
    # return    
    return(1);
}

sub Usage
{
   print <<USAGE;
   Usage   : UpdateCWBCRs.pl -a -u -p -f
   Example : UpdateCWBCRs.pl -h
             UpdateCWBCRs.pl -a=https://cid.wdf.sap.corp/sap/bc/bsp/spn -u=git_ngcp -p=**** -f=CWB.txt

   -help|?      argument displays helpful information about builtin commands.
   -a.ddress    specifies the CWB address
   -u.ser       specifies the user name.
   -p.assword   specifies the password. 
   -f.ile       specifies the password
USAGE
    exit;
}
