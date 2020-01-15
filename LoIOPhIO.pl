#!/usr/bin/perl -w

use Data::Dumper;
use File::Find;
use XML::DOM;

die("ERROR: the environment variable SRC_DIR must be set") unless(exists($ENV{SRC_DIR}));
die("ERROR: the environment variable HTTP_DIR must be set") unless(exists($ENV{HTTP_DIR}));
die("ERROR: the environment variable context must be set") unless(exists($ENV{context}));
die("ERROR: the environment variable BUILD_NAME must be set") unless(exists($ENV{BUILD_NAME}));
die("ERROR: the environment variable PLATFORM must be set") unless(exists($ENV{PLATFORM}));
die("ERROR: the environment variable BUILD_MODE must be set") unless(exists($ENV{BUILD_MODE}));

########
# Main #
########

exit if(exists($ENV{MY_PROJECTMAP}));
find(\&PhIO, "$ENV{SRC_DIR}/cms/content/localization");
open(DAT, ">$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=$ENV{PLATFORM}_$ENV{BUILD_MODE}_loiophio_1.dat") or warn("ERROR: cannot open '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=$ENV{PLATFORM}_$ENV{BUILD_MODE}_loiophio_1.dat': $!");
$Data::Dumper::Indent = 0;
print DAT Data::Dumper->Dump([\%LoIOs], ["*LoIOs"]);
close(DAT);

#############
# Functions #
#############

sub PhIO
{
    return unless(my($Language, $LoIO) = $File::Find::name =~ /[\\\/]localization[\\\/]([^\\\/]+).*([0-9a-f]{32})\.xml$/i);

    (my $Properties = $File::Find::name) =~ s/\.xml/.properties/;
    my $DOCUMENTPROPERTIES = XML::DOM::Parser->new()->parsefile($Properties);
    my $Name = $DOCUMENTPROPERTIES->getElementsByTagName('name')->item(0)->getFirstChild()->getData();
    my $Collection = $DOCUMENTPROPERTIES->getElementsByTagName('collection')->item(0)->getFirstChild()->getData();
    my $Version = $DOCUMENTPROPERTIES->getElementsByTagName('version')->item(0)->getFirstChild()->getData();
    $DOCUMENTPROPERTIES->dispose();

    ${$LoIOs{$Language}}{$LoIO} = "$Collection$Name;$Version";
}