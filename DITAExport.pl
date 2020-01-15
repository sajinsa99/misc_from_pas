#!/usr/bin/perl -w

use File::Copy;

##############
# Parameters #
##############

die("ERROR: PACKAGES_DIR environment variable must be set") unless($ENV{PACKAGES_DIR});
die("ERROR: IMPORT_DIR environment variable must be set") unless($ENV{IMPORT_DIR});
die("ERROR: DROP_DIR environment variable must be set") unless($ENV{DROP_DIR});
die("ERROR: Context environment variable must be set") unless($ENV{Context});
die("ERROR: BUILD_NUMBER environment variable must be set") unless($ENV{BUILD_NUMBER});
$RAR = '"C:/Program Files/WinRAR/Rar.exe"';

########
# Main #
########

chdir($ENV{PACKAGES_DIR}) or warn("ERROR: cannot chdir '$ENV{PACKAGES_DIR}': $!");
system("$RAR a -r -inul -m0 $ENV{PACKAGES_DIR}/../packages.rar *");
copy("$ENV{PACKAGES_DIR}/../packages.rar", "$ENV{DROP_DIR}/$ENV{Context}/latest") or warn("ERROR: cannot copy '$ENV{PACKAGES_DIR}/../packages.rar': $!");
$Result = system("robocopy /E /NS /NC /NFL /NDL /NP /R:3 \"$ENV{PACKAGES_DIR}\" \"$ENV{IMPORT_DIR}/$ENV{Context}/$ENV{BUILD_NUMBER}/packages\" /XD metadata") & 0xff;
warn("ERROR: cannot robocopy '$ENV{PACKAGES_DIR}' to '$ENV{IMPORT_DIR}/$ENV{Context}/$ENV{BUILD_NUMBER}/packages': $!") if($Result);