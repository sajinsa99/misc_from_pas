#!/usr/bin/perl -w

use Getopt::Long;
use Data::Dumper;
use File::Path;
use File::Find;
use File::Copy;
use XML::DOM;

##############
# Parameters #
##############

GetOptions("help|?" => \$Help, "cms=s"=>\$CMS_DIR, "name=s"=>\$BuildName, "project=s"=>\$Project, "source=s"=>\$SRC_DIR, "stream=s"=>\$Stream, "output=s"=>\$OUTPUT_DIR);
Usage() if($Help);

$Stream    ||= $ENV{context} || 'i051348819098590';
$Project   ||= $ENV{PROJECT} || 'documentation';
($SRC_DIR ||= $ENV{SRC_DIR} || 'E:\$Stream\src') =~ s/\\/\//g;
($OUTPUT_DIR ||= $ENV{OUTPUT_DIR} || 'E:\$Stream\win64_x64\release') =~ s/\\/\//g;
($CMS_DIR ||= "$SRC_DIR/cms") =~ s/\\/\//g;
$BuildName ||= $ENV{BUILD_NAME};

########
# Main #
########

$CMSProject = <$CMS_DIR/content/projects/*.project>;
$PROJECT = XML::DOM::Parser->new()->parsefile($CMSProject);
for my $DELIVERABLE (@{$PROJECT->getElementsByTagName('deliverable')})
{
    for my $FULLPATH (@{$DELIVERABLE->getElementsByTagName('fullpath')})
    {
        my $FullPath = $FULLPATH->getFirstChild()->getData();
        (my $OutputMap = "$CMS_DIR$FullPath") =~ s/^$SRC_DIR\///;
        eval
        {   
            my $DOCUMENT = XML::DOM::Parser->new()->parsefile("$SRC_DIR/$OutputMap");
            if(my $OUTPUT = $DOCUMENT->getElementsByTagName('output')->item(0))
            {
                my $Id = $OUTPUT->getAttribute('id');
                push(@OutputMaps, [$OutputMap, $Id, $FullPath]);
            }
            $DOCUMENT->dispose();
        };
        warn("ERROR: cannot parse outputmap '$SRC_DIR/$OutputMap': $@; $!") if($@);
    }
}
$PROJECT->dispose();

# %Areas{Area}{Language}{TransType} = [OutputMap, OutputFile]
my %isNewOutputMapsVersions;
mkpath("$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files") or warn("ERROR: cannot mkpath '$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files': $!") unless(-e "$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files");
foreach (@OutputMaps)
{
    my($OutputMap, $GUID, $FullPath) = @{$_};
    my $OUTPUT = XML::DOM::Parser->new()->parsefile("$SRC_DIR/$OutputMap");
    # [BESTL-2371] Remove previous expender form build process and validate in Dev system 
    $isNewOutputMapsVersions{"$SRC_DIR/$OutputMap"}=($OUTPUT->getDoctype() && $OUTPUT->getDoctype()->getPubId() =~ /\s1\.1\s/) || 0;
    my $Value = $isNewOutputMapsVersions{"$SRC_DIR/$OutputMap"} ? 'value' : 'content';
    
    (my $Title = $OUTPUT->getElementsByTagName('title')->item(0)->getFirstChild()->getData()) =~ s/\s+/_/g;
    (my $BuildableMapLoIO = $OUTPUT->getElementsByTagName('mapref')->item(0)->getAttribute('href')) =~ s/\.ditamap$//;
    
    my(%OutputFileNames, $DefaultOutputFileName, $IsMetadaToGenerate);
    for my $LANGUAGEMETA (@{$OUTPUT->getElementsByTagName('languageMeta')})
    {
        my($Id, $DefaultStatus, $OutputFileName) = ($LANGUAGEMETA->getAttribute('id'), $LANGUAGEMETA->getAttribute('pubStatus'), $LANGUAGEMETA->getElementsByTagName('outputFilename')->item(0)->getAttribute($Value));
        if($Id =~ /^All$/i) { $DefaultOutputFileName = $OutputFileName }
        else { ($OutputFileNames{$Id} = $OutputFileName) =~ s/\[lang\]/$Id/g }
        if($isNewOutputMapsVersions{"$SRC_DIR/$OutputMap"})
        {
DELIVERYCHANNELS:            
			foreach my $DELIVERYCHANNEL (@{$LANGUAGEMETA->getElementsByTagName('deliveryChannel')})
            {
                my($Name, $Value, $Status) = ($DELIVERYCHANNEL->getAttribute('name'), $DELIVERYCHANNEL->getAttribute('value'), $DELIVERYCHANNEL->getAttribute('pubStatus')||$DefaultStatus);
                next DELIVERYCHANNELS unless($Status && $Status eq 'enabled'); 
                if($Name eq 'preview-server' && $Value=~/^https?:/) { $IsMetadaToGenerate=1; last DELIVERYCHANNELS }
                foreach my $PARAMETER (@{$DELIVERYCHANNEL->getElementsByTagName('parameter')})
                {
                    my($parameterName, $parameterValue) = ($PARAMETER->getAttribute('name'), $PARAMETER->getAttribute('value'));
                    if($parameterName && $parameterName eq "metadata" && $parameterValue) {$IsMetadaToGenerate=1; last DELIVERYCHANNELS }
                }
            }
        }
        else
        {
            my $PREPUBLISHING = $LANGUAGEMETA->getElementsByTagName('prepublishing');
            if($PREPUBLISHING->getLength())
            {
                $IsMetadaToGenerate = 1 if($PREPUBLISHING->item(0)->getAttribute('pubStatus') ne 'disabled' && $PREPUBLISHING->item(0)->getAttribute('url') =~ /^https?:/);
            }
        }
    }
    my $OUTPUTMETA = $OUTPUT->getElementsByTagName('outputMeta')->item(0);
    $DefaultOutputFileName ||= $OUTPUTMETA->getElementsByTagName('outputFilename')->item(0)->getAttribute($Value) unless($isNewOutputMapsVersions{"$SRC_DIR/$OutputMap"});
    if($isNewOutputMapsVersions{"$SRC_DIR/$OutputMap"}) { $OutputOwner=$OUTPUTMETA->getElementsByTagName('outputOwner')->getLength()>0 ? $OUTPUTMETA->getElementsByTagName('outputOwner')->item(0)->getAttribute('value'):'' }
    else { $OutputOwner=$OUTPUTMETA->getElementsByTagName('outputOwner')->item(0)->getFirstChild() ? $OUTPUTMETA->getElementsByTagName('outputOwner')->item(0)->getFirstChild()->getData():'' }
    my($TransType, $Languages) = ($OUTPUTMETA->getElementsByTagName('transtype')->item(0)->getAttribute($Value), $OUTPUTMETA->getElementsByTagName('languages')->item(0)->getAttribute($Value));
    my($Strm) = $OutputMap =~ /([^\/]+)\.ditamap$/;
    (my $TrnsTp = $TransType) =~ s/\./00/g;
    foreach my $Language (split('\s*;\s*', $Languages))
    {
        (my $DOFN = $DefaultOutputFileName) =~ s/\[lang\]/$Language/g;
        my $OFN = exists($OutputFileNames{$Language}) ? $OutputFileNames{$Language} : $DOFN;
        warn("ERROR: outputFilename not found for '$Language' in '$OutputMap' ($Title)") unless($OFN);
        @{${${$Areas{"${Language}_$Strm"}}{$Language}}{$TransType}} = ($OutputMap, $OFN, $IsMetadaToGenerate);
        $Properties{"${Language}_$Strm"} = [$Title, $GUID, $FullPath, $OutputOwner, "packages/$TrnsTp/$Language/$ENV{BUILD_MODE}/$OFN", "loio$BuildableMapLoIO"];
    }
    $OUTPUT->dispose();
    copy("$SRC_DIR/$OutputMap", "$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/") or warn("ERROR: cannot copy '$SRC_DIR/$OutputMap' to '$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/': $!");
    mkpath("$OUTPUT_DIR/obj") or warn("ERROR: cannot mkpath '$OUTPUT_DIR/obj': $!") unless(-d "$OUTPUT_DIR/obj");
    print("$SRC_DIR/$OutputMap ($Title)\n");
    # only execute this line if the output map is an old version because the new DITA-OT SAP Wrapper does not know how to deal with the old one containing DITAVALs
    unless($isNewOutputMapsVersions{"$SRC_DIR/$OutputMap"})
    {
        my($Stream) = $OutputMap =~ /([^\/]+)\.ditamap$/;
        print("\tGenerating '$OUTPUT_DIR/obj/$Stream.ditaval'\n");
        system("java -cp $OUTPUT_DIR/bin/core.build.tools.docs/src/landscape-conditions-management/dropins/landscape-conditions-management.jar com.sap.prd.dita.demo.OutputMapToDITAVal -conditional $OUTPUT_DIR/bin/core.build.tools.docs/com.ixasoft/textml/Repository/system/conf/conditionaltext.xml -outputmap $SRC_DIR/$OutputMap -out $OUTPUT_DIR/obj/$Stream.ditaval");
    }
}

($CMSProjectName) = $CMSProject =~ /([^\\\/]+)\.project$/; 
copy("$SRC_DIR/cms/$CMSProjectName.project.mf.xml", "$ENV{HTTP_DIR}/$Stream/$BuildName/$BuildName.project.mf.xml") or warn("ERROR: cannot copy '$SRC_DIR/cms/$CMSProjectName.project.mf.xml' to '$ENV{HTTP_DIR}/$Stream/$BuildName/$BuildName.project.mf.xml': $!");
copy("$SRC_DIR/cms/$CMSProjectName.project.mf.xml", "$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/") or warn("ERROR: cannot copy '$SRC_DIR/cms/$CMSProjectName.project.mf.xml' to '$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/': $!");
copy("$SRC_DIR/cms/content/projects/$CMSProjectName.project", "$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/") or warn("ERROR: cannot copy '$SRC_DIR/cms/content/projects/$CMSProjectName.project' to '$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/': $!");

open(GMK, ">$SRC_DIR/$Project/export/$Stream.gmk") or die("ERROR: cannot open '$SRC_DIR/$Project/export/$Stream.gmk': $!");
print(GMK "export AREAS=", join(' ', keys(%Areas)), "\n");
print(GMK "#ifndef SRC_DIR\n");
print(GMK "SRC_DIR := \$(shell for n in 1 2 3 4 5; do \\\n");
print(GMK "     test -f Build/export/root.gmk && { pwd; break; }; cd ..; done)\n");
print(GMK "#endif\n");
print(GMK "include \$(SRC_DIR)/documentation/export/DITA_Area.gmk\n");
close(GMK);

foreach my $Area (keys(%Areas))
{
    mkpath("$SRC_DIR/$Area") or warn("ERROR: cannot mkpath '$SRC_DIR/$Area': $!") unless(-e "$SRC_DIR/$Area");
    unless(open(GMK, ">".Win32::GetShortPathName("$SRC_DIR/$Area")."/$Area.gmk")) { warn("ERROR: cannot open '$SRC_DIR/$Area/$Area.gmk': $!"); next }

    my($GUId) = $Area =~ /_([^_]+)$/;
    print(GMK "ifndef SRC_DIR\n");
    print(GMK "\tSRC_DIR := \$(shell for n in 1 2 3 4 5; do test -f Build/export/root.gmk && { pwd; break; }; cd ..; done)\n");
    print(GMK "endif\n");
    print(GMK "include \$(SRC_DIR)/documentation/export/DITA_Unit.gmk\n\n");
    print(GMK "AREA=$Area\n");
    print(GMK "ifneq (\$(rmbuild_type),Smoke)\n");
    print(GMK "\tifneq (\$(rmbuild_type),Export)\n");
    print(GMK "\t\texport UNITS=");
    foreach my $Language (keys(%{$Areas{$Area}}))
    {
        foreach $TransType (keys(%{${$Areas{$Area}}{$Language}}))
        {
            $TransType =~ s/\./00/g;
            print(GMK "build_${TransType}_$Area ");
        }
    }
    print(GMK "\n\telse\n\t");
    print(GMK "\texport UNITS=");
    foreach my $Language (keys(%{$Areas{$Area}}))
    {
        foreach $TransType (keys(%{${$Areas{$Area}}{$Language}}))
        {
            $TransType =~ s/\./00/g;
            print(GMK "export_${TransType}_${Area}_", defined($ENV{RC_BUILD_NUMBER})?"publishing":"prepublishing", " ");
        }
    }
    print(GMK "\n\tendif\n");
    print(GMK "else\n\t");
    print(GMK "export UNITS=");
    foreach my $Language (keys(%{$Areas{$Area}}))
    {
        foreach $TransType (keys(%{${$Areas{$Area}}{$Language}}))
        {
            $TransType =~ s/\./00/g;
            print(GMK "smoke_${TransType}_$Area ");
        }
    }
    print(GMK "\nendif\n");
    print(GMK "\n");
    foreach my $Language (keys(%{$Areas{$Area}}))
    {
        foreach $TransType (keys(%{${$Areas{$Area}}{$Language}}))
        {
            my($OutputMap, $OutputFileName, $IsMetadaToGenerate) = @{${${$Areas{$Area}}{$Language}}{$TransType}};
            $TransType =~ s/\./00/g;
            print(GMK "build_${TransType}_$Area:\n");
            print(GMK "\t\$(SUBUNIT_START) run build_${TransType}_$Area...\n");
            if($TransType eq 'wiki00sap')
            {
                my $OUTPUT = XML::DOM::Parser->new()->parsefile("$SRC_DIR/$OutputMap");
                my $HRef = $OUTPUT->getElementsByTagName('mapref')->item(0)->getAttribute('href');
                $OUTPUT->dispose();
                my($PhIO) = $OutputMap =~ /([^\/]*)\.ditamap$/;
                print(GMK "\tcd \$(OUTPUT_DIR)/bin/core.build.tools.docs/dita2confluence ; \$(ANT_HOME)/bin/ant -noclasspath -Dcontent=\$(OUTPUT_DIR)/bin/core.build.tools.docs/dita2confluence/confluence.content_$PhIO.xml\n");
            }
            else
            {
                mkpath("$OUTPUT_DIR/../packages/$TransType/$Language/$ENV{BUILD_MODE}") or warn("ERROR: cannot mkpath '$OUTPUT_DIR/../packages/$TransType/$Language/$ENV{BUILD_MODE}': $!") unless(-e "$OUTPUT_DIR/../packages/$TransType/$Language/$ENV{BUILD_MODE}");
                mkpath("$OUTPUT_DIR/obj/$Area/$TransType/$Language/$ENV{BUILD_MODE}") or warn("ERROR: cannot mkpath '$OUTPUT_DIR/obj/$Area/$TransType/$Language/$ENV{BUILD_MODE}': $!") unless(-e "$OUTPUT_DIR/obj/$Area/$TransType/$Language/$ENV{BUILD_MODE}");
                (my $LocalOutputMap = $OutputMap) =~ s/authoring/localization\/$Language/;
                my $OMap = -e "$SRC_DIR/$LocalOutputMap" ? $LocalOutputMap : $OutputMap;
# temporary fix waiting for fetch tools fix
# Louis: put in comment as the new fetcher fixing localized dirs was delivered so we do not need anymore this workaround 
# $OMap = $OutputMap if($Language eq 'en-US');
                my($Stream) = $OMap =~ /([^\/]+)\.ditamap$/;
                print(GMK "\tcd \$(OUTPUT_DIR)/bin/tp.net.sf.dita-ot ; \$(ANT_HOME)/bin/ant -f build_sap.xml \$(DITA_OT_OPTIONS) ", $IsMetadaToGenerate?"-Dsap.preview-server.metadata.dir=\$(OUTPUT_DIR)/../packages/additional/$Area/$TransType/$Language/\$(BUILD_MODE) -Dsap.args.project=\"$CMSProject\"":"", " -Dclean.temp=no ".($isNewOutputMapsVersions{"$SRC_DIR/$OutputMap"}?"":"-Dsap.ditaval=\"\$(OUTPUT_DIR)/obj/$Stream.ditaval\" ")."-Dsap.args.input=\"\$(SRC_DIR)/$OMap\" -Dargs.debug=", $ENV{BUILD_MODE}eq'debug'?'yes':'no' ," -Dsap.temp.dir=\$(OUTPUT_DIR)/obj/$Area/$TransType/$Language/\$(BUILD_MODE) -Dsap.args.locale=$Language -Dsap.output.dir=\$(OUTPUT_DIR)/../packages/$TransType/$Language/\$(BUILD_MODE) -Dsap.output.name=\"$OutputFileName\" -Dsap.log.dir=\$(OUTPUT_DIR)/logs/$Area -Dsap.args.project=\"$CMSProject\" -Dsap.chmhp.dat.dir=\${SRC_DIR}/documentation/export/dat\n");
            }
            print(GMK "\n");
            print(GMK "smoke_${TransType}_$Area:\n");
            print(GMK "\t\$(SUBUNIT_START) run smoke_${TransType}_$Area...\n");
            print(GMK "\t\@test -s \"\\$ENV{DROP_DIR}/$ENV{Context}/$ENV{build_number}/packages/$TransType/$Language/\$(BUILD_MODE)/$OutputFileName\" || echo \"[SMKP0001F][FATAL] '$ENV{DROP_DIR}/$ENV{Context}/$ENV{build_number}/packages/$TransType/$Language/\$(BUILD_MODE)/$OutputFileName' is not available.\"\n");
            print(GMK "\n");
            print(GMK "export_${TransType}_${Area}_", defined($ENV{RC_BUILD_NUMBER})?"publishing":"prepublishing", ":\n");
            print(GMK "\t\$(SUBUNIT_START) run export_${TransType}_$Area...\n");
            print(GMK "\tperl \$(OUTPUT_DIR)/bin/core.build.tools/export/shared/prepublishingOutput.pl ", defined($ENV{RC_BUILD_NUMBER})?"-editing":"", " -f=\"\$(SRC_DIR)/$OutputMap\" -o=\"\$(OUTPUT_DIR)/../packages/$TransType/$Language/\$(BUILD_MODE)/$OutputFileName\" -p=\"$CMSProject\"\n");
        }
    }
    close(GMK);
}

foreach my $Area (keys(%Areas))
{
    foreach my $Language (keys(%{$Areas{$Area}}))
    {
        foreach $TransType (keys(%{${$Areas{$Area}}{$Language}}))
        {
            my($OutputMap, $OutputFileName) = @{${${$Areas{$Area}}{$Language}}{$TransType}};
            my($Folder, $DITAMap) = $OutputMap =~ /^(.+)\/([^\/]+)$/;
            if($TransType eq 'wiki.sap')
            {
                my($GenerateTOC, $Comment);
                my $OUTPUT = XML::DOM::Parser->new()->parsefile("$SRC_DIR/$OutputMap");
                my $Title = $OUTPUT->getElementsByTagName('title')->item(0)->getFirstChild()->getData();
                my $HRef = $OUTPUT->getElementsByTagName('mapref')->item(0)->getAttribute('href');
                for my $OPENTOPICPROPERTY (@{$OUTPUT->getElementsByTagName('opentopicproperty')})
                {
                    my $Name = $OPENTOPICPROPERTY->getAttribute('name'); 
                    my $Content = $OPENTOPICPROPERTY->getAttribute('value') || $OPENTOPICPROPERTY->getAttribute('content'); 
                    if($Name eq 'wiki.generatetoc') { $GenerateTOC = $Content }
                    elsif($Name eq 'wikicomments') { $Comment = $Content }
                }
                $OUTPUT->dispose();
                my $Id;
                eval
                {   
                    my $BUILDABLEMAP = XML::DOM::Parser->new()->parsefile("$SRC_DIR/$Folder/$HRef");
                    $Id = $BUILDABLEMAP->getElementsByTagName('buildable-map')->item(0)->getAttribute('id');
                    $BUILDABLEMAP->dispose();
                    copy("$SRC_DIR/$Folder/$HRef", "$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/") or warn("ERROR: cannot copy '$SRC_DIR/$Folder/$HRef' to '$ENV{DROP_DIR}/$Stream/$ENV{BUILDREV}/contexts/allmodes/files/': $!");
                };
                warn("ERROR: cannot parse buildablemap '$SRC_DIR/$Folder/$HRef' from outputmap '$OutputMap ($Title)': $@; $!") if($@);
                my($PhIO) = $OutputMap =~ /([^\/]*)\.ditamap$/;
                open(XML, ">$OUTPUT_DIR/bin/core.build.tools.docs/dita2confluence/confluence.content_$PhIO.xml") or die("ERROR: cannot open '$OUTPUT_DIR/bin/core.build.tools.docs/dita2confluence/confluence.content_$PhIO.xml': $!");
                print(XML "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
                print(XML "\t<content xmlns:xs=\"http://www.w3.org/2001/XMLSchema-instance\" xs:noNamespaceSchemaLocation=\"./d2ccontent.xsd\">\n");
                print(XML "\t<contentroot path=\"$SRC_DIR/cms/content\">\n");
                print(XML "\t\t<module\n");
                print(XML "\t\t\tfolder=\"authoring\"\n");
                print(XML "\t\t\tspacekey=\"$Id\"\n");
                print(XML "\t\t\tspacename=\"$OutputFileName\"\n");
                print(XML "\t\t\tditamap=\"$HRef\"\n");
                print(XML "\t\t\tgeneratetoc=\"$GenerateTOC\"\n");
                print(XML "\t\t\tcomment=\"$Comment\"\n");
                print(XML "\t\t\twipecomments=\"false\"\n");
                print(XML "\t\t\twipelabels=\"false\"\n");
                print(XML "\t\t\twipespace=\"false\"\n");
                print(XML "\t\t/>\n");
                print(XML "\t</contentroot>\n");       
                print(XML "</content>\n");
                close(XML);
            }
        }
    }
}

open(DAT, ">$ENV{HTTP_DIR}/$Stream/$BuildName/$BuildName=win64_x64_$ENV{BUILD_MODE}_properties.dat") or die("ERROR: cannot open '$ENV{HTTP_DIR}/$Stream/$BuildName/$BuildName=win64_x64_$ENV{BUILD_MODE}_properties.dat': $!");
$Data::Dumper::Indent = 0;
print(DAT Data::Dumper->Dump([\%Properties], ["*Properties"]));
close(DAT);

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : GenMakefile.pl -h -c -n -p -q -s 
             GenMakefile.pl -h.elp|?
   Example : GenMakefile.pl -p=documentation -t=HANA -s=D:\\HANA\\src 
    
   [options]
   -help|?   argument displays helpful information about builtin commands.
   -c.ms     specifies the cms source directory, default is <source>/cms.
   -t.ag     specifies the build name, default is \$ENV{MY_BUILD_NAME}.
   -p.roject specifies the project name, default is \$ENV{PROJECT}.
   -st.ream  specifies the stream name, default is \$ENV{context}
   -so.urce  specifies the source directory, default is \$ENV{SRC_DIR}.
   -o.utput  specifies the output directory, default is \$ENV{OUTPUT_DIR}.
USAGE
    exit;
}