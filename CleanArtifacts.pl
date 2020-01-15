#!/usr/bin/perl -w

use HTTP::Request::Common(qw(POST));
use LWP::UserAgent;
use JSON;

use FindBin;
use lib ($FindBin::Bin);
$ENV{PROJECT} = 'documentation';
require Site;

#$ENV{MY_DITA_PROJECT_ID} = 'ruw1541677374132';
##$ENV{SRC_DIR} = "D:\\$ENV{MY_DITA_PROJECT_ID}\\src";
#$ENV{SRC_DIR} = "D:\\deleted_test\\ruw1541677374132_CBTBC\\src";
#$ENV{MY_PROJECTMAP} = 'bae1475755354663.ditamap';
#$ENV{OUTPUT_DIR} = "D:\\deleted_test\\ruw1541677374132_CBTBC\\win64_x64\\release";
#$ENV{BUILD_NUMBER} = 11;
#$ENV{BUILD_MODE} = 'release'

#$ENV{MY_DITA_PROJECT_ID} = 'ruw1541677374132';
#$ENV{SRC_DIR} = 'C:/cbt_bc/export/shared/JM/src';
#$ENV{MY_PROJECTMAP} = 'bae1475755354663.ditamap';
#$ENV{OUTPUT_DIR} = 'C:/cbt_bc/export/shared/JM/win64_x64/release';
#$ENV{BUILD_NUMBER} = 11;
#$ENV{BUILD_MODE} = 'release'

exit(0) unless($ENV{MY_PROJECTMAP});

die("ERROR: MY_DITA_PROJECT_ID environment variable must be set") unless($ENV{MY_DITA_PROJECT_ID});
die("ERROR: DROP_DIR environment variable must be set") unless($ENV{DROP_DIR});
die("ERROR: SRC_DIR environment variable must be set") unless($ENV{SRC_DIR});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});
die("ERROR: BUILD_NUMBER environment variable must be set") unless($ENV{BUILD_NUMBER});
die("ERROR: BUILD_MODE environment variable must be set") unless($ENV{BUILD_MODE});

$CURRENTDIR = $FindBin::Bin;
$PROXY = 'http://proxy.wdf.sap.corp:8080';

$PMFrom = "$ENV{DROP_DIR}/$ENV{MY_DITA_PROJECT_ID}/".($ENV{BUILD_NUMBER}-1)."/contexts/allmodes/files/$ENV{MY_PROJECTMAP}";
$PMTo = "$ENV{SRC_DIR}/cms/content/localization/en-US/$ENV{MY_PROJECTMAP}";
system("cd /d $CURRENTDIR/buildconfigurator & buildconfigurator.bat --deleted --ixiaprojectid $ENV{MY_DITA_PROJECT_ID} --projectmap $PMTo --deletedFile $ENV{OUTPUT_DIR}/obj/ProjectMapTo.json");
eval {
    open(JSON, "$ENV{OUTPUT_DIR}/obj/ProjectMapTo.json") or die("ERROR: cannot open '$ENV{OUTPUT_DIR}/obj/ProjectMapTo.json': $!");
    { local $/; $rhProject1 = ProjectMap(decode_json(<JSON>)) }
    close(JSON);
};
die("ERROR: cannot read JSON from '$PMTo': $@") if($@ or !$rhProject1);
if(-f $PMFrom)
{
    system("cd /d $CURRENTDIR/buildconfigurator & buildconfigurator.bat --deleted  --ixiaprojectid $ENV{MY_DITA_PROJECT_ID} --projectmap $PMFrom --deletedFile $ENV{OUTPUT_DIR}/obj/ProjectMapFrom.json");
    eval {
        open(JSON, "$ENV{OUTPUT_DIR}/obj/ProjectMapFrom.json") or die("ERROR: cannot open '$ENV{OUTPUT_DIR}/obj/ProjectMapFrom.json': $!");
        { local $/; $rhProject2 = ProjectMap(decode_json(<JSON>)) }
        close(JSON);
    };
    die("ERROR: cannot read JSON from '$PMFrom': $@") if($@ or !$rhProject2);
}

