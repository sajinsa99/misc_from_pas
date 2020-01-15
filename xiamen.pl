#!/usr/bin/perl -w



my $OS_FAMILY = ($^O eq "MSWin32") ? "windows" : "unix";
my $SZ_ROOTDIR ||= ($OS_FAMILY eq "windows") ? "C:\\" : $ENV{HOME};
$SZ_ROOTDIR =~ s/[\/\\]$//;

my $PROD_PASS_ACCESS_ROOT_PATH="$SZ_ROOTDIR/core.build.tools/export/shared/prodpassaccess";
my $PROD_PASS_ACCESS_PATH="$PROD_PASS_ACCESS_ROOT_PATH/bin/prodpassaccess";
sub Import_ProdPassAccess
{
	if( -e $PROD_PASS_ACCESS_PATH )
	{
		# print "DEBUG: prodpassaccess is already available.\n";
		return;
	}

	use File::Path;
	use LWP::Simple qw(getstore); # for nexus
	use Archive::Zip qw(:ERROR_CODES :CONSTANTS);

	die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
	$TEMPDIR =~ s/[\\\/]\d+$//;

	# @Nexus = [platform, url, artifact, root, destination]
	push(@Nexus, ['all', 'http://nexus.wdf.sap.corp:8081/nexus/content/groups/build.milestones/com/sap/prd/access/credentials/com.sap.prd.access.credentials.dist.cli/2.8', 'com.sap.prd.access.credentials.dist.cli-2.8.zip', 'prodpassaccess-2.8', "$PROD_PASS_ACCESS_ROOT_PATH"]);
	foreach (@Nexus)
	{
		my($Platform, $URL, $Artifact, $Root, $Destination) = @{$_};
		next unless($Platform eq $^O || $Platform=~/^all$/i);

		mkpath("$TEMPDIR/$$") or warn("ERROR: cannot mkpath '$TEMPDIR/$$': $!") unless(-e "$TEMPDIR/$$");
		my $rc = getstore("$URL/$Artifact", "$TEMPDIR/$$/$Artifact");
		`wget $URL/$Artifact` unless(-f "$TEMPDIR/$$/$Artifact");
		if(-f "$TEMPDIR/$$/$Artifact")
		{
			if($Artifact =~ /\.zip$/i)
			{
				my $Zip = Archive::Zip->new();
				warn("ERROR: cannot read '$TEMPDIR/$$/$Artifact': $!") unless($Zip->read("$TEMPDIR/$$/$Artifact") == AZ_OK);
				warn("ERROR: cannot extractTree '$Root': $!") unless($Zip->extractTree($Root, $Destination) == AZ_OK);
			} elsif($Artifact =~ /\.tar.gz$/) { warn("ERROR: format tar.gz not supported") }
		} else { warn("ERROR: cannot getstore '$URL/$Artifact': $rc") }
		rmtree("$TEMPDIR/$$") or warn("ERROR: cannot rmtree '$TEMPDIR/$$': $!");
	}

	# Required for unix systems
	chmod(0755, "$PROD_PASS_ACCESS_PATH") or warn("ERROR: cannot chmod '$PROD_PASS_ACCESS_PATH': $!");
}




my $PW_DIR = $ENV{PW_DIR} || (($^O eq "MSWin32") ? '\\\\build-drops-wdf\dropzone\aurora_dev\.xiamen' : '/net/build-drops-wdf/dropzone/aurora_dev/.xiamen');
my $PWFILE = $ENV{PWFILE} || (($^O eq "MSWin32") ? "$PW_DIR\\.PW" : "$PW_DIR/.PW");
#%P4Hosts{P4HOST} = [PASS, EXPIRATION LOGIN DATE]
if(-e $PWFILE)
{
	if(open(PW, $PWFILE))
	{
		while(<PW>)
		{
			s/^\s*//;
			s/\s*$//;
			my($P4Host, $PW) = split(/\s*=\s*/);
			$P4Hosts{$P4Host} = [$PW, undef];

			# If password contains a 'star' it means it is encrypted. Need to decrypt it.
			if(${$P4Hosts{$P4Host}}[0]=~/^\s*\*+\s*$/)
			{
				Import_ProdPassAccess;
				${$P4Hosts{$P4Host}}[0] = `$PROD_PASS_ACCESS_PATH --credentials-file $PWFILE.properties --master-file $PW_DIR/.master.xml get $P4Host password`; chomp(${$P4Hosts{$P4Host}}[0]);
			}

		}
		close(PW);
	}
}

# Proceed to login:
if(%P4Hosts)
{
    my $P4Host = $ENV{'P4PORT'};
    ($P4Host) = `p4 set P4PORT` =~ /=(.+)\s+\(set\)$/ unless($P4Host);
    system("echo ${$P4Hosts{$P4Host}}[0]|p4 login");
}
