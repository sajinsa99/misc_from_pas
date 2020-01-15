##############################################################################
##### declare uses

# basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

# required for the script
use Getopt::Long;

use FindBin;
use lib $FindBin::Bin;

use File::Find;
use File::Path;
use File::Spec;
use File::Basename;



##############################################################################
##### declare vars

# obsoletes but cannot remove right now
use vars qw (
    $TP_SUN_JDK
    $TP_SUN_JDK_VERSION
    $nbInParallel
);

# system
use vars qw (
    $USER
    $NULL_DEVICE

);

# folders
use vars qw (
    $temp_dir
    $current_dir
);

# java related
use vars qw (
    $java_version
    $java_exist
    $java_extension
);

# for artifactimporter
use vars qw (
    $default_url_repo
    %artifacts_for_subpath
    $out_artifactimporter_log
    $SRC_DIR
    $OUTPUT_DIR
);

# options/parameters without variables listed above
use vars qw (
    $opt_help
    $mapping_file
    $param_mapping_files
    $param_TARGET_DIRS
    $TARGET_DIR
    $log_timestamp
    $log_artifact_list
    $opt_post_import
    $opt_no_clean
    $opt_just_clean
    $opt_untgz
    $opt_perms
);



##############################################################################
##### declare vars
sub extract_info_from_groovy($);
sub init_process();
sub run_artifact_importer();
sub post_import();
sub uncompress();
sub search_errors();
sub clean_ai_tmp();
sub display_usage($);



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "help|?"    =>\$opt_help,
    "p4jdk"     =>\$TP_SUN_JDK, # obsolete
    "jdkver=s"  =>\$TP_SUN_JDK_VERSION, # obsolete
    "np=s"      =>\$nbInParallel, # obsolete
    "f=s"       =>\$mapping_file,
    "mf=s"      =>\$param_mapping_files,
    "t=s"       =>\$TARGET_DIR,
    "mt=s"      =>\$param_TARGET_DIRS,
    "lst=s"     =>\$log_timestamp,
    "al=s"      =>\$log_artifact_list,
    "pi"        =>\$opt_post_import,
    "nc"        =>\$opt_no_clean,
    "jc"        =>\$opt_just_clean,
    "untgz=s"   =>\$opt_untgz,
    "perms=s"   =>\$opt_perms,
);



##############################################################################
##### init vars

if($opt_just_clean) { # set here to skip all next checks
    print "\njust clean\n";
    # create array for all groovy and target dirs
    my @list_mapping_files = split ',',$param_mapping_files;
    my @list_target_dirs   = split ',',$param_TARGET_DIRS;
    # get info from all groovy files
    foreach my $this_groovy_file (sort @list_mapping_files) {
        if( -e $this_groovy_file) {
            extract_info_from_groovy($this_groovy_file);
        }
        else {
            print "warning : $this_groovy_file not found\n";
        }
    }
    # cleans
    foreach my $path (keys %artifacts_for_subpath) {
        next if($path =~ /^no\s+subpath$/i);
        foreach my $this_target_dir (sort @list_target_dirs) {
            # get the 1st sub folder
            my @sub_paths = split '/',$path;
            if( -d "$this_target_dir/$sub_paths[0]" ) {
                print "clean $sub_paths[0]\n";
                system "rm -rf \"$this_target_dir/$sub_paths[0]\"";
            }
        }
    }
    exit 0;
}

# obsoletes but cannot be removed to not break all ini files
$TP_SUN_JDK = q{};
$TP_SUN_JDK_VERSION = q{};
$nbInParallel = 1;

# systems
if($^O eq "MSWin32")  {
    $USER = $ENV{USERNAME}
}
else {
    $USER = `whoami`;
    chomp $USER;
}
$NULL_DEVICE = ($^O eq "MSWin32") ? "nul" : "/dev/null" ;
$current_dir = $FindBin::Bin;
unless($temp_dir = $ENV{TEMP}) {
    die "ERROR: TEMP environment variable must be set";
}

