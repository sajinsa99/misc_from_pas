#############################################################################
##### declare uses

## basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

# required for the script
use Getopt::Long;

use File::Path;



##############################################################################
##### declare vars

# paths
use vars qw (
    $cbt_path
    $mwf_tools_path
);

# for rebuild
use vars qw (
    $rebuild_cmd
    $ini_file
    $BUILD_MODE
    $OBJECT_MODEL
);

# for the script itself
use vars qw (
    $mwf_touch_perl_script
    $rebuild_cmd
    @list_areas
    @list_langs
    @list_file_types
);

# vars like Build.pl
use vars qw (
    $SRC_DIR
    $OUTLOG_DIR
);

# options / paramaeters without variable listed above
use vars qw (
    $opt_help
    $opt_object_model
    $param_areas
    $param_langs
    $param_file_types
);



##############################################################################
##### declare functions
sub display_usage();
sub start_script();
sub end_script();



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "a=s"       =>\$param_areas,
    "ft=s"      =>\$param_file_types,
    "help|?"    =>\$opt_help,
    "ini=s"     =>\$ini_file,
    "lg=s"      =>\$param_langs,
    "m=s"       =>\$BUILD_MODE,
    "o=s"       =>\$OUTLOG_DIR,
    "src=s"     =>\$SRC_DIR,
    '64!'       =>\$opt_object_model,
);
&display_usage() if($opt_help);
unless($ini_file) {
    die "\nERROR : -i missed, this is mandatory\n";
}



##############################################################################
##### init vars
# paths
$cbt_path = "c:/core.build.tools/export/shared";
$ENV{TOUCH1998} ||= "c:/MWF_Automation/mwf/export/xliff_tools/touch1998.pl";
$mwf_tools_path = $ENV{TOUCH1998};
if( ! -e $mwf_tools_path) {
    if( -e "c:/MWF_Automation/mwf/export/xliff_tools/touch1998.pl") {
        $mwf_tools_path = "c:/MWF_Automation/mwf/export/xliff_tools";
    }
    elsif( -e "$cbt_path/xliff_tools/touch1998.pl") {
        $mwf_tools_path = "$cbt_path/xliff_tools";
    }
    else {
        print <<FIN_ERR_MISSING_TOUCH1998;

ERROR : touch1998.pl not found in:
in environment variable TOUCH1998=$ENV{TOUCH1998}
or in
c:/MWF_Automation/mwf/export/xliff_tools/
or in
$cbt_path/xliff_tools/

FIN_ERR_MISSING_TOUCH1998
        exit 1; # exit as error
    }
}
if($mwf_tools_path =~ /touch1998\.pl$/i) {
    $mwf_touch_perl_script = "$mwf_tools_path";
}
else {
    $mwf_touch_perl_script = "$mwf_tools_path/touch1998.pl";
}



# set for rebuild.pl
$OBJECT_MODEL = $opt_object_model ? "64" : "32";

$BUILD_MODE ||= $ENV{BUILD_MODE} || "release";
if("debug"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="debug";
}
elsif("release"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="release";
}
elsif("releasedebug"=~/^$BUILD_MODE/i) {
    $BUILD_MODE="releasedebug";
}
else {
    my $msg_error = "compilation mode '$BUILD_MODE' is unknown,"
                  . " available values : [d.ebug|r.elease|releasedebug]"
                  ;
    print "\nERROR : $msg_error\n\n";
    exit 1;
}
$rebuild_cmd  = "perl $cbt_path/rebuild.pl -m=$BUILD_MODE -i=$ini_file";
$rebuild_cmd .= " -64" if($opt_object_model);

# get infos from rebuild.pl
$SRC_DIR ||= $ENV{SRC_DIR};
if( ! $SRC_DIR) {
    $SRC_DIR = `$rebuild_cmd -si=src_dir`;
    chomp $SRC_DIR;
}
if( ! -e $SRC_DIR) {
    print "\nERROR : $SRC_DIR not found\n\n";
    exit 1;
}
($SRC_DIR) =~ s-\\-\/-g; # prefer to transform as unix path
$OUTLOG_DIR ||= $ENV{OUTLOG_DIR};
if( ! $OUTLOG_DIR) {
    $OUTLOG_DIR = `$rebuild_cmd -si=logdir`;
    chomp $OUTLOG_DIR;
}
($OUTLOG_DIR) =~ s-\\-\/-g; # prefer to transform as unix path
if( ! -e $OUTLOG_DIR) {
    mkpath $OUTLOG_DIR or die "\nERROR : cannot mkpath $OUTLOG_DIR : $!\n\n";
}

