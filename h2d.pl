use Getopt::Long;
use XML::libXML;
use File::Find;
use File::Path;
use File::Copy;
use XML::DOM;
use FindBin;

##############
# PARAMETERS #
##############

GetOptions("help|?" => \$Help, "dir=s"=>\$Dir, "output=s"=>\$OutputDir);
Usage() if($Help);
die("ERROR: -d.ir option is mandatory.\n") unless($Dir); 
$CURRENTDIR = $FindBin::Bin;
$Dir =~ /([^\\\/]+)$/;
$OutputDir |= "$CURRENTDIR/../$1";

########
# Main #
########

rmtree($OutputDir) or die("ERROR: cannot rmtree '$OutputDir': $!") if(-d "$OutputDir/src/cms");
mkpath("$OutputDir/src/cms/content/authoring") or die("ERROR: cannot mkpath '$OutputDir/src/cms/content/authoring': $!");
mkpath("$OutputDir/src/cms/content/localization/en-US") or die("ERROR: cannot mkpath '$OutputDir/src/cms/content/localization/en-US': $!");
mkpath("$OutputDir/src/cms/content/projects") or die("ERROR: cannot mkpath '$OutputDir/src/cms/content/projects': $!");
copy("$CURRENTDIR/i051369301687777.outputmap", "$OutputDir/src/cms/content/localization/en-US") or die("ERROR: cannot copy 'i051369301687777.outputmap': $!"); 
copy("$CURRENTDIR/i051351610561288.project", "$OutputDir/src/cms/content/projects") or die("ERROR: cannot copy 'i051351610561288.project': $!"); 
system("robocopy /MIR /NP /NFL /NDL /NJS /NJH /R:3 $CURRENTDIR/system $OutputDir/src/cms/system");
system("robocopy /MIR /NP /NFL /NDL /NJS /NJH /R:3 $CURRENTDIR/system $OutputDir/src/cms/content/system");

$Parser = XML::LibXML->new();
$Parser->validation(1);
find(\&H2D, $Dir);

print("$OutputDir/src/cms/content/localization/en-US/2a24c230e52a489f8f979fb9bb9c3a1c.ditamap\n");