# should be coming from Build.pl
$SRC_DIR     = $ENV{SRC_DIR};
$OUTPUT_DIR  = $ENV{OUTPUT_DIR};

# check folders exists
if( ! -e $SRC_DIR) {
    die "\n\nERROR : SRC_DIR $SRC_DIR not found\n\n";
}
if( ! -e $OUTPUT_DIR) {
    die "\n\nERROR : OUTPUT_DIR $OUTPUT_DIR not found\n\n";
}

# java managment part
# use 1st AI_JAVA_HOME environment variable set in ini file
$java_extension = ($^O eq "MSWin32") ? ".exe" : "";
if($ENV{AI_JAVA_HOME} && -e "$ENV{AI_JAVA_HOME}/bin/java$java_extension") {
    $ENV{PATH} = ($^O eq "MSWin32")
               ? "$ENV{AI_JAVA_HOME}/bin;$ENV{PATH}"
               : "$ENV{AI_JAVA_HOME}/bin:$ENV{PATH}"
               ;
    $ENV{JAVA_HOME} = $ENV{AI_JAVA_HOME};
}
else {
    # by default, use java found in path
    $java_exist = `which java`;
    chomp $java_exist;
    if( ! $java_exist) {
        # at least, use JAVA_HOME if set and exist
        if($ENV{JAVA_HOME} && -e "$ENV{JAVA_HOME}/bin/java$java_extension") {
            # add it in the path, hope java_home is good
            $ENV{PATH} = ($^O eq "MSWin32")
                       ? "$ENV{JAVA_HOME}/bin;$ENV{PATH}"
                       : "$ENV{JAVA_HOME}/bin:$ENV{PATH}"
                       ;
        }
        else {
            # the worst case scenario : no java found, neither JAVA_HOME
            print "\nERROR no java found in the machine\n";
            print "use at least :AI_JAVA_HOME,";
            print " or JAVA_HOME and check it exists\n";
            exit 1;
        }
    }
    else {
        # unset JAVA_HOME, sometimes JAVA_HOME is wrong on some build machines
        $ENV{JAVA_HOME} = "" if(defined $ENV{JAVA_HOME});
    }
}
# rexecute these commands after updating (or not) the PATH
$java_exist = `which java`;
chomp $java_exist;
my $java_path = dirname $java_exist;
chdir $java_path;
$java_version = `java -version 2>&1`;
chomp $java_version;
chdir $current_dir;

# variables for artifactimporter
# check if artifactimporter is dowloaded
$ENV{AI_HOME} ||= "$current_dir/artifactimporter";
if( ! -e "$ENV{AI_HOME}/bin" ) {
    display_usage("ERROR : $ENV{AI_HOME} not found");
}
# check TARGET_DIR
unless($TARGET_DIR) {
    my $msg = "ERROR : TARGET_DIR not set,"
            . " please use perl $0 -t=target"
            ;
    display_usage("\n$msg\n");
}
if( ! -e $TARGET_DIR) {
    mkpath $TARGET_DIR
        or die "ERROR : cannot mkpath $TARGET_DIR : $!\n";
}
# check mapping / groovy file
die "ERROR : no -f option for $0"        unless($mapping_file);
die "ERROR : $mapping_file not found"  if( ! -e $mapping_file);

# nexus repo
$default_url_repo  = "http://nexus.wdf.sap.corp:8081"
                   . "/nexus/content/repositories"
                   . "/3rd-party.releases.manual-uploads.hosted"
                   ;
$ENV{NEXUS_REPOS} ||= "--repo-url $default_url_repo";

# log file
$out_artifactimporter_log   = basename $mapping_file;
($out_artifactimporter_log) =~ s-\.groovy$--i;
$out_artifactimporter_log   = "ai_output_cmd_"
                            . $out_artifactimporter_log
                            ;

display_usage("") if($opt_help);



##############################################################################
##### MAIN

my $start = scalar localtime;

