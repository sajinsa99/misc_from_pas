package sm;
##############################################################################
##############################################################################
##### declare uses
use warnings;
use diagnostics;
use Carp qw(cluck confess); # to use instead of (warn die)

use JSON;

use Exporter;

use JIRA::REST;
use JIRA::Client::Automated;

use File::Path;
use File::stat;

use Time::Local;

use Tie::Hash::Indexed;


##############################################################################
##############################################################################
##### declare functions
sub sap_sm_force_rm($);
sub sap_sm_mask_and_read_password($);
sub sap_sm_get_iNumbers();
sub sap_sm_get_password();
sub sap_sm_jira_perl_login();
sub sap_jira_login2();
sub sap_sm_jira_wget_login();
sub sap_sm_jql($);
sub sap_sm_rewrite_html($);
sub sap_sm_get_takt_dates();
sub sap_sm_calc_current_takt();
sub sap_sm_date_to_timestamp($$$$$$);

sub sap_sm_wget_json_jira($$$);
sub sap_sm_wget_multiples_json_jira($$);
sub sap_sm_read_json_jira($$$);
sub sap_sm_list_epics();



##############################################################################
##############################################################################
##### declare vars
# vars to export
#paths
use vars qw (
    $WORKDIR
    $OUTPUTS_LOGS
    $OUTPUTS_JIRAS
    $OUTPUTS_STO
    $OUTPUTS_CS
    $OUTPUTS_REPORTS
    $OUTPUTS_NOTES
    $HTTP_SM_URL
    $SITE
);
#jira
use vars qw (
    $jira_Connexion
    $jira_Connexion2
    $jira_Url
    $jira_User
    $jira_Password
    $wget_credentials
    $currentTakt
    %CurrentTakt
    %Takts
    %JiraINumbers
    %Components
    %fixVersions
);
#parameters/options
use vars qw (
    $opt_RefreshData
    $param_Takt
    $opt_Open
    $opt_Closed
    $opt_RTS
    $opt_FJC
    $opt_CurrentSprint
    $opt_WholeStatus
    $opt_No_mail
    $opt_Epics
    $param_TaktFrom
    $param_TaktTo
    $opt_JiraUser
    $opt_ForceLogin
    $param_JIRA_PRJ
    $param_This_Jira
    $opt_Watchers
);


#date/time
use vars qw (
    $Local_Sec
    $Local_Min
    $Local_Hour
    $Local_Day
    $Local_Month
    $Local_Year
    $display_Local_Sec
    $display_Local_Min
    $display_Local_Hour
    $display_Local_Day
    $display_Local_Month
);

##############################################################################
##############################################################################
##### init vars
@ISA = qw(Exporter);
@EXPORT = qw (
    $WORKDIR
    $OUTPUTS_LOGS
    $OUTPUTS_JIRAS
    $OUTPUTS_STO
    $OUTPUTS_CS
    $OUTPUTS_REPORTS
    $OUTPUTS_NOTES
    $HTTP_SM_URL
    $SITE
    $jira_Connexion
    $jira_Connexion2
    $jira_Url
    $jira_User
    $jira_Password
    $wget_credentials
    %Takts
    %JiraINumbers
    %Components
    %fixVersions
    $currentTakt
    %CurrentTakt
    $opt_RefreshData
    $param_Takt
    $opt_Open
    $opt_Closed
    $opt_RTS
    $opt_FJC
    $opt_CurrentSprint
    $opt_WholeStatus
    $opt_Alerts
    $opt_No_mail
    $opt_Epics
    $param_TaktFrom
    $param_TaktTo
    $opt_JiraUser
    $opt_ForceLogin
    $param_JIRA_PRJ
    $param_This_Jira
    $opt_Watchers
    $Local_Sec
    $Local_Min
    $Local_Hour
    $Local_Day
    $Local_Month
    $Local_Year
    $display_Local_Sec
    $display_Local_Min
    $display_Local_Hour
    $display_Local_Day
    $display_Local_Month
    &sap_sm_force_rm
    &sap_sm_mask_and_read_password
    &sap_sm_get_password
    &sap_sm_jira_perl_login
    &sap_jira_login2
    &sap_sm_jira_wget_login
    &sap_sm_jql
    &sap_sm_rewrite_html
    &sap_sm_wget_json_jira
    &sap_sm_wget_multiples_json_jira
    &sap_sm_read_json_jira
    &sap_sm_list_epics
);