foreach my $LoIO (keys(%{$rhProject1}))
{
    foreach my $Language (keys(%{${$rhProject1}{$LoIO}}))
    {
        foreach my $Name (keys(%{${$rhProject1}{$LoIO}{$Language}}))
        {
            my($IsDeleted1, $rhChannel1) = @{${$rhProject1}{$LoIO}{$Language}{$Name}};
            my($IsDeleted2, $rhChannel2) = @{${$rhProject2}{$LoIO}{$Language}{$Name}} if($rhProject2 and exists(${$rhProject2}{$LoIO}) and exists(${$rhProject2}{$LoIO}{$Language}) and exists(${$rhProject2}{$LoIO}{$Language}{$Name}));
            CleanChannel($rhChannel1) if($IsDeleted1 and !$IsDeleted2);
        }
    }
}
foreach my $LoIO (keys(%{$rhProject2}))
{
    foreach my $Language (keys(%{${$rhProject2}{$LoIO}}))
    {
        foreach my $Name (keys(%{${$rhProject2}{$LoIO}{$Language}}))
        {
            my($IsDeleted, $rhChannel) = @{${$rhProject2}{$LoIO}{$Language}{$Name}};
            CleanChannel($rhChannel) if(!$IsDeleted and (!exists(${$rhProject1}{$LoIO}) or !exists(${$rhProject1}{$LoIO}{$Language}) or !exists(${$rhProject1}{$LoIO}{$Language}{$Name})));
        }
    }
}

sub ProjectMap 
{
    my($rhJSON) = @_;
    return undef unless($rhJSON);
    
    my %ProjectMap;
    foreach my $LoIO (keys(%{$rhJSON}))
    {
        my $rhDeliverables = ${$rhJSON}{$LoIO}{deliverables};
        for my $Language (keys(%{$rhDeliverables}))
        {
            my $rhChannels = ${$rhDeliverables}{$Language}{channels};
            foreach my $Name (keys(%{$rhChannels}))
            {
                my $rhChannel = ${$rhChannels}{$Name};
                my $IsDeleted = (${$rhJSON}{$LoIO}{status} eq 'deleted' or ${$rhDeliverables}{$Language}{status} eq 'deleted' or ${$rhChannel}{status} eq 'deleted') ? 1 : 0;
                $ProjectMap{$LoIO}{$Language}{$Name} = [$IsDeleted, $rhChannel];
            }
        }
    }
    return \%ProjectMap;
}

sub CleanChannel
{
    my($rhChannel) = @_;

    if(${$rhChannel}{type} eq 'uacp')
    {
        (my $URL = ${$rhChannel}{uacp_url}) =~s/\/upload_secure$//;
        my $Language = ${$rhChannel}{uacp_locale};
        my $Version = ${$rhChannel}{uacp_version_id};
        my $Loio = ${$rhChannel}{uacp_output_id};
        #https://uacp2uploader.hana.ondemand.com/uploader/deliverable?state=<DRAFT|TEST|PRODUCTION>&loio=<deliverable output loio>&version=<version id>&langauge=<language code, eg, en-US>
        #https://uacp3uploader.hana.ondemand.com/uploader/deliverable?state=<DRAFT|TEST|PRODUCTION>&loio=<deliverable output loio>&version=<version id>&langauge=<language code, eg, en-US>
        my $State = $ENV{BUILD_MODE} eq 'release' ? 'TEST' : 'DRAFT';
        $URL .= "/deliverable\?state=$State&loio=$Loio&version=$Version&language=$Language";
        my $ua = LWP::UserAgent->new() or warn("ERROR: cannot create LWP agent: $!");
        $ua->proxy(['http', 'https'] => $PROXY);
        print("HTTP delete $URL\n");
        my $Request = HTTP::Request->new('GET', $URL);
        $Request->authorization_basic($ENV{DPS_USER}, $ENV{DPS_PASSWORD}) if($ENV{DPS_USER} && $ENV{DPS_PASSWORD});
        #my $Response = $ua->request($Request);
        #unless($Response->is_success())
        #{
        #    warn("ERROR: unexpected HTTP response of '$URL': ", $Response->status_line());
        #    print($Response->content(), "\n");
        #}
    }
    elsif(${$rhChannel}{type} eq 'dropzone')
    {
        my $Path = ${$rhChannel}{path};
        print("unlink $ENV{DROP_DIR}/$Path\n");
        #unlink("$ENV{DROP_DIR}/$Path") or warn("ERROR: cannot unlink '$ENV{DROP_DIR}/$Path': $!");
    }
}