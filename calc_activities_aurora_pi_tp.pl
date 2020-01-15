#############################################################################
##### declare uses

## basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

# required for the script
use Sys::Hostname;
use File::Basename;
use Getopt::Long;
use FindBin;
use lib $FindBin::Bin;
use XML::DOM;



##############################################################################
##### abbreviations

# bld : build
# rev : rev
# prev : prev
# ctxt : context
# descr : description
# cl : changelist



##############################################################################
##### declare functions
sub get_prev_bld_rev();
sub calc_duration($$);
sub display_usage($);
sub parse_p4_client();
sub calcul_activities();
sub search_new_removed_tp($$);
sub get_fetch_level_from_ctxt($);
sub get_fetch_level_from_ctxt_for_scm($$);
sub remove_spaces($);
sub build_html_file($$);
sub get_full_name_for_p4user($);
sub get_email_for_p4user($);



##############################################################################
##### declare vars

# paths
use vars qw (
    $CURRENT_DIR
    $DROP_DIR
    $HTTP_DIR
    $CIS_DIR
);

# files
use vars qw (
    $ini_file
    $dat_file
    $first_ctxt_file
    $second_ctxt_file
);

# for the script itself
use vars qw (
    $script_start_time
    $p4_client
);

# basic vars for bld ctxt
use vars qw (
    $bld_name
    $PROJECT
    $bld_mode
    $PLATFORM
    $OBJECT_MODEL
    $os_family
);

# for the calculation
use vars qw (
    $prev_bld_rev
    $param_prev_bld_rev
    $current_bld_rev
    $full_bld_name_first_rev
    $full_bld_name_second_rev
    %files_in_cl
    %descr_for_cl
    $fetch_level_first_ctxt
    $fetch_level_second_ctxt
    %delta_scms
    $rebuild_cmd
);

# options / paramaeters without variable listed above
use vars qw (
    $opt_object_model
    $opt_no_export
    $opt_help
);



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "i=s"       =>\$ini_file,
    "c=s"       =>\$p4_client,
    "p=s"       =>\$param_prev_bld_rev,
    "v=s"       =>\$current_bld_rev,
    "noexp"     =>\$opt_no_export,
    "help|h|?"  =>\$opt_help,
);

if($opt_help) {
    display_usage("");
}

$ini_file           ||= "contexts/aurora_pi_tp.ini";
$param_prev_bld_rev ||= "greatest";

if( ! -e $ini_file) {
    display_usage("$ini_file not found");
}



##############################################################################
##### init vars
$CURRENT_DIR = $FindBin::Bin;

# define PLATFORM
$OBJECT_MODEL = $opt_object_model ? "64"
              : ($ENV{OBJECT_MODEL} || "32")
              ;

if($^O eq "MSWin32") {
    $PLATFORM = ($OBJECT_MODEL==64)
              ? "win64_x64"
              : "win32_x86"
              ;
}
else { # not windows
    die "ERROR: $0 run only on windows";
}
$os_family = "windows";

# define compile mode
$bld_mode ||= $ENV{BUILD_MODE} || "release";
if("debug"           =~ /^$bld_mode/i) {
    $bld_mode = "debug";
}
elsif("release"      =~ /^$bld_mode/i) {
    $bld_mode = "release";
}
elsif("releasedebug" =~ /^$bld_mode/i) {
    $bld_mode = "releasedebug";
}
elsif("rd"           =~ /^$bld_mode/i) {
    $bld_mode = "releasedebug";
}
else { # mode unknow
    my $msg = "ERROR: compilation mode"
            . "'$bld_mode' is unknown"
            . " [d.ebug"
            . "|r.elease"
            . "|releasedebug"
            . "|rd]"
            ;
    display_usage($msg);
}

# get cleintspec
$rebuild_cmd = "perl $CURRENT_DIR/rebuild.pl"
             . " -om=$OBJECT_MODEL"
             . " -m=$bld_mode"
             . " -i=$ini_file"
             ;