$param_JIRA_PRJ ||="DTXMAKE";

$WORKDIR = $ENV{SM_WORKDIR} || "/build/pblack/gitHub/i051566/scrum-reports" ;

$OUTPUTS_LOGS    ||= "$WORKDIR/outputs/logs" ;
$OUTPUTS_JIRAS   ||= "$WORKDIR/outputs/JIRAS" ;
$OUTPUTS_STO     ||= "$WORKDIR/outputs/sto" ;
$OUTPUTS_CS      ||= "$WORKDIR/outputs/cs" ;
$OUTPUTS_REPORTS ||= "$WORKDIR/www/Reports" ;
$OUTPUTS_NOTES   ||= "$WORKDIR/www/Reports/notes" ;

$HTTP_SM_URL = $ENV{HTTP_SM_URL}
             || "http://mo-60192cfe2.mo.sap.corp:8888"
             ;

$SITE = $ENV{SITE} || "Walldorf";

$jira_Url = "https://sapjira.wdf.sap.corp";
$jira_Password   ||= sap_sm_get_password();
$wget_credentials = "--no-check-certificate"
                  . " --load-cookies"
                  . " $WORKDIR/jira_cookies_$jira_User.txt -p"
                  ;

sap_sm_get_iNumbers();

($Local_Sec,$Local_Min,$Local_Hour,$Local_Day,$Local_Month,$Local_Year)
    = localtime time
    ;
$Local_Year = $Local_Year + 1900;
$Local_Month++;
$display_Local_Sec   = ($Local_Sec   < 10) ? "0$Local_Sec"   : $Local_Sec;
$display_Local_Min   = ($Local_Min   < 10) ? "0$Local_Min"   : $Local_Min;
$display_Local_Hour  = ($Local_Hour  < 10) ? "0$Local_Hour"  : $Local_Hour;
$display_Local_Day   = ($Local_Day   < 10) ? "0$Local_Day"   : $Local_Day;
$display_Local_Month = ($Local_Month < 10) ? "0$Local_Month" : $Local_Month;
sap_sm_get_takt_dates();
sap_sm_calc_current_takt();



##############################################################################
##############################################################################
##### my functions
sub sap_sm_force_rm($) {
    my ($file) = @_ ;
    sleep 1;
    system "rm -vf $file > $OUTPUTS_LOGS/deletes.log 2>&1";
    sleep 1;
}

sub sap_sm_mask_and_read_password($) {
    my ($msg) = @_ ;

    my $stty = `which stty`;
    chomp $stty;
    if ($^O eq "MSWin32") {
        $stty = "c:/cygwin/bin/stty";
    }

    print "$msg :";
    system $stty, '-echo';  # Disable echoing
    my $password = <STDIN>;
    chomp $password;
    system $stty, 'echo';   # Turn it back on
    print "\n";
    return $password;
}

sub sap_sm_get_password() {
    return "" if($^O =~ /^MSWin32$/i );
    $jira_User = `prodpassaccess get jira user`;
    chomp $jira_User;
    $jira_User ||= "perforce";
    my $password = `prodpassaccess get jira password`;
    chomp $password;
    if($password) {
        return $password
    }  else  {
        confess "\nERROR : no password found.\n\n";
    }
}

