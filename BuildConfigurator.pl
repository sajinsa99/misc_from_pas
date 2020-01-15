#!/usr/bin/perl -w

use File::Copy;
use File::Path;
use XML::DOM;
use JSON;

use FindBin;
use lib ($FindBin::Bin);
$ENV{PROJECT} = 'documentation';
require Site;

##############
# Parameters #
##############

die("ERROR: MY_BUILD_NAME environment variable must be set") unless($PROJECT_ID=$ENV{MY_BUILD_NAME});
die("ERROR: SRC_DIR environment variable must be set") unless($SRC_DIR=$ENV{SRC_DIR});
die("ERROR: PROJECT environment variable must be set") unless($PROJECT=$ENV{PROJECT});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});
die("ERROR: context environment variable must be set") unless($ENV{context});

($CURRENTDIR = $FindBin::Bin) =~ s/\//\\/g;
$ENV{CURRENTDIR} = $CURRENTDIR;

########
# Main #
########

if(exists($ENV{MY_PROJECTMAP}))
{
    my $ProjectMap = $ENV{MY_PROJECTMAP};
    system("cd /d $CURRENTDIR/buildconfigurator & buildconfigurator.bat --buildcycles $ENV{q_p_buildcycles} --ixiaprojectid $PROJECT_ID --projectmap $SRC_DIR/cms/content/localization/en-US/$ProjectMap --targetpath $SRC_DIR/$PROJECT/export");
    copy("$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=win64_x64_release_properties.dat", "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/properties.dat") or warn("ERROR: cannot copy '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=win64_x64_release_properties.dat': $!") if($ENV{BUILD_MODE} eq 'release');
    copy("$SRC_DIR/cms/content/projects/$PROJECT_ID.project", "$SRC_DIR/cms/content/projects/${PROJECT_ID}_pm.project") or warn("ERROR: cannot copy '$SRC_DIR/cms/content/projects/$PROJECT_ID.project': $!");
    if($ENV{MY_IS_DELTA_COMPILATION} and -f "$SRC_DIR/cms/content/localization/en-US/${ProjectMap}delta")
    {
        $ProjectMap .= 'delta';
        system("cd /d $CURRENTDIR/buildconfigurator & buildconfigurator.bat --buildcycles $ENV{q_p_buildcycles} --ixiaprojectid $PROJECT_ID --projectmap $SRC_DIR/cms/content/localization/en-US/$ProjectMap --targetpath $SRC_DIR/$PROJECT/export");
    }
}
# compatibility
else
{
    ($SRC_DIR = $ENV{SRC_DIR}) =~ s/\\/\//g;
    ($CMS_DIR = "$SRC_DIR/cms") =~ s/\\/\//g;
    
    $CMSProject = <$CMS_DIR/content/projects/*.project>;
    $PROJECT = XML::DOM::Parser->new()->parsefile($CMSProject);
    $FullPath = $PROJECT->getElementsByTagName('deliverable')->item(0)->getElementsByTagName('fullpath', 0)->item(0)->getFirstChild()->getData();
    $PROJECT->dispose();
    ($PrjctMp = "$CMS_DIR$FullPath") =~ s/authoring/localization\/en-US/;
    if(-f $PrjctMp) { $ProjectMap = $PrjctMp }
    else
    {
        opendir(LG, "$CMS_DIR/content/localization") or warn("ERROR: cannot opendir '$CMS_DIR/content/localization': $!");
        while(defined(my $Language = readdir(LG)))
        {
            next unless($Language =~ /^[a-z][a-z]-[A-Z][A-Z]$/);
            (my $PrjctMp = "$CMS_DIR$FullPath") =~ s/authoring/localization\/$Language/;
            next unless(-f $PrjctMp);
            $ProjectMap = $PrjctMp;
            last;   
        }
        close(LG);
    }
    warn("ERROR: cannot found project map in '$CMS_DIR/content/localization'") unless($ProjectMap);
    
    ($IxiasoftProjectID) = $CMSProject =~ /([^\\\/]+)\.project$/;
    system("cd /d $CURRENTDIR/buildconfigurator & buildconfigurator.bat --buildcycles $ENV{q_p_buildcycles} --ixiaprojectid $IxiasoftProjectID --projectmap $ProjectMap --targetpath $ENV{SRC_DIR}/$ENV{PROJECT}/export");
    copy("$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=win64_x64_release_properties.dat", "$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/properties.dat") or warn("ERROR: cannot copy '$ENV{HTTP_DIR}/$ENV{context}/$ENV{BUILD_NAME}/$ENV{BUILD_NAME}=win64_x64_release_properties.dat': $!") if($ENV{BUILD_MODE} eq 'release');
    copy("$ENV{SRC_DIR}/cms/content/projects/$ENV{MY_BUILD_NAME}.project", "$ENV{SRC_DIR}/cms/content/projects/$ENV{MY_BUILD_NAME}_pm.project") or die("ERROR: cannot copy '$ENV{SRC_DIR}/cms/content/projects/$ENV{MY_BUILD_NAME}.project': $!") if(-e "$ENV{SRC_DIR}/cms/content/projects/$ENV{MY_BUILD_NAME}.project");
}
# end compatibility

if(-f "$ENV{SRC_DIR}/documentation/export/feature.ditaval")
{
    $ProjectMap = "$SRC_DIR/cms/content/localization/en-US/$ENV{MY_PROJECTMAP}" if(exists($ENV{MY_PROJECTMAP}));
    my $PROJECTMAP = XML::DOM::Parser->new()->parsefile($ProjectMap);
    OUTPUT: for my $OUTPUT (@{$PROJECTMAP->getElementsByTagName('output')})
    {
        for my $DELIVRABLE (@{$OUTPUT->getElementsByTagName('deliverable')})
        {
            next unless($DELIVRABLE->getAttribute('status') eq 'enabled');
            my $Id = $OUTPUT->getAttribute('id');
            open(PROPERTIES, ">>$SRC_DIR/documentation/export/$Id.properties") or warn("ERROR: cannot open '$SRC_DIR/documentation/export/$Id.properties': $!");
            print(PROPERTIES "\nsap.feature.ditaval=$ENV{SRC_DIR}/documentation/export/feature.ditaval\n");
            close(PROPERTIES);
            next OUTPUT;
        }
    }
    $PROJECTMAP->dispose();
}

if(-f "$ENV{OUTPUT_DIR}/logs/Build/FeatureImpactedOutputs.dat") {
    my $JSONResponse;
    open(LOG, "$ENV{OUTPUT_DIR}/logs/Build/cms.log") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/Build/cms.log': $!");
    LOG: while(<LOG>) {
        next unless(/start HTTP response/);
        while(<LOG>) {
            last LOG if(/stop HTTP response/);
            $JSONResponse .= $_;
        }
    }
    close(LOG);
    my $rhMessage = decode_json($JSONResponse);
    (my $Message = ${${$rhMessage}{error}}{message}) =~ s/"/'/g;;
    chomp($Message);

    my(@OutputsImpactedByFeature, %OutputsImpactedByFeature);
    open(DAT, "$ENV{OUTPUT_DIR}/logs/Build/FeatureImpactedOutputs.dat") or warn("ERROR: cannot open '$ENV{OUTPUT_DIR}/logs/Build/FeatureImpactedOutputs.dat': $!");
    { local $/; eval <DAT> }
    close(DAT);
    foreach (@OutputsImpactedByFeature) {
        $OutputsImpactedByFeature{${$_}[4]} = undef;
    }

    open(GMKIN, "$SRC_DIR/documentation/export/$ENV{CONTEXT}.gmk") or warn("ERROR: cannot open '$SRC_DIR/documentation/export/$ENV{CONTEXT}.gmk': $!");
    open(GMKOUT, ">$SRC_DIR/documentation/export/$ENV{CONTEXT}.temp.gmk") or warn("ERROR: cannot open '$SRC_DIR/documentation/export/$ENV{CONTEXT}.temp.gmk': $!");
    while(<GMKIN>) {
        my $Line = $_;
        if($Line =~ /perl dita-ot_build.pl.+\/(loio.{32})\// and exists($OutputsImpactedByFeature{$1})) {
            print(GMKOUT "\t\t\@echo \"ERROR: [SMKP002F][FATAL] This output is using Feature Flags. It was not built since Feature Flag information cannot be retrieved. $Message This output is marked with FATAL error and will be rebuilt in the next build cycle.'\"\n");
            next;
        }
        print(GMKOUT $Line);
    }
    close(GMKOUT);
    close(GMKIN);
    unlink("$SRC_DIR/documentation/export/$ENV{CONTEXT}.gmk") or warn("ERROR: cannot unlink '$SRC_DIR/documentation/export/$ENV{CONTEXT}.gmk': $!");
    rename("$SRC_DIR/documentation/export/$ENV{CONTEXT}.temp.gmk", "$SRC_DIR/documentation/export/$ENV{CONTEXT}.gmk") or warn("ERROR: cannot copy '$SRC_DIR/documentation/export/$ENV{CONTEXT}.temp.gmk': $!") ;
}
