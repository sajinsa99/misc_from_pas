#!/usr/bin/perl -w

use File::Copy;

die("ERROR: MY_TEXTML environment variable must be set") unless($ENV{MY_TEXTML});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($ENV{OUTPUT_DIR});

push(@RDSServers, 'dewdfth1240d.wdf.sap.corp');
($Server) = $ENV{MY_TEXTML} =~ /\@(.*?):/;

foreach my $RDSServer (@RDSServers)
{
    if($RDSServer =~ /^$Server$/i)
    {
		CopyFile("$ENV{OUTPUT_DIR}/bin/tp.net.sf.dita-ot/resource/conditionaltext_rds.xml", "$ENV{OUTPUT_DIR}/bin/tp.net.sf.dita-ot/resource/conditionaltext.xml"); 
        CopyFile("$ENV{OUTPUT_DIR}/bin/tp.net.sf.dita-ot/plugins/com.sap.prd.dita.dtd/dtd/client/TICM-profilingAttDomain_rds.ent", "$ENV{OUTPUT_DIR}/bin/tp.net.sf.dita-ot/plugins/com.sap.prd.dita.dtd/dtd/client/TICM-profilingAttDomain.ent"); 
        last;
    } 
}

sub CopyFile
{
    my($Source, $Destination) = @_;
	unlink($Destination) or warn("ERROR: cannot unlink '$Destination': $!") if(-f $Destination);
    copy($Source, $Destination) or warn("ERROR: cannot copy '$Source' to '$Destination': $!");
}