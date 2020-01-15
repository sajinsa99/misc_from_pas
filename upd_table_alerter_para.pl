#######################################################################################################################################################################################################
##### declare uses
#use strict;
use diagnostics;

use Getopt::Long;

use DBI;
use DBD::mysql;


#######################################################################################################################################################################################################
##### declare vars

#for the script itself
use vars qw (
	%forDB
	%BUILDS
	%Checks
	%Issues
	%PLATFORMS
	$RegExp
	$SMTP_SERVER
	$currentTime
);

# options/parameters
use vars qw (
	$Help
	$iniFile
	$Site
	$optBuild
	$Mail
	$overrideTrace
	$noTrace
);

#for parsing ini
use vars qw (
	$DROP_DIR
	$DEFAULT_SMTP_FROM
	$DEFAULT_SMTP_TO
	$DEFAULT_AVAILABLE
	$DEFAULT_TOLERANCE
	$db_host
	$db_user
	$db_passwd
	$db_name
	$db_table
);


#######################################################################################################################################################################################################
##### declare functions
sub Usage();
sub paseIniFile($);
sub getVersion($);
sub CheckIfExistInTable($);
sub addInTable($);
sub deleteInTable($);


#######################################################################################################################################################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
	"help|?"	=>\$Help,
	"ini=s"		=>\$iniFile,
	"site=s"	=>\$Site,
);
&Usage() if($Help);


#######################################################################################################################################################################################################
##### init vars

$Site ||= $ENV{'SITE'} || "Walldorf";
unless($Site eq "Levallois" || $Site eq "Walldorf" || $Site eq "Vancouver" || $Site eq "Bangalore"  || $Site eq "Paloalto" || $Site eq "Lacrosse") {
    die("\nERROR: SITE environment variable or 'perl $0 -s=my_site' must be set\navailable sites : Levallois | Walldorf | Vancouver | Bangalore | Paloalto | Lacrosse\n");
}
$ENV{'SITE'} = $Site;

# set different possible configurations
$PLATFORMS{windows}	= [qw(win32_x86 win64_x64)];
$PLATFORMS{unix}	= [qw(solaris_sparc linux_x86 aix_rs6000 hpux_pa-risc mac_x86 solaris_sparcv9 linux_x64 aix_rs6000_64 hpux_ia64 mac_x64)];
$PLATFORMS{linux}	= [qw(linux_x86 linux_x64)];
$PLATFORMS{solaris}	= [qw(solaris_sparc solaris_sparcv9)];
$PLATFORMS{aix}		= [qw(aix_rs6000 aix_rs6000_64)];
$PLATFORMS{hp}		= [qw(hpux_pa-risc hpux_ia64)];
$PLATFORMS{mac}		= [qw(mac_x86 mac_x64)];
$PLATFORMS{32}		= [qw(win32_x86 solaris_sparc linux_x86 aix_rs6000 hpux_pa-risc mac_x86)];
$PLATFORMS{64}		= [qw(win64_x64 solaris_sparcv9 linux_x64 aix_rs6000_64 hpux_ia64 mac_x64)];
$PLATFORMS{all}		= [qw(win32_x86 solaris_sparc linux_x86 aix_rs6000 hpux_pa-risc mac_x86 win64_x64 solaris_sparcv9 linux_x64 aix_rs6000_64 hpux_ia64 mac_x64)];

$iniFile ||= "$Site.ini";
$SMTP_SERVER = $ENV{SMTP_SERVER} || "mail.sap.corp";
$RegExp = qr/smtp_from|smtp_to|drop_dir|available|tolerance|version/;

#for db
$db_host	= $ENV{SBOP_DB_SRV}			|| "vermw64mst05.dhcp.wdf.sap.corp";
$db_user	= $ENV{SBOP_DB_USER}		|| "sbop";
$db_passwd	= $ENV{SBOP_DB_PASSWORD}	|| "sbop";
$db_name	= $ENV{SBOP_DB_NAME}		|| 'sbop_dashboard';
$db_table	= $ENV{SBOP_DB_TABLE}		|| 'alerter_para';

#######################################################################################################################################################################################################
##### MAIN

print "\n";

# runs only under windows to have windows paths to click in mails
if($^O ne "MSWin32") {
	print "\n\n[ERROR] $0 runs only under windows to have windows paths to click in mails\n\n";
	exit;
}

# create structure
&paseIniFile($iniFile) if ( -e $iniFile );

print "
DB infos:
db_host  = $db_host
db_user  = $db_user
db_name  = $db_name
db_table = $db_table

";