$TOC = XML::DOM::Parser->new()->parsefile("$TOC_DIR/toc.xml");
open(MAP, ">$OutputDir/src/cms/content/localization/en-US/2a24c230e52a489f8f979fb9bb9c3a1c.ditamap") or die("ERROR: cannot open '$OutputDir/src/cms/content/localization/en-US/2a24c230e52a489f8f979fb9bb9c3a1c.ditamap': $!");
print(MAP "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
print(MAP "<!DOCTYPE buildable-map PUBLIC \"-//SAP//DTD SAP DITA Map//EN\" \"../../system/dtd/client/sap-map.dtd\">\n");
print(MAP "<buildable-map id=\"aaaaaaa\" xml:lang=\"en-US\">\n");
print(MAP "\t<title>", $TOC->getElementsByTagName('toc')->item(0)->getAttribute('label'), "</title>\n");
print(MAP "\t<sap-map-meta/>\n");
for my $TOPIC (@{$TOC->getElementsByTagName('topic')})
{
    next unless(my $LINK = $TOPIC->getElementsByTagName('link')->item(0));
    (my $HRef = $TOPIC->getAttribute('href')) =~ s/^.*?([^\\\/]+)\.[^\\\/]+$/$1.xml/;
    if($HRef) { print(MAP "\t<topicref href=\"$HRef\">\n") } else { print(MAP "\t<topichead navtitle=\"", $TOPIC->getAttribute('label'), "\">\n") } 
    my $TOCLINK = XML::DOM::Parser->new()->parsefile("$TOC_DIR/".$LINK->getAttribute('toc'));
    TOPIC(2, @{$TOCLINK->getElementsByTagName('toc')->item(0)->getChildNodes()});
    if($HRef) { print(MAP "\t</topicref>\n") } else { print(MAP "\t</topichead>\n") }
    $TOCLINK->dispose();
}
$TOC->dispose();
print(MAP "</buildable-map>\n");
close(MAP);

#############
# Functions #
#############

sub H2D
{
    $TOC_DIR = $File::Find::dir if($_ eq 'toc.xml');
    return unless($File::Find::name =~ /\.html?$/i);
    #next unless($File::Find::name=~/\/using_code_completion\.html/);
    my $DocType;
    return unless(($DocType) = $File::Find::dir =~ /(tasks|concepts)$/);
    if(-d "$File::Find::dir/images" && !$IsCopied{"$File::Find::dir/images"}) { system("robocopy /NP /NFL /NDL /NJS /NJH /R:3 $File::Find::dir/images $OutputDir/src/cms/content/localization/en-US"); $IsCopied{"$File::Find::dir/images"}=undef }
    
    $DocType =~ s/s$//;
    open(HTML, $File::Find::name) or die("ERROR: cannot open '$File::Find::name': $!");
    {
	    local $/ = undef;
        $Lines = <HTML>;	    
	}

    $Lines =~ s/(?:<br>|<br\/>|<\/br>)//gs;
    $Lines =~ s/<td[^>\/]*\/>/<td><\/td>/gs;
    $Lines =~ s/&ndash;/&#8211;/g;
    $Lines =~ s/&nbsp;/&#160;/gs;
    $Lines =~ s/&lsquo;/&#8216;/gs;
    $Lines =~ s/&rsquo;/&#8217;/gs;
    $Lines =~ s/<p>(?:[\n\s]*<b>)?NOTE\s*:?\s*(?:[\n\s]*<\/b>\s*?:?\s*)?(.+?)<\/p>/<note type="note">\n<p>$1<\/p>\n<\/note>/gs;
    $Lines =~ s/<(?:b|strong)\s*>/<emphasis>/gs;
    $Lines =~ s/<\/(?:b|strong)\s*>/<\/emphasis>/gs;
    $Lines =~ s/(<p>[\n\s]*)<code>/$1<codeblock>/gs;
    foreach($Lines =~ s/(<codeblock>.*?)<\/code>/$1<\/codeblock>/gs) {}
    foreach($Lines =~ s/(<codeblock>.*?<\/codeblock>)/Code($1)/egs) {}
    $Lines =~ s/<code>/<codeph>/gs;
    $Lines =~ s/<\/code>/<\/codeph>/gs;
    $Lines =~ s/<img src=".*?([^\\\/]+?)"[^>]*>/<image href="$1"\/>/gs;
    foreach($Lines =~ s/(<dl>.*?<\/dl>)/dl($1)/egs) {}
    foreach($Lines =~ s/(<table[^>]*?>.*?<\/table>)/Table($1)/egs) {}
    my($Title) = $Lines =~ /<h1>(.+?)<\/h1>/gs;

    my($XMLFilePath, $XMLFileName) = $File::Find::name =~ /^(.*)[\\\/]([^\\\/]+)$/;
    $XMLFileName =~ s/\.[^.]+$/.xml/;
    $XMLFilePath =~ s/[\\\/][^\\\/]+[\\\/][^\\\/]+$//;
    push(@TopicRefs, $XMLFileName);
    ($XMLFileName = "$OutputDir/src/cms/content/localization/en-US/$XMLFileName") =~ s/\//\\/g;
    open(XML, ">$XMLFileName") or die("ERROR: cannot open '$XMLFileName': $!");
    print(XML "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    print(XML "<!DOCTYPE $DocType PUBLIC \"-//SAP//DTD SAP DITA Composite//EN\" \"../../system/dtd/client/sap-ditabase-no-constraint.dtd\">\n");
    print(XML "<$DocType id=\"aaaaaaa\" xml:lang=\"en-US\">\n");
    print(XML "\t<title>$Title</title>\n");
    if($DocType eq 'concept')
    {
        my($Body) = $Lines =~ /<\/h1>(.*?)(?:<h[23456789]>|<p>RECOMMENDATION<\/p>|<!-- Related topics -->|<\/body>)/gs;
        $Body =~ s/<h[23456789]>/<b>/gs;
        $Body =~ s/<\/h[23456789]>/<\/b>/gs;
        $Body =~ s/<a.+?href="(.+?)\..+?"[^>]*>/<xref href="$1.xml">/gs;
        $Body =~ s/<\/a>/<\/xref>/gs;
        $Body =~ s/\s&\s/ &amp; /gs;
        my($Recommendation) = $Lines =~ /<p>RECOMMENDATION<\/p>(.*?)(?:<!-- Related topics -->|<\/body>)/gs;
        my($Title, $Section) = $Lines =~ /<h[23456789]>(.+?)<\/h\d>(.*?)(?:<!-- Related topics -->|<\/body>)/gs;
        $Section =~ s/<h[23456789]>/<b>/gs;
        $Section =~ s/<\/h[23456789]>/<\/b>/gs;
        $Section =~ s/<a.+?href="(.+?)\..+?"[^>]*>/<xref href="$1.xml">/gs;
        $Section =~ s/<\/a>/<\/xref>/gs;
        $Section =~ s/["\s]&[",\s]/ &amp; /gs;

        print(XML "\t<conbody>\n");
        print(XML $Body);
        if($Section || $Recommendation)
        {
            print(XML "\t\t<section>\n");
            if($Section)
            {
                print(XML "\t\t\t<title>$Title</title>\n");
                print(XML $Section);
            }
            if($Recommendation)
            {
                print(XML "\t\t\t<sap-recommendation>\n");
                print(XML $Recommendation);
                print(XML "\t\t\t</sap-recommendation>\n");
            }
            print(XML "\t\t</section>\n");
        }
        print(XML "\t<\/conbody>\n");
    }
    else
    {
        my($Context) = $Lines =~ /<\/h1>(.+?)(?:<!-- Prerequisites section -->|<!-- Related topics -->|<!-- Results section -->|<!-- Procedure section -->|<\/body>)/s;
        $Context =~ s/<h[23456789]>/<b>/gs;
        $Context =~ s/<\/h[23456789]>/<\/b>/gs;
        $Context =~ s/<a.+?href="(.+?)\..+?"[^>]*>/<xref href="$1.xml">/gs;
        $Context =~ s/<\/a>/<\/xref>/gs;
        my($PreRequisites) = $Lines =~ /<!-- Prerequisites section -->.*?<h3>Prerequisites<\/h3>(.+?)(?:<!-- Related topics -->|<!-- Results section -->|<!-- Procedure section -->|<\/body>)/s;
        $PreRequisites =~ s/<h[23456789]>/<b>/gs;
        $PreRequisites =~ s/<\/h[23456789]>/<\/b>/gs;
        $PreRequisites =~ s/<!--.*?-->//gs;
        $PreRequisites =~ s/<a.+?href="(.+?)\..+?"[^>]*>/<xref href="$1.xml">/gs;
        $PreRequisites =~ s/<\/a>/<\/xref>/gs;
        my($Result) = $Lines =~ /<!-- Results section -->.*?<h3>Results<\/h3>(.+?)(?:<!-- Prerequisites section -->|<!-- Related topics -->|<!-- Procedure section -->|<\/body>)/s;
        $Result =~ s/<h[23456789]>/<b>/gs;
        $Result =~ s/<\/h[23456789]>/<\/b>/gs;
        my($Steps) = $Lines =~ /<!-- Procedure section -->.*?<h3>Procedure<\/h3>(.+?)(?:<!-- Prerequisites section -->|<!-- Related topics -->|<!-- Results section --><\/body>)/s;
        $Steps =~ s/<!--.*?-->//gs;
        $Steps =~ s/<a.+?href="(.+?)\..+?"[^>]*>/<xref href="$1.xml">/gs;
        $Steps =~ s/<\/a>/<\/xref>/gs;
        print(XML "\t<taskbody>\n") ;
        if($PreRequisites)
        {
            print(XML "\t\t<prereq>\n");
            print(XML "$PreRequisites\n");
            print(XML "\t\t<\/prereq>\n");
        }
        print(XML "\t\t<context>\n");
        print(XML "$Context\n");
        print(XML "\t\t</context>\n");
        if($Steps)
        {
            print(XML "\t\t<steps>\n");
            while($Steps =~ s/(<ul>.*?)<li>(.*?<\/ul>)/$1<il>$2/s) {}
            while($Steps =~ s/(<ul>.*?)<\/li>(.*?<\/ul>)/$1<\/il>$2/s) {}
            while($Steps =~ /<li>(.+?)<\/li>/gs)
            {
                my $SubTarget = ((my $Cmd = $1) =~ s/<ul>(.*?)<\/ul>//s) ? $1 : '';
                print(XML "\t\t\t<step>\n");
                my($Cmd, $TutorialInfo) = $Cmd =~ /^(.*?)((?:<p>|<note|<xref).*)?$/s;
                print(XML "\t\t\t\t<cmd>$Cmd</cmd>\n");
                if($TutorialInfo)
                {
                    print(XML "\t\t\t\t<tutorialinfo>$TutorialInfo<\/tutorialinfo>\n");
                }
                if($SubTarget)
                {
                    print(XML "\t\t\t\t<substeps>\n");
                    while($SubTarget =~ /<il>(.+?)<\/il>/gs)
                    {
                        my($Cmd, $TutorialInfo) = $1 =~ /^(.+?)(<p>.*)?$/s;
                        print(XML "\t\t\t\t\t<substep>\n");
                        print(XML "\t\t\t\t\t\t<cmd>$Cmd</cmd>\n");
                        if($TutorialInfo)
                        {
                            print(XML "\t\t\t\t\t<tutorialinfo>$TutorialInfo<\/tutorialinfo>\n");
                        }
                        print(XML "\t\t\t\t\t</substep>\n");
                    }
                    print(XML "\t\t\t\t</substeps>\n");
                }
                print(XML "\t\t\t<\/step>\n");    
            }
            print(XML "\t\t<\/steps>\n");
        }
        if($Result)
        {
            print(XML "\t\t\t<result>\n");
            print(XML $Result);
            print(XML "\t\t\t<\/result>\n");
        }
        print(XML "\t</taskbody>\n") ;
    }
    if(my($RelatedLinks) = $Lines =~ /<!-- Related topics -->(.+?)(?:<!-- Prerequisites section -->|<!-- Results section -->|<!-- Procedure section -->|<\/body>)/gs)
    {
        print(XML "\t<related-links>\n");
        while($RelatedLinks =~ /<a\s+href="(.*?)".*?>(.+?)</gs)
        {
            my $Description = $2;
            (my $Link = $1) =~ s/\.html/.xml/;
            ($Link) = $Link =~ /([^\\\/]+)$/;
            print(XML "\t\t<link href=\"$Link\">\n");
            print(XML "\t\t\t<desc>$Description</desc>\n");
            print(XML "\t\t</link>\n");
        }
        print(XML "\t<\/related-links>\n");
    }
    print(XML "</$DocType>\n");
    close(XML);
    
    eval { $Parser->parse_file($XMLFileName) };
    if($@) { (my $File=$File::Find::name)=~s/\//\\/g; die("ERROR: '$XMLFileName'\n\tfrom $File:\n $@") }
}

system("robocopy /MIR /NP /NFL /NDL /NJS /NJH /R:3 $OutputDir/src/cms $OutputDir/migration");
rmtree("$OutputDir/migration/system") or die("ERROR: cannot rmtree '$OutputDir/migration/system': $!") if(-d "$OutputDir/migration/system");
rmtree("$OutputDir/migration/content/projects") or die("ERROR: cannot rmtree '$OutputDir/migration/content/projects': $!") if(-d "$OutputDir/migration/content/projects");
rmtree("$OutputDir/migration/content/system") or die("ERROR: cannot rmtree '$OutputDir/migration/content/system': $!") if(-d "$OutputDir/migration/content/system");
rmtree("$OutputDir/migration/content/authoring") or die("ERROR: cannot rmtree '$OutputDir/migration/content/authoring': $!") if(-d "$OutputDir/migration/content/authoring");
rename("$OutputDir/migration/content/localization", "$OutputDir/migration/content/authoring") or die("ERROR: cannot rename '$OutputDir/migration/content/localization': $!");
system("robocopy /MIR /NP /NFL /NDL /NJS /NJH /R:3 $OutputDir/migration/content/authoring/en-US $OutputDir/migration/content/authoring/XML/en_US/dita");

#############
# Functions #
#############

sub TOPIC
{
    my($Level, @Topics) = @_;
    for my $TOPIC (@Topics)
    {
        next unless($TOPIC->getNodeTypeName() eq 'ELEMENT_NODE' && $TOPIC->getTagName() eq 'topic');
        (my $HRef = $TOPIC->getAttribute('href')) =~ s/^.*?([^\\\/]+)\.[^\\\/]+$/$1.xml/;
        if($TOPIC->getElementsByTagName('topic')->item(0))
        {
            if($HRef) { print(MAP "\t"x$Level, "<topicref href=\"$HRef\">\n") } else { print(MAP "\t"x$Level, "<topichead navtitle=\"", $TOPIC->getAttribute('label'), "\">\n") } 
            TOPIC($Level+1, $TOPIC->getChildNodes());
            if($HRef) { print(MAP "\t"x$Level, "</topicref>\n") } else { print(MAP "\t"x$Level, "\t</topichead>\n") }
        } else { print(MAP "\t"x$Level, "<topicref href=\"$HRef\"/>\n") }
    }    
}

sub Table
{
    my($Table) = @_;

    my(@Heads, @Entries);
    my $i =0;
    while($Table =~ /<tr>(.*?)<\/tr>/gs)
    {
        my $Row = $1;
        if($Row =~ /<th[^>]*>/)
        {
            while($Row =~ /<th[^>]*>(.*?)<\/th>/gs) { push(@Heads, $1) }
        }
        else
        {
            while($Row =~ /<td[^>]*>(.*?)<\/td>/gs) { push(@{$Entries[$i]}, $1) }
            $i++;
        }
    }
    $Table = "<table>\n";
    $Table .= "\t<tgroup cols=\"". scalar(@{$Entries[0]}) . "\">\n";
    if(@Heads)
    {
        $Table .= "\t\t<thead>\n";
        $Table .= "\t\t\t<row>\n";
        foreach my $Head (@Heads)
        {
            $Table .= "\t\t\t\t<entry>$Head</entry>\n";
        }
        $Table .= "\t\t\t</row>\n";
        $Table .= "\t\t</thead>\n";
    }
    $Table .= "\t\t<tbody>\n";
    foreach my $raRow (@Entries)
    {
        $Table .= "\t\t\t<row>\n";
        foreach my $Entry (@{$raRow})
        {
            $Table .= "\t\t\t\t<entry>$Entry</entry>\n";
        }
        $Table .= "\t\t\t</row>\n";
    }
    $Table .= "\t\t</tbody>\n";
    $Table .= "\t</tgroup>\n";
    $Table .= "<\/table>\n";

    return $Table;
}
sub dl
{
    my($dl) = @_;
    my $DL = "<dl>\n";
    $DL .= "\t<dlhead>\n";
    $DL .= "\t<\/dlhead>\n";
    while($dl =~ /(<dt>.*?<\/dt>.*?<dd>.*?<\/dd>)/gs) { $DL .= "\t<dlentry>$1<\/dlentry>" }
    $DL .= "<\/dl>";
    return $DL;
}

sub Code
{
    my($Code) = @_;
    $Code =~ s/(?:<p>|<\/p>)//gs;
    return $Code;
}

sub Usage
{
   print <<USAGE;
   Usage   : h2d.pl -h -d
             h2d.pl -h.elp|?
   Example : h2d.pl -d=D:\\HANA\\cms -o=C:\project
    
   [options]
   -help|?   argument displays helpful information about builtin commands.
   -d.ir     specifies the source directory.
   -o.utput  specifies the destination directory.
USAGE
    exit;
}
