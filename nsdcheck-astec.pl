#############################################################################
##### declare uses

## basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

## required for the script
use XML::DOM;
use SOAP::Lite;
use File::Path;
use Time::Local;
use Getopt::Long;



##############################################################################
##### declare vars

# for the script itself
use vars qw (
    $orig_Site
    $Site
    %BUILD
    %NSD_SERVERS_PATH
    %NSD_SERVERS_TARGET
    $DROP_DIR
    %PACKAGES
    %PATCHES
    %Registered
    $nbLoop
    %SETUP_FILE
    $CBT_PATH
);

# options/parameters
use vars qw (
    $Help
    $param_project
    $param_build
    $param_revision
    $param_platform
    $param_mode
    $param_folder
    $param_pkg_Name
    $param_ini_file
    $param_astec_trigger_file
    $ASTEC
    $param_nb_loop
    $param_duration_loop
    $opt_force_registration
    $opt_just_search
    $opt_no_check
    @param_Folders
    @param_Platforms
    @param_PNames
    $param_date_time
    $opt_latest
    $opt_nowaitcheck
    $opt_latestxml
);



##############################################################################
##### declare functions
sub search_transfer_for_date_on_target_nsd_server($$);
sub transform_date_to_seconds($$);
sub check_size_of_project_package_path($$);
sub ASTEC_registration($$$$$$$@);
sub get_version_from_xml($);
sub check_already_registered($$$$$$);
sub display_infos();


sub display_usage();
sub start_script();
sub end_script();



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "F"         =>\$opt_force_registration,
    "JS"        =>\$opt_just_search,
    "Z"         =>\$ASTEC,
    "atf=s"     =>\$param_astec_trigger_file,
    "b=s"       =>\$param_build,
    "d=s"       =>\$DROP_DIR,
    "f=s"       =>\$param_folder,
    "help|?"    =>\$Help,
    "ini=s"     =>\$param_ini_file,
    "latest"    =>\$opt_latest,
    "lx"        =>\$opt_latestxml,
    "m=s"       =>\$param_mode,
    "n=s"       =>\$param_nb_loop,
    "noc"       =>\$opt_no_check,
    "p=s"       =>\$param_project,
    "pf=s"      =>\$param_platform,
    "pn=s"      =>\$param_pkg_Name,
    "s=s"       =>\$param_date_time,
    "t=s"       =>\$param_duration_loop,
    "ts=s"      =>\$Site,
    "v=s"       =>\$param_revision,
    "nwc"       =>\$opt_nowaitcheck,
);




##############################################################################
##### init vars
$orig_Site   = $ENV{SITE} || "Walldorf";
$Site      ||=$ENV{SITE}  || "Walldorf";
$ENV{SITE}   = $Site;

$CBT_PATH   = $ENV{CBTPATH} if($ENV{CBTPATH});
$CBT_PATH ||= ($^O eq "MSWin32")
             ? "c:/core.build.tools/export/shared"
             : "$ENV{HOME}/core.build.tools/export/shared"
             ;

if($ENV{NSD_SERVERS_PATH}) {
    $NSD_SERVERS_PATH{$Site} = $ENV{NSD_SERVERS_PATH};
}
else {
    $NSD_SERVERS_PATH{$Site}
        = ($^O eq "MSWin32")
        ? "//wdf-s-nsd001/builds"
        : "/net/wdf-s-nsd001/vol/aggr2_Global_Replication/q_data/builds"
        ;
}

$NSD_SERVERS_TARGET{Walldorf}   = $ENV{NSD_SERVERS_TARGET} || "dewdfgr02";
$NSD_SERVERS_TARGET{Vancouver}  = $ENV{NSD_SERVERS_TARGET} || "cavangr02";
$NSD_SERVERS_TARGET{Levallois}  = $ENV{NSD_SERVERS_TARGET} || "frpargr01";
$NSD_SERVERS_TARGET{Bangalore}  = $ENV{NSD_SERVERS_TARGET} || "inblrgr01";
$NSD_SERVERS_TARGET{Lacrosse}   = $ENV{NSD_SERVERS_TARGET} || "uslsegr01";
$NSD_SERVERS_TARGET{Paloalto}   = $ENV{NSD_SERVERS_TARGET} || "uspalgr01";
$NSD_SERVERS_TARGET{Shangai}    = $ENV{NSD_SERVERS_TARGET} || "cnshggr01";
$NSD_SERVERS_TARGET{Sofia}      = $ENV{NSD_SERVERS_TARGET} || "bgsofgr01";
$NSD_SERVERS_TARGET{Israel}     = $ENV{NSD_SERVERS_TARGET} || "iltlvgr01";

##########  default packages/patches name, use -pn to override these values
### Aurora
$PACKAGES{aurora}{win32_x86}    = "BusinessObjectsClient";
$PACKAGES{aurora}{win64_x64}    = "BusinessObjectsServer";
$PACKAGES{aurora}{unix}         = "BusinessObjectsServer";

$PATCHES{aurora}{win32_x86}     = "BusinessObjectsClient_Patch";
$PATCHES{aurora}{win64_x64}     = "BusinessObjectsServer_Patch";
$PATCHES{aurora}{unix}          = "BusinessObjectsServer_Patch";
# please put '/' is 1 sub-folder exist, even if windows
$SETUP_FILE{aurora}{win32_x86}  = $SETUP_FILE{aurora}{win64_x64}
                                = "setup.exe"
                                ;
$SETUP_FILE{aurora}{unix}       = "setup.sh";

