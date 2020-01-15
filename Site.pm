package Site;

###################################################################
# In order to use Site.pm module it is necessary to define        #
# the two environment variables SITE and PROJECT (default=Saturn) #
###################################################################

$ENV{SITE} = "\u\L$ENV{SITE}";
unless($ENV{SITE} eq "Levallois" || $ENV{SITE} eq "Vancouver" || $ENV{SITE} eq "Bangalore"  || $ENV{SITE} eq "Walldorf" || $ENV{SITE} eq "Paloalto" || $ENV{SITE} eq "Lacrosse")
{
    die("ERROR: SITE environment variable must be set (Levallois|Vancouver|Bangalore|Walldorf|Paloalto|Lacrosse)");
}
unless($ENV{PROJECT})
{
    warn("ERROR: PROJECT environment variable was not set, using default 'Saturn'");
    $ENV{PROJECT} = "Aurora";
}
$PLATFORM = $^O eq "MSWin32" ? "win32_x86" : "Unix";

# set %VARS2{Site}{Platform}{Variable}
# set %VARS3{Site}{Platform}{Project}{Variable}

# WEB_SERVICE: Servername to access the web service & log info for Torch
$VARS2{Levallois}{win32_x86}{BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";
$VARS2{Levallois}{Unix}     {BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";
$VARS2{Vancouver}{win32_x86}{BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";
$VARS2{Vancouver}{Unix}     {BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";
$VARS2{Bangalore}{win32_x86}{BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";
$VARS2{Bangalore}{Unix}     {BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";
$VARS2{Walldorf}{win32_x86} {BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";
$VARS2{Walldorf}{Unix}      {BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";
$VARS2{Paloalto}{win32_x86} {BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";
$VARS2{Paloalto}{Unix}      {BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";
$VARS2{Lacrosse}{win32_x86} {BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";
$VARS2{Lacrosse}{Unix}      {BUILD_DASHBOARD_WS} = "http://vanpglnxc9b4.pgdev.sap.corp:1080/torch/services/reporter";

# HTTP DIR: temporary dashboard (to be replaced with Lego)
$VARS2{Levallois}{win32_x86}{HTTP_DIR} = "\\\\lv-s-build01\\preintegration\\cis";
$VARS2{Levallois}{Unix}     {HTTP_DIR} = "/net/lv-s-build01/space1/drop/preintegration/cis";
$VARS2{Vancouver}{win32_x86}{HTTP_DIR} = "\\\\build-drops-vc.van.sap.corp\\tools\\preintegration\\cis";
$VARS2{Vancouver}{Unix}     {HTTP_DIR} = "/net/build-drops-vc.van.sap.corp/tools/preintegration/cis";
$VARS2{Bangalore}{win32_x86}{HTTP_DIR} = "\\\\build-drops-blr.blrl.sap.corp\\buildevents\\cis";
$VARS2{Bangalore}{Unix}     {HTTP_DIR} = "/net/build-drops-blr.blrl.sap.corp/inblrvi01a_buildevents/q_builds/cis";
$VARS2{Walldorf}{win32_x86} {HTTP_DIR} = $ENV{PROJECT} eq 'documentation' ? "\\\\build-drops-wdf\\dropzone\\DAM" : "\\\\build-drops-wdf\\preintegration\\CIS";
$VARS2{Walldorf}{Unix}      {HTTP_DIR} = $ENV{PROJECT} eq 'documentation' ? "/net/build-drops-wdf/dropzone/.volume8/DAM" : "/net/build-drops-wdf/preintegration/CIS";
$VARS2{Paloalto}{win32_x86} {HTTP_DIR} = "\\\\pahome\\inxight\\CIS";
$VARS2{Paloalto}{Unix}      {HTTP_DIR} = "/net/pahome/sjhome/inxight/CIS";
# may be legacy but build.pl still checks for this dir and writes to it. as of 4/14/2011
$VARS2{Lacrosse}{win32_x86} {HTTP_DIR} = "\\\\10.162.40.205\\cis";
$VARS2{Lacrosse}{Unix}      {HTTP_DIR} = "/mounts/bts/cis";

# IMPORT_DIR: input directory for binaries and greatest.xml on central file server
# project Saturn (default)
$VARS3{Levallois}{win32_x86}{Saturn}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\Saturn";
$VARS3{Levallois}{Unix}     {Saturn}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/Saturn";
$VARS3{Vancouver}{win32_x86}{Saturn}{IMPORT_DIR} = "\\\\vcbuild_drops.product.businessobjects.com\\dropzone\\Saturn";
$VARS3{Vancouver}{Unix}     {Saturn}{IMPORT_DIR} = "/build/vcfsclus/vanpgfs02sg2/dropzone/Saturn";
# project Titan
$VARS3{Levallois}{win32_x86}{Titan}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\Titan";
$VARS3{Levallois}{Unix}     {Titan}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/Titan";
$VARS3{Vancouver}{win32_x86}{Titan}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV12\\Titan";
$VARS3{Vancouver}{Unix}     {Titan}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV12/Titan";
$VARS3{Bangalore}{win32_x86}{Titan}{IMPORT_DIR} = "\\\\bgbuild-drops.pgdev.sap.corp\\dropzone";
$VARS3{Bangalore}{Unix}     {Titan}{IMPORT_DIR} = "/net/bgbuild-drops.pgdev.sap.corp/build/pblack/dropzone";
$VARS3{Walldorf}{win32_x86}{Titan}{IMPORT_DIR}	= "\\\\wdf-s-nsd001\\builds\\Titan";
$VARS3{Walldorf}{Unix}{Titan}{IMPORT_DIR}		= "/net/wdf-s-nsd001/vol/aggr2_Global_Replication/q_data/builds/Titan";
$VARS3{Walldorf}{win32_x86}{Titan}{ASTEC_DIR}	= "\\\\build-drops-wdf\\dropzone\\ASTEC";
$VARS3{Walldorf}{Unix}{Titan}{ASTEC_DIR}		=  "/net/build-drops-wdf/dropzone/ASTEC";

# project TitanLAFix
#$VARS3{Levallois}{win32_x86}{TitanLAFix}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\Titan";
#$VARS3{Levallois}{Unix}     {TitanLAFix}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/Titan";
$VARS3{Vancouver}{win32_x86}{TitanLAFix}{IMPORT_DIR} = "\\\\build-drops-vc\\archiveV12\\Titan";
$VARS3{Vancouver}{Unix}     {TitanLAFix}{IMPORT_DIR} = "/net/build-drops-vc/archiveV12/Titan";
#$VARS3{Bangalore}{win32_x86}{TitanLAFix}{IMPORT_DIR} = "\\\\bgbuild-drops.pgdev.sap.corp\\dropzone";
#$VARS3{Bangalore}{Unix}     {TitanLAFix}{IMPORT_DIR} = "/net/bgbuild-drops.pgdev.sap.corp/build/pblack/dropzone";

# project aladdin
$VARS3{Vancouver}{win32_x86}{aladdin_dev}{IMPORT_DIR} = "\\\\build-drops-vc.van.sap.corp\\dropzone\\aladdin_dev";
$VARS3{Vancouver}{Unix}     {aladdin_dev}{IMPORT_DIR} = "/net/build-drops-vc.van.sap.corp/dropzone/aladdin_dev";
$VARS3{Vancouver}{win32_x86}{aladdin_dev}{DROP_DIR} = "\\\\build-drops-vc.van.sap.corp\\dropzone\\aladdin_dev";
$VARS3{Vancouver}{Unix}     {aladdin_dev}{DROP_DIR} = "/net/build-drops-vc.van.sap.corp/dropzone/aladdin_dev";

# project Aurora
$VARS3{Levallois}{win32_x86}{Aurora}{IMPORT_DIR} = "\\\\lv-s-nsd001\\builds\\Aurora";
$VARS3{Levallois}{Unix}     {Aurora}{IMPORT_DIR} = "/net/lv-s-nsd001/frparvi01_BUILDS/q_files/Aurora";
$VARS3{Levallois}{Unix}     {Aurora}{WINDROP_DIR} = "/net/build-drops-lv/space1/drop/dropzone/Aurora"; #used by win4unix
$VARS3{Levallois}{win32_x86}{Aurora}{DROP_DIR} = "\\\\build-drops-lv\\dropzone\\Aurora";
$VARS3{Levallois}{Unix}     {Aurora}{DROP_DIR} = "/net/build-drops-lv/space1/drop/dropzone/Aurora";

$VARS3{Vancouver}{win32_x86}{Aurora}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\Aurora";
$VARS3{Vancouver}{Unix}     {Aurora}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/Aurora";
$VARS3{Vancouver}{win32_x86}{Aurora}{ASTEC_DIR} = "\\\\build-drops-vc\\dropzoneV13\\ASTEC";
$VARS3{Vancouver}{Unix}     {Aurora}{ASTEC_DIR} = "/net/build-drops-vc/dropzoneV13/ASTEC";

# project aurora_dev
$VARS3{Levallois}{win32_x86}{aurora_dev}{IMPORT_DIR} = "\\\\lv-s-nsd001\\builds\\aurora_dev";
$VARS3{Levallois}{Unix}     {aurora_dev}{IMPORT_DIR} = "/net/lv-s-nsd001/frparvi01_BUILDS/q_files/aurora_dev";
$VARS3{Levallois}{Unix}     {aurora_dev}{WINDROP_DIR} = "/net/lv-s-nsd001/frparvi01_BUILDS/q_files/aurora_dev"; #used by win4unix
$VARS3{Levallois}{win32_x86}{aurora_dev}{DROP_DIR} = "\\\\lv-s-nsd001\\builds\\aurora_dev";
$VARS3{Levallois}{Unix}     {aurora_dev}{DROP_DIR} = "/net/lv-s-nsd001/frparvi01_BUILDS/q_files/aurora_dev";

$VARS3{Vancouver}{win32_x86}{aurora_dev}{IMPORT_DIR}   = "\\\\build-drops-vc\\dropzone\\aurora_dev";
$VARS3{Vancouver}{Unix}     {aurora_dev}{IMPORT_DIR}   = "/net/build-drops-vc/dropzone/aurora_dev";
$VARS3{Vancouver}{win32_x86}{aurora_dev}{DROP_DIR}     = "\\\\build-drops-vc\\dropzone\\aurora_dev";
$VARS3{Vancouver}{Unix}     {aurora_dev}{DROP_DIR}     = "/net/build-drops-vc/dropzone/aurora_dev";
$VARS3{Vancouver}{win32_x86}{aurora_dev}{ASTEC_DIR}    = "\\\\build-drops-vc\\dropzone\\ASTEC";
$VARS3{Vancouver}{Unix}     {aurora_dev}{ASTEC_DIR}    = "/net/build-drops-vc/dropzone/ASTEC";

$VARS3{Lacrosse}{win32_x86}{aurora_dev}{IMPORT_DIR}   = "\\\\10.162.40.203\\dropzone\\aurora_dev";
$VARS3{Lacrosse}{Unix}     {aurora_dev}{IMPORT_DIR}   = "/mounts/bts/dropzone/aurora_dev";

$VARS3{Paloalto}{win32_x86}{aurora_dev}{IMPORT_DIR}   = "\\\\build-drops-pal.pal.sap.corp\\PAL_Dropzone\\aurora_dev";
$VARS3{Paloalto}{Unix}     {aurora_dev}{IMPORT_DIR}   = "/net/build-drops-pal.pal.sap.corp/vol/vol_PAL_Dropzone/q_TIP_PGDEV/aurora_dev";

# project aurora_maint
$VARS3{Walldorf}{win32_x86}{aurora_maint}{IMPORT_DIR} 	= "\\\\build-drops-wdf\\dropzone\\aurora_maint";
$VARS3{Walldorf}{Unix}     {aurora_maint}{IMPORT_DIR} 	= "/net/build-drops-wdf/dropzone/aurora_maint";
$VARS3{Walldorf}{win32_x86}{aurora_maint}{ASTEC_DIR} 		= "\\\\build-drops-wdf\\dropzone\\ASTEC";
$VARS3{Walldorf}{Unix}     {aurora_maint}{ASTEC_DIR} 		= "/net/build-drops-wdf/dropzone/ASTEC";
$VARS3{Walldorf}{Unix}     {aurora_maint}{WINDROP_DIR} 	= "/net/build-drops-wdf/dropzone/aurora_maint"; #used by win4unix

$VARS3{Vancouver}{win32_x86}{aurora_maint}{IMPORT_DIR}   = "\\\\build-drops-vc\\dropzone\\aurora_maint";
$VARS3{Vancouver}{Unix}     {aurora_maint}{IMPORT_DIR}   = "/net/build-drops-vc/dropzone/aurora_maint";
$VARS3{Vancouver}{win32_x86}{aurora_maint}{DROP_DIR}     = "\\\\build-drops-vc\\dropzone\\aurora_maint";
$VARS3{Vancouver}{Unix}     {aurora_maint}{DROP_DIR}     = "/net/build-drops-vc/dropzone/aurora_maint";
$VARS3{Vancouver}{win32_x86}{aurora_maint}{ASTEC_DIR}    = "\\\\build-drops-vc\\dropzone\\ASTEC";
$VARS3{Vancouver}{Unix}     {aurora_maint}{ASTEC_DIR}    = "/net/build-drops-vc/dropzone/ASTEC";

$VARS3{Lacrosse}{win32_x86}{aurora_maint}{IMPORT_DIR}   = "\\\\10.162.40.203\\dropzone\\aurora_maint";
$VARS3{Lacrosse}{Unix}     {aurora_maint}{IMPORT_DIR}   = "/mounts/bts/dropzone/aurora_maint";

$VARS3{Paloalto}{win32_x86}{aurora_maint}{IMPORT_DIR}   = "\\\\build-drops-pal.pal.sap.corp\\PAL_Dropzone\\aurora_maint";
$VARS3{Paloalto}{Unix}     {aurora_maint}{IMPORT_DIR}   = "/net/build-drops-pal.pal.sap.corp/vol/vol_PAL_Dropzone/q_TIP_PGDEV/aurora_maint";

$VARS3{Vancouver}{win32_x86}{aurora40_maint}{IMPORT_DIR}   = "\\\\build-drops-vc\\dropzone\\aurora40_maint";
$VARS3{Vancouver}{Unix}     {aurora40_maint}{IMPORT_DIR}   = "/net/build-drops-vc/dropzone/aurora40_maint";
$VARS3{Vancouver}{win32_x86}{aurora40_maint}{DROP_DIR}     = "\\\\build-drops-vc\\dropzone\\aurora40_maint";
$VARS3{Vancouver}{Unix}     {aurora40_maint}{DROP_DIR}     = "/net/build-drops-vc/dropzone/aurora40_maint";
$VARS3{Vancouver}{win32_x86}{aurora40_maint}{ASTEC_DIR}    = "\\\\build-drops-vc\\dropzone\\ASTEC";
$VARS3{Vancouver}{Unix}     {aurora40_maint}{ASTEC_DIR}    = "/net/build-drops-vc/dropzone/ASTEC";

$VARS3{Vancouver}{win32_x86}{aurora41_maint}{IMPORT_DIR}   = "\\\\build-drops-vc\\dropzone\\aurora41_maint";
$VARS3{Vancouver}{Unix}     {aurora41_maint}{IMPORT_DIR}   = "/net/build-drops-vc/dropzone/aurora41_maint";
$VARS3{Vancouver}{win32_x86}{aurora41_maint}{DROP_DIR}     = "\\\\build-drops-vc\\dropzone\\aurora41_maint";
$VARS3{Vancouver}{Unix}     {aurora41_maint}{DROP_DIR}     = "/net/build-drops-vc/dropzone/aurora41_maint";
$VARS3{Vancouver}{win32_x86}{aurora41_maint}{ASTEC_DIR}    = "\\\\build-drops-vc\\dropzone\\ASTEC";
$VARS3{Vancouver}{Unix}     {aurora41_maint}{ASTEC_DIR}    = "/net/build-drops-vc/dropzone/ASTEC";

$VARS3{Levallois}{win32_x86}{aurora_maint}{IMPORT_DIR}   = "\\\\lv-s-nsd001\\builds\\aurora_maint";
$VARS3{Levallois}{Unix}     {aurora_maint}{IMPORT_DIR}   = "/net/lv-s-nsd001/frparvi01_BUILDS/q_files/aurora_maint";
$VARS3{Levallois}{Unix}     {aurora_maint}{WINDROP_DIR} = "/net/lv-s-nsd001/frparvi01_BUILDS/q_files/aurora_maint"; #used by win4unix
$VARS3{Levallois}{win32_x86}{aurora_maint}{DROP_DIR}     = "\\\\lv-s-nsd001\\builds\\aurora_maint";
$VARS3{Levallois}{Unix}     {aurora_maint}{DROP_DIR}     = "/net/lv-s-nsd001/frparvi01_BUILDS/q_files/aurora_maint";

$VARS3{Vancouver}{win32_x86}{Build_Tools}{IMPORT_DIR}   = "\\\\build-drops-vc\\dropzone\\Build_Tools";
$VARS3{Vancouver}{Unix}     {Build_Tools}{IMPORT_DIR}   = "/net/build-drops-vc/dropzone/Build_Tools";
$VARS3{Vancouver}{win32_x86}{Build_Tools}{DROP_DIR}     = "\\\\build-drops-vc\\dropzone\\Build_Tools";
$VARS3{Vancouver}{Unix}     {Build_Tools}{DROP_DIR}     = "/net/build-drops-vc/dropzone/Build_Tools";
$VARS3{Vancouver}{win32_x86}{Build_Tools}{ASTEC_DIR}    = "\\\\build-drops-vc\\dropzone\\ASTEC";
$VARS3{Vancouver}{Unix}     {Build_Tools}{ASTEC_DIR}    = "/net/build-drops-vc/dropzone/ASTEC";

$VARS3{Bangalore}{win32_x86}{Aurora}{IMPORT_DIR} = "\\\\bglnx009.pgdev.sap.corp\\builds\\Aurora";
$VARS3{Bangalore}{Unix}     {Aurora}{IMPORT_DIR} = "/net/bgbuild-drops.pgdev.sap.corp/build/pblack/dropzone";
$VARS3{Bangalore}{win32_x86}{Aurora}{DROP_DIR} = "\\\\bgbuild-drops.pgdev.sap.corp\\export2\\Aurora";
$VARS3{Bangalore}{Unix}     {Aurora}{DROP_DIR} = "/net/bgbuild-drops.pgdev.sap.corp/export2/Aurora";

$VARS3{Walldorf}{win32_x86}{Aurora}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\Aurora";
$VARS3{Walldorf}{Unix}     {Aurora}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/Aurora";
$VARS3{Walldorf}{win32_x86}{Aurora}{ASTEC_DIR} = "\\\\build-drops-wdf\\dropzone\\ASTEC";
$VARS3{Walldorf}{Unix}     {Aurora}{ASTEC_DIR} = "/net/build-drops-wdf/dropzone/ASTEC";
$VARS3{Walldorf}{Unix}     {Aurora}{WINDROP_DIR} = "/net/build-drops-wdf/dropzone/Aurora"; #used by win4unix
$VARS3{Walldorf}{win32_x86}{components}{IMPORT_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\components";
$VARS3{Walldorf}{Unix}     {components}{IMPORT_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/components";

$VARS3{Walldorf}{win32_x86}{aurora_dev}{IMPORT_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\aurora_dev";
$VARS3{Walldorf}{Unix}     {aurora_dev}{IMPORT_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/aurora_dev";
$VARS3{Walldorf}{win32_x86}{aurora_dev}{DROP_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\aurora_dev";
$VARS3{Walldorf}{Unix}     {aurora_dev}{DROP_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/aurora_dev";
$VARS3{Walldorf}{win32_x86}{aurora_dev}{ASTEC_DIR} = "\\\\build-drops-wdf\\dropzone\\ASTEC";
$VARS3{Walldorf}{Unix}     {aurora_dev}{ASTEC_DIR} = "/net/build-drops-wdf/dropzone/ASTEC";
$VARS3{Walldorf}{Unix}     {aurora_dev}{WINDROP_DIR} = "/net/build-drops-wdf/dropzone/aurora_dev"; #used by win4unix
$VARS3{Bangalore}{win32_x86}{aurora_dev}{IMPORT_DIR} = "\\\\build-drops-blr.blrl.sap.corp\\dropzone\\aurora_dev";
$VARS3{Bangalore}{Unix}     {aurora_dev}{IMPORT_DIR} = "/net/build-drops-blr.blrl.sap.corp/inblrvi01a_dropzone/q_files/aurora_dev";
$VARS3{Bangalore}{win32_x86}{aurora_dev}{DROP_DIR} = "\\\\build-drops-blr.blrl.sap.corp\\dropzone\\aurora_dev";
$VARS3{Bangalore}{Unix}     {aurora_dev}{DROP_DIR} = "/net/build-drops-blr.blrl.sap.corp/inblrvi01a_dropzone/q_files/aurora_dev";

#b1 PROJECT
$VARS3{Walldorf}{win32_x86}{b1_dev}{IMPORT_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\b1_dev";
$VARS3{Walldorf}{Unix}     {b1_dev}{IMPORT_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/b1_dev";
$VARS3{Walldorf}{win32_x86}{b1_dev}{DROP_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\b1_dev";
$VARS3{Walldorf}{Unix}     {b1_dev}{DROP_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/b1_dev";


# for DEC
$VARS3{Bangalore}{win32_x86}{DEC}{IMPORT_DIR}   = "\\\\inblrnas02.pgdev.sap.corp\\dropzone\\RTM\\aurora_maint";
$VARS3{Bangalore}{win32_x86}{DEC}{DROP_DIR} = "\\\\build-drops-blr.pgdev.sap.corp\\dropzone\\DEC";
$VARS3{Bangalore}{Unix}     {DEC}{DROP_DIR} = "/net/build-drops-blr.pgdev.sap.corp/vol/dropzone/DEC";


# for prajnaa_client
$VARS3{Bangalore}{win32_x86}{prajnaa}{DROP_DIR} = "\\\\build-drops-blr.pgdev.sap.corp\\dropzone\\prajnaa";

# for ebilanz
$VARS3{Walldorf}{win32_x86}{ebilanz}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\ebilanz_maint";

#for nwsso_slc
$VARS3{Walldorf}{win32_x86}{nwsso_slc}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nwsso_dev";
$VARS3{Walldorf}{Unix}     {nwsso_slc}{DROP_DIR} = "/net/build-drops-wdf/dropzone/nwsso_dev";

#for nwsso_scl_fstt
$VARS3{Walldorf}{win32_x86}{nwsso_scl_fstt}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nwsso_dev";
$VARS3{Walldorf}{Unix}     {nwsso_scl_fstt}{DROP_DIR} = "/net/build-drops-wdf/dropzone/nwsso_dev";

#for nwsso_esc
$VARS3{Walldorf}{win32_x86}{nwsso_dev}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nwsso_dev";
$VARS3{Walldorf}{Unix}     {nwsso_dev}{DROP_DIR} = "/net/build-drops-wdf/dropzone/nwsso_dev";

#for nwsso_esl
$VARS3{Walldorf}{win32_x86}{nwsso_esl}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nwsso_dev";
$VARS3{Walldorf}{Unix}     {nwsso_esl}{DROP_DIR} = "/net/build-drops-wdf/dropzone/nwsso_dev";

#for nwsso_esl_fstt
$VARS3{Walldorf}{win32_x86}{nwsso_esl_fstt}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nwsso_dev";
$VARS3{Walldorf}{Unix}     {nwsso_esl_fstt}{DROP_DIR} = "/net/build-drops-wdf/dropzone/nwsso_dev";

#for nwsso_esc_fstt
$VARS3{Walldorf}{win32_x86}{nwsso_esc_fstt}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nwsso_dev";
$VARS3{Walldorf}{Unix}     {nwsso_esc_fstt}{DROP_DIR} = "/net/build-drops-wdf/dropzone/nwsso_dev";



#for nwsso_esll
$VARS3{Walldorf}{win32_x86}{nwsso_esll}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nwsso_dev";
$VARS3{Walldorf}{Unix}     {nwsso_esll}{DROP_DIR} = "/net/build-drops-wdf/dropzone/nwsso_dev";

#for nwsso_maint
$VARS3{Walldorf}{win32_x86}{nwsso_maint}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nwsso_maint";
$VARS3{Walldorf}{Unix}     {nwsso_maint}{DROP_DIR} = "/net/build-drops-wdf/dropzone/nwsso_maint";
$VARS3{Walldorf}{win32_x86}{nwsso_maint}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nwsso_maint";
$VARS3{Walldorf}{Unix}     {nwsso_maint}{DROP_DIR} = "/net/build-drops-wdf/dropzone/nwsso_maint";

$VARS3{Walldorf}{win32_x86}{nwsso_maint}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nwsso_maint";
$VARS3{Walldorf}{Unix}     {nwsso_maint}{DROP_DIR} = "/net/build-drops-wdf/dropzone/nwsso_maint";
$VARS3{Walldorf}{win32_x86}{nwsso_maint}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nwsso_maint";
$VARS3{Walldorf}{Unix}     {nwsso_maint}{DROP_DIR} = "/net/build-drops-wdf/dropzone/nwsso_maint";






# for pas
$VARS3{Bangalore}{win32_x86}{pas}{IMPORT_DIR}   = "\\\\inblrnas02.pgdev.sap.corp\\dropzone\\RTM\\aurora_maint";
$VARS3{Bangalore}{win32_x86}{pas}{DROP_DIR} = "\\\\build-drops-blr.pgdev.sap.corp\\dropzone\\pas";

# for B1Analysis
$VARS3{Walldorf}{Unix}{IMCE}{IMPORT_DIR}   = "/sapmnt/production/makeresults/BUSMB/IMCE";
$VARS3{Walldorf}{Unix}{IMCE}{DROP_DIR} = "/sapmnt/production/makeresults/BUSMB/IMCE";

$VARS3{Walldorf}{win32_x86}{Build_Tools}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\Build_Tools";
$VARS3{Walldorf}{Unix}     {Build_Tools}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/Build_Tools";
$VARS3{Walldorf}{win32_x86}{Build_Tools}{ASTEC_DIR} = "\\\\build-drops-wdf\\dropzone\\ASTEC";
$VARS3{Walldorf}{Unix}     {Build_Tools}{ASTEC_DIR} = "/net/build-drops-wdf/dropzone/ASTEC";
$VARS3{Walldorf}{Unix}     {Build_Tools}{WINDROP_DIR} = "/net/build-drops-wdf/dropzone/Build_Tools"; #used by win4unix
$VARS3{Bangalore}{win32_x86}{Build_Tools}{IMPORT_DIR} = "\\\\bgbuild-drops.pgdev.sap.corp\\dropzone\\Build_Tools";
$VARS3{Bangalore}{Unix}     {Build_Tools}{IMPORT_DIR} = "/net/blr-s-nsd001/rsync/builds/Build_Tools";
$VARS3{Bangalore}{win32_x86}{Build_Tools}{DROP_DIR} = "\\\\bgbuild-drops.pgdev.sap.corp\\export3\\Build_Tools";
$VARS3{Bangalore}{Unix}     {Build_Tools}{DROP_DIR} = "/net/bgbuild-drops.pgdev.sap.corp/export3/Build_Tools";

# project EIM_DIRS - prefix of EIM isn't consumed with rule below
$VARS3{Paloalto}{win32_x86} {EIM_DIRS}{IMPORT_DIR} = "\\\\build-drops-pal.pal.sap.corp\\PAL_Dropzone\\EIM\\DQ_Directories\\DS4X";
$VARS3{Paloalto}{Unix} {EIM_DIRS}{IMPORT_DIR} = "/net/build-drops-pal.pal.sap.corp/vol/vol_PAL_Dropzone/q_TIP_PGDEV/EIM/DQ_Directories/DS4X";

# project IM_DS
$VARS3{Levallois}{win32_x86}{IM_DS}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\IM_DS";
$VARS3{Levallois}{Unix}     {IM_DS}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/IM_DS";
$VARS3{Vancouver}{win32_x86}{IM_DS}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\IM_DS";
$VARS3{Vancouver}{Unix}     {IM_DS}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/IM_DS";
$VARS3{Paloalto}{win32_x86} {IM_DS}{IMPORT_DIR} = "\\\\build-drops-pal.pal.sap.corp\\PAL_Dropzone\\IM_DS";
$VARS3{Paloalto}{Unix} {IM_DS}{IMPORT_DIR} = "/net/build-drops-pal.pal.sap.corp/vol/vol_PAL_Dropzone/q_TIP_PGDEV/IM_DS";
$VARS3{Lacrosse}{win32_x86} {IM_DS}{IMPORT_DIR} = "\\\\10.162.40.203\\dropzone\\aurora";
$VARS3{Lacrosse}{Unix}      {IM_DS}{IMPORT_DIR} = "/mounts/bts/dropzone/aurora";
$VARS3{Lacrosse}{win32_x86} {IM_DS}{DROP_NSD_DIR} = "/net/10.162.40.203/dropzone/aurora";
$VARS3{Lacrosse}{Unix}      {IM_DS}{DROP_NSD_DIR} = "/net/10.162.40.203/dropzone/aurora";
# project IM_ICC
$VARS3{Levallois}{win32_x86}{IM_ICC}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\IM_ICC";
$VARS3{Levallois}{Unix}     {IM_ICC}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/IM_ICC";
$VARS3{Vancouver}{win32_x86}{IM_ICC}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\IM_ICC";
$VARS3{Vancouver}{Unix}     {IM_ICC}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/IM_ICC";
$VARS3{Paloalto}{win32_x86} {IM_ICC}{IMPORT_DIR} = "\\\\build-drops-pal.pal.sap.corp\\PAL_Dropzone\\IM_ICC";
$VARS3{Paloalto}{Unix} {IM_ICC}{IMPORT_DIR} = "/net/build-drops-pal.pal.sap.corp/vol/vol_PAL_Dropzone/q_TIP_PGDEV/IM_ICC";
$VARS3{Lacrosse}{win32_x86} {IM_ICC}{IMPORT_DIR} = "\\\\10.162.40.203\\dropzone\\aurora";
$VARS3{Lacrosse}{Unix}      {IM_ICC}{IMPORT_DIR} = "/mounts/bts/dropzone/aurora";
$VARS3{Lacrosse}{win32_x86} {IM_ICC}{DROP_NSD_DIR} = "/net/10.162.40.203/dropzone/aurora";
$VARS3{Lacrosse}{Unix}      {IM_ICC}{DROP_NSD_DIR} = "/net/10.162.40.203/dropzone/aurora";
# project IM_TEXTANALYSIS
$VARS3{Levallois}{win32_x86}{IM_TEXTANALYSIS}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\IM_TEXTANALYSIS";
$VARS3{Levallois}{Unix} {IM_TEXTANALYSIS}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/IM_TEXTANALYSIS";
$VARS3{Vancouver}{win32_x86}{IM_TEXTANALYSIS}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\IM_TEXTANALYSIS";
$VARS3{Vancouver}{Unix} {IM_TEXTANALYSIS}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/IM_TEXTANALYSIS";
$VARS3{Vancouver}{win32_x86}{IM_TEXTANALYSIS}{NSD_DIR} = "\\\\cavanvf06\\nsd_status_a";
$VARS3{Vancouver}{Unix} {IM_TEXTANALYSIS}{NSD_DIR} = "/net/cavanvf06/vol/nsd_status_a";
$VARS3{Paloalto}{win32_x86} {IM_TEXTANALYSIS}{IMPORT_DIR} = "\\\\pahome\\inxight\\Dropzone\\IM_TEXTANALYSIS";
$VARS3{Paloalto}{Unix} {IM_TEXTANALYSIS}{IMPORT_DIR} = "/net/pahome/sjhome/inxight/Dropzone/IM_TEXTANALYSIS";
$VARS3{Lacrosse}{win32_x86} {IM_TEXTANALYSIS}{IMPORT_DIR} = "\\\\10.162.40.203\\dropzone\\aurora";
$VARS3{Lacrosse}{Unix}      {IM_TEXTANALYSIS}{IMPORT_DIR} = "/mounts/bts/dropzone/aurora";

# project IM_EmDQ - Aurora / 14.0.0.1 & Later
$VARS3{Lacrosse}{win32_x86} {IM_EmDQ}{IMPORT_DIR}    = "\\\\10.162.40.203\\dropzone\\aurora";
$VARS3{Lacrosse}{Unix}      {IM_EmDQ}{IMPORT_DIR}    = "/mounts/bts/dropzone/aurora";
$VARS3{Lacrosse}{win32_x86} {IM_EmDQ}{DROP_NSD_DIR}  = "/net/10.162.40.203/dropzone/aurora";
$VARS3{Lacrosse}{Unix}      {IM_EmDQ}{DROP_NSD_DIR}  = "/net/10.162.40.203/dropzone/aurora";
$VARS3{Levallois}{win32_x86}{IM_EmDQ}{IMPORT_DIR}    = "\\\\build-drops-lv\\dropzone\\IM_EmDQ";
$VARS3{Levallois}{Unix} {IM_EmDQ}{IMPORT_DIR}        = "/net/build-drops-lv/space5/drop/dropzone/IM_EmDQ";
$VARS3{Vancouver}{win32_x86}{IM_EmDQ}{IMPORT_DIR}    = "\\\\build-drops-vc\\dropzoneV13\\IM_EmDQ";
$VARS3{Vancouver}{Unix} {IM_EmDQ}{IMPORT_DIR}        = "/net/build-drops-vc/dropzoneV13/IM_EmDQ";
$VARS3{Vancouver}{win32_x86} {IM_EmDQ}{DROP_NSD_DIR} = "/net/build-drops-vc/dropzoneV13/IM_EmDQ";
$VARS3{Vancouver}{win32_x86}{IM_EmDQ}{NSD_DIR}       = "\\\\cavanvf06\\nsd_status_a";
$VARS3{Vancouver}{Unix} {IM_EmDQ}{NSD_DIR}           = "/net/cavanvf06/vol/nsd_status_a";
$VARS3{Paloalto}{win32_x86} {IM_EmDQ}{IMPORT_DIR}    = "\\\\pahome\\inxight\\Dropzone\\IM_EmDQ";
$VARS3{Paloalto}{Unix} {IM_EmDQ}{IMPORT_DIR}         = "/net/pahome/sjhome/inxight/Dropzone/IM_EmDQ";

# project IM_CpData - Aurora / 14.0.0.1 and Later
$VARS3{Lacrosse}{win32_x86} {IM_CpData}{IMPORT_DIR} = "\\\\10.162.40.203\\dropzone\\aurora";
$VARS3{Lacrosse}{Unix}      {IM_CpData}{IMPORT_DIR} = "/mounts/bts/dropzone/aurora";
$VARS3{Lacrosse}{win32_x86} {IM_CpData}{DROP_NSD_DIR} = "/net/10.162.40.203/dropzone/aurora";
$VARS3{Lacrosse}{Unix}      {IM_CpData}{DROP_NSD_DIR} = "/net/10.162.40.203/dropzone/aurora";
$VARS3{Levallois}{win32_x86}{IM_CpData}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\IM_CpData";
$VARS3{Levallois}{Unix} {IM_CpData}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/IM_CpData";
$VARS3{Vancouver}{win32_x86}{IM_CpData}{IMPORT_DIR} = "\\\\build-drops-vc\\IM\\IM_CpData";
$VARS3{Vancouver}{Unix} {IM_CpData}{IMPORT_DIR} = "/net/build-drops-vc/IM/IM_CpData";
$VARS3{Paloalto}{win32_x86} {IM_CpData}{IMPORT_DIR} = "\\\\pahome\\inxight\\Dropzone\\IM_CpData";
$VARS3{Paloalto}{Unix} {IM_CpData}{IMPORT_DIR} = "/net/pahome/sjhome/inxight/Dropzone/IM_CpData";

# project IM_verified_test_data
#$VARS3{Vancouver}{win32_x86}{IM_verified_test_data}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\IM_DS";
#$VARS3{Vancouver}{Unix}     {IM_verified_test_data}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/IM_DS";
#$VARS3{Paloalto}{win32_x86} {IM_verified_test_data}{IMPORT_DIR} = "\\\\build-drops-pal.pal.sap.corp\\PAL_Dropzone\\IM_DS";
#$VARS3{Paloalto}{Unix}      {IM_verified_test_data}{IMPORT_DIR} = "/net/build-drops-pal.pal.sap.corp/vol/vol_PAL_Dropzone/q_TIP_PGDEV/IM_DS";
$VARS3{Lacrosse}{win32_x86} {IM_verified_test_data}{IMPORT_DIR} = "\\\\10.162.40.106\\testcomp\\verified";
$VARS3{Lacrosse}{Unix}      {IM_verified_test_data}{IMPORT_DIR} = "/mounts/testcomp/verified";

# project SmartBI_dev
$VARS3{Walldorf}{Unix}     {SmartBI_dev}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/SmartBI_dev";
$VARS3{Walldorf}{win32_x86}{SmartBI_dev}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\SmartBI_dev";
$VARS3{Walldorf}{Unix}     			{SmartBI_dev}{DROP_NSD_DIR} = "/net/build-drops-wdf/dropzone/SmartBI_dev";
$VARS3{Walldorf}{win32_x86}     {SmartBI_dev}{DROP_NSD_DIR} = "/net/build-drops-wdf/dropzone/SmartBI_dev";
$VARS3{Walldorf}{win32_x86}     {SmartBI_dev}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\SmartBI_dev";

# project epmim
$VARS3{Walldorf}{win32_x86}{epmim_dev}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\epmim_dev";
$VARS3{Walldorf}{Unix}     {epmim_dev}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/epmim_dev";
$VARS3{Walldorf}{win32_x86}{epmim_maint}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\epmim_maint";
$VARS3{Walldorf}{Unix}     {epmim_maint}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/epmim_maint";

# project HiVo
$VARS3{Vancouver}{win32_x86}{eim_mds_dev}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\eim_mds_dev";
$VARS3{Vancouver}{Unix}     {eim_mds_dev}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/eim_mds_dev";
$VARS3{Paloalto}{win32_x86}{eim_mds_dev}{IMPORT_DIR} = "\\\\build-drops-pal\\PAL_Dropzone\\eim_mds_dev";
$VARS3{Paloalto}{Unix}     {eim_mds_dev}{IMPORT_DIR} = "/net/build-drops-pal/PAL_Dropzone/eim_mds_dev";

# project Hilo
$VARS3{Walldorf}{win32_x86}{hilo_dev}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\hilo_dev";
$VARS3{Walldorf}{Unix}     {hilo_dev}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/hilo_dev";
$VARS3{Walldorf}{Unix}     {hilo_dev}{DROP_DIR} = "/net/build-drops-wdf/dropzone/hilo_dev";
$VARS3{Vancouver}{win32_x86}{hilo_dev}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\hilo_dev";
$VARS3{Vancouver}{Unix}     {hilo_dev}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/hilo_dev";
$VARS3{Vancouver}{win32_x86}{hilo_dev}{DROP_DIR} = "\\\\build-drops-vc\\dropzone\\hilo_dev";
$VARS3{Vancouver}{Unix}     {hilo_dev}{DROP_DIR} = "/net/build-drops-vc/dropzone/hilo_dev";
$VARS3{Bangalore}{win32_x86}{hilo_dev}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\hilo_dev";
$VARS3{Bangalore}{win32_x86}{hilo_dev}{DROP_DIR} = "\\\\build-drops-blr.pgdev.sap.corp\\dropzone\\hilo_dev";



$VARS3{Walldorf}{win32_x86}{hilo_maint}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\hilo_maint";
$VARS3{Walldorf}{Unix}     {hilo_maint}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/hilo_maint";
$VARS3{Vancouver}{win32_x86}{hilo_maint}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\hilo_maint";
$VARS3{Vancouver}{Unix}     {hilo_maint}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/hilo_maint";
$VARS3{Vancouver}{win32_x86}{hilo_maint}{DROP_DIR} = "\\\\build-drops-vc\\dropzone\\hilo_maint";
$VARS3{Vancouver}{Unix}     {hilo_maint}{DROP_DIR} = "/net/build-drops-vc/dropzone/hilo_maint";

# project NETT
$VARS3{Walldorf}{Unix}     {nett_dev}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/nett_dev";
$VARS3{Walldorf}{win32_x86}{nett_dev}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\nett_dev";
$VARS3{Walldorf}{Unix}     			{nett_dev}{DROP_NSD_DIR} = "/net/build-drops-wdf/dropzone/nett_dev";
$VARS3{Walldorf}{win32_x86}     {nett_dev}{DROP_NSD_DIR} = "/net/build-drops-wdf/dropzone/nett_dev";
$VARS3{Walldorf}{win32_x86}     {nett_dev}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nett_dev";

$VARS3{Walldorf}{Unix}     {nett_maint}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/nett_maint";
$VARS3{Walldorf}{win32_x86}{nett_maint}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\nett_maint";
$VARS3{Walldorf}{Unix}     			{nett_maint}{DROP_NSD_DIR} = "/net/build-drops-wdf/dropzone/nett_maint";
$VARS3{Walldorf}{win32_x86}     {nett_maint}{DROP_NSD_DIR} = "/net/build-drops-wdf/dropzone/nett_maint";
$VARS3{Walldorf}{win32_x86}     {nett_maint}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\nett_maint";

# project agentry_dev
$VARS3{Vancouver}{Unix}     {agentry_dev}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/agentry_dev";
$VARS3{Vancouver}{win32_x86}{agentry_dev}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\agentry_dev";
$VARS3{Vancouver}{Unix}     {agentry_dev}{DROP_DIR} = "/net/build-drops-vc/dropzone/agentry_dev";
$VARS3{Vancouver}{win32_x86}{agentry_dev}{DROP_DIR} = "\\\\build-drops-vc\\dropzone\\agentry_dev";

# project agentry_maint
$VARS3{Vancouver}{Unix}     {agentry_maint}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/agentry_maint";
$VARS3{Vancouver}{win32_x86}{agentry_maint}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\agentry_maint";
$VARS3{Vancouver}{Unix}     {agentry_maint}{DROP_DIR} = "/net/build-drops-vc/dropzone/agentry_maint";
$VARS3{Vancouver}{win32_x86}{agentry_maint}{DROP_DIR} = "\\\\build-drops-vc\\dropzone\\agentry_maint";
$VARS3{Walldorf}{Unix}     {agentry_maint}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/agentry_maint";
$VARS3{Walldorf}{win32_x86}{agentry_maint}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\agentry_maint";
$VARS3{Walldorf}{Unix}     {agentry_maint}{DROP_DIR} = "/net/build-drops-wdf/dropzone/agentry_maint";
$VARS3{Walldorf}{win32_x86}{agentry_maint}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\agentry_maint";

# project smp3
$VARS3{Walldorf}{win32_x86}{smp3_dev}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\smp3_dev";
$VARS3{Walldorf}{win32_x86}{smp3_dev}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\smp3_dev";
$VARS3{Walldorf}{Unix}{smp3_dev}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/smp3_dev";
$VARS3{Walldorf}{Unix}{smp3_dev}{DROP_DIR} = "/net/build-drops-wdf/dropzone/smp3_dev";
$VARS3{Paloalto}{win32_x86}{smp3_dev}{IMPORT_DIR} = "\\\\build-drops-pal.pal.sap.corp\\PAL_Dropzone\\smp3_dev";
$VARS3{Paloalto}{win32_x86}{smp3_dev}{DROP_DIR} = "\\\\build-drops-pal.pal.sap.corp\\PAL_Dropzone\\smp3_dev";
$VARS3{Paloalto}{Unix}{smp3_dev}{IMPORT_DIR} = "/net/build-drops-pal.pal.sap.corp/vol/vol_PAL_Dropzone/q_TIP_PGDEV/smp3_dev";
$VARS3{Paloalto}{Unix}{smp3_dev}{DROP_DIR} = "/net/build-drops-pal.pal.sap.corp/vol/vol_PAL_Dropzone/q_TIP_PGDEV/smp3_dev";
$VARS3{Walldorf}{win32_x86}{smp3_maint}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\smp3_maint";
$VARS3{Walldorf}{win32_x86}{smp3_maint}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\smp3_maint";
$VARS3{Walldorf}{Unix}{smp3_maint}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/smp3_maint";
$VARS3{Walldorf}{Unix}{smp3_maint}{DROP_DIR} = "/net/build-drops-wdf/dropzone/smp3_maint";

# project kxen_dev
$VARS3{Walldorf}{Unix}     {kxen_dev}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/kxen_dev";
$VARS3{Walldorf}{win32_x86}{kxen_dev}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\kxen_dev";
$VARS3{Walldorf}{Unix}     {kxen_dev}{DROP_DIR} = "/net/build-drops-wdf/dropzone/kxen_dev";
$VARS3{Walldorf}{win32_x86}{kxen_dev}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\kxen_dev";

# project kxen_maint
$VARS3{Walldorf}{Unix}     {kxen_maint}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/kxen_maint";
$VARS3{Walldorf}{win32_x86}{kxen_maint}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\kxen_maint";
$VARS3{Walldorf}{Unix}     {kxen_maint}{DROP_DIR} = "/net/build-drops-wdf/dropzone/kxen_maint";
$VARS3{Walldorf}{win32_x86}{kxen_maint}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\kxen_maint";

# project lms_dev
$VARS3{Walldorf}{Unix}     {lms_dev}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/lms_dev";
$VARS3{Walldorf}{win32_x86}{lms_dev}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\lms_dev";

# project lms_maint
$VARS3{Walldorf}{Unix}     {lms_maint}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/lms_maint";
$VARS3{Walldorf}{win32_x86}{lms_maint}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\lms_maint";

# project IM_ESS
$VARS3{Walldorf}{Unix}     {im_ess_dev}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/im_ess_dev";
$VARS3{Walldorf}{win32_x86}{im_ess_dev}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\im_ess_dev";
$VARS3{Walldorf}{Unix}                          {im_ess_dev}{DROP_NSD_DIR} = "/net/build-drops-wdf/dropzone/im_ess_dev";
$VARS3{Walldorf}{win32_x86}     {im_ess_dev}{DROP_NSD_DIR} = "/net/build-drops-wdf/dropzone/im_ess_dev";
$VARS3{Walldorf}{win32_x86}     {im_ess_dev}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\im_ess_dev";

# project analysis.aad
$VARS3{Walldorf}{win32_x86}{"analysis.aad_dev"}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\aurora_maint";
$VARS3{Walldorf}{Unix}     {"analysis.aad_dev"}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/aurora_maint";
$VARS3{Walldorf}{win32_x86}{"analysis.aad_dev"}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\analysis.aad_dev";
$VARS3{Walldorf}{Unix}     {"analysis.aad_dev"}{DROP_DIR} = "/net/build-drops-wdf/dropzone/analysis.aad_dev";
$VARS3{Walldorf}{win32_x86}{"analysis.aad_dev"}{ASTEC_DIR} = "\\\\build-drops-wdf\\dropzone\\ASTEC";
$VARS3{Walldorf}{Unix}     {"analysis.aad_dev"}{ASTEC_DIR} = "/net/build-drops-wdf/dropzone/ASTEC";

$VARS3{Walldorf}{win32_x86}{"analysis.aad_maint"}{IMPORT_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\aurora_maint";
$VARS3{Walldorf}{Unix}     {"analysis.aad_maint"}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/aurora_maint";
$VARS3{Walldorf}{win32_x86}{"analysis.aad_maint"}{DROP_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\analysis.aad_maint";
$VARS3{Walldorf}{Unix}     {"analysis.aad_maint"}{DROP_DIR} = "/net/build-drops-wdf/dropzone/analysis.aad_maint";

#project analysis.ao
$VARS3{Walldorf}{win32_x86}{"analysis.ao_dev"}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\aurora_maint";
$VARS3{Walldorf}{win32_x86}{"analysis.ao_dev"}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\analysis.ao_dev";
$VARS3{Walldorf}{win32_x86}{"analysis.ao_maint"}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\aurora_maint";
$VARS3{Walldorf}{win32_x86}{"analysis.ao_maint"}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\analysis.ao_maint";

# All IM projects going forward from late 4.0 releases should follow the same pattern...
if (($ENV{PROJECT} =~ /^IM[_\/\\]/) &&
    ($ENV{PROJECT} ne "IM_DS") &&
    ($ENV{PROJECT} ne "IM_ICC") &&
    ($ENV{PROJECT} ne "IM_TEXTANALYSIS") &&
    ($ENV{PROJECT} ne "IM_EmDQ") &&
    ($ENV{PROJECT} ne "IM_CpData") &&
    ($ENV{PROJECT} ne "IM_verified_test_data"))
{
    my $project_subdirectory = $ENV{PROJECT};
    $project_subdirectory =~ s/^IM[_\/\\]//;
    # The expectation is that all significant naming information exists
    # prior to any digits.  Anything between digits gets normalized to
    # a period, and anything after the digits is thrown out.
    # This facilitates using special naming to help control agents on the
    # La Crosse Build Farm while keeping the NSD and Dropzone setup consistent.
    # However, we'll also allow, unlimited period delimited versions to be kept,
    # For example, IM_HANA_2.0.0, we'll assume the user intends that the entire
    # version be important.
    $project_subdirectory =~ s/(\d+)([^0-9\.]+(\d+)|\.(\d+(\.\d+)*)).*$/$1.$3$4/g;
    $project_subdirectory =~ s/[_\\\/]+/\//g;
    my $unix_folder;
    if ($project_subdirectory =~ /\//)
    {
        $unix_folder = "IM_$project_subdirectory";
    }
    else
    {
        $unix_folder = "IM/$project_subdirectory";
    }
    my $win_folder = $unix_folder;
    $win_folder =~ s/\//\\/g;

    my $dropzone_variable = "IMPORT_DIR";
    if ($project_subdirectory =~ /^4\.[01]$/)
    {
        # Since late 4.0 / early 4.1 releases were when the standard was defined, we'll allow the existing import directory
        # to be used, however, we'll export the projects to the IM/4.x directory.  If this doesn't work, define a
        # separate project to handle that special case.  This might be temporary until we fully transition...
        $dropzone_variable = "DROP_DIR";
        $VARS3{Lacrosse}{win32_x86} {$ENV{PROJECT}}{IMPORT_DIR} = "\\\\10.162.40.203\\dropzone\\aurora";
        $VARS3{Lacrosse}{Unix}      {$ENV{PROJECT}}{IMPORT_DIR} = "/mounts/bts/dropzone/aurora";

        # We'll use the pre-existing IM_DS project for these early projects in Vancouver.
        # there isn't a great way of this working, but this is about as good as we could get.
        $VARS3{Vancouver}{win32_x86}{$ENV{PROJECT}}{IMPORT_DIR} = $VARS3{Vancouver}{win32_x86}{IM_DS}{IMPORT_DIR};
        $VARS3{Vancouver}{Unix}{$ENV{PROJECT}}{IMPORT_DIR}      = $VARS3{Vancouver}{Unix}{IM_DS}{IMPORT_DIR};

    }
    $VARS3{Vancouver}{win32_x86}{$ENV{PROJECT}}{$dropzone_variable} = "\\\\build-drops-vc\\dropzone\\$win_folder";
    $VARS3{Vancouver}{Unix}{$ENV{PROJECT}}{$dropzone_variable}      = "/net/build-drops-vc/dropzone/$unix_folder";

    $VARS3{Vancouver}{win32_x86}{$ENV{PROJECT}}{DROP_NSD_DIR} = $VARS3{Vancouver}{Unix}{$ENV{PROJECT}}{$dropzone_variable};
    $VARS3{Vancouver}{Unix}{$ENV{PROJECT}}{DROP_NSD_DIR}      = $VARS3{Vancouver}{win32_x86} {$ENV{PROJECT}}{DROP_NSD_DIR};

    $VARS3{Lacrosse}{win32_x86} {$ENV{PROJECT}}{$dropzone_variable} = "\\\\10.162.40.203\\dropzone\\$win_folder";
    $VARS3{Lacrosse}{Unix}      {$ENV{PROJECT}}{$dropzone_variable} = "/mounts/bts/dropzone/$unix_folder";
    $VARS3{Lacrosse}{win32_x86} {$ENV{PROJECT}}{DROP_NSD_DIR} = "/net/10.162.40.203/dropzone/$unix_folder";
    $VARS3{Lacrosse}{Unix}      {$ENV{PROJECT}}{DROP_NSD_DIR} = $VARS3{Lacrosse}{win32_x86} {$ENV{PROJECT}}{DROP_NSD_DIR};

    $VARS3{Paloalto}{win32_x86} {$ENV{PROJECT}}{IMPORT_DIR} = "\\\\build-drops-pal.pal.sap.corp\\PAL_Dropzone\\$win_folder";
    $VARS3{Paloalto}{Unix}      {$ENV{PROJECT}}{IMPORT_DIR} = "/net/build-drops-pal.pal.sap.corp/vol/vol_PAL_Dropzone/q_TIP_PGDEV/$unix_folder";
    $VARS3{Paloalto}{win32_x86} {$ENV{PROJECT}}{DROP_NSD_DIR} = $VARS3{Paloalto}{Unix}{$ENV{PROJECT}}{IMPORT_DIR};
    $VARS3{Paloalto}{Unix}      {$ENV{PROJECT}}{DROP_NSD_DIR} = $VARS3{Paloalto}{win32_x86} {$ENV{PROJECT}}{DROP_NSD_DIR};

    $VARS3{Walldorf}{win32_x86} {$ENV{PROJECT}}{IMPORT_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\$win_folder";
    $VARS3{Walldorf}{Unix}      {$ENV{PROJECT}}{IMPORT_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/$unix_folder";
    $VARS3{Walldorf}{win32_x86} {$ENV{PROJECT}}{DROP_NSD_DIR} = $VARS3{Walldorf}{Unix}{$ENV{PROJECT}}{IMPORT_DIR};
    $VARS3{Walldorf}{Unix}      {$ENV{PROJECT}}{DROP_NSD_DIR} = $VARS3{Walldorf}{win32_x86} {$ENV{PROJECT}}{DROP_NSD_DIR};
}
$VARS3{Vancouver}{win32_x86}{IM_maint}{IMPORT_DIR}   = "\\\\build-drops-vc\\dropzone\\IM_maint";
$VARS3{Vancouver}{Unix}     {IM_maint}{IMPORT_DIR}   = "/net/build-drops-vc/dropzone/IM_maint";
$VARS3{Vancouver}{win32_x86}{IM_maint}{DROP_NSD_DIR}   = "\\\\build-drops-vc\\dropzone\\IM_maint";
$VARS3{Vancouver}{Unix}     {IM_maint}{DROP_NSD_DIR}   = "/net/build-drops-vc/dropzone/IM_maint";

$VARS3{Lacrosse}{win32_x86}{IM_maint}{IMPORT_DIR}   = "\\\\10.162.40.203\\dropzone\\IM_maint";
$VARS3{Lacrosse}{Unix}     {IM_maint}{IMPORT_DIR}   = "/mounts/bts/dropzone/IM_maint";

$VARS3{Paloalto}{win32_x86}{IM_maint}{IMPORT_DIR}   = "\\\\build-drops-pal.pal.sap.corp\\PAL_Dropzone\\IM_maint";
$VARS3{Paloalto}{Unix}     {IM_maint}{IMPORT_DIR}   = "/net/build-drops-pal.pal.sap.corp/vol/vol_PAL_Dropzone/q_TIP_PGDEV/IM_maint";

# project IW
$VARS3{Levallois}{win32_x86}{IW}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\IW";
$VARS3{Levallois}{Unix}     {IW}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/IW";
$VARS3{Vancouver}{win32_x86}{IW}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV11\\IW";
$VARS3{Vancouver}{Unix}     {IW}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV11/IW";
# project Labs
$VARS3{Levallois}{win32_x86}{Labs}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\Labs";
$VARS3{Levallois}{Unix}     {Labs}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/Labs";
$VARS3{Vancouver}{win32_x86}{Labs}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV12\\Labs";
$VARS3{Vancouver}{Unix}     {Labs}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV12/Labs";
# project MercuryA
$VARS3{Levallois}{win32_x86}{MercuryA}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\MercuryA";
$VARS3{Levallois}{Unix}     {MercuryA}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/MercuryA";
$VARS3{Vancouver}{win32_x86}{MercuryA}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV12\\MercuryA";
$VARS3{Vancouver}{Unix}     {MercuryA}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV12/MercuryA";
# project Polestar
$VARS3{Levallois}{win32_x86}{Polestar}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\Polestar";
$VARS3{Levallois}{Unix}     {Polestar}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/Polestar";
$VARS3{Vancouver}{win32_x86}{Polestar}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV11\\Polestar";
$VARS3{Vancouver}{Unix}     {Polestar}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV11/Polestar";

# project polestar_maint
$VARS3{Walldorf}{win32_x86}{polestar_maint}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone4\\polestar_maint";
$VARS3{Walldorf}{Unix}     {polestar_maint}{IMPORT_DIR} = "/net/build-drops-lv/space4/drop/dropzone/polestar_maint";

# project POA_SBC
$VARS3{Levallois}{win32_x86}{POA_SBC}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\POA_SBC";
$VARS3{Levallois}{Unix}     {POA_SBC}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/POA_SBC";
$VARS3{Vancouver}{win32_x86}{POA_SBC}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\POA_SBC";
$VARS3{Vancouver}{Unix}     {POA_SBC}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/POA_SBC";
# project POA_AUI
$VARS3{Levallois}{win32_x86}{POA_AUI}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\POA_AUI";
$VARS3{Levallois}{Unix}     {POA_AUI}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/POA_AUI";
$VARS3{Vancouver}{win32_x86}{POA_AUI}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\POA_AUI";
$VARS3{Vancouver}{Unix}     {POA_AUI}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/POA_AUI";
$VARS3{Walldorf}{win32_x86} {POA_AUI}{IMPORT_DIR} = "\\\\vmw3100.wdf.sap.corp\\dropzone\\POA_AUI";
# project SearchPartnering2007
$VARS3{Levallois}{win32_x86}{SearchPartnering2007}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\SearchPartnering2007";
$VARS3{Levallois}{Unix}     {SearchPartnering2007}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/SearchPartnering2007";
$VARS3{Vancouver}{win32_x86}{SearchPartnering2007}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV12\\SearchPartnering2007";
$VARS3{Vancouver}{Unix}     {SearchPartnering2007}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV12/SearchPartnering2007";

# project Andromeda
$VARS3{Walldorf}{win32_x86}{Andromeda}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\Andromeda";
$VARS3{Walldorf}{Unix}     {Andromeda}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/Andromeda";

# project FPM70
$VARS3{Levallois}{win32_x86}{FPM70}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\FPM70";
$VARS3{Levallois}{Unix}     {FPM70}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/FPM70";
# project Olympus
$VARS3{Levallois}{win32_x86}{Olympus}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\Olympus";
$VARS3{Levallois}{Unix}     {Olympus}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/Olympus";
$VARS3{Walldorf}{win32_x86} {Olympus}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\Olympus";
$VARS3{Walldorf}{Unix}      {Olympus}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/Olympus";
$VARS3{Vancouver}{win32_x86}{Olympus}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\Olympus";
$VARS3{Vancouver}{Unix}     {Olympus}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/Olympus";
$VARS3{Walldorf}{win32_x86}{Olympus}{SMTP_SERVER} = "mailhost.product.businessobjects.com:26";
$VARS3{Walldorf}{Unix}     {Olympus}{SMTP_SERVER} = "mailhost.product.businessobjects.com:26";


# project X5
$VARS3{Levallois}{win32_x86}{X5}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\Titan";
$VARS3{Levallois}{Unix}     {X5}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/Titan";
$VARS3{Vancouver}{win32_x86}{X5}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV12\\Titan";
$VARS3{Vancouver}{Unix}     {X5}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV12/Titan";
$VARS3{Levallois}{win32_x86}{X5}{DROP_DIR} = "\\\\build-drops-lv\\dropzone\\X5";
$VARS3{Levallois}{Unix}     {X5}{DROP_DIR} = "/net/build-drops-lv/space5/drop/dropzone/X5";
$VARS3{Vancouver}{win32_x86}{X5}{DROP_DIR} = "\\\\build-drops-vc\\dropzoneV12\\X5";
$VARS3{Vancouver}{Unix}     {X5}{DROP_DIR} = "/net/build-drops-vc/dropzoneV12/X5";
# project X6
$VARS3{Levallois}{win32_x86}{X6}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\Titan";
$VARS3{Levallois}{Unix}     {X6}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/Titan";
$VARS3{Vancouver}{win32_x86}{X6}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV12\\Titan";
$VARS3{Vancouver}{Unix}     {X6}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV12/Titan";
$VARS3{Levallois}{win32_x86}{X6}{DROP_DIR} = "\\\\build-drops-lv\\dropzone\\X6";
$VARS3{Levallois}{Unix}     {X6}{DROP_DIR} = "/net/build-drops-lv/space5/drop/dropzone/X6";
$VARS3{Vancouver}{win32_x86}{X6}{DROP_DIR} = "\\\\build-drops-vc\\dropzoneV12\\X6";
$VARS3{Vancouver}{Unix}     {X6}{DROP_DIR} = "/net/build-drops-vc/dropzoneV12/X6";
# project Pegasus
$VARS3{Levallois}{win32_x86}{Pegasus}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\Pegasus";
$VARS3{Levallois}{Unix}     {Pegasus}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/Pegasus";
$VARS3{Vancouver}{win32_x86}{Pegasus}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV12\\Pegasus";
$VARS3{Vancouver}{Unix}     {Pegasus}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV12/Pegasus";
# project Columbus
$VARS3{Levallois}{win32_x86}{Columbus}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\Titan";
$VARS3{Levallois}{Unix}     {Columbus}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/Titan";
$VARS3{Vancouver}{win32_x86}{Columbus}{IMPORT_DIR} = "\\\\vcbuild_drops.product.businessobjects.com\\dropzone\\Titan";
$VARS3{Vancouver}{Unix}     {Columbus}{IMPORT_DIR} = "/build/vcfsclus/vanpgfs02sg2/dropzone/Titan";
$VARS3{Bangalore}{win32_x86}{Columbus}{IMPORT_DIR} = "\\\\bgbuild-drops.pgdev.sap.corp\\dropzone";
$VARS3{Bangalore}{Unix}     {Columbus}{IMPORT_DIR} = "/net/bgbuild-drops.pgdev.sap.corp/build/pblack/dropzone";
$VARS3{Levallois}{win32_x86}{Columbus}{DROP_DIR} = "\\\\build-drops-lv\\dropzone\\Columbus";
$VARS3{Levallois}{Unix}     {Columbus}{DROP_DIR} = "/net/build-drops-lv/space5/drop/dropzone/Columbus";
$VARS3{Vancouver}{win32_x86}{Columbus}{DROP_DIR} = "\\\\build-drops-vc\\dropzoneV12\\Columbus";
$VARS3{Vancouver}{Unix}     {Columbus}{DROP_DIR} = "/net/build-drops-vc/dropzoneV12/Columbus";
$VARS3{Bangalore}{win32_x86}{Columbus}{DROP_DIR} = "\\\\bgbuild-drops.pgdev.sap.corp\\dropzone";
$VARS3{Bangalore}{Unix}     {Columbus}{DROP_DIR} = "/net/bgbuild-drops.pgdev.sap.corp/build/pblack/dropzone";
# project Pioneer
$VARS3{Vancouver}{win32_x86}{Pioneer}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV12\\Titan";
$VARS3{Vancouver}{Unix}     {Pioneer}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV12/Titan";
$VARS3{Walldorf}{win32_x86}{Pioneer}{IMPORT_DIR} = "\\\\dewdfgrnas01\\builds\\Titan";
$VARS3{Vancouver}{win32_x86}{Pioneer}{DROP_DIR} = "\\\\build-drops-vc\\dropzoneV12\\Pioneer";
$VARS3{Vancouver}{Unix}     {Pioneer}{DROP_DIR} = "/net/build-drops-vc/dropzoneV12/Pioneer";
$VARS3{Walldorf}{win32_x86}{Pioneer}{DROP_DIR} = "\\\\wdfd00166548a\\EXCHANGE\\dropzone\\Pioneer";
# project Cortez
$VARS3{Vancouver}{win32_x86}{Cortez}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\Cortez";
$VARS3{Vancouver}{Unix}     {Cortez}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/Cortez";
# project IDDC_CES
$VARS3{Levallois}{win32_x86}{IDDC_CES}{IMPORT_DIR} = "\\\\build-drops-lv.pgdev.sap.corp\\dropzone\\IDDC_CES";
$VARS3{Levallois}{Unix}     {IDDC_CES}{IMPORT_DIR} = "/net/build-drops-lv/space5/drop/dropzone/IDDC_CES";
$VARS3{Vancouver}{win32_x86}{IDDC_CES}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\IDDC_CES";
$VARS3{Vancouver}{Unix}     {IDDC_CES}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/IDDC_CES";
# project components
$VARS3{Levallois}{win32_x86}{components}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\components";
$VARS3{Levallois}{Unix}     {components}{IMPORT_DIR} = "/net/build-drops-lv/space12/drop/dropzone/Aurora";
$VARS3{Levallois}{Unix}     {components}{DROP_DIR_B} = "/net/build-drops-lv/space5/drop/dropzone/components";
$VARS3{Vancouver}{win32_x86}{components}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\components";
$VARS3{Vancouver}{Unix}     {components}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/components";
$VARS3{Vancouver}{win32_x86}{components}{DROP_DIR} = "\\\\build-drops-vc\\dropzone\\components";
$VARS3{Vancouver}{Unix}     {components}{DROP_DIR} = "/net/build-drops-vc/dropzone/components";
$VARS3{Bangalore}{win32_x86}{components}{IMPORT_DIR} = "\\\\bgbuild-drops.pgdev.sap.corp\\dropzone";
$VARS3{Bangalore}{Unix}     {components}{IMPORT_DIR} = "/net/bgbuild-drops.pgdev.sap.corp/build/pblack/dropzone";
$VARS3{Walldorf}{win32_x86}{components}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\components";
$VARS3{Walldorf}{Unix}     {components}{DROP_DIR} = "/net/build-drops-wdf/dropzone/components";
# project misc (To be over-written by envrionment parameters in INI file)
$VARS3{Levallois}{win32_x86}{misc}{IMPORT_DIR} = "";
$VARS3{Levallois}{Unix}     {misc}{IMPORT_DIR} = "";
$VARS3{Vancouver}{win32_x86}{misc}{IMPORT_DIR} = "";
$VARS3{Vancouver}{Unix}     {misc}{IMPORT_DIR} = "";
# project mwf
$VARS3{Levallois}{win32_x86}{mwf}{IMPORT_DIR} = "\\\\build-drops-lv\\dropzone\\mwf";
$VARS3{Levallois}{Unix}     {mwf}{IMPORT_DIR} = "/net/build-drops-lv/space12/dropzone/mwf";
$VARS3{Vancouver}{win32_x86}{mwf}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\mwf";
$VARS3{Vancouver}{Unix}     {mwf}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/mwf";
$VARS3{Bangalore}{win32_x86}{mwf}{IMPORT_DIR} = "\\\\bglnx009.pgdev.sap.corp\\builds\\Aurora";
$VARS3{Bangalore}{Unix}     {mwf}{IMPORT_DIR} = "/net/bgbuild-drops.pgdev.sap.corp/export/stg01/dropzone/mwf";
$VARS3{Walldorf}{win32_x86} {mwf}{IMPORT_DIR} = "\\\\Build-drops-wdf\\dropzone\\mwf";
$VARS3{Walldorf}{Unix}      {mwf}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/mwf";

# project EventInsight
$VARS3{Levallois}{win32_x86}{eventinsight}{IMPORT_DIR} = "\\\\lv-s-nsd001\\builds\\Eventinsight";
$VARS3{Levallois}{Unix}     {eventinsight}{IMPORT_DIR} = "/net/lv-s-nsd001/frparvi01_BUILDS/q_files/Eventinsight";
$VARS3{Levallois}{win32_x86}{eventinsight}{DROP_DIR} = "\\\\build-drops-lv\\dropzone\\Eventinsight";
$VARS3{Levallois}{Unix}     {eventinsight}{DROP_DIR} = "/net/build-drops-lv/space1/drop/dropzone/Eventinsight";
$VARS3{Walldorf}{win32_x86}{eventinsight}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\Eventinsight";
$VARS3{Walldorf}{Unix}     {eventinsight}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/Eventinsight";
$VARS3{Vancouver}{win32_x86}{eventinsight}{DROP_DIR} = "\\\\build-drops-vc\\dropzoneV13\\Eventinsight";
$VARS3{Vancouver}{Unix}     {eventinsight}{DROP_DIR} = "/net/build-drops-vc/dropzoneV13/Eventinsight";
$VARS3{Vancouver}{win32_x86}{eventinsight}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzoneV13\\Eventinsight";
$VARS3{Vancouver}{Unix}     {eventinsight}{IMPORT_DIR} = "/net/build-drops-vc/dropzoneV13/Eventinsight";

# project nova_dev
$VARS3{Levallois}{win32_x86}{nova_dev}{IMPORT_DIR} = "\\\\lv-s-nsd001\\builds\\nova_dev";
$VARS3{Levallois}{Unix}     {nova_dev}{IMPORT_DIR} = "/net/lv-s-nsd001/frparvi01_BUILDS/q_files/nova_dev";
$VARS3{Levallois}{win32_x86}{nova_dev}{DROP_DIR} = "\\\\build-drops-lv\\dropzone\\nova_dev";
$VARS3{Levallois}{Unix}     {nova_dev}{DROP_DIR} = "/net/build-drops-lv/space1/drop/dropzone/nova_dev";
$VARS3{Walldorf}{win32_x86}{nova_dev}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\nova_dev";
$VARS3{Walldorf}{Unix}     {nova_dev}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/nova_dev";
$VARS3{Vancouver}{win32_x86}{nova_dev}{IMPORT_DIR}   = "\\\\build-drops-vc\\dropzone\\nova_dev";
$VARS3{Vancouver}{Unix}     {nova_dev}{IMPORT_DIR}   = "/net/build-drops-vc/dropzone/nova_dev";
$VARS3{Vancouver}{win32_x86}{nova_dev}{DROP_DIR}     = "\\\\build-drops-vc\\dropzone\\nova_dev";
$VARS3{Vancouver}{Unix}     {nova_dev}{DROP_DIR}     = "/net/build-drops-vc/dropzone/nova_dev";

# project nova_maint
$VARS3{Levallois}{win32_x86}{nova_maint}{IMPORT_DIR} = "\\\\lv-s-nsd001\\builds\\nova_maint";
$VARS3{Levallois}{Unix}     {nova_maint}{IMPORT_DIR} = "/net/lv-s-nsd001/frparvi01_BUILDS/q_files/nova_maint";
$VARS3{Levallois}{win32_x86}{nova_maint}{DROP_DIR} = "\\\\build-drops-lv\\dropzone\\nova_maint";
$VARS3{Levallois}{Unix}     {nova_maint}{DROP_DIR} = "/net/build-drops-lv/space1/drop/dropzone/nova_maint";
$VARS3{Walldorf}{win32_x86}{nova_maint}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\nova_maint";
$VARS3{Walldorf}{Unix}     {nova_maint}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/nova_maint";
$VARS3{Vancouver}{win32_x86}{nova_maint}{IMPORT_DIR}   = "\\\\build-drops-vc\\dropzone\\nova_maint";
$VARS3{Vancouver}{Unix}     {nova_maint}{IMPORT_DIR}   = "/net/build-drops-vc/dropzone/nova_maint";
$VARS3{Vancouver}{win32_x86}{nova_maint}{DROP_DIR}     = "\\\\build-drops-vc\\dropzone\\nova_maint";
$VARS3{Vancouver}{Unix}     {nova_maint}{DROP_DIR}     = "/net/build-drops-vc/dropzone/nova_maint";

# project lumira_dev
$VARS3{Vancouver}{win32_x86}{lumira_dev}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\lumira_dev";
$VARS3{Vancouver}{Unix}     {lumira_dev}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/lumira_dev";
$VARS3{Vancouver}{win32_x86}{lumira_dev}{DROP_DIR} = "\\\\build-drops-vc\\dropzone\\lumira_dev";
$VARS3{Vancouver}{Unix}     {lumira_dev}{DROP_DIR} = "/net/build-drops-vc/dropzone/lumira_dev";
$VARS3{Vancouver}{win32_x86}{lumira_dev}{ASTEC_DIR} = "\\\\build-drops-vc\\dropzone\\ASTEC";
$VARS3{Vancouver}{Unix}     {lumira_dev}{ASTEC_DIR} = "/net/build-drops-vc/dropzone/ASTEC";
$VARS3{Walldorf}{win32_x86}{lumira_dev}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\lumira_dev";
$VARS3{Walldorf}{Unix}     {lumira_dev}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/lumira_dev";
$VARS3{Walldorf}{win32_x86}{lumira_dev}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\lumira_dev";
$VARS3{Walldorf}{Unix}     {lumira_dev}{DROP_DIR} = "/net/build-drops-wdf/dropzone/lumira_dev";
$VARS3{Walldorf}{win32_x86}{lumira_dev}{ASTEC_DIR} = "\\\\build-drops-wdf\\dropzone\\ASTEC";
$VARS3{Walldorf}{Unix}     {lumira_dev}{ASTEC_DIR} = "/net/build-drops-wdf/dropzone/ASTEC";

# project lumira_maint
$VARS3{Vancouver}{win32_x86}{lumira_maint}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\lumira_maint";
$VARS3{Vancouver}{Unix}     {lumira_maint}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/lumira_maint";
$VARS3{Vancouver}{win32_x86}{lumira_maint}{DROP_DIR} = "\\\\build-drops-vc\\dropzone\\lumira_maint";
$VARS3{Vancouver}{Unix}     {lumira_maint}{DROP_DIR} = "/net/build-drops-vc/dropzone/lumira_maint";
$VARS3{Vancouver}{win32_x86}{lumira_maint}{ASTEC_DIR} = "\\\\build-drops-vc\\dropzone\\ASTEC";
$VARS3{Vancouver}{Unix}     {lumira_maint}{ASTEC_DIR} = "/net/build-drops-vc/dropzone/ASTEC";
$VARS3{Walldorf}{win32_x86}{lumira_maint}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\lumira_maint";
$VARS3{Walldorf}{Unix}     {lumira_maint}{IMPORT_DIR} = "/net/build-drops-wdf/dropzone/lumira_maint";
$VARS3{Walldorf}{win32_x86}{lumira_maint}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\lumira_maint";
$VARS3{Walldorf}{Unix}     {lumira_maint}{DROP_DIR} = "/net/build-drops-wdf/dropzone/lumira_maint";
$VARS3{Walldorf}{win32_x86}{lumira_maint}{ASTEC_DIR} = "\\\\build-drops-wdf\\dropzone\\ASTEC";
$VARS3{Walldorf}{Unix}     {lumira_maint}{ASTEC_DIR} = "/net/build-drops-wdf/dropzone/ASTEC";

# project hana_bi_dev
$VARS3{Vancouver}{win32_x86}{hana_bi_dev}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\hana_bi_dev";
$VARS3{Vancouver}{Unix}     {hana_bi_dev}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/hana_bi_dev";
$VARS3{Vancouver}{win32_x86}{hana_bi_dev}{DROP_DIR} = "\\\\build-drops-vc\\dropzone\\hana_bi_dev";
$VARS3{Vancouver}{Unix}     {hana_bi_dev}{DROP_DIR} = "/net/build-drops-vc/dropzone/hana_bi_dev";
$VARS3{Vancouver}{win32_x86}{hana_bi_dev}{ASTEC_DIR} = "\\\\build-drops-vc\\dropzone\\ASTEC";
$VARS3{Vancouver}{Unix}     {hana_bi_dev}{ASTEC_DIR} = "/net/build-drops-vc/dropzone/ASTEC";

# project hana_bi_maint
$VARS3{Vancouver}{win32_x86}{hana_bi_maint}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\hana_bi_maint";
$VARS3{Vancouver}{Unix}     {hana_bi_maint}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/hana_bi_maint";
$VARS3{Vancouver}{win32_x86}{hana_bi_maint}{DROP_DIR} = "\\\\build-drops-vc\\dropzone\\hana_bi_maint";
$VARS3{Vancouver}{Unix}     {hana_bi_maint}{DROP_DIR} = "/net/build-drops-vc/dropzone/hana_bi_maint";
$VARS3{Vancouver}{win32_x86}{hana_bi_maint}{ASTEC_DIR} = "\\\\build-drops-vc\\dropzone\\ASTEC";
$VARS3{Vancouver}{Unix}     {hana_bi_maint}{ASTEC_DIR} = "/net/build-drops-vc/dropzone/ASTEC";

# project cloud_bi_dev
$VARS3{Vancouver}{win32_x86}{cloud_bi_dev}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\cloud_bi_dev";
$VARS3{Vancouver}{Unix}     {cloud_bi_dev}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/cloud_bi_dev";
$VARS3{Vancouver}{win32_x86}{cloud_bi_dev}{DROP_DIR} = "\\\\build-drops-vc\\dropzone\\cloud_bi_dev";
$VARS3{Vancouver}{Unix}     {cloud_bi_dev}{DROP_DIR} = "/net/build-drops-vc/dropzone/cloud_bi_dev";

# project ondemand_dev
$VARS3{Vancouver}{win32_x86}{ondemand_dev}{IMPORT_DIR} = "\\\\build-drops-vc\\dropzone\\ondemand_dev";
$VARS3{Vancouver}{Unix}     {ondemand_dev}{IMPORT_DIR} = "/net/build-drops-vc/dropzone/ondemand_dev";
$VARS3{Vancouver}{win32_x86}{ondemand_dev}{DROP_DIR} = "\\\\build-drops-vc\\dropzone\\ondemand_dev";
$VARS3{Vancouver}{Unix}     {ondemand_dev}{DROP_DIR} = "/net/build-drops-vc/dropzone/ondemand_dev";

# project CrystalServer2011
$VARS3{Vancouver}{win32_x86}{cs2011}{ASTEC_DIR}    = "\\\\build-drops-vc.van.sap.corp\\dropzone\\ASTEC";
$VARS3{Vancouver}{Unix}     {cs2011}{ASTEC_DIR}    = "/net/build-drops-vc.van.sap.corp/dropzone/ASTEC";
$VARS3{Vancouver}{win32_x86}{cs2011}{DROP_DIR}     = "\\\\build-drops-vc.van.sap.corp\\dropzone\\aurora_dev";
$VARS3{Vancouver}{Unix}     {cs2011}{DROP_DIR}     = "/net/build-drops-vc.van.sap.corp/dropzone/aurora_dev";
$VARS3{Vancouver}{win32_x86}{cs2011}{IMPORT_DIR}   = "\\\\build-drops-vc.van.sap.corp\\dropzone\\aurora_maint";
$VARS3{Vancouver}{Unix}     {cs2011}{IMPORT_DIR}   = "/net/build-drops-vc.van.sap.corp/dropzone/aurora_maint";

# project components_maint
$VARS3{Vancouver}{win32_x86}{components_maint}{IMPORT_DIR}   = "\\\\build-drops-vc\\dropzone\\components_maint";
$VARS3{Vancouver}{Unix}     {components_maint}{IMPORT_DIR}   = "/net/build-drops-vc/dropzone/components_maint";
$VARS3{Vancouver}{win32_x86}{components_maint}{DROP_DIR}     = "\\\\build-drops-vc\\dropzone\\components_maint";
$VARS3{Vancouver}{Unix}     {components_maint}{DROP_DIR}     = "/net/build-drops-vc/dropzone/components_maint";

# project streamwork_outlook_dev
$VARS3{Vancouver}{win32_x86}{streamwork_outlook_dev}{DROP_DIR}   = "\\\\build-drops-vc.van.sap.corp\\dropzone\\streamwork_outlook_dev";
$VARS3{Vancouver}{Unix}     {streamwork_outlook_dev}{DROP_DIR}   = "/net/build-drops-vc.van.sap.corp/dropzone/streamwork_outlook_dev";
$VARS3{Vancouver}{win32_x86}{streamwork_outlook_dev}{IMPORT_DIR} = "\\\\build-drops-vc.van.sap.corp\\dropzone\\streamwork_outlook_dev";
$VARS3{Vancouver}{Unix}     {streamwork_outlook_dev}{IMPORT_DIR} = "/net/build-drops-vc.van.sap.corp/dropzone/streamwork_outlook_dev";

# project documentation
$VARS3{Levallois}{win32_x86}{documentation}{IMPORT_DIR}     = "\\\\build-drops-lv.pgdev.sap.corp\\dropzone\\documentation";
$VARS3{Levallois}{Unix}     {documentation}{IMPORT_DIR}     = "/net/build-drops-lv.pgdev.sap.corp/space5/drop/dropzone/documentation";
$VARS3{Vancouver}{win32_x86}{documentation}{IMPORT_DIR}     = "\\\\build-drops-vc.van.sap.corp\\dropzoneV12\\documentation";
$VARS3{Vancouver}{Unix}     {documentation}{IMPORT_DIR}     = "/net/build-drops-vc.van.sap.corp/dropzoneV12/documentation";
$VARS3{Walldorf}{win32_x86} {documentation}{IMPORT_DIR}     = "\\\\build-drops-wdf\\dropzone\\documentation";
$VARS3{Walldorf}{Unix}      {documentation}{IMPORT_DIR}     = "/net/build-drops-wdf/dropzone/documentation";
$VARS3{Walldorf}{win32_x86} {documentation}{BUILDTOOLS_DIR} = "\\\\build-drops-wdf\\BuildTools";
$VARS3{Walldorf}{Unix}      {documentation}{BUILDTOOLS_DIR} = "/net/build-drops-wdf/BuildTools";

$VARS2{Levallois}{win32_x86}{NSD_DIR} = "\\\\lv-s-nsd001\\builds\\status";
$VARS2{Levallois}{Unix}     {NSD_DIR} = "/net/lv-s-nsd001/frparvi01_BUILDS/q_files/status";
$VARS2{Vancouver}{win32_x86}{NSD_DIR} = "\\\\cavanvf06\\nsd_status_a";
$VARS2{Vancouver}{Unix}     {NSD_DIR} = "/net/cavanvf06/vol/nsd_status_a";
$VARS2{Bangalore}{win32_x86}{NSD_DIR} = "\\\\gr-trigger-file.wdf.sap.corp\\trigger";
$VARS2{Bangalore}{Unix}     {NSD_DIR} = $^O eq "hpux" ? "/net/inblrnas01.pgdev.sap.corp/vol/status" : "/net/inblrnas01.pgdev.sap.corp/vol/status";
$VARS2{Walldorf}{win32_x86}{NSD_DIR} = "\\\\dewdfgrnas02.wdf.sap.corp\\trigger";
$VARS2{Walldorf}{Unix}     {NSD_DIR} = "/net/dewdfgrnas02.wdf.sap.corp/vol/nsvf1672a_GRS/grs_trigger";
$VARS2{Lacrosse}{win32_x86}{NSD_DIR} = "\\\\uslsefs03.pgdev.sap.corp\\status";
$VARS2{Lacrosse}{Unix}     {NSD_DIR} = "/net/uslsefs03.pgdev.sap.corp/vol/status";

$VARS2{Levallois}{win32_x86}{SMTP_SERVER} = "mailhost.product.businessobjects.com:26";
$VARS2{Levallois}{Unix}     {SMTP_SERVER} = "mailhost.product.businessobjects.com:26";
$VARS2{Vancouver}{win32_x86}{SMTP_SERVER} = "mail.sap.corp";
$VARS2{Vancouver}{Unix}     {SMTP_SERVER} = "mail.sap.corp";
$VARS2{Bangalore}{win32_x86}{SMTP_SERVER} = "mailhost.pgdev.sap.corp:26";
$VARS2{Bangalore}{Unix}     {SMTP_SERVER} = "mailhost.pgdev.sap.corp:26";
$VARS2{Walldorf}{win32_x86}{SMTP_SERVER} = "mailhost.pgdev.sap.corp";
$VARS2{Walldorf}{Unix}     {SMTP_SERVER} = "mailhost.pgdev.sap.corp";

#SOP
$VARS3{Bangalore}{win32_x86}{sop_dev}{IMPORT_DIR} = "\\\\build-drops-blr.pgdev.sap.corp\\dropzone\\sop_dev";
$VARS3{Bangalore}{Unix}     {sop_dev}{IMPORT_DIR} = "/net/build-drops-blr.pgdev.sap.corp/vol/dropzone/sop_dev";
$VARS3{Bangalore}{win32_x86}{sop_dev}{DROP_DIR} = "\\\\build-drops-blr.pgdev.sap.corp\\dropzone\\sop_dev";
$VARS3{Bangalore}{Unix}     {sop_dev}{DROP_DIR} = "/net/build-drops-blr.pgdev.sap.corp/vol/dropzone/sop_dev";

#LumiraEdge
$VARS3{Bangalore}{win32_x86}{lumiraedge_dev}{IMPORT_DIR} = "\\\\build-drops-blr.pgdev.sap.corp\\dropzone\\lumiraedge_dev";
$VARS3{Bangalore}{Unix}     {lumiraedge_dev}{IMPORT_DIR} = "/net/build-drops-blr.blrl.sap.corp/inblrvi01a_dropzone/q_files/lumiraedge_dev";
$VARS3{Bangalore}{win32_x86}{lumiraedge_dev}{DROP_DIR} = "\\\\build-drops-blr.pgdev.sap.corp\\dropzone\\lumiraedge_dev";
$VARS3{Bangalore}{Unix}     {lumiraedge_dev}{DROP_DIR} = "/net/build-drops-blr.blrl.sap.corp/inblrvi01a_dropzone/q_files/lumiraedge_dev";

$VARS3{Walldorf}{win32_x86}{lumiraedge_dev}{IMPORT_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\lumiraedge_dev";
$VARS3{Walldorf}{Unix}     {lumiraedge_dev}{IMPORT_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/lumiraedge_dev";
$VARS3{Walldorf}{win32_x86}{lumiraedge_dev}{DROP_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\lumiraedge_dev";
$VARS3{Walldorf}{Unix}     {lumiraedge_dev}{DROP_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/lumiraedge_dev";
$VARS3{Walldorf}{win32_x86}{lumiraedge_dev}{ASTEC_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\ASTEC";
$VARS3{Walldorf}{Unix}     {lumiraedge_dev}{ASTEC_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/ASTEC";

$VARS3{Vancouver}{win32_x86}{lumiraedge_dev}{IMPORT_DIR} = "\\\\build-drops-vc.van.sap.corp\\dropzone\\lumiraedge_dev";
$VARS3{Vancouver}{Unix}     {lumiraedge_dev}{IMPORT_DIR} = "/net/build-drops-vc.van.sap.corp/dropzone/lumiraedge_dev";
$VARS3{Vancouver}{win32_x86}{lumiraedge_dev}{DROP_DIR} = "\\\\build-drops-vc.van.sap.corp\\dropzone\\lumiraedge_dev";
$VARS3{Vancouver}{Unix}     {lumiraedge_dev}{DROP_DIR} = "/net/build-drops-vc.van.sap.corp/dropzone/lumiraedge_dev";
$VARS3{Vancouver}{win32_x86}{lumiraedge_dev}{ASTEC_DIR} = "\\\\build-drops-vc.van.sap.corp\\dropzone\\ASTEC";
$VARS3{Vancouver}{Unix}     {lumiraedge_dev}{ASTEC_DIR} = "/net/build-drops-vc.van.sap.corp/dropzone/ASTEC";

#LumiraEdge
$VARS3{Bangalore}{win32_x86}{lumiraedge_maint}{IMPORT_DIR} = "\\\\build-drops-blr.pgdev.sap.corp\\dropzone\\lumiraedge_maint";
#$VARS3{Bangalore}{Unix}     {lumiraedge_dev}{IMPORT_DIR} = "/net/build-drops-blr.blrl.sap.corp/inblrvi01a_dropzone/q_files/lumiraedge_maint";
$VARS3{Bangalore}{win32_x86}{lumiraedge_maint}{DROP_DIR} = "\\\\build-drops-blr.pgdev.sap.corp\\dropzone\\lumiraedge_maint";
#$VARS3{Bangalore}{Unix}     {lumiraedge_dev}{DROP_DIR} = "/net/build-drops-blr.blrl.sap.corp/inblrvi01a_dropzone/q_files/lumiraedge_maint";
$VARS3{Walldorf}{win32_x86}{lumiraedge_maint}{IMPORT_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\lumiraedge_maint";
$VARS3{Walldorf}{Unix}     {lumiraedge_maint}{IMPORT_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/lumiraedge_maint";
$VARS3{Walldorf}{win32_x86}{lumiraedge_maint}{DROP_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\lumiraedge_maint";
$VARS3{Walldorf}{Unix}     {lumiraedge_maint}{DROP_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/lumiraedge_maint";
$VARS3{Walldorf}{win32_x86}{lumiraedge_maint}{ASTEC_DIR} = "\\\\build-drops-wdf.wdf.sap.corp\\dropzone\\ASTEC";
$VARS3{Walldorf}{Unix}     {lumiraedge_maint}{ASTEC_DIR} = "/net/build-drops-wdf.wdf.sap.corp/dropzone/ASTEC";



$VARS3{Walldorf}{win32_x86}{sop_cor}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\sop_maint";
$VARS3{Walldorf}{win32_x86}{sop_cor}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\sop_maint";

$VARS3{Walldorf}{win32_x86}{sop_rel}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\sop_maint";
$VARS3{Walldorf}{win32_x86}{sop_rel}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\sop_maint";

$VARS3{Walldorf}{win32_x86}{sop_maint}{IMPORT_DIR} = "\\\\build-drops-wdf\\dropzone\\sop_maint";
$VARS3{Walldorf}{win32_x86}{sop_maint}{DROP_DIR} = "\\\\build-drops-wdf\\dropzone\\sop_maint";


# set environment variables according with SITE, PLATFORM and PROJECT
warn("ERROR: unknown '$ENV{PROJECT}' PROJECT environment variable") unless(exists($VARS3{$ENV{SITE}}{$PLATFORM}{$ENV{PROJECT}}));
$ENV{$Key} ||= $Value while(($Key, $Value) = each(%{$VARS3{$ENV{SITE}}{$PLATFORM}{$ENV{PROJECT}}}));
$ENV{$Key} ||= $Value while(($Key, $Value) = each(%{$VARS2{$ENV{SITE}}{$PLATFORM}}));

# DROP_DIR: output directory for binaries, packages and logs on central file server
$ENV{DROP_DIR}     ||= $ENV{IMPORT_DIR};
$ENV{DROP_NSD_DIR} ||= $ENV{DROP_DIR};
$ENV{ASTEC_DIR}     ||= "$ENV{DROP_DIR}/..";
$ENV{GLOBAL_REPLICATION_SERVER} ||= 'http://dewdfgrsig01.wdf.sap.corp';

$ENV{DITA_CONTAINER_DIR} ||= '\\\\derotvi0355/volume9$';
$ENV{CIS_HREF} = 'https://cis-dashboard.wdf.sap.corp';

sub getremotedropdir{
    my $remotesite = shift;
    my $remotedropdir;
    $remotedropdir ||= $Value while(($Key, $Value) = each(%{$VARS3{$remotesite}{$PLATFORM}{$ENV{PROJECT}}}));
    return $remotedropdir;
}

1;
