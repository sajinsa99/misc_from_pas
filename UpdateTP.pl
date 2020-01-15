#!/usr/bin/perl -w

use XML::DOM;
use Getopt::Long;
use Sys::Hostname;

use FindBin;
use lib ($FindBin::Bin);
use Perforce;

##############
# Parameters #
##############

@Depots = qw(tp internal);
$TPPOM_DEPOT     = "//product/thirdparties/1.0/REL/pom.xml";
$TPMAKE_DEPOT    = "//product/thirdparties/1.0/REL/export/thirdparties.gmk";
$TPMAPPING_DEPOT = "//product/thirdparties/1.0/REL/export/area_mapping.gmk";
die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/[\\\/]\d+$//;
$HOST = hostname();

GetOptions("help|?"=>\$Help, "client=s"=>\$Client, "description=s"=>\$Description);
$Client ||= "Builder_\L$HOST";
$Description ||= 'automatic TP update';
Usage() if($Help);

########
# Main #
########

my $p4 = new Perforce;
$p4->SetClient($Client);
die("ERROR: cannot set client '$Client': ", @{$p4->Errors()}) if($p4->ErrorCount());

foreach my $File (qw(TPPOM TPMAKE TPMAPPING))
{
    my $rafstat = $p4->fstat(${"${File}_DEPOT"});
    die("ERROR: cannot fstat '", ${"${File}_DEPOT"}, "': ", @{$p4->Errors()}) if($p4->ErrorCount());
    foreach(@{$rafstat})
    {
        last if((${"${File}_CLIENT"}) = /clientFile\s+(.+)$/);
    }
}

foreach my $Depot (@Depots)
{
    my $raDirs = $p4->Dirs("//$Depot/*/*/REL/export");
    die("ERROR: cannot dirs '//$Depot/*/*/REL/export': ", @{$p4->Errors()}) if($p4->ErrorCount());
    TP: foreach my $TP (@{$raDirs})
    {
        next unless(my($Area) = $TP =~ /\/\/$Depot\/(tp\.[^\\\/]+)/);
        chomp($TP);
        $TP =~ s/\/export$//;
        foreach my $File ("pom.xml", "$Area.gmk")
        {
            $p4->print("-o", $File, "-q", "$TP/$File");
            if($p4->ErrorCount() && ${$p4->Errors()}[0]=~/no such file\(s\).$/) { print(STDERR "WARNING: '$TP' is ignored (no contains $File)\n"); next TP } 
            die("ERROR: cannot print '$TP/$File': ", @{$p4->Errors()}) if($p4->ErrorCount());
        }
        my $POM = XML::DOM::Parser->new()->parsefile("pom.xml");
        my $GroupId    = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("groupId", 0)->item(0)->getFirstChild()->getData();
        my $ArtifactId = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("artifactId", 0)->item(0)->getFirstChild()->getData();
        my $Version    = $POM->getElementsByTagName("project")->item(0)->getElementsByTagName("version", 0)->item(0)->getFirstChild()->getData();
        $POM->dispose();
        warn("ERROR: the GroupId of $TP/pom.xml is '$GroupId' instead 'com.sap.tp'.") if($GroupId ne "com.sap.tp");
        $ArtifactIDs{$ArtifactId}{$Version} = $GroupId;
    }
}

