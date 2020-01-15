use Getopt::Long;

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "database=s"=>\$Database);
Usage() if($Help);

#$Depends{$Area} = [\%Providers, \%Clients];

open(DB, $Database) or die("ERROR: cannot open '$DATABASE': $!");
while(<DB>)
{
    my($Area1, $Area2) = /^[^:]+:([^:]+):[^:]+\|[^:]+:([^:]+):[^:]+\|/;    
    ${${$Depends{$Area1}}[0]}{$Area2} = undef if($Area1 ne $Area2);
}
close(DB);
foreach my $Area1 (keys(%Depends))
{
    foreach my $Area2 (keys(%{${$Depends{$Area1}}[0]}))
    {
        ${${$Depends{$Area2}}[1]}{$Area1} = undef if($Area1 ne $Area2);
    }
}

foreach my $Area1 (sort(keys(%Depends)))
{
    print("$Area1\n");
    print("\tProviders:", join(',', sort(keys(%{${$Depends{$Area1}}[0]}))), "\n");
    print("\tClients  :", join(',', sort(keys(%{${$Depends{$Area1}}[1]}))), "\n");
}

sub Usage
{
   print <<USAGE;
   Usage   : AreaDeps.pl -h -d
             AreaDeps.pl -h.elp|?
   Example : AreaDeps.pl -d=aurora.database.log 
    
   [options]
   -help|?     argument displays helpful information about builtin commands.
   -d.atabase  specifies the database log from depends build.
USAGE
    exit;
}