sub sap_sm_jira_wget_login() {
    $jira_Password ||= sap_sm_get_password();
    chdir "$WORKDIR";
    my $goLogin = 0;
    $goLogin = 1 if( ! -e "$WORKDIR/jira_cookies_$jira_User.txt" );
    if( -e "$WORKDIR/jira_cookies_$jira_User.txt" ) {
        if(open COOKIE,"$WORKDIR/jira_cookies_$jira_User.txt") {
            # check not too old, check the month
            # Generated by Wget on 2014-05-28 14:05:52.
            while(<COOKIE>) {
                if(/^\#\s+Generated\s+by\s+Wget\s+on\s+(\d+)\-(\d+)\-(\d+)\s+/i) {
                    my $month = $2;
                    $goLogin = 1 if($month ne $display_Local_Month );
                    last;
                }
            }
            close COOKIE;
        }
    }
    if($opt_ForceLogin || ($goLogin == 1)) {
        sap_sm_force_rm("$WORKDIR/login.jsp*");
        my $wget_cmd = "wget --no-proxy --no-check-certificate"
                     . " --save-cookies $WORKDIR/jira_cookies_$jira_User.txt"
                     . " --post-data=\"os_username=$jira_User&"
                     . "os_password=$jira_Password&"
                     . "os_cookie=true\""
                     . " $jira_Url/login.jsp"
                     ;
		local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
        system "$wget_cmd > $OUTPUTS_LOGS/login.log 2>&1";
        sap_sm_force_rm("$WORKDIR/login.jsp*");
    }
}

sub sap_sm_jira_perl_login() {
    local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
    $jira_Connexion = JIRA::REST->new($jira_Url,$jira_User,$jira_Password);
}

sub sap_jira_login2() {
	local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
	$jira_Connexion2 = JIRA::Client::Automated->new($jira_Url, $jira_User, $jira_Password);
}

sub sap_sm_jql($) {
    my ($request) = @_;
    sap_sm_jira_perl_login();
    my $search = $jira_Connexion->POST('/search', undef, {
        jql        => $request,
        startAt    => 0,
        maxResults => 1030,
    });
    return @{$search->{issues}} if( @{$search->{issues}} );
}

sub sap_sm_rewrite_html($) {
    my ($HTMLFile) = @_;
    if(open HTML,"$HTMLFile") {
        if(open OUT,">$HTMLFile.new") {
            while(<HTML>) {
                my $line = $_;
                print OUT "$line";
                last if($line =~ /\<\/html\>/i);
            }
            close OUT;
        }
        close HTML;
        rename "$HTMLFile.new","$HTMLFile";
    }
}