#add in db
print "
\t### check if builds & platform need to be added in db ###
";
foreach my $project (sort(keys(%Checks))) {
	print $project,"\n";
	foreach my $Build (keys(%{$Checks{$project}})) {
		print "\t",$Build,"\n";
		foreach my $platform (keys(%{$Checks{$project}{$Build}})) {
			next if($platform =~ /$RegExp/);
			print "\t\t",$platform;
			my $existInTable = &CheckIfExistInTable("$Build $platform") || 0;
			if($existInTable == 0) {
				print " => ADD in table $db_table\@$db_name\n";
				&addInTable("$Build $platform");
			} else {
				print " => already in table $db_table\@$db_name\n";
			}
		}
	}
}

#delete
print "
\t### check if builds & platform need to be deleted in db ###
";

my $request = "SELECT ind,alert_para FROM $db_table WHERE alert_name = 'alert_build_availability'";
my $dbh =  DBI->connect("DBI:mysql:$db_name:$db_host", $db_user, $db_passwd) or die "Unable to connect: $DBI::errstr\n";
my $sth = $dbh->prepare($request);
$sth->execute();
my %buildsTodelete;
while (@row= $sth->fetchrow_array()) {
	my $indice = $row[0];
	my $pattern = $row[1];
	print "$pattern";
	my $foundInHash = 0;
	foreach my $project (sort(keys(%Checks))) {
		foreach my $Build (keys(%{$Checks{$project}})) {
			foreach my $platform (keys(%{$Checks{$project}{$Build}})) {
				next if($platform =~ /$RegExp/);
				my $buildPlatform = "$Build $platform";
				if($buildPlatform eq $pattern) {
					$foundInHash = 1;
					last;
				}
			}
		}
	}
	if($foundInHash == 1) {
		print " => keep\n";
	} else {
		print " => TO DELETE\n";
		$buildsTodelete{$indice}=$pattern;
	}
}
$sth -> finish;

if(%buildsTodelete) {
	print "\n";
	foreach my $indice (sort(keys(%buildsTodelete))) {
		print "deleting $buildsTodelete{$indice} ($indice)\n";
		&deleteInTable($indice);
	}
} else {
	print "\n=> nothing to delete\n";
}

print "\n";
exit;