# set areas, langs and file types
if($param_areas) {
    @list_areas = split ',',$param_areas;
}
else {
    my $areas = `$rebuild_cmd -si=areas`;
    chomp $areas;
    @list_areas = split ' ',$areas;
}

if($param_langs) {
    @list_langs = split ',',$param_langs;
}
else {
    my $core_langs = `$rebuild_cmd -si=envvars | grep -w CORELANGLIST`;
    chomp $core_langs;
    my $extra_langs = `$rebuild_cmd -si=envvars | grep -w EXTRALANGLIST`;
    chomp $extra_langs;
    my $langs = "$core_langs $extra_langs";
    @list_areas = split ' ',$langs;
}

if($param_file_types) {
    @list_file_types = split ',',$param_file_types;
}
else {
    @list_file_types = qw(xliff properties);
}



##############################################################################
##### MAIN

&start_script();

foreach my $area (@list_areas) {
    my $area_dir = "$SRC_DIR/$area";
    ($area_dir) =~ s-\\-\/-g; # trasnform to unix paths
    if( ! -e $area_dir) {
        print "$area_dir not found\n";
        next;
    }
    print "\n$area\n";
    foreach my $file_type (@list_file_types) {
        print "\t$file_type\n";
        foreach my $lang (@list_langs) {
            print "\t\t$lang\n";
            my $cmd = "perl $mwf_touch_perl_script"
                    . " $area_dir $file_type $lang"
                    ;
            mkpath "$OUTLOG_DIR/$area" if( ! -e "$OUTLOG_DIR/$area");
            my $log_file = "$OUTLOG_DIR/$area/touch1998_"
                         . "$file_type"
                         . "_$lang.log"
                         ;
            system "$cmd > $log_file 2>&1";
            print "  done, see in $log_file\n\n";
            system "cat $log_file";
            print "\n";
        }
        print "\n";
    }
}

&end_script();



##############################################################################
### my functions

#   "help|?"    =>\$opt_help,
#   "ini=s"         =>\$Config,
#   "a=s"           =>\$param_areas,
#   "lg=s"          =>\$param_langs,
#   "ft=s"          =>\$param_file_types,
#   "src=s"         =>\$optSRC_DIR,
#   "o=s"           =>\$optOUTLOG_DIR,

sub display_usage() {
    print <<FIN_USAGE;

    Usage   : perl $0 [options]
    Example : perl $0 -h

$0 read ini file to get areas, langs, SRC_DIR, OUTLOG_DIR and
call the perl script touch1998.pl
touch1998.pl, by default is in c:/MWF_Automation/mwf/export/xliff_tools
and at least, in c:/core.build.tools/export/shared/xliff_tools.
But you can specify yours, using environment variable TOUCH1998.
e.g.: TOUCH1998=c:/my_scripts/touch1998.pl


[options]
    -h|?    argument displays helpful information about builtin commands.
    -i      !!! MANDATORY !!! choose an in file, there is NO default value
    -a      choose a list areas, separated with ','
            eg.: -a=WebI,DSL
    -lg     choose a list langs, separated with ','
            eg.: -a=en,fr,ja
            by default $0 set langs:
            dev + CORELANGLIST + EXTRALANGLIST (from ini file)
    -ft     choose a list of file type, separated with ','
            eg.: -a=xliff
            by default -ft=xliff,properties
    -src    specify a specific SRC_DIR
            by default, $0 calculate SRC_DIR from ini file
    -o      specify a specific OUTLOG_DIR
            (only used for redirect touch1998.pl output
            in \$OUTLOG_DIR/\$AREA/touch1998_\$fileType_\$lang.log)
            by default, $0 calculate OUTLOG_DIR from ini file
    -m      build mode, by default -m=release
    -64     for 64B, but should not.

FIN_USAGE
    exit;
}


sub start_script() {
    my $date_start = scalar localtime;
    print "\nSTART of '$0' at $date_start\n";
    print  "#" x length "START of '$0' at $date_start","\n";
    print "\n";
}

sub end_script() {
    print "\n\n";
    my $date_end = scalar localtime;
    print  "#" x length "END of '$0' at $date_end","\n";
    print "END of '$0' at $date_end\n";
    exit;
}
