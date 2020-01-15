%Sites=(
	"Levallois"=>'\\\\build-drops-wdf',
	"Vancouver"=>'\\\\build-tools-vc\\tools\\Saturn',
	"Walldorf"=>"\\\\build-drops-wdf",
);
$location='BuildTools\\win32_x86\\ActiveState\\Packages';

die("ERROR : The SITE system environment variable is not defined !") unless(defined($ENV{"SITE"}));
die("ERROR : '$ENV{SITE}' is an unknown site!, known sites: ", join(", ", keys(%Sites)), "\n") unless(defined($Sites{$ENV{"SITE"}}));

$ENV{"SITE_PPM_DIR"} ||= $ARGV[0] || $Sites{$ENV{"SITE"}}.'\\'.$location;
$ENV{"SITE_PPM_URL"} ||= 'file:'.$ENV{"SITE_PPM_DIR"};
$ENV{"SITE_PPM_URL"} =~ s/\\/\//g;
print("Installing new packages from: '$ENV{SITE_PPM_DIR}'\n");
print("File URL : '$ENV{SITE_PPM_URL}'\n");

opendir(REP, $ENV{"SITE_PPM_DIR"}) or die("ERROR : cannot open directory '$ENV{SITE_PPM_DIR}'!");
@Files = readdir REP;
closedir REP;

open(REP, "ppm3 rep |") or die("ERROR: cannot execute 'ppm3 rep'");
while(<REP>)
{
    if(my($Repository) = /^\[\d+\]\s+(.+)$/)
    {
        push(@ActivatedRepositories, $Repository);
        system("ppm3 rep off $Repository");
    }
}
close(REP);
system("ppm3 rep add SAP_TDCORE $ENV{SITE_PPM_DIR}");

foreach $File (@Files)
{
    next unless($File =~ /\.ppd$/); # only threat files name.dep.#number
    #print("ppm3 install $ENV{SITE_PPM_DIR}\\$File -force -follow\n");
    system("ppm3 install $ENV{SITE_PPM_DIR}\\$File -force -follow");
}
system("ppm3 rep delete SAP_TDCORE");
foreach my $Repository (@ActivatedRepositories)
{
    system("ppm3 rep on $Repository");
}