### Titan
$PACKAGES{Titan}{win32_x86}     = "BusinessObjectsClient";
$PACKAGES{Titan}{win64_x64}     = "BusinessObjects";
$PACKAGES{Titan}{unix}          = "BusinessObjects";

$PATCHES{Titan}{win32_x86}      = "BusinessObjectsClient_FP";
$PATCHES{Titan}{win64_x64}      = "BusinessObjects_FP";
$PATCHES{Titan}{unix}           = "BusinessObjects_FP";

# please put '/' is 1 sub-folder exist, even if windows
$SETUP_FILE{Titan}{win32_x86}   = $SETUP_FILE{Titan}{win64_x64}
                                = "setup.exe"
                                ;
$SETUP_FILE{Titan}{unix}        = "DISK_1/install.sh";

########## ########## ########## ########## ########## ########## ##########

$param_project   ||= "aurora_dev";
$param_build     ||= "aurora41_feat_deski";

if($param_folder) {
    ($param_folder) =~ s-contexts-files-;
    if($opt_latestxml) {
        $param_folder .= ",files";
    }
    @param_Folders  =  split ',',$param_folder;
}
if($param_platform) {
    my $set_of_platforms;
    my @tmp_Platforms = split ',',$param_platform;
    foreach my $tmp_Platform (sort @tmp_Platforms) {
        if($tmp_Platform =~ /^all$/i) {
            $set_of_platforms = "win32_x86,win64_x64,"
                              . "solaris_sparc,linux_x86,aix_rs6000,"
                              . "hpux_pa-risc,solaris_sparcv9,linux_x64,"
                              . "linux_ppc64,aix_rs6000_64,hpux_ia64,"
                              . "mac_x64,mac_x86,"
                              ;
            last;
        }
        elsif($tmp_Platform    =~ /^win$/i) {
            $set_of_platforms .=  "win32_x86,win64_x64,";
        }
        elsif($tmp_Platform    =~ /^windows$/i) {
            $set_of_platforms .=  "win32_x86,win64_x64,";
        }
        elsif($tmp_Platform    =~ /^unix$/i) {
            $set_of_platforms .=  "solaris_sparc,linux_x86,aix_rs6000,"
                               .  "hpux_pa-risc,solaris_sparcv9,linux_x64,"
                               .  "linux_ppc64,aix_rs6000_64,hpux_ia64,"
                               .  "mac_x64,mac_x86,"
                               ;
        }
        elsif($tmp_Platform    =~ /^lin$/i) {
            $set_of_platforms .=  "linux_x86,linux_x64,linux_ppc64,";
        }
        elsif($tmp_Platform    =~ /^linux$/i) {
            $set_of_platforms .=  "linux_x86,linux_x64,linux_ppc64,";
        }
        elsif($tmp_Platform    =~ /^sol$/i) {
            $set_of_platforms .=  "solaris_sparc,solaris_sparcv9,";
        }
        elsif($tmp_Platform    =~ /^solaris$/i) {
            $set_of_platforms .=  "solaris_sparc,solaris_sparcv9,";
        }
        elsif($tmp_Platform    =~ /^aix$/i) {
            $set_of_platforms .=  "aix_rs6000,aix_rs6000_64,";
        }
        elsif($tmp_Platform    =~ /^hp$/i) {
            $set_of_platforms .=  "hpux_pa-risc,hpux_ia64,";
        }
        elsif($tmp_Platform    =~ /^mac$/i) {
            $set_of_platforms .=  "mac_x64,mac_x86,";
        }
        elsif($tmp_Platform    =~ /^macos$/i) {
            $set_of_platforms .=  "mac_x64,mac_x86,";
        }
        elsif($tmp_Platform    =~ /^macosx$/i) {
            $set_of_platforms .=  "mac_x64,mac_x86,";
        }
        else {
            $set_of_platforms .= "$tmp_Platform,";
        }
    }
    ($set_of_platforms) =~ s-\,$--;
    if($opt_latestxml) {
        $set_of_platforms .= ",contexts";
    }
    @param_Platforms    = split ',',$set_of_platforms;
}

if($param_pkg_Name) {
    @param_PNames = split ',',$param_pkg_Name;
}

$ENV{PROJECT} = ($param_project) ? $param_project : "aurora_dev";

if($Site =~ /^help$/i) {
    display_usage();
}

unless($DROP_DIR) {
    eval {
        require Site;
    };
    $DROP_DIR = $ENV{DROP_DIR};
    unless($DROP_DIR) {
        unless($Help) {
            print "\n\nERROR : DROP_DIR not found in Site.pm for $Site\n";
            my $msg = "Please, use $0 with -ts=$Site -p=$param_project"
                    . " -b=$param_build -d=your_drop_dir"
                    ;
            print "$msg\n\n";
            exit 1;
        }
    }
}
else {
    $DROP_DIR = "$DROP_DIR/$ENV{PROJECT}";
}

