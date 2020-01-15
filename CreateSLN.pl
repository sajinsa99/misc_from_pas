use File::Find;
use File::Basename;

$SRC_DIR = $ENV{SRC_DIR} || 'D:\Fortify_Mira\src';

my $rsSLN = sub
{
	my($Name, $Path, $Extension) = fileparse($File::Find::name, '\.vcproj');	
	return unless($Extension);
    return if($Name =~ /\.fortify$/);

    $CR = "";
	open(SRC, $File::Find::name) or die("ERROR: cannot open '$File::Find::name': $!");
	open(DST, ">$Path\\$Name.fortify.vcproj") or die("ERROR: cannot open '$Path\\$Name.fortify.vcproj': $!");
	while(<SRC>)
	{
	    chomp;
		print(DST "$CR$_") unless(/SccProjectName=/ or /SccAuxPath=/ or /SccLocalPath=/ or /SccProvider=/);
		print(DST ">") if(/SccProvider=.+>/ or /SccLocalPath=.+>/ or /SccProjectName=.+>/ or /SccAuxPath=.+>/);
		$CR = "\n";
	}
	close(DST);
	close(SRC);
};

find($rsSLN, $SRC_DIR);
