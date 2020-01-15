use LWP::UserAgent;

@OnDemandServers = qw(pwdf3868 dewdfth12417 dewdfth12418);

$ua = LWP::UserAgent->new();
$NumberOfBuilds = 1000000;
foreach my $Srv (@OnDemandServers)
{
    my $req = HTTP::Request->new(GET => "http://$Srv:8082/?mode=INFO");
    my $Response = $ua->request($req);
    next unless($Response->is_success());
    my $Content = $Response->decoded_content();
    my($Nb) = $Content =~ /'currentProcesses' => (\d+)/m;
    if($Nb < $NumberOfBuilds) { $NumberOfBuilds = $Nb; $Server = $Srv }
}
$Server ||= $OnDemandServers[0];
print("$Server\n");