if($param_nb_loop) {
    if( !($param_nb_loop =~ /^\d+$/) ) { # if -n=not numeric value
        if(    ($param_nb_loop =~ /^u$/i)
            or ($param_nb_loop =~ /^i$/i)
            or ($param_nb_loop =~ /^d$/i) ) {
                $param_nb_loop = 122400;
        }
        else {
            my $warning_msg = "WARNING : $param_nb_loop not recognized,"
                            . " '-n' could be a number or 'u' (unlimited)"
                            . " or 'i' (infinite) or 'd' (day)"
                            ;
            print "$warning_msg\n";
            exit;
        }
    }
}
else {
    $param_nb_loop = 1;
}
if($param_duration_loop) {
    if($param_duration_loop  =~ /^(\d+)[h]$/i) {   # if h for hours
        $param_duration_loop =  $1 * 3600;         # transform to secondes
    }
    if($param_duration_loop  =~ /^(\d+)[m]$/i) {   # if m for minutes
        $param_duration_loop =  $1 * 60;           # transform to secondes
    }
    if($param_duration_loop  =~ /^(\d+)[s]$/i) {   # if s for secondes
        $param_duration_loop =  $1;                # remove 's' to keep value
    }
    # complexe format for psychopath !!! XD
    if(    ($param_duration_loop =~ /^(\d+)[h](\d+)$/i)
        or ($param_duration_loop =~ /^(\d+)\:(\d+)$/i)
        or ($param_duration_loop =~ /^(\d+)[h](\d+)[m]$/i) ) { # if 00h00 or 00h00m or 00:00
            my $hour = $1;
            my $min  = $2;
            # remove first 0 like 01:01
            ($hour)  =~ s/^0//   if($hour =~ /^0/);
            ($min)   =~ s/^0//   if($min  =~ /^0/);
            $param_duration_loop = ($hour * 3600) + ($min * 60) ; # transform to secondes
    }
    # complexe format for big psychopath :)
    if(    ($param_duration_loop =~ /^(\d+)[h](\d+)[m](\d+)$/i)
        or ($param_duration_loop =~ /^(\d+)\:(\d+)\:(\d+)$/i)
        or ($param_duration_loop =~ /^(\d+)[h](\d+)[m](\d+)s$/i) ) { # if 00h00m00s or 00h00m00 or 00:00:00
            my $hour = $1;
            my $min  = $2;
            my $sec  = $3;
            # remove first 0 like 01:01:01
            ($hour)  =~ s/^0//   if($hour =~ /^0/);
            ($min)   =~ s/^0//   if($min  =~ /^0/);
            ($sec)   =~ s/^0//   if($sec  =~ /^0/);
            # transform to secondes :
            $param_duration_loop = ($hour * 3600) + ($min * 60) + $sec ;
    }
}
else {
    $param_duration_loop = 600; # wait for 10 minutes by default
}
$nbLoop = 0;
$param_nb_loop = 1 if($opt_just_search);



##############################################################################
##### MAIN
display_usage() if($Help);

start_script();

print "\nTarget Site : $Site\n\n";

while(1) {
    $nbLoop++;
    unless($opt_just_search) {
        print "\n\t==== iteration number : $nbLoop/$param_nb_loop ====\n";
    }
    # extract infos
    # format date : 2013-01-30 00:00:01
    my ($LocalSec,$LocalMin,$LocalHour,
        $LocalDay,$LocalMonth,$LocalYear,
        $wday,$yday,$isdst)
        = localtime time
        ;
    $LocalYear            = $LocalYear  + 1900;
    $LocalMonth           = $LocalMonth + 1;
    #$LocalDay             = $LocalDay - $param_SinceNDay; # for case with timezone difference
    $LocalDay             = "0$LocalDay"        if($LocalDay   < 10);
    $LocalMonth           = "0$LocalMonth"      if($LocalMonth < 10);
    my $sinceThisDateTime = "$LocalYear-$LocalMonth-$LocalDay 00:00:01";
    $sinceThisDateTime    = $param_date_time    if($param_date_time);
    print "\nsearch from $sinceThisDateTime\n";
    search_transfer_for_date_on_target_nsd_server($sinceThisDateTime,$NSD_SERVERS_TARGET{$Site});
    # display infos found
    print "\n";
    if(%BUILD) {
        display_infos();
    }
    else {
        my $warning_msg = "WARNING : nothing found for the build $param_build,"
                        . "\nmaybe check the target site (=$Site),"
                        . "the buildName (=$param_build),"
                        . " the project (=$param_project)"
                        ;
        print "$warning_msg\n";
    }
    last if($param_nb_loop == $nbLoop);

    unless($opt_just_search) {
        ##############################
        # print a dot for each seconds
        print "\n";
        my $counter = 1;
        my $cr      = "\r";
        $| = 1; # Set the 'autoflush' on stdout
        while ($counter <= $param_duration_loop) {
            print ".";
            sleep 1;
            print "\n" if(($counter % 60) == 0); # next line per minute
            $counter++;
        }
        #############################
    }
    print "\n";
    ($LocalSec,$LocalMin,$LocalHour,
     $LocalDay,$LocalMonth,$LocalYear,
     $wday,$yday,$isdst) = q{};
}


# end script
end_script();