$p4_client ||=`$rebuild_cmd -si=clientspec`;
chomp $p4_client;

# ini
($ini_file)  =~ s-\\-\/-g;
$bld_name  ||=  `$rebuild_cmd -si=context`;
chomp $bld_name;
printf "\ncontext %s\n",$bld_name;

$DROP_DIR = `$rebuild_cmd -si=dropdir`;
chomp $DROP_DIR;
($DROP_DIR) =~ s-\\-\/-g; # transform to unix path, even if it is windows

# set project for Site.pm
$PROJECT = `$rebuild_cmd -si=project`;
chomp $PROJECT;
$ENV{PROJECT} = $PROJECT;


# get some environment variables needed
require Site;

$HTTP_DIR   = $ENV{HTTP_DIR}; # get fro Site.pm
($HTTP_DIR) =~ s-\\-\/-g; # transform to unix path, even if it is on windows

# calc bld revs
$prev_bld_rev  = get_prev_bld_rev();
unless($prev_bld_rev) {
    display_usage("no first rev");
}

$current_bld_rev ||= `$rebuild_cmd -si=revision`;
chomp $current_bld_rev;
unless($current_bld_rev) {
    display_usage("no second rev");
}

# need the full bld name to calcul the ctxt file names
$full_bld_name_first_rev  = sprintf "%05d",$prev_bld_rev;
$full_bld_name_first_rev  = "$bld_name"
                          . "_$full_bld_name_first_rev"
                          ;
$full_bld_name_second_rev = sprintf "%05d",$current_bld_rev;
$full_bld_name_second_rev = "$bld_name"
                          . "_$full_bld_name_second_rev"
                          ;

# set ctxtfile names
$first_ctxt_file = "$DROP_DIR/$bld_name/"
                 . "$prev_bld_rev/contexts/allmodes/files/"
                 . "$bld_name.context.xml"
                 ;
if( ! -e $first_ctxt_file) {
    $first_ctxt_file = "$HTTP_DIR/$bld_name/"
                     . "$full_bld_name_first_rev/"
                     . "$full_bld_name_first_rev"
                     . ".context.xml"
                     ;
    if( ! -e $first_ctxt_file) {
        display_usage("'$first_ctxt_file' not found");
    }
}
$second_ctxt_file = "$DROP_DIR/$bld_name/"
                  . "$current_bld_rev/contexts/allmodes/files/"
                  . "$bld_name.context.xml"
                  ;
if( ! -e $second_ctxt_file) {
    $second_ctxt_file = "$HTTP_DIR/$bld_name"
                      . "/$full_bld_name_second_rev/"
                      . "$full_bld_name_second_rev"
                      . ".context.xml"
                      ;
    if( ! -e $second_ctxt_file) {
        display_usage("'$second_ctxt_file' not found");
    }
}



##############################################################################
##### MAIN
printf "\nStart at %s\n",scalar localtime;
$script_start_time = time ;

print "\n\t$bld_name - $ini_file\n";
my $display = "Activities between"
            . " $full_bld_name_first_rev and"
            . " $full_bld_name_second_rev"
            ;
print "$display\n\n";

calcul_activities();

print "\n'$0' took : "
      , calc_duration($script_start_time,time)
      , "\n";

print "\nEND\n\n";
exit;



##############################################################################
### internal functions

