use XML::DOM;

use FindBin;
use lib ($FindBin::Bin);
use Perforce;

die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/[\\\/]\d+$//;
($Client) = @ARGV;
die("ERROR: perforce clientspec name is mandatory (example: ImpactedGAVs.pl Aurora_REL_LVWIN038)") unless($Client);

$p4 = new Perforce;
$p4->SetClient($Client);
die("ERROR: cannot set client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount());

$raResults = $p4->sync("-n");
die("ERROR: cannot sync '$Sync': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);
foreach my $File (@{$raResults})
{
    next if($File=~/ - deleted as / || $File=~/\.context\.xml#/ || $File=~/\.dep#/ || $File=~/\.dep.new#/ || $File=~/\.ini#/);
    next unless(my($POMPath)= $File=~/^(\/\/.+?\/.+?\/.+?\/.+?)\//);
    $POMPaths{$POMPath} = undef;
}

foreach my $POMPath (keys(%POMPaths))
{
    (my $POMFile = "$POMPath/pom.xml") =~ s/^\/\/[^\/]+/$TEMPDIR\/$Client/;
    $p4->print("-o", $POMFile, "$POMPath/pom.xml");
    die("ERROR: cannot print '$POMPath/pom.xml'", @{$p4->Errors()}, " ") if($p4->ErrorCount());

    my $POM = XML::DOM::Parser->new()->parsefile($POMFile);
    my $GroupId = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("groupId", 0)->item(0)->getFirstChild()->getData();
    my $ArtifactId = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("artifactId", 0)->item(0)->getFirstChild()->getData();
    my $Version    = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("version", 0)->item(0)->getFirstChild()->getData();
    my($Staging) = $POM->getElementsByTagName("scm")->item(0)->getElementsByTagName("connection")->item(0)->getFirstChild()->getData() =~ /([^\/]+)\/pom\.xml/;
    $POM->dispose();
    print("$Staging:$GroupId:$ArtifactId:$Version\n");
}

END { $p4->Final() if($p4) }