#############################################################################
##### declare uses

## basics to ensure good quality and get good messages in runtime.
use strict;
use warnings;
use diagnostics;

# required for the script
use Getopt::Long;
use File::Basename;



##############################################################################
##### declare vars
use vars qw (
    @QSets
    $initial_ini_file
    $final_ini_file
    $just_display_new_ini_file
    $opt_help
);



##############################################################################
##### declare functions
sub display_usage();



##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
    "help|?"    =>\$opt_help,
    "i=s"       =>\$initial_ini_file,
    "f=s"       =>\$final_ini_file,
    "qset=s@"   =>\@QSets,
    "jdnif"     =>\$just_display_new_ini_file,
);
&display_usage() if($opt_help);



##############################################################################
##### MAIN
if( -e $initial_ini_file) {
    if( ! @QSets) {
        print "\n\nERROR : no qset, use $0 -q=VARIABLE_NAME:VALUE -q=...\n\n";
        exit 1;
    }
    ($initial_ini_file) =~ s-\\-\/-g;
    # base_dir required to store the new ini file
    my $base_dir  = dirname  $initial_ini_file;
    # filename required to be incuded in the new ini file
    my $file_name = basename $initial_ini_file;
    if($final_ini_file) {
        my $full_final_ini_file = "$base_dir/$final_ini_file";
        open FINAL_INI , ">$full_final_ini_file"
            or die "\n\nERROR : cannot create $full_final_ini_file :$!\n\n";
                print FINAL_INI "\#include $file_name\n";
                print FINAL_INI "\n";
                print FINAL_INI "[environment]\n";
                foreach (@QSets) {
                    my ($variable_name , $value) = /^(.+?):(.*)$/;
                    print FINAL_INI "$variable_name=$value\n";
                }
                print FINAL_INI "\n";
        close FINAL_INI;
        if($just_display_new_ini_file) {
            # could be interresting for automation
            print "$full_final_ini_file";
        }
        else { # display result with content
            print "\nini file available here : $full_final_ini_file\n";
            print "Content :\n";
            print "____________________\n";
            system "cat $full_final_ini_file";
            print "____________________\n";
            print "Now, you can use perl Build.pl -i=$full_final_ini_file\n";
            print "end of $0\n";
        }
        exit 0;
    }
    else {
        die "\n\nRROR : no final ini file, use perl $0 -f=your_ini\n\n";
    }
}
else {
    die "\n\nERROR : $initial_ini_file not found.\n\n";
}
exit 0;



##############################################################################
### internal functions
sub display_usage() {
    print <<FIN_USAGE;

    Description :
$0 generete a new ini file, pending on the list of -Q(Sets) required.
$0 is interresting only if QSets are required and instead of launch manually,
with a list of QSets you have to search, or skip to have a long command line.

    Usage       :
perl $0 [options]

    options     :
-i          : MANDATORY : initial ini file name
-f          : MANDATORY : final ini file name, will be saved in the same
              location than the initial ini file.
-Q(Sets)    : MANDATORY : list environment variables required,
              same usage than Build.pl
-jdnif      : just diplay the final ini file name,
              otherwise, it display also the content.

FIN_USAGE
    exit 0;
}