sub get_prev_bld_rev() {
    my $bld_rev_found = "";
    if( ! $param_prev_bld_rev) {
        my $current_rev = `$rebuild_cmd -si=rev`;
        chomp $current_rev;
        $bld_rev_found = $current_rev - 1;
    }
    else { # if -p=previous build revision
        if( $param_prev_bld_rev eq "greatest") {
            if( ! -e "$DROP_DIR/$bld_name/greatest.xml") {
                my $warn_msg = "$DROP_DIR/$bld_name/greatest.xml"
                             . " not found"
                             ;
                display_usage($warn_msg);
            }
            my $grep_cmd = "grep \"version context\""
                         . " $DROP_DIR/$bld_name/greatest.xml"
                         . " | grep $bld_name"
                         ;
            my $current_greatest = `$grep_cmd`;
            chomp $current_greatest;
            ($bld_rev_found) = $current_greatest =~
                /\<version\s+context\=\"$bld_name\"\>(.+?)\<\/version\>/
                ;
            ($bld_rev_found) =~ s-^\d+\.\d+\.\d+\.--;
        }
        else { # if not -p=greatest
            $bld_rev_found = $param_prev_bld_rev;
        }
    }
    return $bld_rev_found;
}

sub parse_p4_client() {
    my @list_scms;
    print "\n activities: $p4_client\n";
    require Perforce;
    my $p4 = new Perforce;
    eval {
        $p4->Login("-s");
    };
    $p4->SetClient($p4_client);
    if( -e "$CURRENT_DIR/$p4_client.log") {
        system "rm -f $CURRENT_DIR/$p4_client.log";
    }
    $p4->client("-o"," > $CURRENT_DIR/$p4_client.log 2>&1");
    $p4->Final() if($p4);
    if(open CLIENT_SPEC,"$CURRENT_DIR/$p4_client.log") {
        my $flag_start_get_scms = 0;
        while(<CLIENT_SPEC>) {
            chomp;
            s-^\s+--; # remove all spaces at the begin of the line
            # skip unwanted lines
            next if(/^\+/); # skip + added in ini files
            next if(/^\-/); # skip - added in ini files
            s-\/\/--; # replace '//' by nothing for eaiser regexp
            if(/^View\:/) {
                $flag_start_get_scms = 1;
                next;
            }
            s/\s+\/\/.+?$//; # remove 2part of scm, need only 1st part
                             # eg //tp/toto/... //clientspec/toto/...,
                             # remove  //clientspec/toto
            if($flag_start_get_scms == 1) {
                # get only TPs and compilation.framework
                # and product/aurora
                next unless($_);
                next if(/^depot/i);
                next if(/^components/i);
                if(/^tp\/tp\.|^internal\/tp\.|^internal\/compilation\.framework|^product\/aurora/i) {
                    push @list_scms,"//$_";
                }
            }
        }
        close CLIENT_SPEC;
        push @list_scms,"//depot3/shared.tp.aurora/trunk/PI/...";
        push @list_scms,"//internal/commonrepo/trunk/PI/...";
    }
    else { # default clientspec
        @list_scms = qw(
            //tp/*/*/REL/...
            //internal/tp.*/*/REL/...
            //internal/compilation.framework/trunk/PI/export/...
            //product/aurora/trunk/PI/...
            //depot3/shared.tp.aurora/trunk/PI/...
            //internal/commonrepo/trunk/PI/...
            );
    }
    return @list_scms;
}

