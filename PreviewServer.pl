#!/usr/bin/perl -w

use HTTP::Request::Common 'POST';
use LWP::UserAgent;
use Getopt::Long;
use LWP::Simple;
use XML::DOM;
use Exec;

##############
# Parameters #
##############

GetOptions("help|?" => \$Help, "src=s"=>\$SRC_DIR, "url=s"=>\$URL);
Usage() if($Help);
$SRC_DIR ||= $ENV{SRC_DIR};
unless($URL) { warn("ERROR: -u.rl parmeter is mandatory"); Usage() }
($OUTPUT_DIR = $SRC_DIR) =~ s/src/win64_x64/;

########
# Main #
########

$CMSProject = <$SRC_DIR/cms/content/projects/*.project>;
$PROJECT = XML::DOM::Parser->new()->parsefile($CMSProject);
for my $DELIVERABLE (@{$PROJECT->getElementsByTagName('deliverable')})
{
    for my $FULLPATH (@{$DELIVERABLE->getElementsByTagName('fullpath')})
    {
        my $FullPath = $FULLPATH->getFirstChild()->getData();
        eval
        {   
            my $DOCUMENT = XML::DOM::Parser->new()->parsefile("$SRC_DIR/cms/$FullPath");
            if(my $OUTPUT = $DOCUMENT->getElementsByTagName('output')->item(0))
            {
                my $Id = $OUTPUT->getAttribute('id');
                push(@OutputMaps, [$Id, $FullPath]);
            }
            $DOCUMENT->dispose();
        };
        warn("ERROR: cannot parse outputmap '$SRC_DIR/cms/$FullPath': $@; $!") if($@);
    }
}
$PROJECT->dispose();

foreach (@OutputMaps)
{
    my($GUID, $FullPath) = @{$_};
    my $OUTPUT = XML::DOM::Parser->new()->parsefile("$SRC_DIR/cms/$FullPath");

    my $IsNewVersion = ($OUTPUT->getDoctype() && $OUTPUT->getDoctype()->getPubId()=~/\s1\.1\s/) || 0;
    my($PhIO) = $FullPath =~ /([^\/]*)\.ditamap$/;
    my($Title) = $OUTPUT->getElementsByTagName('title')->item(0)->getFirstChild()->getData();

    if($IsNewVersion)
    {
        my $GUID = $OUTPUT->getElementsByTagName('output')->item(0)->getAttribute('id');
        my $OUTPUTMETA = $OUTPUT->getElementsByTagName('outputMeta')->item(0);
        (my $TransType = $OUTPUTMETA->getElementsByTagName('transtype')->item(0)->getAttribute('value'));
        for my $LANGUAGEMETA (@{$OUTPUT->getElementsByTagName('languageMeta')})
        {
            my($Language, $OutputFileName, $DefaultStatus) = ($LANGUAGEMETA->getAttribute('id'), $LANGUAGEMETA->getElementsByTagName('outputFilename')->item(0)->getAttribute('value'), $LANGUAGEMETA->getAttribute('pubStatus'));
            next if($Language eq 'All');
            foreach my $DELIVERYCHANNEL (@{$LANGUAGEMETA->getElementsByTagName('deliveryChannel')})
            {
                my($Name, $Value, $Type, $Status, $Params) = ($DELIVERYCHANNEL->getAttribute('name'), $DELIVERYCHANNEL->getAttribute('value'), $DELIVERYCHANNEL->getAttribute('type'), $DELIVERYCHANNEL->getAttribute('pubStatus')||$DefaultStatus);
                next unless($Status eq 'enabled');
                foreach my $PARAMETER (@{$DELIVERYCHANNEL->getElementsByTagName('parameter')})
                {
                    my($Key, $Value) = ($PARAMETER->getAttribute('name'), $PARAMETER->getAttribute('value'));
                }
                ${${${${$Channels{$FullPath}}{$Name}}{$Type}}{$Language}}{'value'}     = $Value;
                ${${${${$Channels{$FullPath}}{$Name}}{$Type}}{$Language}}{'transtype'} = $TransType;
                ${${${${$Channels{$FullPath}}{$Name}}{$Type}}{$Language}}{'outputname'} = $OutputFileName;
                foreach my $PARAMETER (@{$DELIVERYCHANNEL->getElementsByTagName('parameter')})
                {
                    my($Key, $Value) = ($PARAMETER->getAttribute('name'), $PARAMETER->getAttribute('value'));
                    ${${${${$Channels{$FullPath}}{$Name}}{$Type}}{$Language}}{$Key} = $Value;
                }
            }
        }
    }
    $OUTPUT->dispose();
}

$Jobs = Exec->new();
foreach my $FullPath (keys(%Channels))
{
    foreach my $Name (keys(%{$Channels{$FullPath}}))
    {
        next unless($Name eq 'preview-server');
        foreach my $Type (keys(%{${$Channels{$FullPath}}{$Name}}))
        {
            next unless($Type eq 'pre-publishing');
            foreach my $Language (keys(%{${${$Channels{$FullPath}}{$Name}}{$Type}}))
            {
                my %Parameters = %{${${${$Channels{$FullPath}}{$Name}}{$Type}}{$Language}};

                print("== PUSH TO PREVIEW SERVER ==\n\ttype=$Type\n\tlanguage=$Language\n");
                map({print("\t$_=$Parameters{$_}\n")} keys(%Parameters));

                (my $TransType = $Parameters{transtype}) =~ s/\./00/g;
                (my $Stream = $FullPath) =~ s/^.+[\\\/](.+)\.ditamap$/${Language}_$1/;

                $Jobs->start(undef, "perl PushToPreviewServer.pl -f=$OUTPUT_DIR/packages/$TransType/$Language/release/$FullPath -n=$Stream -u=$URL", 3);
            }
        }
    }
}

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : PreviewServer.pl -h -s 
             PreviewServer.pl -h.elp|?
   Example : PreviewServer.pl -s=D:\\HANA\\src 
    
   [options]
   -help|?   argument displays helpful information about builtin commands.
   -s.ource  specifies the source directory, default is \$ENV{SRC_DIR}.
   -u.rl     specifies the preview server URL.
USAGE
    exit;
}