#######################################################################################################################################################################################################
### my functions
sub paseIniFile($) {
	my ($configFile) = @_;
		if(open(INI,"$configFile")) {
		SECTION: while(<INI>) {
			chomp;
			s-^\s+$--;
			next unless($_);
			next if(/^\#/); #skip comments
			s-\#(.+?)$--; # remove comments in end of line
			$DROP_DIR		= $1 if(/DROP_DIR\=(.+?)$/);
			$DEFAULT_SMTP_FROM	= $1 if(/DEFAULT_SMTP_FROM\=(.+?)$/);
			$DEFAULT_SMTP_TO	= $1 if(/DEFAULT_SMTP_TO\=(.+?)$/);
			$DEFAULT_AVAILABLE	= $1 if(/DEFAULT_AVAILABLE\=(.+?)$/);
			$DEFAULT_TOLERANCE	= $1 if(/DEFAULT_TOLERANCE\=(.+?)$/);
			next unless(my ($Build) = /^\[(.+?)\]/);
			my ($project,$smtp_from,$smtp_to,$drop_dir,$available,$tolerance);
			while(<INI>) {
				chomp;
				s-^\s+$--;
				next unless($_);
				s-\#(.+?)$--; # remove comments in end of line
            	redo SECTION if(/^\[(.+)\]/);
            	my $this_drop_dir = "";
            	if(/^(.+?)\=(.+?)$/) {
            		my $var = $1;
            		my $value = $2;
					$project	= $value if($var =~ /^project/);
					$smtp_from	= $value if($var =~ /^smtp_from/);
					$smtp_to	= $value if($var =~ /^smtp_to/);
					$drop_dir	= $value if($var =~ /^drop_dir/);
					$available	= $value if($var =~ /^available/);
					$tolerance	= $value if($var =~ /^tolerance/);
					$Checks{$project}{$Build}{smtp_from}	= $smtp_from	if(defined($smtp_from));
					$Checks{$project}{$Build}{smtp_to}		= $smtp_to		if(defined($smtp_to));
					$Checks{$project}{$Build}{drop_dir}		= $drop_dir		if(defined($drop_dir));
					$Checks{$project}{$Build}{available}	= $available	if(defined($available));
					$Checks{$project}{$Build}{tolerance}	= $tolerance	if(defined($tolerance));
					$this_drop_dir = $Checks{$project}{$Build}{drop_dir}	|| $DROP_DIR; # if specifc drop_dir
					($this_drop_dir) =~ s-\\-\/-g if(defined($this_drop_dir)); #unix style
					my $version = &getVersion("$this_drop_dir/$project/$Build") if(defined($project));
					$Checks{$project}{$Build}{version}=$version if(defined($version));
            	}
            	if(/\s+\|\s+/) { #if platform(s) | folder(s) | available(?)
            		s-\s+--g;
            		#structure:
            		#platform | folder1,folder2
            		#or
            		#platform | folder1,folder2 | available
            		my @elems	= split('\|',$_); # seperate elements
            		my @folders	= split(',',$elems[1]); #$elem[1] = list of folders
            		my $specificAvailable = $elems[2] if($elems[2]); #if $elem[2], override vailable value for this build but for specific platform
            		($specificAvailable) =~ s-^available\=--i if(defined($specificAvailable));
            		my $specificTolerance = $elems[3] if($elems[3]); #if $elem[3], override vailable value for this build but for specific platform
            		($specificTolerance) =~ s-^tolerance\=--i if(defined($specificTolerance));
            		#provide real platforms;
            		my @PlatformsToCheck = split(',',$elems[0]);
            		#get skip platforms
            		my @skipPlatforms;
            		foreach my $platformToCheck (@PlatformsToCheck) {
            			if($platformToCheck =~ /^\-(.+?)$/) {
            				push(@skipPlatforms,$1) unless(grep /^$1$/,@skipPlatforms);
            			}
            		}
            		#ass folders for each platforms
            		foreach my $platformToCheck (@PlatformsToCheck) {
            			next if($platformToCheck =~ /^\-/);
            			if(defined(@{$PLATFORMS{$platformToCheck}})) {
							foreach my $thisPlatform (@{$PLATFORMS{$platformToCheck}}) {
								my $skip = 0;
								foreach my $skipPlatform (@skipPlatforms) {
									if($thisPlatform =~ /^$skipPlatform/) {
										$skip = 1;
										last;
									}
								}
								if($skip == 0) {
									@{$Checks{$project}{$Build}{$thisPlatform}{folders}}	= @folders;
									$Checks{$project}{$Build}{$thisPlatform}{available}		= $specificAvailable if(defined($specificAvailable));
									$Checks{$project}{$Build}{$thisPlatform}{tolerance}		= $specificTolerance if(defined($specificTolerance));
								}
							}
						} else {
	            			@{$Checks{$project}{$Build}{$platformToCheck}{folders}}	= @folders;
	            			$Checks{$project}{$Build}{$platformToCheck}{available}	= $specificAvailable if(defined($specificAvailable));
	            			$Checks{$project}{$Build}{$platformToCheck}{tolerance}	= $specificTolerance if(defined($specificTolerance));
	            		}
            		}
        		}
			}
		}
		close(INI);
	}
}

sub getVersion($) {
	my ($versionDir) = @_;
    my $tmp = 0;
    if(open(VER, "$versionDir/version.txt"))
    {
        chomp($tmp = <VER>);
        $tmp = int($tmp);
        close(VER);
    }
    else # If version.txt does not exists or opening failed, instead of restarting from 1, look for existing directory versions & generate the hightest version number based on the hightest directory version
    {
        # open current context dir to find the hightest directory version inside
        if(opendir(BUILDVERSIONSDIR, "$versionDir"))
        {
            while(defined(my $next = readdir(BUILDVERSIONSDIR)))
            {
                $tmp = $1 if ($next =~ /^(\d+)(\.\d+)?$/ && $1 > $tmp && -d "$versionDir/$next"); # Only take a directory with a number as name, which can be a number or a float number with a mandatory decimal value & optional floating point
            }   
            closedir(BUILDVERSIONSDIR);
        }
    }
    return $tmp;
}

sub updDB() {
	my $dbh =  DBI->connect("DBI:mysql:$db_name:$db_host", $db_user, $db_passwd) or die "Unable to connect: $DBI::errstr\n";
}


sub CheckIfExistInTable($) {
	my ($pattern) = @_ ;
	my $request = "SELECT alert_para FROM $db_table WHERE alert_para = '$pattern'";
	my $dbh =  DBI->connect("DBI:mysql:$db_name:$db_host", $db_user, $db_passwd) or die "Unable to connect: $DBI::errstr\n";
	my $sth = $dbh->prepare($request);
	$sth->execute();
	my $result = $sth->fetchrow_hashref();
	my $result_alert_para = $result->{alert_para};
	$sth -> finish;
	return 1 if($result_alert_para);
}

sub addInTable($) {
	my ($pattern) = @_ ;
	my $dbh =  DBI->connect("DBI:mysql:$db_name:$db_host", $db_user, $db_passwd) or die "Unable to connect: $DBI::errstr\n";
	my $sth = $dbh->prepare("INSERT INTO $db_table (alert_name,alert_para,site) VALUES(?,?,?)");
	$sth->execute("alert_build_availability",$pattern,$Site);
	$sth -> finish;
}

sub deleteInTable($) {
	my ($thisIndice) = @_ ;
	my $dbh =  DBI->connect("DBI:mysql:$db_name:$db_host", $db_user, $db_passwd) or die "Unable to connect: $DBI::errstr\n";
	my $request = "DELETE FROM $db_table WHERE ind = '$thisIndice'";
	my $sth = $dbh->prepare($request);
	$sth->execute();
	$sth -> finish;

}