# display environment info
if($ENV{AI_JAVA_HOME}) {
    print "
AI_JAVA_HOME=$ENV{AI_JAVA_HOME}";
}
if($ENV{JAVA_HOME}) {
    print "
JAVA_HOME=$ENV{JAVA_HOME}";
}
print "
which java : $java_exist
java version :
$java_version

groovy file=$mapping_file
TARGET_DIR=$TARGET_DIR

start at $start

";

extract_info_from_groovy($mapping_file);

# display artiftacts info
print "\nlist of artifacts to import :\n";
foreach my $path (keys %artifacts_for_subpath) {
    print "\n[$path]\n";
    foreach my $this_file ( @{$artifacts_for_subpath{$path}} ) {
        my ($unzip,$artifact,$extention,$version,$classifier)
           = split ',',$this_file;
        my $file;
        $file  = "$artifact-$version";
        $file .= "-$classifier" if($classifier);
        $file .= ".$extention";
        $file .= "  ($unzip)"   if($unzip ne "none");
        print "\t$file\n";
    }
}
print "\n";

init_process();

# run artifatimporter
print "\nDownloads\n";
run_artifact_importer();
my $end_download = scalar localtime;
print "\nDownloads done at $end_download\n";

# post import
post_import();

# workaround due to some issues with artifactimporter
if($opt_untgz) {
    my @dirs = split ',',$opt_untgz;
    foreach my $dir (sort @dirs) {
        if ( -e "$TARGET_DIR/$dir") {
            find(\&uncompress,"$TARGET_DIR/$dir");
        }
        else {
            print "warning : $dir not found in $TARGET_DIR\n";
        }
    }
    chdir $current_dir;
}

# check log
search_errors();



##############################################################################
### internal functions

