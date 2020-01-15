our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
BEGIN {
    use Exporter   ();
    
    # set the version for version checking
    $VERSION = sprintf "%d.000", q$Revision: #3 $ =~ /(\d+)/g;
    
    @ISA         = qw(Exporter);

    # your exported package globals go here,
    @EXPORT = qw(
        &modifyVersionedFiles
    );

    # any optionally exported functions go here
    @EXPORT_OK   = qw(
    );

    # collections of exported globals go here
    %EXPORT_TAGS = (
        'all' => [@EXPORT, @EXPORT_OK],
        'reporting' => [
            @EXPORT
        ],
    );
    
}

use File::Copy;

#############
# Functions #
#############
sub modifyVersionedFiles($$$$$$$;$) {
	my ($companyName,$copyRight,$buildDate,$buildNumber, $versionHashTableRef, $srcVersionDir, $srcTmpDir, $bOverwrite)=@_;
    # resources #
    foreach my $VersionFile (qw(version.cs version.cpp version.rc version.js version.h Manifest.mf version.properties))
    {
        if(open(SRC, "$srcVersionDir/$VersionFile")) {
	        if(open(DST, ">$srcTmpDir/$VersionFile")) {
		        my $buildNumber4digits = sprintf("%04d", $buildNumber);
		        while(<SRC>)
		        {
		            if(s/\d*,\d*,\d*,\d*/$versionHashTableRef->{MAJOR},$versionHashTableRef->{MINOR},$versionHashTableRef->{SLIP},$versionHashTableRef->{BUILDREV}/) {}
		            elsif(my($Pattern)=/§((MAJOR\+?\d*\.|MINOR\+?\d*\.|SLIP\+?\d*\.|BUILDREV\+?\d*|\d+\.*){4})/)
		            {
		                while($Pattern=~s/(MAJOR|MINOR|SLIP|BUILDREV)/$versionHashTableRef->{$1}/g) {}
		                while($Pattern=~s/(\d+)\s*\+\s*(\d+)/$1+$2/eg) {}
		                s/\d*\.\d*\.\d*\.\d*/$Pattern/;
		            }
		            elsif(s/\d*\.\d*\.\d*\.\d*/$versionHashTableRef->{MAJOR}.$versionHashTableRef->{MINOR}.$versionHashTableRef->{SLIP}.$versionHashTableRef->{BUILDREV}/) {}
		            elsif(s/\d+\/\d+\/\d+\s+\d+:\d+:\d+/$buildDate/) {}
		            elsif(s/"(.*)Copyright[-\.\s\w]+/"$1$copyRight/i) {}
		            elsif(s/([="])(SAP\s*\w*)((\\0)?".*)?$/$1$companyName$3/i) {}
		            elsif(s/VERSION_MAJOR\s+\d*/VERSION_MAJOR $versionHashTableRef->{MAJOR}/) {}
		            elsif(s/VERSION_MINOR\s+\d*/VERSION_MINOR $versionHashTableRef->{MINOR}/) {}
		            elsif(s/VERSION_SP\s+\d*/VERSION_SP $versionHashTableRef->{SLIP}/) {}
		            elsif(s/VERSION_BUILD\s+\d*/VERSION_BUILD $versionHashTableRef->{BUILDREV}/) {}
		            elsif(s/build\.major=\d+/build\.major=$versionHashTableRef->{MAJOR}/) {}
		            elsif(s/build\.minor=\d+/build\.minor=$versionHashTableRef->{MINOR}/) {}
		            elsif(s/build\.slip=\d+/build\.slip=$versionHashTableRef->{SLIP}/) {}
		            elsif(s/build\.number=\d+/build\.number=$versionHashTableRef->{BUILDREV}/) {}
		            elsif(s/version\.number=\d+\.\d+\.\d+/version\.number=$versionHashTableRef->{MAJOR}.$versionHashTableRef->{MINOR}.$versionHashTableRef->{SLIP}/) {}
		            elsif(s/build\.number\.4digits=\d+/build.number.4digits=$buildNumber4digits/) { }
		            print DST;
		        }
		        close(DST);
		        close(SRC);
		        if($bOverwrite) {
			        chmod(0755, "$srcVersionDir/$VersionFile");
			       	move("$srcTmpDir/$VersionFile", "$srcVersionDir/$VersionFile") or warn("ERROR: cannot move '$srcTmpDir/$VersionFile': $!");
		        }
	        } else {
	        	 warn("ERROR: cannot open '$srcTmpDir/$VersionFile': $!");
	        	 close(SRC);	        	 
	        }
        }
    }
}

1;
