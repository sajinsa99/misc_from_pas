#!/usr/bin/perl -w

use UUID::Generator::PurePerl;
use File::Find;
use File::Path;
use XML::DOM;

##############
# Parameters #
##############

$SRC_DIR = 'C:\IxiaPilot\XML';
$DST_DIR = 'C:\IxiaPilot\XML_new';
@DocTypes{qw(concept dita map reference task topic ditabuild)} = ();

($SrcDir = $SRC_DIR) =~ s/\\/\//g;
($DstDir = $DST_DIR) =~ s/\\/\//g;

########
# Main #
########

$GUIDGenerator = UUID::Generator::PurePerl->new();

rmtree($DST_DIR) or warn("ERROR: cannot rmtree '$DST_DIR': $!") if(-e $DST_DIR);
system("robocopy /MIR /NP /NFL /NDL /R:3 \"$SRC_DIR\" \"$DST_DIR\"");
system("robocopy /E /NP /NFL /NDL /R:3 \"$SRC_DIR/../XML_OutputMap\" \"$DST_DIR\"");

find(\&LOIO, $SrcDir);

#############
# Functions #
#############

sub LOIO
{
    return unless(-f $File::Find::name);
    return unless($File::Find::name =~ /\.(ditamap|dita|xml)$/i);

    #return unless($File::Find::name =~ /chart_graph_options\.dita/);    # DEBUG ONLY

    $DOCUMENT = XML::DOM::Parser->new()->parsefile("$File::Find::name");
    my $DocType = $DOCUMENT->getDoctype();
    unless($DocType) { warn("ERROR: DOCTYPE is in undefined in $File::Find::name."); $DOCUMENT->dispose(); return }
    my $DocTypeName = $DocType->getName();
    unless(exists($DocTypes{$DocTypeName})) { warn("ERROR: '$DocTypeName' DOCTYPE unknow  in '$File::Find::name'"); $DOCUMENT->dispose(); return }
    if($DocTypeName eq "ditabuild" or $DocTypeName eq "map") { $DOCUMENT->dispose(); return}

    my $PROLOG = $DOCUMENT->getElementsByTagName('prolog')->item(0);
    unless($PROLOG)
    { 
        warn("ERROR: <prolog> tag not found in $File::Find::name\n");
        $PROLOG = $DOCUMENT->createElement('prolog');
        $PROLOG->setAttribute('class', '- topic/prolog ');
        if(my $CONCEPT=$DOCUMENT->getElementsByTagName('concept')->item(0)) { $CONCEPT->appendChild($PROLOG) }
        elsif(my $TASK=$DOCUMENT->getElementsByTagName('task')->item(0))    { $TASK->appendChild($PROLOG) }
        elsif(my $DITA=$DOCUMENT->getElementsByTagName('dita')->item(0))    { $DITA->appendChild($PROLOG) }
        else { die("ERROR: tag 'concept|task|dita) not found in $File::Find::name") }
    }
    my $GUID = $GUIDGenerator->generate_v1();
    $GUID =~s/-//g;
    $GUID = "sap\U$GUID";
    my $COMMENT = $DOCUMENT->createComment("resourceid id=\"$GUID\" appname=\"sap_GUID\"");
    $PROLOG->appendChild($COMMENT);
    (my $FullPathName = $File::Find::name) =~ s/^$SrcDir/$DstDir/;
    open(XML, "| cat >\"$FullPathName\"") or die("ERROR: cannot open '$FullPathName': $!.");
    binmode XML, ":utf8";
    print(XML $DOCUMENT->toString());
    close(XML);    
    $DOCUMENT->dispose();
}
