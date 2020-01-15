#!/usr/bin/perl
#======================================================================================== 
# Script: XBM.pm
# Purpose: upload build info and smoke testing results to build matrix db
# Author: Jeffrey.Shi@sap.com
# History:
#   May-23-08: Created
#   Feb-18-09: Add BM2 support
#======================================================================================== 
package XBM;
use strict;
use warnings;
use FindBin qw($Bin);
use lib ($Bin, "$Bin/site_perl");
use Sys::Hostname;
use Mail::Sendmail;
use File::Path;
use Cwd qw(abs_path);
use Data::Dump qw(dump);

my $SoapOn = 0;
eval { require "SOAP/Lite.pm" };
unless($@)
{
    if($SOAP::Lite::VERSION eq "0.60"){
        $SoapOn = 1;
    } 
    else { 
    	warn("ERROR:XBM: SOAP::Lite version 0.60 is required and you have SOAP::Lite version $SOAP::Lite::VERSION.") 
    }
} 
else { 
    warn("ERROR:XBM: can't locate SOAP::Lite module.");
}


# var
#my $EndPoint='http://vanpgrmapps02.product.businessobjects.com:90/BuildStatusWS/services/BMWS?wsdl';

my $EndPoint2='http://vanpgamd07.pgdev.sap.corp:1080/BuildMetricsWS/services/BM2WebServices?wsdl';

my $Admin     = "jeffrey.shi\@sap.com";
my $BM2Element = "smtEl";

my $TypeSmT   = 'smoke';
my $TypeBuild = 'build';
my $rTypes = { 
$TypeSmT => '-f',
$TypeBuild => '-b'
};
my $TypeBM2SmTStart = 'smtStart';
my $TypeBM2SmTEnd   = 'smtEnd';

my $BmHome   = "$Bin/../java/buildmatrix";
my $JmsDir   = "$BmHome/client";

my $Jre      = "$BmHome/jre";
my $External = "$Bin/../../../External/JDK";
my $JreMap   = {
'win64_x64'       => 'jdk1.5.0_12',
'win32_x86'       => 'jdk1.5.0_12',
'solaris_sparcv9' => 'jdk1.5.0_06',
'solaris_sparc'   => 'jdk1.5.0_12',
'aix_rs6000_64'   => undef,
'aix_rs6000'      => 'jdk1.5.0_SR7',
'hpux_ia64'       => 'jdk1.5.0_03',
'hpux_pa-risc'    => 'jdk1.5.0_08',
'linux_x64'       => undef,
'linux_x86'       => 'jdk1.5.0_12'	
};

my $P4Proxies = {
'levallois' => '10.50.80.149:1971',
'vancouver' => '10.6.4.99:1971',
'bangalore' => '172.25.70.48:1971'	
};

# sub
sub new;
sub DESTROY;
sub uploadSmT($$$$);
sub uploadBuild($$$$$);
sub errAlert($);
sub objGenErrBuild($$$$$$);
sub objGenErrSmT($$$$$);

sub findBM2Info();
sub sendBM2SmT($$);
sub objGenErrBM2SmTStart($$);
sub objGenErrBM2SmTEnd($$);

sub _ws($$$);
sub _jms($$$);
sub _upload($$$$$$;$);
sub _callService($$$);
sub _genXML($$$$$;$);
sub _makeDirs($);
sub _sendEmail($$$;$);
sub _isRevFine($);
sub _isDateFormat($);
sub _syncJre($$);
sub _processPrevFailures($);
sub _backupFailures($$);
sub _hasPrevFailures($);

