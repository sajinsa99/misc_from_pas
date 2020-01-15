use File::Find;
use File::Copy;
use File::Path;

($InputDir, $OutputDir) = @ARGV;

mkpath($OutputDir) or die("ERROR: cannot mkpath '$OutputDir': $!") unless(-e $OutputDir);
find(\&CopyJars, $InputDir);

sub CopyJars
{
	return unless($File::Find::name =~ /\.jar/i);
	(my $File = $_) =~ s/[_-]\d.*\.jar$//;           
	copy($File::Find::name, "$OutputDir/$File.jar") or die("ERROR: cannot copy '$File::Find::name': $!");
}