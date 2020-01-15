use Getopt::Long;

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "database=s"=>\$Database);
Usage() if($Help);

#$Depends{$Unit} = [\%Providers, \%Clients];

open(DB, $Database) or die("ERROR: cannot open '$DATABASE': $!");
while(<DB>)
{
    #aurora:mda.clients.shared:MDA_Client_java|aurora:mda.clients.common:MDA_Client_Common_java|$OUTPUT_DIR/bin/unifiedrendering/java/themes/sap_hcb/r/common/richtextedit/rte_bold.gif
    my($Unit1, $Unit2) = /^[^:]+:([^:]+:[^:]+)\|[^:]+:([^:]+:[^:]+)\|/;    
    ${${$Depends{$Unit1}}[0]}{$Unit2} = undef if($Unit1 ne $Unit2);
}
close(DB);
foreach my $Unit1 (keys(%Depends))
{
    foreach my $Unit2 (keys(%{${$Depends{$Unit1}}[0]}))
    {
        ${${$Depends{$Unit2}}[1]}{$Unit1} = undef if($Unit1 ne $Unit2);
    }
}

foreach my $Unit1 (sort(keys(%Depends)))
{
    print("$Unit1\n");
    print("\tProviders:", join(',', sort(keys(%{${$Depends{$Unit1}}[0]}))), "\n");
    print("\tClients  :", join(',', sort(keys(%{${$Depends{$Unit1}}[1]}))), "\n");
}

sub Usage
{
   print <<USAGE;
   Usage   : UnitDeps.pl -h -d
             UnitDeps.pl -h.elp|?
   Example : UnitDeps.pl -d=aurora.database.log 
    
   [options]
   -help|?     argument displays helpful information about builtin commands.
   -d.atabase  specifies the database log from depends build.
USAGE
    exit;
}