sub calcul_activities() {
    # 1 get fetch levels
    $fetch_level_first_ctxt
        ||= get_fetch_level_from_ctxt($first_ctxt_file);
    $fetch_level_second_ctxt
        ||= get_fetch_level_from_ctxt($second_ctxt_file);
    my $msg1 = "$full_bld_name_first_rev"
             . " fetch level  ="
             . "$fetch_level_first_ctxt"
             ;
    print "$msg1\n";
    my $msg2 = "$full_bld_name_second_rev"
             . " fetch level  ="
             . "$fetch_level_second_ctxt"
             ;
    print "$msg2\n";
    my @scms    = parse_p4_client();
    my $log_act = "$CURRENT_DIR/"
                . "$bld_name"
                ."_acts.log"
                ;
    if( -e $log_act) {
        system "rm -f $log_act";
    }
    # 2 search new or removed TP
    # no need to make a p4 diff in this case
    search_new_removed_tp(\@scms,$first_ctxt_file);
    # 3 diff between
    # fetch_level_first_ctxt and
    # fetch_level_second_ctxt
    # to obtain list of impacted files
    my $tmp_first  = $fetch_level_first_ctxt;
    my $tmp_second = $fetch_level_second_ctxt;
    foreach my $scm (sort @scms) {
        next if( grep /^$scm/i , @{$delta_scms{new}} );
        next if( grep /^$scm/i , @{$delta_scms{removed}} );
		$fetch_level_first_ctxt  = get_fetch_level_from_ctxt_for_scm($first_ctxt_file,$scm)  || $tmp_first;
		$fetch_level_second_ctxt = get_fetch_level_from_ctxt_for_scm($second_ctxt_file,$scm) || $tmp_second;
        my $cmdGrep = "p4 diff2 -q ${scm}$fetch_level_first_ctxt"
                    . " ${scm}$fetch_level_second_ctxt"
                    . " | grep -v \".context.xml#\" "
                    . " | grep -v \"export\/shared\/context\""
                    . " | grep -wv \"identical\""
                    . ">> $log_act 2>&1"
                    ;
        system "echo $cmdGrep";
        system $cmdGrep;
        open ACTLOG,">>$log_act";
            print ACTLOG "\n";
        close ACTLOG;
    }
    # 4 filter list of impacted files
    if(open LOG_ACTIVITIES,$log_act) {
        my $log_impacted_files
            = "$CURRENT_DIR/"
            . "$bld_name"
            . "_impacted_files"
            . ".log"
            ;
        if( -e $log_impacted_files) {
            system "rm -f $log_impacted_files";
        }
        open OUT_IMPACTED_FILES,">$log_impacted_files";
        while(<LOG_ACTIVITIES>) {
            if(/^\=\=\=\=\s+/) {
                print OUT_IMPACTED_FILES ;
            }
        }
        close OUT_IMPACTED_FILES;
        close LOG_ACTIVITIES;
    }
    # 5 foreach all files found, search activities
    print "\n1 foreach all files found, search activities\n";
    my %Acts;
    if(open LOG_IMPACTED,$log_act) {
        while(<LOG_IMPACTED>) {
            chomp;
            s/^\s+$//; # remove spaces at the begining of the line
            # skip unwanted lines
            next if(/No file\(s\) to diff\./);
            next if(/^p4 diff2/);
            # get file
            (my $file) = $_ =~ /\s+\-\s+\/\/(.+?)\s+/;
            next unless($file);
            # get changelist
            my $cl = `p4 fstat \"//$file\" | grep headChange`;
            chomp $cl;
            # get cl ID
            (my $cl_ID) = $cl =~ /\s+(\d+)$/;
            next unless($cl_ID);
            unless( grep /^$file$/ ,
                    @{$files_in_cl{$cl_ID}} ) {
                        # ensure not already added
                        push @{$files_in_cl{$cl_ID}},$file;
            }
        }
        close LOG_IMPACTED;
    }
    # 6 foreach activities found, search descriptions
    # p4 describe -s
    print "2 foreach activities found, search descriptions\n";
    foreach my $cl (sort {$b <=> $a} keys %files_in_cl) {
        next unless($cl);
        print "$cl\n";
        my $cl_ID = remove_spaces($cl);
        print "\n\tcl: $cl_ID \n";
        if(open DESCRIBE_CHANGELIST,"p4 describe -s $cl_ID |") {
            my ($user,$date,$task,$summary) = "";
            while(<DESCRIBE_CHANGELIST>) {
                chomp;
                s/^\s+$//; # remove lines with spaces only
                next unless($_);
                s/^\s+//; # remove spaces at the begining of the line
                if(/^Change\s+$cl_ID\s+by\s+(.+?)\@(.+?)\s+on\s+(.+?)$/i) {
                    $user = remove_spaces($1);
                    $date = remove_spaces($3);
                    print "user:$user\n";
                    print "date:$date\n";
                }
                if(/^Summary\:\s+(.+?)$/i) {
                    $summary = remove_spaces($1);
                    print "Summary: $summary\n"
                }
                if(/^Task\:\s+(.+?)$/i) {
                    if($1) {
                        $task = remove_spaces($1);
                        print "Task: $task\n";
                    }
                    else { # no task found
                        $task = "";
                    }
                }
            }
            close DESCRIBE_CHANGELIST;
            # to have no empty value :
            $user    ||= " ";
            $date    ||= " ";
            $task    ||= " ";
            $summary ||= " ";
            $descr_for_cl{$cl_ID}
                = "\"$user\" "
                . " + \"$date\""
                . " + \"$task\""
                . " + \"$summary\""
                ;
        }
        print "Affected files:\n";
        foreach my $file (sort @{$files_in_cl{$cl_ID}} ) {
            print "//$file\n";
        }
        print "\n";
    }
    print "\n";
    # 7 create csv file for the mail
    my $csv_file = "$CURRENT_DIR/"
                 . "$bld_name"
                 . "_activities.csv"
                 ;
    open CSV,">$csv_file"
        or die "ERROR: cannot create $csv_file: $!";
    print CSV "\"cl\";\"user\";\"date\";\"ADAPT\";\"Summary\"\n";
    foreach my $cl_ID (sort keys %descr_for_cl) {
        my ($user,$date,$FR,$summary)
           = $descr_for_cl{$cl_ID}
           =~ /^\"(.+?)\"\s+\+\s+\"(.+?)\"\s+\+\s+\"(.+?)\"\s+\+\s+\"(.+?)\"$/
           ;
        print CSV "\"$cl_ID\";\"$user\";\"$date\";\"$FR\";\"$summary\"\n";
    }
    close CSV;
    # create html fiel to have a quick view of activities
    build_html_file($fetch_level_first_ctxt,$fetch_level_second_ctxt);
    # copy html & cv files on dropzone
    unless($opt_no_export) {
        if( -d "$DROP_DIR/$bld_name") {
            if( -e $csv_file) {
                system "cp -vpf $csv_file $DROP_DIR/$bld_name/";
            }
            my $html_file = "$CURRENT_DIR/"
                          . "$bld_name"
                          . "_activities.html"
                          ;
            if( -e $html_file) {
                system "cp -vpf $html_file $DROP_DIR/$bld_name/";
            }
        }
    }
}