##############################################################################
### internal functions
sub search_transfer_for_date_on_target_nsd_server($$) {
    my ($date,$nsdServerTarget) = @_ ;
    # help in https://wiki.wdf.sap.corp/wiki/display/ProductionUnits/GR+external+event+SOAP+interface
    my $tmp = SOAP::Lite
            -> uri('http://dewdfgrdb01.wdf.sap.corp/gr_ext')
            -> proxy('http://dewdfgrdb01.wdf.sap.corp:1080/cgi-bin/gr-ext')
            -> lastsinceByTarget("$date|$nsdServerTarget")
            -> result
            ;
    my @Results = split '\n',$tmp;
    #e.g. format : cavangr02.pgdev.sap.corp,dewdfgr02,aurora_maint/Aurora_40_SP_COR/969/win64_x64/release/pdb,969,complete,2013-01-30 07:36:01
    foreach my $result (@Results) {
        my ($nsdrSrc,$nsdTarget,$syncDir,$versionTransferred,$statusTransfer,$dateTime)
            = split ',',$result;
        my ($this_Project,$this_Build,$this_Version,$this_Platform,$this_Mode,$this_Folder)
            = split '/',$syncDir;
        my ($thisDate,$thisTime) =
            split ' ',$dateTime;
        my $time_Stamp = transform_date_to_seconds($thisDate,$thisTime);
        next if( (defined $param_project)  && ($param_project   ne $this_Project));
        next if( (defined $param_build)    && ($param_build     ne $this_Build));
        next if( (defined $param_revision) && ($param_revision  ne $this_Version));
        next if( (defined $param_platform) && ( !(grep /^$this_Platform$/i , @param_Platforms)) );
        next if( (defined $param_mode)     && ($param_mode      ne $this_Mode));
        next if( (defined $param_folder)   && ( !(grep /^$this_Folder$/ , @param_Folders)) );
        $BUILD{$this_Project}{$this_Build}{$this_Version}{$this_Platform}{$this_Mode}{$this_Folder}{status} = $statusTransfer;
        $BUILD{$this_Project}{$this_Build}{$this_Version}{$this_Platform}{$this_Mode}{$this_Folder}{dt}     = "$thisDate $thisTime";
        # use an array if a new transfer of the same build is restarted during the same day, permit after to know the most recent
        unless(grep /^$time_Stamp$/ , @{$BUILD{$this_Project}{$this_Build}{$this_Version}{$this_Platform}{$this_Mode}{$this_Folder}{timestamp}}) {
            push @{$BUILD{$this_Project}{$this_Build}{$this_Version}{$this_Platform}{$this_Mode}{$this_Folder}{timestamp}},$time_Stamp;
        }
    }
}

sub transform_date_to_seconds($$) {
    my ($Date2,$Time2)     = @_;
    my ($hour,$min,$sec)   = $Time2 =~ /^(\d+)\:(\d+)\:(\d+)$/;
    my ($Year,$Month,$Day) = $Date2 =~ /^(\d+)\-(\d+)\-(\d+)$/;
    $Month                 = $Month - 1;
    my @temps              = ($sec,$min,$hour,$Day,$Month,$Year);
    return timelocal @temps;
}