# POM
$p4->print("-o", "$TEMPDIR/pom.xml", "-q", $TPPOM_DEPOT);
die("ERROR: cannot print '$TPPOM_DEPOT': ", @{$p4->Errors()}) if($p4->ErrorCount());
chmod(0755, $TPPOM_CLIENT) or die("ERROR: cannot chmod '$TPPOM_CLIENT': $!") if(-e $TPPOM_CLIENT);
open(SRC, "$TEMPDIR/pom.xml") or die("ERROR: cannot open '$TEMPDIR/pom.xml': $!");
open(DST, ">$TPPOM_CLIENT") or die("ERROR: cannot open '$TPPOM_CLIENT': $!");
LINE: while(<SRC>)
{
    if(/<properties>/)
    {
        print(DST);
        foreach my $ArtifactId (sort(keys(%ArtifactIDs)))
        {
            print(DST "\t\t<$ArtifactId>", join(";", map({s/-SNAPSHOT//; $_} sort(keys(%{$ArtifactIDs{$ArtifactId}})))), "</$ArtifactId>\n");
        }
        while(<SRC>) { redo LINE if(/<\/properties>/) }
    }
    elsif(/<dependencies>/)
    {
        print(DST);
        foreach my $ArtifactId (sort(keys(%ArtifactIDs)))
        {
            foreach my $Version (sort(keys(%{$ArtifactIDs{$ArtifactId}})))
            {
                print(DST "\t\t<dependency>\n");
                print(DST "\t\t\t<groupId>${$ArtifactIDs{$ArtifactId}}{$Version}</groupId>\n");
                print(DST "\t\t\t<artifactId>$ArtifactId</artifactId>\n");
                print(DST "\t\t\t<version>$Version</version>\n");
                print(DST "\t\t</dependency>\n");
            }
        }
        while(<SRC>) { redo LINE if(/<\/dependencies>/) }
    } 
    else { print(DST) }
}
close(DST);
close(SRC);
unlink("$TEMPDIR/pom.xml") or die("ERROR: cannot unlink '$TEMPDIR/pom.xml': $!");

# Makefile
$p4->print("-o", "$TEMPDIR/thirdparties.gmk", "-q", $TPMAKE_DEPOT);
die("ERROR: cannot print '$TPMAKE_DEPOT': ", @{$p4->Errors()}) if($p4->ErrorCount());
chmod(0755, $TPMAKE_CLIENT) or die("ERROR: cannot chmod '$TPMAKE_CLIENT': $!") if(-e $TPMAKE_CLIENT);
open(SRC, "$TEMPDIR/thirdparties.gmk") or die("ERROR: cannot open '$TEMPDIR/thirdparties.gmk': $!");
open(DST, ">$TPMAKE_CLIENT") or die("ERROR: cannot open '$TPMAKE_CLIENT': $!");
LINE: while(<SRC>)
{
    if(/AREAS = \\/)
    {
        print(DST);
        print(DST "\tbusinessobjects.mergeresource.cpp \\\n");
        foreach my $ArtifactId (sort(keys(%ArtifactIDs)))
        {
            foreach my $Version (sort(keys(%{$ArtifactIDs{$ArtifactId}})))
            {
                $Version =~ s/-SNAPSHOT//;
                print(DST "\t$ArtifactId/$Version \\\n")
            }
        }
        while(<SRC>) { redo LINE if(/^\s*$/) }
    }
    else { print(DST) }
}
close(DST);
close(SRC);
unlink("$TEMPDIR/thirdparties.gmk") or die("ERROR: cannot unlink '$TEMPDIR/thirdparties.gmk': $!");

# Area Mapping
$p4->print("-o", "$TEMPDIR/area_mapping.gmk", "-q", $TPMAPPING_DEPOT);
die("ERROR: cannot print '$TPMAPPING_DEPOT': ", @{$p4->Errors()}) if($p4->ErrorCount());
chmod(0755, $TPMAPPING_CLIENT) or die("ERROR: cannot chmod '$TPMAPPING_CLIENT': $!") if(-e $TPMAPPING_CLIENT);
open(SRC, "$TEMPDIR/area_mapping.gmk") or die("ERROR: cannot open '$TEMPDIR/area_mapping.gmk': $!");
open(DST, ">$TPMAPPING_CLIENT") or die("ERROR: cannot open '$TPMAPPING_CLIENT': $!");
LINE: while(<SRC>)
{
    if(/^############/)
    {
        print(DST);
        foreach my $ArtifactId (sort(keys(%ArtifactIDs)))
        {
            foreach my $Version (sort(keys(%{$ArtifactIDs{$ArtifactId}})))
            {
                $Version =~ s/-SNAPSHOT//;
                (my $Export = "\U$ArtifactId"."_$Version") =~ s/[.-]/_/g;
                print(DST "export $Export=$ArtifactId/$Version\n"); 
            }
        }
        last LINE;
    }
    else { print(DST) }
}
close(DST);
close(SRC);
unlink("$TEMPDIR/area_mapping.gmk") or die("ERROR: cannot unlink '$TEMPDIR/area_mapping.gmk': $!");

foreach my $File (qw(TPPOM TPMAKE TPMAPPING))
{
    $p4->edit(${"${File}_CLIENT"});
    if($p4->ErrorCount())
    {
        if(${$p4->Errors()}[0]=~/already opened for add/) { }  
        else { die("ERROR: cannot p4 edit '", ${"${File}_CLIENT"}, "': ", @{$p4->Errors()}, "at ", __FILE__, " line ", __LINE__, ".\n") }
    }
    $p4->revert("-a -c default",  ${"${File}_DEPOT"});
    die("ERROR: cannot p4 revert '", ${"${File}_DEPOT"}, "': ", @{$p4->Errors()}, "at ", __FILE__, " line ", __LINE__, ".\n") if($p4->ErrorCount());
    $p4->submit("-d \"$Description\"", ${"${File}_DEPOT"});
    warn("ERROR: cannot p4 submit '", ${"${File}_DEPOT"}, "': ", @{$p4->Errors()}, "at ", __FILE__, " line ", __LINE__, ".\n") if($p4->ErrorCount());
}

END 
{ 
    $p4->Final() if($p4);
}

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : UpdateTP.pl -c -d
             UpdateTP.pl -h.elp|?
   Example : UpdateTP.pl -c=Builder_lvwin038 -d "thirdparties update build 123"
    
   [options]
   -help|?       argument displays helpful information about builtin commands.
   -c.lient      specifies the client name, default is 'Builder_\L$HOST'.
   -d.escription specifies the changelist description.
USAGE
    exit;
}