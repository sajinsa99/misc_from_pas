#############################################################################
##### declare uses

## basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

## for the script itself
use XML::DOM;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;



##############################################################################
##### declare functions
sub p4_login();
sub get_clientspec();
sub get_src_dir();
sub search_areas_and_deps();
sub getDeps($);
sub display_usage();



##############################################################################
##### declare vars

## for the script itself
use vars qw (
    $p4
    $CURRENT_DIR
    $P4_CLIENTSPEC
    @ClientSpecDescr
    $OBJECT_MODEL
    $SRC_DIR
    %all_areas
    @search_versions
    @skip_versions
);

# options / parameters without variables listed above
use vars qw (
    $opt_jl
    $opt_Model
    $opt_help
    $opt_skip_tps
    $param_ini_file
    $param_artifact
    $param_version
    $param_skip_version
);



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "i=s"       =>\$param_ini_file,
    "p4c=s"     =>\$P4_CLIENTSPEC,
    "src=s"     =>\$SRC_DIR,
    "a=s"       =>\$param_artifact,
    "v=s"       =>\$param_version,
    "jl"        =>\$opt_jl,
    "64!"       =>\$opt_Model,
    "help|h|?"  =>\$opt_help,
    "st"        =>\$opt_skip_tps,
    "sv=s"      =>\$param_skip_version,
);
display_usage() if($opt_help);



##############################################################################
##### init vars
$CURRENT_DIR = $FindBin::Bin;
$OBJECT_MODEL ||= $opt_Model ? "64" : "32" if(defined $opt_Model);
$ENV{OBJECT_MODEL} = $OBJECT_MODEL ||= $ENV{OBJECT_MODEL} || "32";

if($param_version) {
    @search_versions = split ',',$param_version;
}


if($param_skip_version) {
    @skip_versions = split ',',$param_skip_version;
}


##############################################################################
##### MAIN

print "\n==== START of $0 ====\n\n";

p4_login();
get_clientspec();

# 1 define SRC_DIR
unless($SRC_DIR && -e $SRC_DIR) {
    get_src_dir();
}
# 2 search all areas (with pom.xml)
search_areas_and_deps();

# 3 display
print "\nsearch ",
     ($param_artifact)? " '$param_artifact'":"",
     ($param_version) ? " version : $param_version":"",
     " in $SRC_DIR\n\n"
     ;
foreach my $area (sort keys %all_areas) {
    foreach my $avg (sort @{$all_areas{$area}}) {
        my ($pom_scm,$ArtifactId,$Version,$GroupId) = split ':',$avg;
        if($param_artifact) { # if search artifact
            if($param_artifact =~ /^$ArtifactId$/i) {
                if(grep /^$Version$/,@search_versions) { # if search also specific version
                     if($param_version =~ /^$Version/i) {
                        next if($opt_skip_tps && $area =~ /^tp\./);
                        next if($param_skip_version && (grep /^$Version$/,@skip_versions));
                        print "\t$area ($pom_scm)\n";
                        print "$ArtifactId/$Version\n\n" unless($opt_jl);
                     }
                }
                else { # otherwise display all versions of artifact found
                    next if($opt_skip_tps && $area =~ /^tp\./);
                    next if($param_skip_version && (grep /^$Version$/,@skip_versions));
                    print "\t$area ($pom_scm)\n";
                    print "$ArtifactId/$Version\n\n" unless($opt_jl);
                }
            }
        }
        else { # if no search artifact, display all artifacts dep
            if($param_version) { # if search all artifacts with specific version
                if(grep /^$Version$/,@search_versions) {
                    next if($opt_skip_tps && $area =~ /^tp\./);
                    next if($param_skip_version && (grep /^$Version$/,@skip_versions));
                    print "\t$area ($pom_scm)\n";
                    print "$ArtifactId/$Version\n\n" unless($opt_jl);
                }
            }
            else { # otherwise display everything
                next if($opt_skip_tps && $area =~ /^tp\./);
                next if($param_skip_version && (grep /^$Version$/,@skip_versions));
                print "\t$area ($pom_scm)\n";
                print "$ArtifactId/$Version\n\n" unless($opt_jl);
            }
        }
    }
}

print "\n==== END of $0 ====\n\n";
exit 0;


##############################################################################
### internal functions

sub p4_login() {
    require Perforce;
    $p4 = new Perforce;
    my $warning_level = 2;
    my $warning_message = $warning_level>0 ? "ERROR" : "WARNING";
    eval { $p4->Login("-s") };
    if($@) {
        if($warning_level < 2) {
            warn "$warning_message: User not logged : $@";
        }
        else {
            die "ERROR: User not logged : $@";
        }
        $p4 = undef;
    }
    elsif($p4->ErrorCount()) {
        if($warning_level < 2) {
            warn "$warning_message: User not logged : ",@{$p4->Errors()};
        }
        else {
            die "ERROR: User not logged : ",@{$p4->Errors()},"\n";
        }
        $p4 = undef;
    }
}