sub display_infos() {
    my %latest;
    foreach my $project (keys%BUILD) {
        next if($param_project && ($param_project ne $project));
        print "$project\n";
        foreach my $build (keys %{$BUILD{$project}}) {
            next if($param_build && ($param_build ne $build));
            print "    $build\n";
            foreach my $version (sort {$a <=> $b} keys %{$BUILD{$project}{$build}}) {
                next if($param_revision && ($param_revision ne $version));
                print "    " x 2,"$version";
                my $displayDropDir =  "$DROP_DIR/$build/$version";
                ($displayDropDir)  =~ s-\/-\\-g if($^O eq "MSWin32");
                print " on $displayDropDir\n";
                foreach my $platform (keys %{$BUILD{$project}{$build}{$version}}) {
                    if(@param_Platforms) {
                        next unless(grep/^$platform$/ , @param_Platforms);
                    }
                    print "    " x 3,"$platform\n";
                    foreach my $mode (keys %{$BUILD{$project}{$build}{$version}{$platform}}) {
                        next if($param_mode && ($param_mode ne $mode));
                        print "    " x 4,"$mode\n";
                        foreach my $folder (keys %{$BUILD{$project}{$build}{$version}{$platform}{$mode}}) {
							if($param_folder) {
								next unless(grep/^$folder$/ ,@param_Folders);
							}
                            my $maxSize    = length "deploymentunits";
                            $maxSize       = length "$param_folder" if($param_folder);
                            my $Size       = length "$folder";
                            my $nbSpaces   = ($maxSize - $Size) + 1;
                            print "    "   x 5,"$folder"," " x $nbSpaces,"=> $BUILD{$project}{$build}{$version}{$platform}{$mode}{$folder}{status} ($BUILD{$project}{$build}{$version}{$platform}{$mode}{$folder}{dt})";
                            my $inDropzone = 0;
                            if( -e "$DROP_DIR/$build/$version/$platform/$mode/$folder") {
                                if( ! -e "$DROP_DIR/$build/$version/$platform/$mode/${folder}_UPDATEINPROGRESS") {
                                    $inDropzone = 1;
                                    print " => available in dropzone";
                                    $latest{$project}{$build}{$version}{$platform}{$mode}{$folder} = 1;
                                    if($opt_latestxml && ($platform =~ /^contexts$/) && ($folder =~ /^files$/)) {
                                        if( -e "$DROP_DIR/$build/$version/contexts/allmodes/files/$build.context.xml" ) {
                                            #my $store_ENV_CYGWIN = $ENV{CYGWIN};
                                            #$ENV{CYGWIN} = "winsymlinks:native";
                                            # ensure that latest.xml is not already updated
                                            my $version_in_xml;
                                            if( -e "$DROP_DIR/$build/latest.xml") {
                                                eval { $version_in_xml = get_version_from_xml("$DROP_DIR/$build/latest.xml") };
                                            }
                                            else {
                                                $version_in_xml = 0 ;
                                            }
                                            if($version_in_xml != $version) { 
                                                chdir "$DROP_DIR/$build" or warn "WARNING : cannot chdir into $DROP_DIR/$build";
                                                if($^O ne "MSWin32") { # if unix
                                                    print " => symlink latest.xml -> $version/contexts/allmodes/files/$build.context.xml\n";
                                                    system "ln -sf $version/contexts/allmodes/files/$build.context.xml latest.xml";
                                                }
                                                else {
                                                    system "rm -f latest.xml";
                                                    print " => copy latest.xml -> $version/contexts/allmodes/files/$build.context.xml\n";
                                                    system "cp -pf $version/contexts/allmodes/files/$build.context.xml latest.xml";
                                                }
                                                chdir $CBT_PATH;
                                            }
                                            else {
                                                print " => already updated";
                                            }
                                            #$ENV{CYGWIN} = $store_ENV_CYGWIN;
                                        }
                                    }
                                }
                                else {
                                    print " => update in dropzone in progress";
                                    $latest{$project}{$build}{$version}{$platform}{$mode}{$folder} = 0;
                                }
                            }
                            else {
                                print " => NOT available in dropzone";
                                $latest{$project}{$build}{$version}{$platform}{$mode}{$folder} = 0;
                            }
                            check_already_registered($project,$build,$version,$platform,$mode,$folder);
                            if($Registered{$project}{$build}{$version}{$platform}{$mode}{$folder}) {
                                print " => ASTEC Registration already done\n";
                                goto AFTER_ASTEC;
                            }
                            print "\n";
                            if($ASTEC) {
                                my $status = $BUILD{$project}{$build}{$version}{$platform}{$mode}{$folder}{status};
                                if( ($status eq "complete") || (($status eq "active") && $opt_nowaitcheck) ) {
                                    if( ($folder eq "packages") or ($folder eq "patches") ) {
                                        if($inDropzone == 1) {
                                            my $prjLogicalName  = $project;
                                            ($prjLogicalName)   =~ s-\_.+?$--;
                                            my $os = ($platform =~ /^win/i) ? $platform : "unix";
                                            my @thesePNames; # Package/Patch names
                                            if( ($folder eq "packages") or ($folder eq "patches") ) {
                                                if($param_pkg_Name) {
                                                    @thesePNames = @param_PNames;
                                                }
                                                else {
                                                    if($folder eq "packages") {
                                                        push @thesePNames,$PACKAGES{$prjLogicalName}{$os};
                                                    }
                                                    if($folder eq "patches") {
                                                        push @thesePNames,$PATCHES{$prjLogicalName}{$os};
                                                    }
                                                }
                                            }
                                            if( ! $Registered{$project}{$build}{$version}{$platform}{$mode}{$folder}) { # not already defined
                                                ASTEC_registration($project,$prjLogicalName,$build,$version,$platform,$mode,$folder,@thesePNames);
                                            }
                                            else {
                                                if($opt_force_registration) {
                                                    ASTEC_registration($project,$prjLogicalName,$build,$version,$platform,$mode,$folder,@thesePNames);
                                                }
                                            }
                                        }
                                        else {
                                            print "WARNING : as the status is not complete, cannot make ASTEC registration\n";
                                        }
                                    }
                                }
                                else {
                                    print "WARNING : as the status is not complete, cannot make ASTEC registration\n";
                                }
                            } # end if ASTEC registration requested
                            AFTER_ASTEC:
                        } # folder
                    } # mode
                } # platform
                print "\n";
            } # version
        } # build
    }
    if($opt_latest) {
        my %flag;
        foreach my $project (keys%BUILD) {
            next if($param_project && ($param_project ne $project));
            foreach my $build (keys %{$BUILD{$project}}) {
                next if($param_build && ($param_build ne $build));
                foreach my $version (keys %{$BUILD{$project}{$build}}) {
                    next if($param_revision && ($param_revision ne $version));
                    foreach my $platform (keys %{$BUILD{$project}{$build}{$version}}) {
                        if(@param_Platforms) {
                            next unless(grep/^$platform$/ , @param_Platforms);
                            foreach my $mode (keys %{$BUILD{$project}{$build}{$version}{$platform}}) {
                                next if($param_mode && ($param_mode ne $mode));
                                foreach my $folder (keys %{$BUILD{$project}{$build}{$version}{$platform}{$mode}}) {
                                    if(@param_Folders) {
                                        foreach my $required_folder (sort @param_Folders) {
                                            if($latest{$project}{$build}{$version}{$platform}{$mode}{$required_folder}
                                                && ($latest{$project}{$build}{$version}{$platform}{$mode}{$required_folder} == 1)) {
                                                $flag{$project}{$build}{$version} = 1;
                                            }
                                            else {
                                                $flag{$project}{$build}{$version} = 0;
                                                goto NEXT_VERSION; # exit at 1st missing/not complete transfer
                                            }
                                        }
                                    }
                                    else { # no param_Folders
                                        if($latest{$project}{$build}{$version}{$platform}{$mode}{$folder}
                                            && ($latest{$project}{$build}{$version}{$platform}{$mode}{$folder} == 1)) {
                                            $flag{$project}{$build}{$version} = 1;
                                        }
                                        else {
                                            $flag{$project}{$build}{$version} = 0;
                                            goto NEXT_VERSION; # exit at 1st missing/not complete transfer
                                        }
                                    }
                                }
                            }
                        }
                        else { # no param_Platforms
                            foreach my $mode (keys %{$BUILD{$project}{$build}{$version}{$platform}}) {
                                next if($param_mode && ($param_mode ne $mode));
                                foreach my $folder (keys %{$BUILD{$project}{$build}{$version}{$platform}{$mode}}) {
                                    if(@param_Folders) {
                                        foreach my $required_folder (sort @param_Folders) {
                                            if($latest{$project}{$build}{$version}{$platform}{$mode}{$required_folder}
                                                && ($latest{$project}{$build}{$version}{$platform}{$mode}{$required_folder} == 1)) {
                                                $flag{$project}{$build}{$version} = 1;
                                            }
                                            else {
                                                $flag{$project}{$build}{$version} = 0;
                                                goto NEXT_VERSION; # exit at 1st missing/not complete transfer
                                            }
                                        }
                                    }
                                    else { # no param_Folders
                                        if($latest{$project}{$build}{$version}{$platform}{$mode}{$folder}
                                            && ($latest{$project}{$build}{$version}{$platform}{$mode}{$folder} == 1)) {
                                            $flag{$project}{$build}{$version} = 1;
                                        }
                                        else {
                                            $flag{$project}{$build}{$version} = 0;
                                            goto NEXT_VERSION; # exit at 1st missing/not complete transfer
                                        }
                                    }
                                }
                            }
                        }
                    }
                    NEXT_VERSION:
                }
            }
        }
        foreach my $prj (keys %flag) {
            foreach my $bld (keys %{$flag{$prj}}) {
                foreach my $version (sort { $a <=> $b } keys %{$flag{$prj}{$bld}}) {
                    if($flag{$prj}{$bld}{$version} == 1) {
                        if ($^O ne "MSWin32") {
                            if( -e "$DROP_DIR/$bld/$version/contexts/allmodes/files/$bld.context.xml") {
                                print  "create symlink latest $version/contexts/allmodes/files/$bld.context.xml\n";
                                chdir  "$DROP_DIR/$bld";
                                print  "in $DROP_DIR/$bld\nln -sf $version/contexts/allmodes/files/$bld.context.xml latest.xml\n";
                                system "ln -sf $version/contexts/allmodes/files/$bld.context.xml latest.xml";
                                # check if symlink well done
                                if( -l "latest.xml") {
                                    my $source = readlink "latest.xml" ;
                                    if($source) {
                                        if( -e "$DROP_DIR/$bld/$source") {
                                            my ($orig_version) = $source =~ /^(\d+)\//i;
                                            if($orig_version  != $version) {
                                                print  "WARNING : bad symlink, symlink to $orig_version instead of $version\n";
                                            }
                                            else {
                                                print  "in $DROP_DIR/$bld\ncreate also latest.xml.done\n";
                                                system "touch latest.xml.done";
                                                print  "in $DROP_DIR/$bld:\n";
                                                system "ls -l $DROP_DIR/$bld";
                                            }
                                        }
                                        else {
                                            print "WARNING : source  $source of symlink latest.xml not found\n";
                                        }
                                    }
                                }
                            }
                            else {
                                print "WARNING : $DROP_DIR/$bld/$version/contexts/allmodes/files/$bld.context.xml not found.\n";
                            }
                        }
                    }
                    else {
                        print "$bld/$version not ready to update the latest.xml\n";
                    }
                }
            }
        }
    }
}