sub search_new_removed_tp($$) {
    my ($latest_scms,$base_ctxt) = @_ ;
    # get the basic reference
    my $XML = XML::DOM::Parser->new()->parsefile($base_ctxt);
    my @base_scms;
    for my $SYNC (@{$XML->getElementsByTagName("fetch")}) {
        my $File = $SYNC->getFirstChild()->getData();
        next if(($File =~ /^\/\/depot/i) && !($File =~ /\/shared.tp.aurora\//i));
        next if($File =~ /^\/\/components/i);
        next if($File =~ /^\+/);
        next if($File =~ /^\-/);
        if($File =~ /shared.tp.aurora|tp\/tp\.|internal\/tp\.|internal\/compilation\.framework|product\/aurora|commonrepo/i) {
            push @base_scms,$File;
        }
    }
    $XML->dispose();
    # search new
    foreach my $latest_scm (sort @$latest_scms) {
        my $found_scm = 0;
        if(grep /^$latest_scm$/ , @base_scms) {
                $found_scm = 1;
        }
        if($found_scm == 0) { # new scm
            print "$latest_scm is new\n";
            push @{$delta_scms{new}},$latest_scm;
            $found_scm = 0;
        }
    }
    # search removed
    foreach my $base_scm (sort @base_scms) {
        my $found_scm = 0;
        if(grep /^$base_scm$/ , @$latest_scms) {
            $found_scm = 1;
        }
        if($found_scm == 0) { # removed scm
            print "$base_scm is removed\n";
            push @{$delta_scms{removed}},$base_scm;
            $found_scm = 0;
        }
    }
}

sub build_html_file($$) {
    my ($fetch_level_first_ctxt,$fetch_level_second_ctxt) = @_ ;
    if(open HTML,">$CURRENT_DIR/${bld_name}_activities.html") {
        print HTML "
<!DOCTYPE html
    PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\"
     \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">
<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"en-US\" xml:lang=\"en-US\">
<head>
<title>Activities $full_bld_name_second_rev</title>
<meta http-equiv=\"Content-Type\" content=\"text/html; charset=iso-8859-1\" />

<style type=\"text/css\">
table.sample {
    border-width: 1px;
    border-spacing: 2px;
    border-style: outset;
    border-color: black;
    border-collapse: collapse;
    background-color: white;
    position: absolute;
    left: 75px;
}
table.sample tr {
    border-width: 1px;
    padding: 5px;
    border-style: inset;
    border-color: black;
    background-color: white;
    -moz-border-radius: 0px 0px 0px 0px;
}
table.sample td {
    border-width: 1px;
    padding: 5px;
    border-style: inset;
    border-color: black;
    background-color: white;
    -moz-border-radius: 0px 0px 0px 0px;
}
table.sample th {
    border-width: 1px;
    padding: 5px;
    border-style: inset;
    border-color: black;
    background-color: #F0F0F0;
    -moz-border-radius: 0px 0px 0px 0px;
}
</style>

</head>

<body>

<br/>
<center>
    <h1>$full_bld_name_second_rev Activities</h1><br/><br/>
    <table border=\"0\">
        <tr align=\"left\"><td>current greatest</td><td> : </td><td>$full_bld_name_first_rev</td><td>fetch level</td><td> = </td><td>$fetch_level_first_ctxt</td></tr>
        <tr align=\"left\"><td>candidate greatest</td><td> : </td><td>$full_bld_name_second_rev</td><td>fetch level</td><td> = </td><td>$fetch_level_second_ctxt</td></tr>
    </table>
</center>
<br/>
<br/>
<br/>
<br/>
<br/>
<table class=\"sample\">
    <tr><th>Changelist</th><th>Submitter</th><th>Full Name</th><th>Email</th><th>Date</th><th>ADAPT/Jira/CWB</th><th>P4 Summary</th></tr>
";

    foreach my $cl_ID (sort keys %descr_for_cl) {
        my ($user,$date,$fix_request,$summary)
            = $descr_for_cl{$cl_ID}
            =~ /^\"(.+?)\"\s+\+\s+\"(.+?)\"\s+\+\s+\"(.+?)\"\s+\+\s+\"(.+?)\"$/
            ;
        my $p4_FullName = get_full_name_for_p4user($user);
        my $p4_email    = get_email_for_p4user($user);
        my $tr_line = "    <tr>"
                    . "<td>$cl_ID</td>"
                    . "<td>$user</td>"
                    . "<td>$p4_FullName</td>"
                    . "<td><a href=\"mailto:$p4_email\">$p4_email</a></td>"
                    . "<td>$date</td>"
                    . "<td>$fix_request</td>"
                    . "<td>$summary</td>"
                    . "</tr>"
                    ;
        print HTML "$tr_line\n";
        print HTML "    <tr><td colspan=\"7\">";
        foreach my $scm_file (sort @{$files_in_cl{$cl_ID}} ) {
            print HTML "//$scm_file<br/>\n";
        }
        print HTML "    </td></tr>\n";
    }
        if(scalar @{$delta_scms{new}} > 0) {
            print HTML "    <tr><th colspan=\"7\">added :</th></tr>\n";
            foreach my $new_scm (sort @{$delta_scms{new}} ) {
                print HTML "<tr><td colspan=\"7\">$new_scm</td></tr>\n";
            }
        }
        if(scalar @{$delta_scms{removed}} > 0) {
            print HTML "    <tr><th colspan=\"7\">removed :</th></tr>\n";
            foreach my $scm_removed (sort @{$delta_scms{removed}} ) {
                print HTML "<tr><td colspan=\"7\">$scm_removed</td></tr>\n";
            }
        }
        print HTML "</table>

<br/>
<br/>
<br/>

</body>
</html>
";
        close HTML;
    }
}

sub get_fetch_level_from_ctxt($) {
    my ($this_ctxt) = @_ ;
    my $fetch_level_found;
    if(open CONTEXT,$this_ctxt) {
        while(<CONTEXT>) {
            chomp;
            s-^\s+--;
            if(/\/\/tp\/tp.infozip\/5.50\/REL/) { # i use this tp always used
                ($fetch_level_found) = $_
                                     =~ /^\<fetch revision\=\"(.+?)\"\s+/
                                     ;
                last;
            }
        }
        close CONTEXT;
    }
    return $fetch_level_found;
}

sub get_fetch_level_from_ctxt_for_scm($$) {
    my ($this_ctxt,$this_scm) = @_ ;
    my $fetch_level_found;
    my $XML_file = "$this_ctxt";
    my $ctxt = XML::DOM::Parser->new()->parsefile($XML_file);
    for my $FETCH_LINE (reverse(@{$ctxt->getElementsByTagName("fetch")})) {
		my($DepotSource, $Revision) = ($FETCH_LINE->getFirstChild()->getData(), $FETCH_LINE->getAttribute("revision"));
		if($DepotSource =~ /$this_scm/) {
			$fetch_level_found = $Revision;
			last;
		}
    }
    $ctxt->dispose();
    return $fetch_level_found;
}

sub remove_spaces($) {
    (my $variable) = @_ ;
    ($variable) =~ s-^\s+--;
    ($variable) =~ s-\s+$--;
    return $variable;
}

sub calc_duration($$) {

    my $Diff = $_[1] - $_[0] ;
    my $ss = $Diff % 60 ;
    my $mm = (($Diff-$ss)/60)%60 ;
    my $hh = ($Diff-$mm*60-$ss)/3600 ;
    sprintf "%02d:%02d:%02d",$hh,$mm,$ss;
}

sub get_full_name_for_p4user($) {
    (my $this_p4user) = @_ ;
    my $p4cmd = `p4 user -o $this_p4user |grep -i FullName | grep -v \#`;
    chomp $p4cmd;
    (my $full_name) = $p4cmd =~ /^FullName\:\s+(.+?)$/i;
    #print "$full_name\n";
    return $full_name;
}


sub get_email_for_p4user($) {
    (my $this_p4user) = @_ ;
    my $p4cmd = `p4 user -o $this_p4user |grep -i Email | grep -v \#`;
    chomp $p4cmd;
    (my $email) = $p4cmd =~ /^Email\:\s+(.+?)$/i;
    #print "$email\n";
    return $email;
}

####################
sub display_usage($) {
    my ($msg) = @_ ;
    if($msg) {
        print "\n";
        print "\tERROR:\n";
        print "\t======\n";
        print "$msg\n";
        print "\n";
    }
    print <<FIN_USAGE;

    Description :
'$0' calcul activities between 2 pi_tp blds.

    Usage       :
perl $0 [options]

    options     :
-i  ini file [MANDATORY]
-p  prev bld
    by default, version=`cat version.txt` - 1
    could be like -p=greatest
-v  by default, get version in version.txt
-c  choose a specific Perforce clientspec
-m  bld mode (release|debug|releasedebug|rd), by default, -m=r
-h|?    argument displays helpful information about builtin commands.

    examples    :
perl $0
perl $0 -i=contexts/aurora_pi_tp.ini
perl $0 -i=contexts/aurora_pi_tp.ini -p=200
perl $0 -i=contexts/aurora_pi_tp.ini -p=200 -v=202
perl $0 -i=contexts/aurora_pi_tp.ini -p=greatest -v=202

FIN_USAGE
    exit 1     if($msg);
    exit 0 unless($msg);
}