sub get_clientspec() {
    if( -e $param_ini_file ) {
        undef $P4_CLIENTSPEC;
        $P4_CLIENTSPEC = `perl $CURRENT_DIR/rebuild.pl -om=$OBJECT_MODEL -i=$param_ini_file -si=clientspec`;
        chomp $P4_CLIENTSPEC;
        $p4->SetOptions("-c \"$P4_CLIENTSPEC\"") if($p4);
        @ClientSpecDescr = $p4->client("-o")     if($p4);
    }
    else {
        print "\nERROR : $param_ini_file not found\n\n";
        exit 1;
    }
}

sub get_src_dir() {
    if( -e $param_ini_file ) {
        undef $SRC_DIR;
        $SRC_DIR = `perl $CURRENT_DIR/rebuild.pl -om=$OBJECT_MODEL -i=$param_ini_file -si=src_dir`;
        chomp $SRC_DIR;
        if($SRC_DIR) {
            if( ! -e $SRC_DIR) {
                print "\nERROR : $SRC_DIR not found\n\n";
                exit 1;
            }
        }
        else {
            print "\nERROR : $SRC_DIR not defined\n\n";
            exit 1;
        }
    }
    else {
        print "\nERROR : $param_ini_file not found\n\n";
        exit 1;
    }
}

sub search_areas_and_deps() {
    chdir $SRC_DIR or die "\nERROR : cannot chdir in $SRC_DIR";
    if(open LS1 , "ls */pom.xml |") {
        while(<LS1>) {
            chomp;
            s-\/pom\.xml$--i;
            getDeps($_); # search dep
        }
        close LS1;
    }
    # for tp multiversions
    if(open LS2 , "ls tp.*/*/pom.xml |") {
        while(<LS2>) {
            chomp;
            s-\/pom\.xml$--i;
            getDeps($_); # search dep
        }
        close LS2;
    }
}

sub get_scm_of_pom($) {
    my ($search_area) = @_ ;
    my @Views = @{$ClientSpecDescr[0]{View}}; # get views
    foreach my $view (sort @Views) {
        next if ($view =~ /\+\//);
        next if ($view =~ /\-\//);
        next unless($view);
        my ($this_scm) = $view =~ /^(.+?)\s+/;
        ($this_scm)    =~ s-\.\.\.$-pom.xml-;
        if($this_scm =~ /\/$search_area\//) {
            return $this_scm;
            last;
        }
    }
}


sub getDeps($) {
    my ($this_area) = @_;
    my $pom_scm = get_scm_of_pom("$this_area");
    my $XML_pom_file = "$SRC_DIR/$this_area/pom.xml";
    my $POM = XML::DOM::Parser->new()->parsefile($XML_pom_file);
    for my $DEPENDENCY (@{$POM->getElementsByTagName("dependency")}) {
        my $GroupId    = $DEPENDENCY->getElementsByTagName("groupId", 0)->item(0)->getFirstChild()->getData();
        next unless($GroupId =~ /^com.sap/i);
        my $ArtifactId = $DEPENDENCY->getElementsByTagName("artifactId", 0)->item(0)->getFirstChild()->getData();
        my $Version    = $DEPENDENCY->getElementsByTagName("version", 0)->item(0)->getFirstChild()->getData();
        ($Version) =~ s-\-SNAPSHOT$--i;
        push @{$all_areas{$this_area}} , "$pom_scm:$ArtifactId:$Version:$GroupId";
    }
    $POM->dispose();
}

sub display_usage() {
    print <<FIN_USAGE;

    Description :
'$0' searches all area(s)/component(s) dependent on what you search on all area(s)/component(s) in SRC_DIR

    Usage       :
perl $0 [options]

    options     :
-p4c  specify P4_VLIENTSPEC, will be overridden -i if -p4c & -i set
-src  specify SRC_DIR, will be overridden -i if -src & -i set
-i    ini file to determine SRC_DIR, will be overridden by -src if -src & -i set
-a    artifact (area/component) to search in all area(s)/component(s)
-v    search a list of versions of artifact to search
-jl   just list area(s)/component(s) found without any details
-st   to not display TPs
-sv   skip a list of specific versions
-h|?  argument displays helpful information about builtin commands.

    examples    :
perl $0 -i=contexts/aurora_pi_tp.ini
perl $0 -i=contexts/aurora_pi_tp.ini -a=tp.apache.poi //search tp.apache.poi on all area(s)/component(s) in SRC_DIR, whatever the version
perl $0 -i=contexts/aurora_pi_tp.ini -a=tp.apache.poi -v=3.0.9 //search tp.apache.poi with version 3.0.9 on all area(s)/component(s)  in SRC_DIR
perl $0 -i=contexts/aurora_pi_tp.ini -v=4.2 //search all area(s)/component(s) with version 4.2 on all area(s)/component(s) in SRC_DIR

FIN_USAGE
    exit 0;
}