sub ASTEC_registration($$$$$$$@) {
    my ($prj,$prjLogicalName,$build,$version,$pf,$mode,$folder,@pkgs) = @_;

    # astec path managment
    my $ASTECPath = ($ENV{ASTEC_DIR})
                  ? $ENV{ASTEC_DIR}
                  : "$DROP_DIR/../ASTEC"
                  ;
    $ASTECPath .="/$prj/$build/$pf";
    ($ASTECPath) =~ s-\\-\/-g;
    if( ! -e $ASTECPath) {
        mkpath $ASTECPath;
    }

    # main infos to put in trigger file(s)
    my $Config       = ($param_ini_file) ? $param_ini_file : "$build.ini";
    my $OBJECT_MODEL = 32;
    if($pf =~ /^(win64_x64|linux_x64|solaris_sparcv9|aix_rs6000_64|hpux_ia64|mac_x64)$/i) {
        $OBJECT_MODEL = 64;
    }

    # list of trigger files
    my @ASTECTriggerFiles;
    if($folder eq "packages") {
         @ASTECTriggerFiles = qw(buildInfo.txt nightly.txt);
    }
    if($folder eq "patches") {
         @ASTECTriggerFiles = qw(buildInfo_patches.txt nightly_patches.txt);
    }
    if($param_astec_trigger_file) {
        push @ASTECTriggerFiles,$param_astec_trigger_file;
    }

    if($param_pkg_Name && ($param_pkg_Name =~ /^\*$/)) { # if -pn=*
        my @tmpPkgs;
        @pkgs = ();
        if(opendir LS,"$DROP_DIR/$build/$version/$pf/$mode/$folder") {
            while(defined(my $tmp = readdir LS)) {
                next if($tmp =~ /^\./);
                if( -d  "$DROP_DIR/$build/$version/$pf/$mode/$folder/$tmp") {
                    push @tmpPkgs,$tmp;
                }
            }
            closedir LS;
        }
        @pkgs = @tmpPkgs ;
    }

    # check if 1 of package/patch exist, if yes, create trigger
    my $GoRegister = 0;
    foreach my $pkg (@pkgs) {
        my $os    = ($pf =~ /^win/i) ? $pf : "unix";
        my $Setup = "$DROP_DIR/$build/$version/$pf/$mode/"
                  . "$folder/$pkg/$SETUP_FILE{$prjLogicalName}{$os}"
                  ;
        if( -e $Setup) {
            $GoRegister = 1;
            last;
        }
    }

    if($GoRegister == 1) {
        my $BUILD_PRODUCT_VERSION;
        my $BUILD_STREAM;
        if( -e "contexts/$Config") {
            $BUILD_PRODUCT_VERSION = `perl rebuild.pl -i=contexts/$Config -si=version`;
            chomp $BUILD_PRODUCT_VERSION;
            $BUILD_STREAM = `perl rebuild.pl -i=contexts/$Config -si=context`;
            chomp $BUILD_STREAM;
        }
        foreach my $ASTECTriggerFile (@ASTECTriggerFiles) {
            if(open   ASTEC,">$ASTECPath/$ASTECTriggerFile") {
                print ASTEC "ARCHITECTURE=$OBJECT_MODEL\n";
                print ASTEC "BUILD_INI_FILE=$Config\n";
                print ASTEC "BUILD_VERSION=$version\n";
                print ASTEC "BUILD_PRODUCT_VERSION=$BUILD_PRODUCT_VERSION\n" if($BUILD_PRODUCT_VERSION);
                print ASTEC "BUILD_MODE=$mode\n";
                print ASTEC "suite=$prj\n";
                print ASTEC "BUILD_STREAM=$BUILD_STREAM\n";
                my $defaultPkg = 0;
                foreach my $pkg (sort @pkgs) {
                    my $os        = ($pf =~ /^win/i) ? $pf : "unix";
                    my $PathList  = "$DROP_DIR/$build/$version/$pf/$mode/$folder";
                    my $PathList2 = "";
                    if($defaultPkg == 0) {
                        if($pkg ne $PACKAGES{$prjLogicalName}{$os}) {
                            $PathList  .= "/$PACKAGES{$prjLogicalName}{$os}";
                            $PathList2 .= "$DROP_DIR/$build/$version/$pf/$mode/$folder/$pkg";
                        }
                        else {
                            $PathList  .= "/$pkg";
                            $PathList2 .= "$DROP_DIR/$build/$version/$pf/$mode/$folder/$pkg";
                        }
                    }
                    else {
                        $PathList  .= "/$pkg";
                    }
                    my $Setup = ($^O eq "MSWin32")
                              ? "$PathList\\$SETUP_FILE{$prjLogicalName}{$os}"
                              : "$PathList/$SETUP_FILE{$prjLogicalName}{$os}"
                              ;
                    if($SETUP_FILE{$prjLogicalName}{$os} =~ /^(.+?)\/(.+?)$/i) {
                        $PathList .= "/$1";
                    }
                    ($PathList) =~ s-\/DISK\_1$--i if($PathList =~ /\/DISK\_1$/i); # remove DISK_1 (requested by Bharathi)
                    ($^O eq "MSWin32") ? $PathList =~ s/\//\\/g : $PathList =~ s/\\/\//g;
                    my $integrity;
                    if($opt_no_check) {
                        $integrity = 1;
                    }
                    else {
                        $integrity = check_size_of_project_package_path($prj,"$build/$version/$pf/$mode/$folder/$pkg");
                    }
                    print $pkg;
                    if( -e $Setup) {
                        if($integrity == 1) {
                            if($defaultPkg == 0) {
                                print ASTEC "SETUP_PATH=$PathList\n";
                                print ASTEC "SETUP_PATH_$pkg=$PathList2\n" if($PathList2);
                            }
                            else {
                                print ASTEC "SETUP_PATH_$pkg=$PathList\n";
                            }
                            print ASTEC "TARGET_PLATFORM_$pkg=$pf\n";
                            print ASTEC "TARGET_PACKAGE_$pkg=$pkg\n";
                            print ASTEC "\n";
                            print " : ADDED in $ASTECPath/$ASTECTriggerFile\n";
                        }
                        else {
                            print " : WARNING : sizes are different between nsd server and dropzone\n";
                        }
                    }
                    else {
                        print " : WARNING : $Setup not found\n";
                    }
                    $defaultPkg++;
                }
                close ASTEC;
            }
            else {
                print " WARNING : cannot create '$ASTECPath/$ASTECTriggerFile'";
            }
        }
        $Registered{$prj}{$build}{$version}{$pf}{$mode}{$folder} = 1;
    }
    else {
        print "any (@pkgs) in $folder found\n";
    }
}

