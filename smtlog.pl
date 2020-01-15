#!/usr/bin/perl
#Copy smt logs in DROPZONE via "sudo builder" 
use Getopt::Long;
GetOptions("pre_sudo=s"=>\$option);

print "\n";
print "START of '$0' ".scalar(localtime());
print "\n";

my $HTTP_DIR_Real = "";
my $site ||= $ENV{SITE} || "Walldorf";
if($^O ne "MSWin32") {
	my  $user = getpwuid($<);
	if( $user =~ /^rm/i ) {
		if(  $site =~ /Walldorf/ ) {
			$HTTP_DIR_Real = $^O eq "hpux" ? "/net/build-drops-wdf/preintegration/CIS" : "/net/build-drops-wdf.pgdev.sap.corp/preintegration/CIS";
		}else {	
			 $HTTP_DIR_Real = $^O eq "hpux" ? "/net/build-drops-lv/space1/preintegration/cis" : "/net/build-drops-lv.pgdev.sap.corp/space1/preintegration/cis";
		}
		my $MKDIR = "sudo -u builder mkdir";
		my $CP = "sudo -u builder cp";
		$ENV{build_number} ||=`cat $ENV{DROP_DIR}/$ENV{context}/version.txt`;
		chomp($ENV{build_number});
		###to simplify code after
		my $build_number = $ENV{build_number};
		my $DROP_DIR = $ENV{DROP_DIR};
		my $OUTPUT_DIR = $ENV{OUTPUT_DIR};
		my $HTTP_DIR_Local = $ENV{HTTP_DIR};
		my $context = $ENV{context};
		my $PLATFORM = $ENV{PLATFORM};
		my $HOSTNAME = $ENV{HOSTNAME};

		my $CurrentDir = `pwd`;
		chomp($CurrentDir);

		my ($buildnumber, $precision) = $build_number =~ /^(\d+)(\.?\d*)/;
		my $f_buildnumber = sprintf("%05d", $buildnumber).$precision;

		if ( $HTTP_DIR_Local =~ /\/preintegration\/cis/i ) {
              print (" HTTP_DIR_Local=$HTTP_DIR_Local is too similar with HTTP_DIR, please check!\n");
              exit;
        }
		
		print ("\nENV for Smtlog.pl:\n");
		print ("==================\n");
		print ("USER= $user\n");
		print ("CP=$CP\n");
		print ("MKDIR=$MKDIR\n");
		print ("SCRIPTS_DIR=$CurrentDir\n");
		print ("builder_number=$build_number\n");
		print ("DROP_DIR=$DROP_DIR\n");
		print ("OUTPUT_DIR=$OUTPUT_DIR\n");
		print ("HTTP_DIR_Local=$HTTP_DIR_Local\n");
		print ("HTTP_DIR_Real=$HTTP_DIR_Real\n");
		print ("context=$context\n");
		print ("PLATFORM=$PLATFORM\n\n");
		my $dest = "$DROP_DIR/$context/$build_number/$PLATFORM/release/logs/$HOSTNAME";
		print ("DEST = $dest\n\n");
		if ( $option ){
			if (! -e $dest ) {system("$MKDIR -p $dest/Build");}
			print("pre_sudo option= $option \n");
			exit 0;
		} else {
			print("sudocp\n");

			open(SUMMARY,">$ENV{OUTPUT_DIR}/logs/Build/sudocp.summary.txt");
			my $Start = time ;
			print SUMMARY "== Build Info: machine=$HOSTNAME, area=sudocp, order=1, buildmode=release, platform=$PLATFORM, context=$context, revision=$build_number\n";
			print SUMMARY "== Sections with errors: 0\n\n";
			print SUMMARY "== Build start: ".scalar(localtime())." ($Start)\n";

			system("$CP -rf $OUTPUT_DIR/logs/Build $dest/");
		#For cis

			my $cisdest = "$HTTP_DIR_Real/$context/${context}_$f_buildnumber";
			print ("cisdest = $cisdest\n");
			system("$MKDIR -p $cisdest");
			$cisdest = "$HTTP_DIR_Real/$context";	
			my $cisloc = "$HTTP_DIR_Local/$context/${context}_$f_buildnumber";
			system(" rm $cisloc/*infra_1.dat 2>/dev/null");                               # no need copy the infra.dat to cis
			system("$CP -rf $cisloc $cisdest/ 2>/dev/null");

			my $EndTime = time ;
			print SUMMARY "== Build end: ".scalar(localtime())." ($EndTime)\n";
			close(SUMMARY);
		}
	} else { print ("You are not users rmXX, No need\n"); }
}

print "\n";
print "STOP of '$0' ".scalar(localtime());
print "\n";

exit 0;