sub sap_sm_get_takt_dates() {
    if(open TAKTS,"$WORKDIR/takts.txt") {
        tie %Takts, 'Tie::Hash::Indexed';
        my $takt;
        my $start = 0;
        $taktFrom = 0;
        while(<TAKTS>) {
            chomp;
            next if(/^\#/); #skip comments
            next unless($_);
            $taktFrom = 1 if(/^\<\<\<takt\s+from/i);
            if(/^takt\=(.+?)$/i)  { $takt = $1 }
            if(/^begin\=(.+?)$/i) { $Takts{$takt}{begin} = $1 }
            if(/^end\=(.+?)$/i)   {
                $Takts{$takt}{end} = $1 ;
                undef $takt ;
                $start++;
            }
            $param_TaktFrom = $takt if(($takt) && ($taktFrom == 0));
        }
        close TAKTS;
    }
}

sub sap_sm_calc_current_takt() {
    my $found = 0;
    foreach my $thisTakt (keys %Takts) {
        my ($taktBeginYear,$taktBeginMonth,$taktBeginDay)
           = split '-',$Takts{$thisTakt}{begin};
        ($taktBeginMonth) =~ s-^0--;
        ($taktBeginDay)   =~ s-^0--;
        my ($taktEndYear,$taktEndMonth,$taktEndDay)
           = split '-',$Takts{$thisTakt}{end};
        ($taktEndMonth) =~ s-^0--;
        ($taktEndDay)   =~ s-^0--;
        my $timpestamp_begin   = sap_sm_date_to_timestamp($taktBeginYear,$taktBeginMonth,$taktBeginDay,0,0,0);
        my $timpestamp_end     = sap_sm_date_to_timestamp($taktEndYear,$taktEndMonth,$taktEndDay,23,59,59);
        my $current_timpestamp = sap_sm_date_to_timestamp($Local_Year,$Local_Month,$Local_Day,$Local_Hour,$Local_Min,$Local_Sec);
        if(($current_timpestamp >= $timpestamp_begin) && ($current_timpestamp <= $timpestamp_end)) {
            $currentTakt = $thisTakt;
            $CurrentTakt{$currentTakt}{begin} = $Takts{$currentTakt}{begin};
            $CurrentTakt{$currentTakt}{end}   = $Takts{$currentTakt}{end};
            last;
        }
    }
}

sub sap_sm_date_to_timestamp($$$$$$) {
    my ($Year,$Month,$Day,$Hour,$Min,$Sec) = @_;
    $Month = $Month - 1;
    my @temps = ($Sec,$Min,$Hour,$Day,$Month,$Year);
    return timelocal @temps;
}

sub sap_sm_get_iNumbers() {
    if(open INUMBERS,"$WORKDIR/${SITE}_iNumbers.txt") {
        while(<INUMBERS>) {
            chomp;
            next unless($_);
            next if(/^\;/); #skip comment
            my ($iNumber,$realFullName) = split ':',$_;
            $JiraINumbers{$iNumber} = $realFullName;
        }
        close INUMBERS;
    }
}

sub sap_sm_wget_multiples_json_jira($$) {
	my ($jiraPrj,$file) = @_;
	$opt_ForceLogin = 1;
	sap_sm_jira_wget_login();
	my $wget_cmd = "wget  --no-proxy --no-check-certificate --load-cookies"
                     . " $WORKDIR/jira_cookies_$jira_User.txt"
                     . " -i $file"
                     ;
    print "$wget_cmd\n";
    system "cd $OUTPUTS_JIRAS/$jiraPrj/ ; $wget_cmd >& $OUTPUTS_LOGS/downloads.log ";
}


sub sap_sm_wget_json_jira($$$) {
    my ($JiraID,$jiraPrj,$decoded_json) = @_;
    if ( ! -e "$OUTPUTS_JIRAS/$jiraPrj") {
        mkpath "$OUTPUTS_JIRAS/$jiraPrj";
    }
    sap_sm_force_rm("$OUTPUTS_JIRAS/$jiraPrj/$JiraID");
    sap_sm_jira_wget_login() if($opt_ForceLogin);
    my $wget_cmd = "wget  --no-proxy --no-check-certificate --load-cookies"
                 . " $WORKDIR/jira_cookies_$jira_User.txt"
                 . " $jira_Url/rest/api/latest/issue/$JiraID"
                 . " -O $OUTPUTS_JIRAS/$jiraPrj/$JiraID"
                 ;
    #print "$wget_cmd\n";
    system "$wget_cmd >& /dev/null";
    my $file_size = stat("$OUTPUTS_JIRAS/$jiraPrj/$JiraID")->size;
    if($file_size > 0) {
        if(open JSON,"$OUTPUTS_JIRAS/$jiraPrj/$JiraID") {
            $$decoded_json = decode_json(<JSON>);
            close JSON;
        }
    }
}

sub sap_sm_read_json_jira($$$) {
	my ($JiraID,$jiraPrj,$decoded_json) = @_;
	#print "debug : $JiraID,$jiraPrj\n";
    my $file_size = stat("$OUTPUTS_JIRAS/$jiraPrj/$JiraID")->size;
    if($file_size > 0) {
        if(open JSON,"$OUTPUTS_JIRAS/$jiraPrj/$JiraID") {
            $$decoded_json = decode_json(<JSON>);
            close JSON;
        }
    }
}

sub sap_sm_list_epics() {
    my $request = "project = $param_JIRA_PRJ AND type = epic ORDER BY key DESC";
    my @results = sap_sm_jql($request);
    my %json_output ;
    foreach my $THIS_EPIC (@results) {
        if( $THIS_EPIC->{'fields'}->{'customfield_15141'} ) {
            my $id = $THIS_EPIC->{'key'} ;
            $json_output{epics}{$id} = $THIS_EPIC->{'fields'}->{'customfield_15141'} ;
        }
    }
    my $json_file_out = "$OUTPUTS_JIRAS/$param_JIRA_PRJ/epics.json";
    #print "create json file\n";
    open my $fh, ">", $json_file_out;
        print $fh encode_json \%json_output;
    close $fh;
}

1;
