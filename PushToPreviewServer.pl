use HTTP::Request::Common 'POST';
use LWP::UserAgent;
use File::Basename;
use Getopt::Long;
use LWP::Simple;


##############
# Parameters #
##############

$PROXY = 'http://proxy.wdf.sap.corp:8080';

GetOptions("help|?" => \$Help, "file=s"=>\$File, "name=s"=>\$Name, "url=s"=>\$URL);
unless($File) { warn("ERROR: -f.ile parmeter is mandatory"); Usage() }
unless($Name) { warn("ERROR: -n.ame parmeter is mandatory"); Usage() }
unless($URL) { warn("ERROR: -u.rl parmeter is mandatory"); Usage() }

########
# Main #
########

print("Sending '$File' called '$Name' to '$URL': \n");
my $ua = LWP::UserAgent->new() or warn("ERROR: ==$Name== cannot create LWP agent: $!");
$ua->proxy(['http', 'https'] => $PROXY);
my $req=POST $URL, Content_Type => 'multipart/form-data',
				   Content => [archive => [$File, basename($File), "Content-Type" => "application/zip"], name => "$Name",];
my $Response = $ua->request($req);
unless($Response->is_success())
{
	warn($Response->status_line()=~/(?:200|201|302|500)/?"WARNING":"ERROR", ": ==$Name== ", $Response->status_line());
	print($Response->content(), "\n");
}

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : PushToPreviewServer.pl -h -f -n -u 
             PushToPreviewServer.pl -h.elp|?
   Example : PushToPreviewServer.pl -f=D:\\HANA\\src 
    
   [options]
   -help|?  argument displays helpful information about builtin commands.
   -f.ile   specifies the source directory, default is \$ENV{SRC_DIR}.
   -f.ile   specifies the name.
   -u.rl    specifies the preview server URL.
USAGE
    exit;
}