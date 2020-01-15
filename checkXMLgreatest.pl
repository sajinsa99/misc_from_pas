use XML::Parser;
use Getopt::Long;

use File::Spec::Functions;


use vars qw (
	$PROJECT
	$CONTEXT
	$VERSION
	$DROP_DIR
	$File
);

$Getopt::Long::ignorecase = 0;
GetOptions(
	"prj=s"		=>\$PROJECT,
	"c=s"		=>\$CONTEXT,
	"v=s"		=>\$VERSION,
	"f=s"		=>\$File
);

$PROJECT ||= "aurora_dev";
$ENV{PROJECT} = $PROJECT;
$CONTEXT ||="aurora41_cons";

$ENV{SITE} ||="Walldorf";

require Site;
$DROP_DIR = $ENV{DROP_DIR};
$VERSION ||=`ls $DROP_DIR/$CONTEXT | grep _greatest`;
chomp($VERSION);
$File ||= catdir($DROP_DIR,$CONTEXT,$VERSION,"contexts","allmodes","files","$CONTEXT.context.xml");
 
my $parser= new XML::Parser();
eval {$parser->parsefile( $File )};
if ($@) { die "\n $File invalid : \n\t\t $@\n" ; }
else { print "$File check OK\n" ; }
exit;