sub get_version_from_xml($) {
    my ($this_latest_xml) = @_;
    my $LATEST_XML = XML::DOM::Parser->new()->parsefile($this_latest_xml);
    my $this_Full_Version_found = $LATEST_XML->getElementsByTagName("version")->item(0)->getFirstChild()->getData();
    $LATEST_XML->dispose();
    # get everything after the 3rd digit because it could be an incremental also
    (my $this_Build_Revision_found) = $this_Full_Version_found =~ /^\d+\.\d+\.\d+\.(.*)$/ ;
    return $this_Build_Revision_found if($this_Build_Revision_found);
}

sub check_already_registered($$$$$$) {
    my ($this_Project,$this_Build,$this_Version,$this_Platform,$this_Mode,$this_Folder) = @_;
    my $ASTECPath =  ($ENV{ASTEC_DIR})
                  ?  $ENV{ASTEC_DIR}
                  :  "$DROP_DIR/../ASTEC"
                  ;
    $ASTECPath   .=  "/$this_Project/$this_Build/$this_Platform";
    ($ASTECPath)  =~ s-\\-\/-g;

    #list of trigger files
    my @ASTECTriggerFiles;
    if($this_Folder eq "packages") {
         @ASTECTriggerFiles = qw(buildInfo.txt nightly.txt);
    }
    if($this_Folder eq "patches") {
         @ASTECTriggerFiles = qw(buildInfo_patches.txt nightly_patches.txt);
    }
    if($param_astec_trigger_file) {
        push @ASTECTriggerFiles,$param_astec_trigger_file;
    }
    foreach my $ASTECTriggerFile (@ASTECTriggerFiles) {
        if(open ASTEC,"$ASTECPath/$ASTECTriggerFile") {
            my ($versionFound,$modeFound,$folderFound);
            while(<ASTEC>) {
                chomp;
                #search version
                if(/^BUILD\_VERSION\=(.+?)$/) {
                    $versionFound = $1;
                    next;
                }
                #search mode
                if(/^BUILD\_MODE\=(.+?)$/) {
                    $modeFound = $1;
                    next;
                }
                if(/^SETUP\_PATH\=(.+?)$/) {
                    my $line = $1;
                    ($line)  =~ s-\\-\/-g;
                    if($line =~ /$this_Mode\/(.+?)\//) {
                        $folderFound = $1;
                    }
                    last;
                }
            }
            close ASTEC;
            if(     ($versionFound eq $this_Version)
                and ($modeFound    eq $this_Mode)
                and ($folderFound  && ($folderFound  eq $this_Folder)) ) {
                    $Registered{$this_Project}{$this_Build}{$this_Version}{$this_Platform}{$this_Mode}{$this_Folder} = 1;
            }
        }
    }
}