sub _findPlatform();
sub _genBM2XML($);
sub _callBM2Service($$$);
sub _ws2($$$);
sub _handleBM2FailureRecover($$);
sub _handleBM1FailureRecover($$);
#======================================================================================== 
# $model     = [32|64]
# $site      = [Vancouver|Levallois|Bangalore]
# $backupDir = the local storage location for failures.
# $java      = full path to jrt 1.5, default "java" assuming this it is jre1.5+
# $useJms    = [0|1] whether jms is turned on
sub new{
    my $class = shift;
    my ($model, $site, $useJms, $backupDir, $java) = @_;
    return 0 unless($SoapOn);
    
    my $self = _makeDirs($backupDir);
# May 7, 2009. turn off bm1
#    my $soap;   
#    eval{ $soap = SOAP::Lite
#               ->service($EndPoint)
#               ->encoding('utf-8');
#         $self->{soap} = $soap;	  
#    };
#    if(!$soap || $@ || $?){
#        warn("WARNING:XBM::new failed in access BMRS web service with ERR: $@; $?; $!");
#    }
    
    my $soap2;
    eval{ 
        $soap2 = SOAP::Lite
            ->service($EndPoint2)
            ->encoding('utf-8');
        $self->{soap2} = $soap2;
    };
    if(! $soap2 || $@ || $?){
        warn("WARNING:XBM::new failed in access BM2 web service with ERR: $@; $?; $!");
    }
    
    my $msg;
    if($useJms){
    	$model = 32 unless($model); 
        my $j = ($^O eq "MSWin32") ? "bin/java.exe" : "bin/java";
 
        if($model && $site){# build machine 
            unless($site){
            	$msg = "ERROR:XBM::new $site is undefined";
                warn($msg);
                errAlert($msg);
                return undef;
            }
        
            my $p4proxy = $P4Proxies->{lc($site)};
            unless($p4proxy){
            	$msg = "ERROR:XBM::new can't find p4 proxy for $site. The site may not be supported.";
                warn($msg);
                errAlert($msg);
                return undef;	
            }
        
            unless(_syncJre($model, $p4proxy)){
            	$msg = "ERROR:XBM::new failed to sync jrt";
                warn($msg);
                errAlert($msg);
                return undef;	
            }
        
            $self->{jms} = "$Jre/$j";
        }
        else{#assume $model and $site not defined
    	    $self->{jms} = "java"; # default to java and assuming it is 1.5+
            $self->{jms} = "$java/$j" if($java && -d $java && -f "$java/$j");
        }
        #warn("INFO:XBM::new use '$self->{jms}'");
        $self->{jms} .= " -jar $BmHome/bsClient.jar";
    }
# May 7, 2009. turn off bm1
#    unless($self->{soap} || $self->{jms}){
    unless($self->{soap2} || $self->{jms}){
    	$msg = "ERROR:XBM::new neither ws nor jms is initialized successfully.";
        warn($msg);
        errAlert($msg);
        return undef;	
    }
                   
    bless $self, $class;
    return $self;
}
#======================================================================================== 
# $rh : with info needed for BM2
# undef : if failed
sub findBM2Info(){
    my ($project, $context, $platform, $buildRev) = (undef, undef, undef, undef);
 
    $platform = _findPlatform();
    unless($platform){
        warn("ERROR:XBM:findBM2Info: failed to find platform");
        return undef;	
    }
    warn("INFO:XBM:findBM2Info: successfully found platform '$platform'");
    
    my $buildName = $ENV{AC_TEST_BUILD};
    unless($buildName){
        warn("INFO:XBM:findBM2Info: AC_TEST_BUILD is not defined");
        return undef;	
    }
    warn("INFO:XBM:findBM2Info: found build name as '$buildName'");
    
    # buildRev and ini file
    ($buildRev, $context) = ($buildName =~ m<(.+\.\d+)\.[^_]+_(\w+)$>);
    unless($buildRev && $buildRev =~ m<^\d+> && $context){
        warn("ERROR:XBM:findBM2Info: Failed to find raw revision($buildRev) or context($context)");
        return undef;
    }
    warn("INFO:XBM:findBM2Info: found context name in build '$context' and build rev '$buildRev'");
    
    #_Patch is appended in Build.pl when registering patch builds
    $context =~ s!_Patch$!!i;
    
    my $iniFile = "$Bin"."/contexts/"."$context".'.ini';
    warn("INFO:XBM:findBM2Info: identified ini file as '$iniFile'");
    unless(-r $iniFile && ! -z $iniFile){
        warn("ERROR:XBM:findBM2Info: $iniFile is not accessible!");	
        return undef;
    }
    $context = undef;
    
    # Get context and project from ini file.
    unless(open(INI, "<$iniFile")){
        warn("ERROR:XBM:findBM2Info: failed to read $iniFile with err: $@, $!, $?");
        return undef;	
    }
    
    my $foundContextTag = 0;
    my $foundProjectTag = 0;
    my $foundVersionTag = 0;
    my $version = undef;
    while(<INI>){
        chomp;
        next if(m<^\s*$> || m<^\s*\#>);
        
        if($context && $project && $version){
            warn("INFO:XBM:findBM2Info: found context '$context' and project '$project' version '$version'");
            last;	
        }
        
        if(m<^\s*\[\s*context\s*\]>i){
            $foundContextTag = 1; 
            next;
        }
        
        if(m<^\s*\[\s*project\s*\]>i){
            $foundProjectTag = 1; 
            next;	
        }
        
        if(m<^\s*\[\s*version\s*\]>i){
            $foundVersionTag = 1;
            next;	
        }
        
        if($foundContextTag && ! $context){
            $context = $_;
            $context =~ s!^\s*!!;
            $context =~ s!\s*$!!;
            next;
        }
        
        if($foundProjectTag && ! $project){
            $project = $_;
            $project =~ s!^\s*!!;
            $project =~ s!\s*$!!;
            next;
        }
        
        if($foundVersionTag && ! $version){
            $version = $_;
            $version =~ s!^\s*!!;
            $version =~ s!\s*$!!;
            next;	
        }
    }
    close(INI);
    unless($project && $context){
        warn("ERROR:XBM:findBM2Info: failed to locate project($project) or context($context)");
        return undef;	
    }
    
    # buildRev
    if($version){
    	unless($version =~ m<^\d+>){
    	    warn("ERROR:XBM:findBM2Info: found invalid version '$version'");
    	    return undef;	
    	}
    	my $v = $buildRev;
    	
    	# just in case having . at the end of version
    	$version =~ s!\.$!!;
        ($buildRev) = ($buildRev =~ m<$version\.(.+)$>);	
        warn("INFO:XBM:findBM2Info: apply version '$version' on buildRev '$v' and get '$buildRev'");
    }
    else{
        ($buildRev) = ($buildRev =~ m<^.+(\d+)$>);
        warn("INFO:XBM:findBM2Info: not found version and buildRev is '$buildRev'");
    }
    unless($buildRev && $buildRev =~ m<^\d+>){
        warn("ERROR:XBM:findBM2Info: failed to find buildRev.");
        return undef;	
    }

    my $rh = {'project'     => lc($project),
              'context'     => lc($context),
              'platform'    => lc($platform),
              'buildRev'    => $buildRev,
              'host'        => hostname(),
              'date'        => time
     };
    warn("INFO:XBM:findBM2Info: successully found all the info project($project) context($context) platform($platform) buildRev($buildRev)");
    return $rh;
}
#======================================================================================== 
sub _findPlatform(){
    my $object_model = 32; 
    my $platform = undef;
    
    defined($ENV{AC_TEST_OBJECT_MODEL}) ? warn("INFO:XBM: defined AC_TEST_OBJECT_MODEL=$ENV{AC_TEST_OBJECT_MODEL}") : 
                                          warn("INFO:XBM: AC_TEST_OBJECT_MODEL is not defined");
    if(defined $ENV{AC_TEST_OBJECT_MODEL} && ($ENV{AC_TEST_OBJECT_MODEL} eq "32" || $ENV{AC_TEST_OBJECT_MODEL} eq "64")){
        $object_model=$ENV{AC_TEST_OBJECT_MODEL};
        warn("INFO:XBM: Valid AC_TEST_OBJECT_MODEL=$ENV{AC_TEST_OBJECT_MODEL}");
    }
    if($^O eq "MSWin32")    { $platform = $object_model==64 ? "win64_x64"       : "win32_x86" }
    elsif($^O eq "solaris") { $platform = $object_model==64 ? "solaris_sparcv9" : "solaris_sparc" }
    elsif($^O eq "aix")     { $platform = $object_model==64 ? "aix_rs6000_64"   : "aix_rs6000" }
    elsif($^O eq "hpux")    { $platform = $object_model==64 ? "hpux_ia64"       : "hpux_pa-risc" }
    elsif($^O eq "linux")   { $platform = $object_model==64 ? "linux_x64"       : "linux_x86" }
    
    return $platform;
}
#======================================================================================== 
# 1 : if success
# 0 : otherwise
sub sendBM2SmT($$){
    my $self = shift;
    my ($rh, $type) = @_;
    
    # handle previous failures if any
    _processPrevFailures($self) if($self);
    
    unless($rh){
        warn("XBM::sendBM2SmT: $type invalid input arg");
        return 0;	
    }
    
    my $xml = _genBM2XML($rh);    
    unless($xml){
        warn("XBM::sendBM2SmT: $type failed to generate XML for rh");
        my $msg = dump($rh);
        dump($rh);
        errAlert("Failed in $type _genBM2XML. HASH:  $msg");
        return 0;	
    }
    
    unless(_callBM2Service($self, $xml, $type)){
        warn("XBM::sendBM2SmT: $type failed in _callBM2Service");
        my $msg = dump($rh);
        errAlert("Failed in $type _callBM2Service. HASH: $msg");
        return 0;	
    }
    warn("XBM::sendBM2SmT: successully sendBM2SmT $type");
    return 1;
}
#======================================================================================== 
# $rh : { testCaseName => [0|\d+] }, 0=pass, int > 0 then failed
# return:
#    1 - if success
#    0 - otherwise
sub uploadSmT($$$$){
    my $self = shift;
    my ($stream, $platform, $buildRevision, $rh) = @_;
    return _upload($self, $stream, $platform, $buildRevision, $rh, $TypeSmT);
} 
#======================================================================================== 
# return:
#    1 - if success
#    0 - otherwise
sub uploadBuild($$$$$){
    my $self = shift;
    my ($buildSystem, $stream, $platform, $buildRevision, $buildDate) = @_;
    return _upload($self, $stream, $platform, $buildRevision, $buildDate, $TypeBuild, $buildSystem);
} 
#======================================================================================== 
sub errAlert($){
    my($msg) = @_;
    my $subj = "[XBM Error from ".(hostname())."]";
    _sendEmail($Admin, $subj, $msg);
}
#======================================================================================== 
sub objGenErrBuild($$$$$$){
    my ($buildSystem, $stream, $platform, $buildRevision, $xvar, $backupRoot) = @_;
    my $xml;
    return 0 unless(_genXML($stream, $platform, $buildRevision, \$xml, $xvar, $buildSystem));
	 
    my $rds = _makeDirs($backupRoot);
    if(defined $rds->{$TypeBuild}){
	_backupFailures($rds->{$TypeBuild}, $xml);
    }
    else{
	my $err = "ERROR:XBM::objGenErrBuild: failed in back up for build $stream, $platform, $buildRevision, $xvar under $backupRoot";
	warn($err);
	errAlert($err);
    }
}
#======================================================================================== 
sub objGenErrSmT($$$$$){
    my ($stream, $platform, $buildRevision, $xvar, $backupRoot) = @_;
    my $xml;
    return 0 unless(_genXML($stream, $platform, $buildRevision, \$xml, $xvar));
	 
    my $rds = _makeDirs($backupRoot);
    if(defined $rds->{$TypeSmT}){
        _backupFailures($rds->{$TypeSmT}, $xml);
    }
    else{
	my $err = "ERROR:XBM::objGenErrSmT: failed in back up for build $stream, $platform, $buildRevision, $xvar under $backupRoot";
	warn($err);
	errAlert($err);
    }
}
#======================================================================================== 
sub objGenErrBM2SmTStart($$){
    my ($rh, $backupRoot) = @_;
    my $xml = _genBM2XML($rh);
    return 0 unless($xml);
    
    my $rds = _makeDirs($backupRoot);
    if(defined $rds->{$TypeBM2SmTStart}){
	_backupFailures($rds->{$TypeBM2SmTStart}, $xml);
    }
    else{
	my $err = "ERROR:XBM::objGenErrBM2SmTStart: failed in back up SmT start under $backupRoot. Hash: ".(dump($rh));
	warn($err);
	errAlert($err);
    }
}
#======================================================================================== 
sub objGenErrBM2SmTEnd($$){
    my ($rh, $backupRoot) = @_;
    my $xml = _genBM2XML($rh);
    return 0 unless($xml);
    
    my $rds = _makeDirs($backupRoot);
    if(defined $rds->{$TypeBM2SmTEnd}){
	_backupFailures($rds->{$TypeBM2SmTEnd}, $xml);
    }
    else{
	my $err = "ERROR:XBM::objGenErrBM2SmTEnd: failed in back up SmT end under $backupRoot. Hash: ".(dump($rh));
	warn($err);
	errAlert($err);
    }
}
#======================================================================================== 
# $xvar = build_date | $rh
# return:
#    1 - if success
#    0 - otherwise
sub _upload($$$$$$;$){
    my ($self, $stream, $platform, $buildRevision, $xvar, $type, $buildSystem) = @_;
    
    # handle previous failures if any
    _processPrevFailures($self) if($self);
    
    unless($self && $stream && $buildRevision && $platform && $xvar && $type){
        warn("WARNING:XBM::_upload: invalid inputs");
        return 0;	
    }
    
    unless(_isRevFine($buildRevision)){
        warn("WARNING:XBM::_upload: not an official build, skip uploading.");
        return 1;
    }
    
    $self->{stream}   = $stream;
    $self->{rev}      = $buildRevision;
    $self->{platform} = $platform;
    
    # xml
    my $xml;
    return 0 unless(_genXML($stream, $platform, $buildRevision, \$xml, $xvar, $buildSystem));
    
    # call BM Services
    return _callService($self, $xml, $type);   
} 
#======================================================================================== 
sub _callService($$$){
    my($self, $xml, $type) = @_;
    
    # ws
    unless(defined($self->{soap})){
        warn("WARNING:XBM::_callService: ws is not available.");	
    }
    else{
        if(_ws($self, $xml, $type)){
            warn("INFO:XBM::_callService: successfully uploaded results by ws.");	
            return 1;
        }
    }
    
    # fallback
    unless($self->{jms}){
         warn("ERROR:XBM::uploadBuild: failed and no jms fallback.");
         unless(errAlert("<XBM::_upload> failed on ws with no jms fallback for xml '$xml'")){
             warn("ERROR:XBM::_callService: failed to send out notification upon ws failure with jms fallback.");	
         }	
         
         # back up
         _backupFailures($self->{$type}, $xml);
         return 0;
    }
    
    warn("WARNING:XBM::_callService: switching to jms...");
    unless(_jms($self, $xml, $type)){
    	warn("ERROR:XBM::_upload: failed again. Email...");
    	unless(errAlert("<XBM build Reg Failure> BM client failed to upload results xml '$xml'")){
    	    warn("ERROR:XBM::_callService: failed to send out notification.");	
    	}
    	
    	# back up
        _backupFailures($self->{$type}, $xml);
    	return 0;
    }
    
    warn("INFO:XBM::_callService: successfully uploaded results by jms.");
    return 1;	
}
#======================================================================================== 
sub _callBM2Service($$$){
    my ($self, $xml, $type) = @_;

    unless(defined($self->{soap2})){
        warn("WARNING:XBM::_callBM2Service: ws is not available.");
        
        # back up
        _backupFailures($self->{$type}, $xml);
        return 0;	
    }

    unless(_ws2($self, $xml, $type)){
        warn("WARNING:XBM::_callBM2Service: failed to upload BM2 msg $type by ws.");
        
        # back up
         _backupFailures($self->{$type}, $xml);
        return 0;      	
    }
    
    warn("INFO:XBM::_callBM2Service: successfully uploaded BM2 msg $type by ws.");
    return 1;
}
#======================================================================================== 
# $xvar : [$date|$rh]
# return:
#    1 - if success
#    0 - otherwise
sub _genXML($$$$$;$){
    my ($stream, $platform, $rev, $rxml, $xvar, $buildSystem) = @_; 
    
    $$rxml = "\<\!\[CDATA\[ <root><build stream=\"$stream\" platform=\"$platform\" build_rev=\"$rev\" ";
    $$rxml .= "buildSystem=\"$buildSystem\" " if($buildSystem);
    
    # date
    if($xvar && ref($xvar) ne 'HASH' &&  _isDateFormat($xvar)){
    	#warn("xvar='$xvar'");
        $$rxml .= "build_date=\"$xvar\" ";
    }
    $$rxml .= " host=\"".(hostname())."\">";
    
    # 
    if($xvar && ref($xvar) eq 'HASH'){
        foreach my $tc (sort keys %$xvar){
    	    my $rc = $xvar->{$tc};
    	    #unless(defined($rc) && $rc =~ m<^[0|1]{1}$>){
    	    unless(defined($rc) && $rc =~ m<^\d+$>){
    	    	if($rc < 0){
    	            warn("ERROR:XBM::_genXML: invalid test results '$rc' detected for test case '$tc', stream='$stream', rev='$rev', platform='$platform'. Abort uploading.");
    	            return 0;
    	        }
    	        $rc = 1 if($rc > 0);	
    	    }
            $$rxml .= "<case name=\"$tc\">$rc</case>";	
        }
    }
    $$rxml .="</build></root> \]\]\>";
    return 1;
}
#======================================================================================== 
# xml : if success
# undef: if failed
sub _genBM2XML($){
    my ($rh) = @_; 
    
    unless($rh){
        warn("XBM::_genBM2XML: failed with invalid arg");
        return undef;	
    }

    
    my $xml = "\<\!\[CDATA\[ <root><smt> ";
    foreach my $e (keys %$rh){
        my $v = $rh->{$e};        
        if($e =~ m<cases>i ){
            foreach my $tc (keys %$v){
            	my $rc = $v->{$tc};
            	unless(defined ($rc) && $rc =~ m<^\d+$>){
            	    warn("ERROR:XBM::_genBM2XML: invalid test result '$rc' detected for test case '$tc'. Abort uploading.");
            	    return 0;
            	}
                $xml .= "<$BM2Element name=\"#". "$tc". "\" value=\"$rc\"/>";	
            }
        }
        else{
            $xml .= "<$BM2Element name=\"$e\" value=\"$v\"/>";
        }
    }
    $xml .= "</smt></root> \]\]\>";
    return $xml;
}
#======================================================================================== 
# return:
#    1 - if success
#    0 - otherwise
sub _ws($$$){
    my ($self, $xml, $type) = @_;

    eval{ $self->{soap}->BMWS($xml, $type); };	
    if($@){
	warn("ERROR:XBM::_ws: failed in using web service with msg: $@");
	return 0;	
    }
    
    return 1;
}
#======================================================================================== 
# return:
#    1 - if success
#    0 - otherwise
sub _ws2($$$){
    my ($self, $xml, $type) = @_;

#warn("calling bm2 ws with type($type) xml($xml)");
 
    eval{ $self->{soap2}->processRemoteSmT($xml, $type); };	
    if($@){
	warn("ERROR:XBM::_ws2: failed in using web service with msg: $@");
	return 0;	
    }
 
    
    return 1;
}
#======================================================================================== 
# return:
#    1 - if success
#    0 - otherwise
sub _jms($$$){
    my ($self, $xml, $type) = @_; 
    my $fxml = "$JmsDir/jms.txt";
    
    unless(open(OUT, ">$fxml")){
        warn("ERROR:XBM::_jms: failed to write jms msg with ERR: $!; $@; $?");
        return 0;	
    }
    $xml =~ s!\<\!\[CDATA\[!!i;
    $xml =~ s!\]\]\>$!!;
    print OUT $xml;
    close(OUT);
    
    my $cmd = "$self->{jms} $rTypes->{$type} \"$fxml\"";
    #warn("INFO:XBM::_jms: running cmd='$cmd'");
    my $rc = system($cmd);    
    if($rc != 0){
        warn("ERROR:XBM::_jms: failed with rc=$rc");
        return 0;	
    }	
    
    return 1;
}
#===============================================================
# return :
#    1 - if success
#    0 - otherwise
sub _sendEmail($$$;$){
    my($to, $subj, $msg, $rCC) = @_;
    
    $to =~ s!\]\s*\[!,!g;
    $to =~ s!^\s*\[\s*!!;
    $to =~ s!\s*\]\s*$!!;
    
    my $inf = "Email to $to";
    my $cc = $rCC && @$rCC ? join(',', @$rCC) : undef;
    $inf .= ", CC $cc" if($cc);
     
    my %mail = (
        To      => $to,
        From    => "RMTOOLS\@businessobjects.com",
        Subject => $subj,
        Message => $msg,
        Smtp 	=> 'mailhost.product.businessobjects.com'
    );
    
    $mail{CC} = $cc if($cc);    
   
    unless(sendmail(%mail)){
        my $err = "Failed to send email to $to. ";
        $err .= "cc $cc" if($cc);
        warn("ERROR:XBM::_sendMail: $err Email Err: ".$Mail::Sendmail::error." Msg: $msg");
        return 0;
    }
 
    return 1;   
}
#======================================================================================== 
# $rev must be positive integer.
sub _isRevFine($){
    my ($rev) = @_;
    return ($rev && $rev =~ m<^\d+$>) ? 1 : 0;	
}
#======================================================================================== 
# 2008-05-30 or 2008/05/30:00:00:00
sub _isDateFormat($){
    my ($d) = @_;
    return 0 unless($d);
    if($d =~ m!^\d{4}-\d{2}-\d{2}$!){
        return 1;	
    }
    elsif($d =~ m!^\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}:\d{2}$!){
    	return 1;
    }
    return 0;
}
#======================================================================================== 
sub _syncJre($$){
    my ($model, $p4proxy) = @_;
  
    unless(-d $Jre){
        eval{ mkpath($Jre); };
        if($@){
            warn("ERROR:XBM::_syncJre: failed to mkpath $Jre with ERR: $@; $!");
            return 0;	
        }	
    }
    
    my $platform = $^O; 
    if($platform eq "MSWin32")    { $platform = $model == 64 ? "win64_x64"       : "win32_x86";  }
    elsif($platform eq "solaris") { $platform = $model == 64 ? "solaris_sparcv9" : "solaris_sparc";  }
    elsif($platform eq "aix")     { $platform = $model == 64 ? "aix_rs6000_64"   : "aix_rs6000";  }
    elsif($platform eq "hpux")    { $platform = $model == 64 ? "hpux_ia64"       : "hpux_pa-risc"; }
    elsif($platform eq "linux")   { $platform = $model == 64 ? "linux_x64"       : "linux_x86";  }
 
    my $locJrt = $JreMap->{$platform};
    unless($locJrt) {
        warn("ERROR:XBM::_syncJre '$platform' is not supported.");
        return 0;	
    }
    
    my $p4Host   = hostname();
    my $p4Client = "BM_$p4Host";
    my $p4User   = "builder";
    my $p4Pwd    = "kamloops11";
    my $p4Prefix = "p4 -p $p4proxy -u $p4User -P $p4Pwd";
    my $p4CRoot  = abs_path($Jre);
    my $p4Depot  = "//depot2/Titan/Stable/External/JDK/$platform/$locJrt";
    my $p4_sync_success = ['up-to-date', 'updating', 'refreshing', 'added'];
                       
    open(BM, "| $p4Prefix client -i");
    print BM <<"_EOF_";
Client: $p4Client
Owner:  $p4User
Host:   $p4Host
Description:
        Autocreated by XBM.pm
Root:   $p4CRoot
Options:        allwrite clobber nocompress unlocked modtime normdir
LineEnd:        local
View:
        $p4Depot/... //$p4Client$p4CRoot/...
_EOF_
    close(BM);
       
   my $p4msg = `$p4Prefix -c $p4Client sync -f 2>&1`;
   unless(grep{$p4msg =~ m<$_>i} @$p4_sync_success){	
       warn("ERROR:XBM::_syncJre: failed in sync with p4 msg: $p4msg");
       return 0;	
   }
  
   return 1;
}
#======================================================================================== 
sub _processPrevFailures($){
    my($self) = @_;
#    -hanldeBM1FailureRecover($self, $TypeBuild);
#    _handleBM1FailureRecover($self, $TypeSmT);   
    _handleBM2FailureRecover($self, $TypeBM2SmTStart);
    _handleBM2FailureRecover($self, $TypeBM2SmTEnd);
}
#======================================================================================== 
sub _handleBM1FailureRecover($$){
    my ($self, $type) = @_;
    
    my $backupDir = $self->{$type} if(defined $self->{$type});
    if($backupDir && -d $backupDir && _hasPrevFailures($backupDir)){
    	opendir(DIR, $backupDir);
    	my @fs = readdir(DIR);
    	closedir(DIR);
    	
    	foreach my $f (sort @fs){
    	    next if($f eq '.' || $f eq '..');
	    my $xmlf = "$backupDir/$f";			
    	    if(-f $xmlf && ! -z $xmlf){
		unless(open(IN, "<$xmlf")){
		    warn("ERROR:XBM::processPrevFailures: failed to read $backupDir/$f with ERR: $?; $@");
		    next;
                }
		my $xml = "";
		while(<IN>){
		    chomp;
		    next if(m!^\s*$!);
		    $xml .= $_;
		}
		close(IN);
    	        unlink($xmlf) if($xml !~ m<^\s*$> &&_callService($self, $xml, $type));
    	    }	
        }
    }	
}
#======================================================================================== 
sub _handleBM2FailureRecover($$){
    my ($self, $type) = @_;
    my $dir;
    $dir = $self->{$type} if(defined $self->{$type});
    if($dir && -d $dir && _hasPrevFailures($dir)){
        opendir(DIR, $dir);
    	my @fs = readdir(DIR);
    	closedir(DIR);
    	
    	foreach my $f (sort @fs){
    	    next if($f eq '.' || $f eq '..');
    	    my $xmlf = "$self->{$type}/$f";			
    	    if(-f $xmlf && ! -z $xmlf){
	        unless(open(IN, "<$xmlf")){
		    warn("ERROR:XBM::processPrevFailures: failed to read $self->{$type}/$f with ERR: $?; $@");
		    next;
	        }
		my $xml = "";
		while(<IN>){
		    chomp;
		    next if(m!^\s*$!);
	            $xml .= $_;
		}
		close(IN);
    	        unlink($xmlf) if($xml !~ m<^\s*$> && _callBM2Service($self, $xml, $type));
    	    }		    		
    	} 
    }
}
#======================================================================================== 
sub _backupFailures($$){
    my ($dir, $xml) = @_;
    my $f = time;    
    unless(open(OUT, ">$dir/$f")){
        warn("ERROR:XBM::_backupFailure: failed to store failure with ERR: $@; $?; $!");
        return 0;	
    }
    print OUT $xml;
    close(OUT);
    return 1;
}
#======================================================================================== 
# returns:
# 1 - if has failures from previous
# 0 - otherwise
sub _hasPrevFailures($){
  my ($dir) = @_;
  return 0 if(! -d $dir);
 
  opendir(DIR, "$dir/");
  my @files = readdir(DIR);
  closedir(DIR);
  
  foreach my $f (@files){
     next if($f eq '.' || $f eq '..');
     return 1;	
  }
  
  return 0;
}
#======================================================================================== 
# make backup dirs
sub _makeDirs($){
    my($backupRoot) = @_;
	
    my $bdirs = {$TypeBuild => undef, $TypeSmT => undef, $TypeBM2SmTStart => undef, $TypeBM2SmTEnd => undef};
    return $bdirs unless($backupRoot && -d $backupRoot);
	
    my $backup_build = "$backupRoot/bm/buildInfo";
    $bdirs->{$TypeBuild} = $backup_build;
    unless(-d $backup_build){
        eval{ mkpath($backup_build);};
        if($@){
            warn("ERROR:XBM::_makeDirs: failed in mkpath $backup_build with ERR: $@");
	    $bdirs->{$TypeBuild} = undef;
        }
    }
    
    my $backup_smoke = "$backupRoot/bm/smokeInfo";
    $bdirs->{$TypeSmT} = $backup_smoke;
    unless(-d $backup_smoke){        
        eval{ mkpath($backup_smoke); };
        if($@){
            warn("ERROR:XBM::_makeDirs: failed in mkpath $backup_smoke with ERR: $@");
	    $bdirs->{$TypeSmT} = undef;
        }      
    }
    
    my $backup_smoke_bm2_start = "$backupRoot/bm2/$TypeBM2SmTStart";
    $bdirs->{$TypeBM2SmTStart} = $backup_smoke_bm2_start;
    unless(-d $backup_smoke_bm2_start){
        eval{
            mkpath($backup_smoke_bm2_start);
        };
        if($@){
            warn("ERROR:XBM::_makeDirs: failed in mkpath $backup_smoke_bm2_start with ERR: $@");
            $bdirs->{$TypeBM2SmTStart} = undef;	
        }	
    }
    
    my $backup_smoke_bm2_end = "$backupRoot/bm2/$TypeBM2SmTEnd";
    $bdirs->{$TypeBM2SmTEnd} = $backup_smoke_bm2_end;
    unless(-d $backup_smoke_bm2_end){
        eval{
            mkpath($backup_smoke_bm2_end);
        };
        if($@){
            warn("ERROR:XBM::_makeDirs: failed in mkpath $backup_smoke_bm2_end with ERR: $@");
            $bdirs->{$TypeBM2SmTEnd} = undef;	
        }	
    }
	
    return $bdirs;
}
#======================================================================================== 
sub DESTROY{
    my $self = shift;
    $self    = undef;
}
#======================================================================================== 
1;

