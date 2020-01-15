use Archive::Tar;
use Getopt::Long;
use XML::LibXML;

unless (@ARGV) { print(STDERR "ERROR: arguments are mandatory.\n"); Usage() }

$Getopt::Long::ignorecase = 0;
GetOptions(
"build--nb=s"=>\$BuildNumber,
"context=s"=>\$Context,
"drop--dir=s"=>\$DROP_DIR,
"output--dir=s"=>\$OUTPUT_DIR,
"src--dir=s"=>\$SRC_DIR);


unless ($SRC_DIR) { print(STDERR "ERROR: src--dir option is mandatory.\n"); Usage() };
unless ($DROP_DIR) { print(STDERR "ERROR: drop--dir option is  mandatory.\n"); Usage() };
unless ($Context) { print(STDERR "ERROR:  context option is mandatory.\n"); Usage() };
unless ($BuildNumber) { print(STDERR "ERROR: build--nb option is mandatory.\n"); Usage() };
unless ($OUTPUT_DIR) { print(STDERR "ERROR: output--dir option is mandatory.\n"); Usage() };

my @files = glob("${OUTPUT_DIR}/bin/WebI/wise_artifacts/*.tgz");#TO DO : take -t path instead of this one
my $log;
my $scm_activity_log_file="package/scm_activity.log"; # Fixed path that all nexus artifacts must follow to track their activities
#my $context_filepath = "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files/$Context.context.xml";
my $context_filepath = "$DROP_DIR/$Context/$BuildNumber/contexts/allmodes/files/$Context.context.xml";
foreach my $artifact (@files)
{
    my $tar = Archive::Tar->new;
    $tar->read("${artifact}");

    if( ! $tar->contains_file($scm_activity_log_file) )
    {
      print("INFO: No scm activity log file ($scm_activity_log_file) found in artifact \"${artifact}\"\n");
      next;
    }
    $log = $tar->get_content($scm_activity_log_file);

    my ($remote_origin_url) = $log =~ / *remote_origin_url *= *(.*)/;
    my ($branch_name) = $log =~ / *branch_name *= *(.*)/;
    my ($commit_id) = $log =~ / *commit_id *= *(.*)/;
    if ( !defined($remote_origin_url) || !defined($branch_name) || !defined($commit_id)){
      print ("WARNING: scm activity log file content issue in artifact \"${artifact}\"\n");
      next;
    }
    my $parser = XML::LibXML->new;
    
    my $doc = $parser->parse_file("$context_filepath");
    my $root = $doc->getDocumentElement();
    my $git = $doc->createElement("git");

    $git->setAttribute('repository'=> "${remote_origin_url}");
    $git->setAttribute('refspec'=>$branch_name);
    $git->setAttribute('destination'=>""); # Test only
    $git->setAttribute('startpoint'=> "${commit_id}");
    $git->setAttribute('logicalstartpoint'=> "FETCH_HEAD");
    $git->setAttribute('nexus_artifact'=> "${artifact}");

    my ($ref_node) = $doc->findnodes('//version[1]');

    $ref_node->parentNode->insertBefore($git, $ref_node);
    open XML, ">$context_filepath";
    print XML $doc->toString();
    close XML;
}

sub Usage
{
   print <<USAGE;
   Usage   : GitContext.pl [options]

   [options]
   -build--nb specifies the build number.
   -context specifies the build context informations (Context).
   -drop--dir    Used to deduce context file to be edited  (DROP_DIR).
   -output--dir specifies the local storage directory where the  artifacts are imported (OUTPUT_DIR).
   -src--dir specifies the path where the code source is fetched (SRC_DIR).
USAGE
    exit;
}