sub check_size_of_project_package_path($$) {
    my ($prj,$logicalPath) = @_ ;
    my $integrity = 0;
    my $refDir    = "$NSD_SERVERS_PATH{$Site}/$prj/$logicalPath";
    my $targetDir = "$DROP_DIR/$logicalPath";
    if($^O eq "MSWin32") {
        ($targetDir) =~ s-\\-\/-g; # for 'du' command
    }
    my $sizeInNSDServer = 0;
    my $sizeInDropzone  = 0;
    $sizeInNSDServer    = sizeFolder($refDir);
    $sizeInDropzone     = sizeFolder($targetDir);
    $integrity = 1 if($sizeInNSDServer == $sizeInDropzone); # same size
    return $integrity;
}

sub sizeFolder($) {
    my ($dir) = @_;
    my $size = 0;
    if(open DU,"du -sb $dir |") {
        while(<DU>) {
            chomp;
            ($size) = $_ =~ /^(\d+)\s+/;
        }
        close DU;
    }
    return $size;
}


#############

sub display_usage() {
    print <<FIN_USAGE;

 $0 will search a build, through a soap call function
 WARNING : this web page provides a daily status, take care about the version to search
 WARNING : there is a CHECK between NSD Server and dropzone, it could take a while

    Usage   : perl $0 [options]
    Example : perl $0 -h

 [options]
    -F      force ASTEC registration, even if a build was already registered
    -JS     Just Search a build
    -Z      ASTEC registration (only for packages)
    -atf    choose an astec trigger file, by default: -atf=buildInfo.txt
    -b      choose a build name, by default: -b=$param_build
    -d      choose a specfic dropzone,
            eg: -d=\\\\build-drops-wdf\\dropzone
            if your project is not in Site.pm for your Site
    -f      find a list of specific folders, put the fullname (e.g.: packages or patches or bin or ...)
            e.g.:
            -f=packages,patches
    -h|?    argument displays helpful information about builtin commands.
    -i      choose an ini file, by default: -i=$param_build.ini, used for ASTEC registration only
    -lx     to create the latest.xml
    -m      find a specific compile mode, put the fullname (e.g.: release)
    -n      choose number of loop, by default, -n=1
            you can also specify
            'u' (unlimited) or 'i' (infinite)
            or 'd' (day),
            then -n=122400 (=nb seconds per day)
    -noc    no check size between nsd server and dropzone
    -p      choose a project name, by default: -p=$param_project
    -pf     find a list of specific platforms
            you can search by family : win, lin, sol, aix, hp, aix, mac, unix
            e.g.:
            -pf=win32_x86,linux_x86
            -pf=win
            -pf=win32_x86,sol
            available values:
            all,
            win,windows,win32_x86,win64_x64,
            unix,sol,solaris,lin,linux,aix,hp,mac,macos,macosx,
            solaris_sparc,solaris_sparc,linux_x86,linux_x64,linux_ppc64,
            aix_rs6000,aix_rs6000_64,hpux_pa-risc,hpux_ia64,mac_x86,mac_x64
    -pn     choose a list of specfic package/patch name to register in ASTEC,
            otherwise it should be for aurora project :
            $PACKAGES{aurora}{win32_x86} (for windows only) or $PACKAGES{aurora}{win64_x64} (for windows & unix)
            for other project, please update $0
            You can also do : -pn=*
    -s      choose a date time, format : \"yyyy-mm-dd hh:mm:ss\"
            e.g.: -s=\"2013-08-01 00:00:01\"
            or
            -s=\"2013-08-01\"
    -t      choose wait time between each iteration, by default -t=600 (10 minutes)
            you can specify seconds or minutes or hours like below:
              -t=1 for 1 second or -t=1s for 1 second
              -t=1m for 1 minute
              -t=1h for 1 hour
              -t=01:00 or -t=01:00:00     for 1h
              -t=01h00 or -t=01h00m       for 1h
              -t=01h00m00s or -t=01h00m00 for 1h
            $0 will convert parameter in to seconds
    -ts     choose a target site, by default: -ts=$orig_Site
            available sites:
Walldorf
Vancouver
Levallois
Bangalore
Lacrosse
Paloalto
Shangai
Sofia
Israel
'-d' is required is your build/project is not in Site.pm

    -v      find a specific version,
            same usage than Build.pl -v=
            warning, if not found play with option '-s' in additional

for more details, see here:
https://wiki.wdf.sap.corp/wiki/display/MultiPlatformBuild/nsdcheck-astec.pl+user+guide

FIN_USAGE
    exit 0;
}

sub start_script() {
    my $dateStart = scalar localtime;
    print "\nSTART of '$0' at $dateStart\n";
    print "#" x (length "START of '$0' at $dateStart"),"\n";
    print "\n";
}

sub end_script() {
    print "\n\n";
    my $dateEnd = scalar localtime;
    print "#" x (length "END of '$0' at $dateEnd"),"\n";
    print "END of '$0' at $dateEnd\n";
    exit;
}