sub extract_info_from_groovy($) {
    my ($this_mapping_file) = @_ ;
    # get infos, no perl modules to scan groovy file
    if(open GROOVY,$this_mapping_file) {
        my $path;
        my $unzip         = "none";
        my $flag_SubPath  = 0;
        my $flag_UnZipTar = 0;
        while(<GROOVY>) {
            chomp;
            next unless($_);
            next if(/^\//); # skip lines started with comments
            # detect sub sections
            if(/subPath\s+\"(.+?)\"/i) {
                $path          = $1;
                $unzip         = "none";
                $flag_SubPath  = 1;
                $flag_UnZipTar = 0 ;
                next;
            }
            if( ! $path) {
                $path          = "no subpath";
            }
            if(/^\s+(unzip|untar)\s+\{/i) {
                $unzip = $1;
                $flag_UnZipTar = $flag_SubPath + 1;
                next;
            }
            if(/\}/) {
                if($flag_UnZipTar == 2) { # is subpath exist;
                    $flag_UnZipTar--;
                    next;
                }
                if($flag_UnZipTar < 2 ) { # no subPath
                    $path          = "no subpath";
                    $flag_SubPath  = 0 ;
                    $flag_UnZipTar = 0 ;
                    next;
                }
            }
            # store artifacts
            if(/artifactFile\s+\"(.+?)\"/i) {
                my ($group,$artifact,$file_type,$classifier,$version)
                    = split ':',$1
                    ;
                unless($version) {
                    $version = $classifier;
                    undef $classifier;
                }
                my $file;
                if($classifier) {
                    push @{$artifacts_for_subpath{$path}}
                        , "$unzip,$artifact,$file_type,$version,$classifier"
                        ;
                }
                else {
                    push @{$artifacts_for_subpath{$path}}
                        , "$unzip,$artifact,$file_type,$version"
                        ;
                }
                next;
            }
        }
        close GROOVY;
    }
}

sub init_process() {
    # cleans
    clean_ai_tmp();
    unless($opt_no_clean) {
        print "\nCleans\n";
        foreach my $path (keys %artifacts_for_subpath) {
            next if($path =~ /^no\s+subpath$/i);
            if( -d "$TARGET_DIR/$path" ) {
                if(($path eq "Build")
                    && (-e "$TARGET_DIR/Build/export/shared/contexts")) {
                # special case to not loose context.xml
                        if( -e "$TARGET_DIR/_Build") {
                            system "rm -rf \"$TARGET_DIR/_Build\"";
                        }
                        system "mv $TARGET_DIR/Build $TARGET_DIR/_Build";
                }
                else {
                    print  "clean $TARGET_DIR/$path\n";
                    system "rm -rf \"$TARGET_DIR/$path\"";
                }
            }
        }
        my $end_clean = scalar localtime;
        print "\nCleans done at $end_clean\n";
    }

    # create folders
    foreach my $path (keys %artifacts_for_subpath) {
        next if($path =~ /^no\s+subpath$/i);
        if( ! -e "$TARGET_DIR/$path") {
            mkpath "$TARGET_DIR/$path";
        }
    }
}

sub clean_ai_tmp() {
    # clean temporary files generated by artifactimport
    # under unix, it is in /tmp, probably hardcoded :(
    my $current_pid = $$;
    my $artifactimport_tmp_dir = ($^O eq "MSWin32")
                               ? $temp_dir
                               : "/tmp"
                               ;
    my $search_process;
    # search all importFromNexus.pl running on the build machine.
    # because cannot clean these files if another process is running
    if($^O eq "MSWin32") {
        $search_process = "WMIC path win32_process"
                        . " get Processid,Commandline"
                        . " | grep -i $0"
                        . " | grep -v grep"
                        . " | grep -v $current_pid"
                        ;
    }
    else { # else unix
        $search_process = "ps -eaf"
                        . " | grep -i $0"
                        . " | grep -v grep"
                        . " | grep -v $current_pid"
                        ;
    }
    $ENV{COLUMNS} = 128; # for unix
    my @other_script_running = `$search_process`;
    $ENV{COLUMNS} = "" if(defined $ENV{COLUMNS});
    if( ! @other_script_running) {
        if($^O eq "MSWin32") {
            if( -d $artifactimport_tmp_dir) {
                my $files_to_clean = "$artifactimport_tmp_dir/artifactimport*";
                print  "clean $files_to_clean\n";
                system "rm -rf $files_to_clean > $NULL_DEVICE 2>&1";
            }
        }
        else {
            my $LOCAL_TEMP = $ENV{TEMP} || "$ENV{HOME}/tmp";
            foreach my $tmpdir (qw($LOCAL_TEMP /tmp /var/tmp)) { # clean $TEMp, /tmp and /var/tmp for unix !!!
                if( -d "$tmpdir") {
                    print  "clean $tmpdir/artifactimport*\n";
                    system "rm -rf $tmpdir/artifactimport* > $NULL_DEVICE 2>&1";
                }
            }
        }
    }
    else {
        my $nb_scripts_running = @other_script_running;
        $nb_scripts_running = $nb_scripts_running + 10;
        # set sleep to let the 1st importFromNexus.pl make the clean
        print "please wait $nb_scripts_running seconds\n";
        sleep $nb_scripts_running;
    }
}

sub run_artifact_importer() {
    # clean logs
    if( -e "$ENV{OUTLOG_DIR}/Build/$out_artifactimporter_log.log") {
        unlink "$ENV{OUTLOG_DIR}/Build/$out_artifactimporter_log.log";
    }
    if($log_timestamp && -e $log_timestamp) {
        unlink $log_timestamp;
    }
    if($log_artifact_list && -e $log_artifact_list) {
        unlink $log_artifact_list;
    }
    # build cmommand line
    $ENV{AI_TARGET} ||= "deploy";
    my $AI_command = "$ENV{AI_HOME}/bin/artifactimporter $ENV{AI_TARGET} -f"
                   . " $mapping_file $ENV{NEXUS_REPOS}"
                   . " -C root.default=$TARGET_DIR"
                   ;
    if($log_timestamp) {
        $AI_command .= " --write-latest-snapshot-timestamp $log_timestamp ";
    }
    if($log_artifact_list) {
        $AI_command .= " --write-artifact-list $log_artifact_list ";
    }
    print "cmd = $AI_command\n";
    my $out_ai_log_file = "$ENV{OUTLOG_DIR}/Build/"
                        . "$out_artifactimporter_log.log"
                        ;
    system "$AI_command > $out_ai_log_file 2>&1";
}

sub post_import() {
    if((-e "$TARGET_DIR/_Build/export/shared/contexts")
        && (-e "$TARGET_DIR/Build")) {
            if( ! -e "$TARGET_DIR/Build/export/shared/contexts") {
                    mkpath "$TARGET_DIR/Build/export/shared/contexts";
                }
            my $contexts     = "$TARGET_DIR/_Build/export/shared/contexts";
            my $target_ctxts = "$TARGET_DIR/Build/export/shared/contexts";
            system "cp -rf $contexts/* $target_ctxts/";
            system "rm -rf \"$TARGET_DIR/_Build\"";
    }
    unless($opt_no_clean) {
        # to clean for the next run
        chdir $TARGET_DIR;
        foreach my $path (keys %artifacts_for_subpath) {
            next unless($path);
            if( -d "$TARGET_DIR/$path") {
                print "\nchmod -R +w, chown -R $USER $path\n";
                system "chown -R $USER \"$path\""; # for unknown reason, sometime it is not pblack
                system "chmod -R 777 \"$path\"";
            }
            else {
                print "warning :'$path' not found in $TARGET_DIR\n";
            }
        }
        my $end_chmod = scalar localtime;
        print "\nChmod and Chown done at $end_chmod\n";
    }
    if($opt_perms) {
        chdir $TARGET_DIR;
        my @folders = split ',',$opt_perms;
        foreach my $folder (sort @folders) {
            if( -d "$TARGET_DIR/$folder") {
                print "\nchmod -R +w, chown -R $USER $folder\n";
                system "chown -R $USER \"$folder\""; # for unknown reason, sometime it is not pblack
                system "chmod -R 777 \"$folder\"";
            }
            else {
                print "warning :'$folder' not found in $TARGET_DIR\n";
            }
        }
        my $end_chmod = scalar localtime;
        print "\nChmod and Chown done at $end_chmod\n";
    }
    if($opt_post_import) {
        print "\nPost Import\n";
        foreach my $path (keys %artifacts_for_subpath) {
            # as the path is different than we want,
            # calcul path from fetch
            my $version = basename $path;
            my $path2 = $path;
            ($path2) =~ s-\/$version$--i;
            my $artifact = basename $path2;
            foreach my $this_file ( @{$artifacts_for_subpath{$path}} ) {
                my ($unzip,$artifact,$extention,$version,$classifier)
                    = split ',',$this_file;
                next if($unzip ne "none"); # if unzip/untar, no rename
                my $file = "$artifact-$version";
                if($classifier) {
                    $file .= "-$classifier";
                }
                $file .= ".$extention";
                my $newFile = $artifact;
                if($classifier) {
                    $newFile .= "-$classifier";
                }
                $newFile .= ".$extention";
                if( -e "$TARGET_DIR/$path/$file") {
                    print  "rename $TARGET_DIR/$path/$file -> $TARGET_DIR/$path/$newFile\n";
                    rename "$TARGET_DIR/$path/$file","$TARGET_DIR/$path/$newFile";
                }
                else {
                    print "ERROR : $TARGET_DIR/$path/$file not found\n";
                }
            }
        }
        if(opendir OUTBINDIR,$TARGET_DIR) {
            while(defined(my $file = readdir OUTBINDIR)) {
                next if($file =~ /^\.\.?$/);
                next if( -d "$TARGET_DIR/$file");
                if( -f "$TARGET_DIR/$file") {
                    system "rm -f \"$TARGET_DIR/$file\"";
                }
            }
            closedir OUTBINDIR;
        }
        my $endPostImport = scalar localtime;
        print "\nPost Import done at $endPostImport\n";
    }
}

sub uncompress() {
    if($File::Find::name =~ /\.tar\.gz$/i) {
        print "found $File::Find::name\n";
        my $base_dir   = dirname  $File::Find::name;  # for chdir
        my $targz_name = basename $File::Find::name;  # for gzip command
        my ($tar_name) = $targz_name =~ /^(.+?)gz$/i; # for tar command
        # can support tar.gz or tgz extension
        ($tar_name) =~ s-\.$--;
        ($tar_name) =~ s-t$-tar-i; # if tgz
        chdir $base_dir;
        print  "gzip -df $targz_name\n";
        system "gzip -df $targz_name";
        if( -e "$base_dir/$tar_name") {
            print  "tar -xf $tar_name\n";
            system "tar -xf $tar_name";
            print  "rm -f   $tar_name\n";
            system "rm -f   $tar_name";
            my ($folder) = $base_dir =~ /^$TARGET_DIR\/(.+?)\//i;
            if($folder && -d "$TARGET_DIR/$folder") {
                chdir $TARGET_DIR;
                print "\nchmod -R +w, chown -R $USER $folder\n";
                system "chown -R $USER \"$folder\"";
                system "chmod -R 777   \"$folder\"";
            }
            return;
        }
    }
}

sub search_errors() {
    my $flag_error = 0;
    my $AI_log = "$ENV{OUTLOG_DIR}/Build"
               . "/$out_artifactimporter_log.log"
               ;
    my $pattern = qr/Could not find artifact|Could not transfer artifact|Permission denied/; # errors returned by ai
    if(open OUTLOG,$AI_log) {
        while(<OUTLOG>) {
            chomp;
            my $line = $_;
            if( ($line =~ /$pattern/i)
             && ($line =~ /java.lang.RuntimeException/i) ) {
                $line = "ERROR: $line";
                $flag_error = 1;
                print "$line\n";
            }
        }
        close OUTLOG;
    }
    my $end = scalar localtime;
    if($flag_error == 1) {
        print "\n\n";
        my $ai_log = "$ENV{OUTLOG_DIR}/Build"
                   . "/$out_artifactimporter_log.log"
                   ;
        print "Error(s) detected in $ai_log\n";
        print "\nend at $end\n\n";
        exit 1 ;
    }
    else {
        print "\nend at $end\n\n";
        exit 0;
    }
}

sub display_usage($) {
    my ($msg) = @_ ;
    if($msg) {
        print STDERR "
\tERROR:
\t======
$msg
";
    }
    print <<FIN_USAGE;

    Description : $0 can import artifact(s) from nexus, using artifactimporter java tool.
The following environment variables have to be set:
    AI_HOME
    NEXUS_REPOS
    SRC_DIR
    OUTPUT_DIR
- AI_HOME should be in $current_dir/artifactimporter
- NEXUS_REPOS has to be set, it contains the list of nexus repositories,
- AI_JAVA_HOME to set if you want/need to use your local/specific JAVA_HOME
  otherwise, it use JAVA_HOME, at least the java found in the path.
e.g.:
=====
NEXUS_REPOS=--repo-url url_1 --repo-url url_2
$0 is called in Build.pl throw the nexusimport section in ini file.

    Usage   : perl $0 [options]
    Example : perl $0 -h

 [options]
    -h|?    argument displays helpful information about builtin commands.
    -f      MANDATORY : mapping|groovy file,
            contains the list of artifacts to import
    -mf     list of multiple mapping|groovy files (only coupled with -jc)
    -t      MANDATORY : target directory
    -mt     list of multiple target dirs (only coupled with -jc)
    -lst    log file containing the timestamp of the list of artifacts imported
    -al     log file containing the list of artifacts imported
    -pi     rename files downloaded (remove version in file name)
    -nc     no clean
    -jc     just clean (need -mf and -mt)
    -untgz  list of folders in TARGET_DIR
            to find targ.gz or tgz files to uncompress
            this is workaround of artifactimporter issue
            eg:
            -untgz=a/b,c-d/e/f,gh/i/45
    -perms  fix chmod and chown on some selected folders
            (apply chown -R and chmod -R 777)

FIN_USAGE
    if($msg) {
        exit 1;
    }
    else {
        exit 0;
    }
}
