package sm_queries;
##############################################################################
##############################################################################
##### declare uses
# ensure code quality
use strict;
use warnings;
use diagnostics;
use Carp qw(cluck confess); # to use instead of (warn die)

# for the script itself
use JSON;
use Exporter;
use File::Path;
use File::stat;
use Time::Local;
use Data::Dumper;
use File::Basename;
use Sort::Versions;
use Store::CouchDB;
use Tie::Hash::Indexed;
use Date::Calc qw(Delta_Days);
# for Jira
use JIRA::REST;
use JIRA::Client::REST;
use JIRA::Client::Automated;



##############################################################################
##############################################################################
##### declare functions
sub sm_inits();
sub sm_get_current_date();
sub sm_get_couchdb_credentials();
sub sm_get_jira_credentials();
sub sm_get_couchdb_doc_ids();
sub sm_load_json_file($$);
sub sm_get_sprints();
sub sm_calculate_current_sprint();
sub sm_date_to_timestamp($$$$$$);
sub sm_get_project_infos();
sub sm_get_project_members();
sub sm_display_main_info();
sub sm_jira_wget_login();
sub sm_jira_perl_login_method1();
sub sm_jira_perl_login_method2();
sub sm_jira_perl_login_method3();
sub sm_jql($);
sub sm_wget_all_jira($$);
sub sm_wget_json_jira($);
sub sm_create_folders();
sub sm_get_queries($$);
sub sm_get_available_queries($);
sub sm_get_title_of_epicLink($);
sub sm_get_parent_title_of_epicLink($);

sub sm_start_script();
sub sm_end_script();


##############################################################################
##############################################################################
##### declare vars
use vars qw(
	@ISA
	@EXPORT
);
# vars to export
# paths
use vars qw (
	$BASE_SM_DIR
	$JSON_SM_DIR
	$OUTPUT_SM_DIR
	$LOG_SM_DIR
	$REPORTS_SM_DIR
	$URL_SM_REPORTS
	$CREDENTIALS_SM_DIR
);

# CouchDB
use vars qw(
	$CouchDB_Server
	$CouchDB_Admin_User
	$CouchDB_Admin_Password
	$CouchDB_DB
	%CouchDB_Documents
);

# Jira
use vars qw (
	$jira_Connexion_method1
	$jira_Connexion_method2
	$jira_Connexion_method3
	$jira_Url
	$jira_Admin_User
	$jira_Admin_Password
	$jira_Project_Members
	%jira_Sprints
	$From_Sprint
	$Current_Sprint
	$Current_Sprint_begin
	$Current_Sprint_end
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


## Options/Parameters
# options
use vars qw (
	$opt_debug
	$opt_force_login
);
# parameters
use vars qw (
	$param_project
	$param_site
	$param_this_jira
	$param_member
	$param_request
	$param_sprint
);



##############################################################################
##############################################################################
##### init vars
$BASE_SM_DIR        = $ENV{BASE_SM_DIR}        || "/build/pblack/gitHub/scrum";
$JSON_SM_DIR        = $ENV{JSON_SM_DIR}        || "/build/pblack/gitHub/scrum/scripts/json";
$OUTPUT_SM_DIR      = $ENV{OUTPUT_SM_DIR}      || "$BASE_SM_DIR/outputs";
$LOG_SM_DIR         = $ENV{LOG_SM_DIR}         || "$BASE_SM_DIR/logs";
$REPORTS_SM_DIR     = $ENV{REPORTS_SM_DIR}     || "$BASE_SM_DIR/reports";
$URL_SM_REPORTS     = $ENV{URL_SM_REPORTS}     || "tbd";
$CREDENTIALS_SM_DIR = $ENV{CREDENTIALS_SM_DIR} || "$BASE_SM_DIR/credentials";
$CouchDB_Server     = $ENV{COUCHDB_SERVER}     || "mo-60192cfe2.mo.sap.corp";



##############################################################################
##############################################################################
##### export vars/functions
@ISA = qw(Exporter);
@EXPORT = qw (
	$BASE_SM_DIR
	$JSON_SM_DIR
	$OUTPUT_SM_DIR
	$LOG_SM_DIR
	$REPORTS_SM_DIR
	$URL_SM_REPORTS
	$CREDENTIALS_SM_DIR
	$CouchDB_DB
	$jira_Url
	$jira_Connexion_method1
	$jira_Connexion_method2
	$jira_Connexion_method3
	$jira_Project_Members
	%jira_Sprints
	$From_Sprint
	$Current_Sprint
	$Current_Sprint_begin
	$Current_Sprint_end
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
	$opt_debug
	$opt_force_login
	$param_project
	$param_site
	$param_member
	$param_this_jira
	$param_request
	$param_sprint
	&sm_inits
	&sm_display_main_info
	&sm_load_json_file
	&sm_jql
	&sm_wget_all_jira
	&sm_wget_json_jira
	&sm_get_queries
	&sm_get_available_queries
	&sm_get_title_of_epicLink
	&sm_get_parent_title_of_epicLink
	&sm_jira_perl_login_method2
	&sm_jira_perl_login_method3
	&sm_start_script
	&sm_end_script
);



##############################################################################
##############################################################################
##### functions
sub sm_inits() {
	sm_get_current_date();
	sm_get_couchdb_doc_ids();
	sm_get_sprints();
	sm_calculate_current_sprint();
	sm_get_project_infos();
	sm_get_project_members();
	sm_get_jira_credentials();
	sm_create_folders();
	sm_jira_perl_login_method1();
	sm_jira_perl_login_method2();
	sm_jira_perl_login_method3();
	sm_jira_wget_login();
}

sub sm_get_current_date() {
	($Local_Sec,$Local_Min,$Local_Hour,$Local_Day,$Local_Month,$Local_Year)
		= localtime time ;
	$Local_Year = $Local_Year + 1900;
	$Local_Month++;
	#human readdable
	$display_Local_Sec   = ($Local_Sec   < 10) ? "0$Local_Sec"   : $Local_Sec;
	$display_Local_Min   = ($Local_Min   < 10) ? "0$Local_Min"   : $Local_Min;
	$display_Local_Hour  = ($Local_Hour  < 10) ? "0$Local_Hour"  : $Local_Hour;
	$display_Local_Day   = ($Local_Day   < 10) ? "0$Local_Day"   : $Local_Day;
	$display_Local_Month = ($Local_Month < 10) ? "0$Local_Month" : $Local_Month;
}

sub sm_get_couchdb_credentials() {
	my $purpose = lc $param_project;
	$CouchDB_Admin_User     = `prodpassaccess --credentials-root $CREDENTIALS_SM_DIR get couchdb.$purpose user`;
	chomp $CouchDB_Admin_User;
	$CouchDB_Admin_Password = `prodpassaccess --credentials-root $CREDENTIALS_SM_DIR get couchdb.$purpose password`;
	chomp $CouchDB_Admin_Password;
}

sub sm_get_jira_credentials() {
	my $purpose = lc $param_project;
	$jira_Admin_User     = `prodpassaccess --credentials-root $CREDENTIALS_SM_DIR get jira.$purpose user`;
	chomp $jira_Admin_User;
	$jira_Admin_Password = `prodpassaccess --credentials-root $CREDENTIALS_SM_DIR get jira.$purpose password`;
	chomp $jira_Admin_Password;
}

sub sm_get_couchdb_doc_ids() {
	my $json_file = "$JSON_SM_DIR/couchdb_documents.json";
	my $json_text = do {
	open(my $json_fh,"<:encoding(UTF-8)",$json_file)
		or confess "\n\nCan't open \$json_file\": $!\n\n";
		local $/;
		<$json_fh>
	};
	#my $json = JSON->new;
	my $json_data = decode_json($json_text);
	my $projects_HRef = $json_data->{projects};
	#print Dumper $projects_HRef;
	for my $this_project (@$projects_HRef) {
		if($this_project->{name} eq $CouchDB_DB) {
			foreach my $this_doc (@{$this_project->{documents}}) {
				my $item = $this_doc->{item};
				$CouchDB_Documents{$CouchDB_DB}{$item}{id}   = $this_doc->{id};
				$CouchDB_Documents{$CouchDB_DB}{$item}{file} = $this_doc->{file};
			}
			last;
		}
	}
}

sub sm_couchdb_get_doc($) {
	my ($this_doc) = @_;
	my $this_id = $CouchDB_Documents{$CouchDB_DB}{$this_doc}{id} ;
	eval {
		my $this_sc = Store::CouchDB->new();
		$this_sc->config({host => $CouchDB_Server , db => $CouchDB_DB});
		my $this_json_doc = $this_sc->get_doc( { id => $this_id, dbname => $CouchDB_DB } );
		return $this_json_doc;
	};
}

sub sm_load_json_file($$) {
	my ($this_json_file,$decoded_json) = @_;
	print "read $this_json_file\n" if($opt_debug);
	my $file_size = stat("$this_json_file")->size;
	if($file_size > 0) {
		if(open JSON,"$this_json_file") {
			$$decoded_json = decode_json(<JSON>);
			close JSON;
		}
	}
}

sub sm_get_sprints() {
	my $json_doc = sm_couchdb_get_doc("sprints");
	unless($json_doc) {
		my $this_json_file = "$JSON_SM_DIR/$CouchDB_Documents{$CouchDB_DB}{sprints}{file}";
		sm_load_json_file($this_json_file,\$json_doc);
	}
	#print Dumper $json_doc;
	$From_Sprint = ${$json_doc}{From};
	foreach my $this_sprint ( @{${$json_doc}{Sprints}} ) {
		my $sprint_name = $this_sprint->{sprint};
		$jira_Sprints{$sprint_name}{begin} = $this_sprint->{begin};
		$jira_Sprints{$sprint_name}{end}   = $this_sprint->{end};
	}
}

sub sm_calculate_current_sprint() {
	foreach my $this_sprint ( sort { versioncmp($b, $a) } keys %jira_Sprints ) {
		my ($sprint_begin_year,$sprint_begin_month,$sprint_begin_day)
			= split '-' , $jira_Sprints{$this_sprint}{begin} ;
		($sprint_begin_month) =~ s-^0--;
		($sprint_begin_day)   =~ s-^0--;
		my ($sprint_end_year,$sprint_endf_month,$sprint_end_day)
			= split '-' , $jira_Sprints{$this_sprint}{end};
		($sprint_endf_month) =~ s-^0--;
		($sprint_end_day)    =~ s-^0--;
		my $current_timpestamp = sm_date_to_timestamp($Local_Year        , $Local_Month        , $Local_Day        ,$Local_Hour,$Local_Min,$Local_Sec);
		my $timpestamp_begin   = sm_date_to_timestamp($sprint_begin_year , $sprint_begin_month , $sprint_begin_day ,0,0,0);
		my $timpestamp_end     = sm_date_to_timestamp($sprint_end_year   , $sprint_endf_month  , $sprint_end_day   ,23,59,59);
		if(($current_timpestamp >= $timpestamp_begin) && ($current_timpestamp <= $timpestamp_end)) {
			$Current_Sprint = $this_sprint;
			$Current_Sprint_begin = $jira_Sprints{$this_sprint}{begin};
			$Current_Sprint_end   = $jira_Sprints{$this_sprint}{end};
			last;
		}
	}
}

sub sm_date_to_timestamp($$$$$$) {
	my ($Year,$Month,$Day,$Hour,$Min,$Sec) = @_;
	$Month = $Month - 1;
	my @temps = ($Sec,$Min,$Hour,$Day,$Month,$Year);
	return timelocal @temps;
}

sub sm_get_project_infos() {
	my $json_doc = sm_couchdb_get_doc("infos");
	unless($json_doc) {
		my $this_json_file = "$JSON_SM_DIR/$CouchDB_Documents{$CouchDB_DB}{infos}{file}";
		sm_load_json_file($this_json_file,\$json_doc);
	}
	foreach my $this_project ( @{${$json_doc}{projects}{project}} ) {
		if ($this_project->{name} =~ /^$param_project$/i) {
			$jira_Url = $this_project->{URL} ;
			last;
		}
	}
}

sub sm_get_project_members() {
	my $json_doc = sm_couchdb_get_doc("members");
	unless($json_doc) {
		my $this_json_file = "$JSON_SM_DIR/$CouchDB_Documents{$CouchDB_DB}{members}{file}";
		sm_load_json_file($this_json_file,\$json_doc);
	}
	foreach my $this_site_href ( @{${$json_doc}{Sites}} ) {
		if($this_site_href->{name} =~ /^$param_site$/i) {
			foreach my $this_project_href ( keys %{$this_site_href->{projects}} ) {
				if($this_site_href->{projects}->{project} =~ /^$param_project$/i) {
					foreach my $this_members ( @{$this_site_href->{projects}->{members}} ) {
						$jira_Project_Members .= $this_members->{id} . ',';
					}
					($jira_Project_Members) =~ s/\,$//;
					last;
				}
			}
			last;
		}
	}
	$jira_Project_Members .= ",EMPTY" ;
}

sub sm_display_main_info() {
	print <<FIN_MAIN_INFO;

	Infos :
	=======
team site           : $param_site
jira url            : $jira_Url
jira project        : $param_project
jira team member(s) : $jira_Project_Members
from sprint : $From_Sprint
current sprint : $Current_Sprint
current sprint begin : $Current_Sprint_begin
current sprint end   : $Current_Sprint_end

FIN_MAIN_INFO
}

sub sm_jira_wget_login() {
	chdir "$BASE_SM_DIR";
	system "rm -f $BASE_SM_DIR/login.jsp*"; #file generated by the wget, no need to keep it
	my $cookie_file = "$BASE_SM_DIR/.jira_cookies_$jira_Admin_User.txt";
	my $goLogin = 0;
	# calculate if need to redo the cookie
	if($opt_force_login) {
		$goLogin = 1;
	} else {
		if( -e "$cookie_file" ) {
			if(open COOKIE,"$cookie_file") {
				# check not too old, check the month
				# Generated by Wget on 2014-05-28 14:05:52.
				while(<COOKIE>) {
					if(/^\#\s+Generated\s+by\s+Wget\s+on\s+(\d+)\-(\d+)\-(\d+)\s+/i) {
						my ($this_cookie_year,$this_cookie_month,$this_cookie_day) = ($1,$2,$3) ;
						($this_cookie_month) =~ s-^0--;
						($this_cookie_day)   =~ s-^0--;
						my $diff_in_days = Delta_Days($this_cookie_year,$this_cookie_month,$this_cookie_day, $Local_Year,$Local_Month,$Local_Day) ;
						if($diff_in_days > 7) { # if over than 1 week
							if($opt_debug) {
								print "$diff_in_days, need to recreate the cookie file\n";
							}
							$goLogin = 1
						}
						last;
					}
				}
				close COOKIE;
			} else {
				$goLogin = 1;
			}
		} else {
			$goLogin = 1;
		}
	}
	if($opt_force_login || ($goLogin == 1)) {
		my $wget_cmd = "wget --no-proxy --no-check-certificate"
					.  " --save-cookies $cookie_file"
					.  " --post-data=\"os_username=$jira_Admin_User&"
					.  "os_password=$jira_Admin_Password&"
					.  "os_cookie=true\""
					.  " $jira_Url/login.jsp"
		;
		local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
		system "$wget_cmd > $LOG_SM_DIR/$param_project/$param_site/login.log 2>&1";
		system "rm -f $BASE_SM_DIR/login.jsp*";
	}
}

sub sm_jira_perl_login_method1() {
	local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
	$jira_Connexion_method1 = JIRA::REST->new($jira_Url,$jira_Admin_User,$jira_Admin_Password);
}

sub sm_jira_perl_login_method2() {
	local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
	$jira_Connexion_method2 = JIRA::Client::Automated->new($jira_Url, $jira_Admin_User, $jira_Admin_Password);
}

sub sm_jira_perl_login_method3() {
	local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
	$jira_Connexion_method3 = JIRA::Client::REST->new(username => $jira_Admin_User, password => $jira_Admin_Password, url => $jira_Url);
}

sub sm_jql($) {
	my ($request) = @_;
	unless($jira_Connexion_method1) {
		sm_jira_perl_login_method1();
	}
	print "\njql : $request\n" if($opt_debug);
	my $search     = $jira_Connexion_method1->POST('/search', undef, {
		jql        => $request,
		startAt    => 0,
		maxResults => 8200,
	});
	if( scalar @{$search->{issues}} > 0 ) {
		undef $jira_Connexion_method1 ;
		return @{$search->{issues}} ;
	}
}

sub sm_wget_all_jira($$) {
	my ($this_list_of_jira,$this_filename)  = @_;
	my $full_filename = "$OUTPUT_SM_DIR/$param_project/$param_site/$this_filename.txt";
	system "rm -f \"$full_filename\"";
	system "cd $OUTPUT_SM_DIR/$param_project/$param_site/issues/ ; rm -f @$this_list_of_jira" ;
	if(open ALL_JIRA , ">$full_filename") {
		foreach my $this_issue (@$this_list_of_jira) {
			print ALL_JIRA "$jira_Url/rest/api/latest/issue/$this_issue\n";
		}
		close ALL_JIRA;
	
	}
	my $cookie_file = "$BASE_SM_DIR/.jira_cookies_$jira_Admin_User.txt";
	if ( ( ! -e "$cookie_file" ) or ($opt_force_login) ) {
		sm_jira_wget_login();
	}
	my $wget_cmd = "wget  --no-proxy --no-check-certificate --load-cookies"
				 . " $cookie_file"
				 . " -i $full_filename"
				 ;
	print "$wget_cmd >& $LOG_SM_DIR/$param_project/$param_site/downloads_$this_filename.log\n" if($opt_debug);
	system "cd $OUTPUT_SM_DIR/$param_project/$param_site/issues ; $wget_cmd >& $LOG_SM_DIR/$param_project/$param_site/downloads_$this_filename.log";
}

sub sm_wget_json_jira($) {
	my ($jira_id)  = @_;
	my $issues_dir = "$OUTPUT_SM_DIR/$param_project/$param_site/issues";
	if ( ! -e "$issues_dir") {
		mkpath "$issues_dir";
	}
	system "rm -f $issues_dir/$jira_id";
	my $cookie_file = "$BASE_SM_DIR/.jira_cookies_$jira_Admin_User.txt";
	if ( ( ! -e "$cookie_file" ) or ($opt_force_login) ) {
		sm_jira_wget_login();
	}
	my $wget_cmd = "wget  --no-proxy --no-check-certificate --load-cookies"
				.  " $cookie_file"
				.  " $jira_Url/rest/api/latest/issue/$jira_id"
				.  " -O $issues_dir/$jira_id"
				;
	print "\ncmd : $wget_cmd\n" if($opt_debug);
	system "touch $issues_dir/$jira_id.downloading";
	system "$wget_cmd >& /dev/null";
	system "rm -f $issues_dir/$jira_id.downloading";
}

sub sm_create_folders() {
	my @folders = qw(outputs logs reports);
	foreach my $this_folder ( @folders ) {
		if( ! -e "$BASE_SM_DIR/$this_folder/$param_project/$param_site") {
			mkpath "$BASE_SM_DIR/$this_folder/$param_project/$param_site";
		}
	}
}

sub sm_get_queries($$) {
	my ($this_item,$this_query) = @_;
	my $this_id = $CouchDB_Documents{$CouchDB_DB}{$this_item}{id} ;
	my $this_json_data;
	eval {
		my $this_sc = Store::CouchDB->new();
		$this_sc->config({host => $CouchDB_Server , db => $CouchDB_DB});
		$this_json_data = $this_sc->get_doc({ id => $this_id, dbname => $CouchDB_DB });
	};
	unless($this_json_data) {
		my $this_json_file = "$JSON_SM_DIR/$CouchDB_Documents{$CouchDB_DB}{$this_item}{file}";
		sm_load_json_file($this_json_file,\$this_json_data);
	}
	if($opt_debug) {
		print "\n\n==========\n";
		print Dumper $this_json_data;
		print "\n\n==========\n\n";
	}
	my $this_data;
	foreach my $this_project ( @{${$this_json_data}{projects}} ) {
		if( $this_project->{project} =~ /^$param_project$/i ) {
			foreach my $this_request ( @{$this_project->{requests}} ) {
				if( $this_request->{name} =~ /^$this_query$/i ) {
					my $nb_queries = 0;
					foreach my $this_jql ( @{$this_request->{request}} ) {
						$this_data->{$this_query}->[$nb_queries]{title} = $this_jql->{title};
						$this_data->{$this_query}->[$nb_queries]{label} = $this_jql->{label};
						$this_data->{$this_query}->[$nb_queries]{jql}   = $this_jql->{jql};
						$nb_queries++;
					}
					last;
				}
			}
			last;
		}
	}
	if($opt_debug) {
		print "\n\n==========\n";
		print Dumper $this_data;
		print "\n\n==========\n\n";
	}
	return $this_data if($this_data);
}

sub sm_get_available_queries($) {
	my ($this_query) = @_;
	my $json_doc = sm_couchdb_get_doc("available_queries");
	unless($json_doc) {
		my $this_json_file = "$JSON_SM_DIR/$CouchDB_Documents{$CouchDB_DB}{available_queries}{file}";
		sm_load_json_file($this_json_file,\$json_doc);
	}
	if($opt_debug) {
		print "\n\n==========\n";
		print Dumper $json_doc;
		print "\n\n==========\n\n";
	}
	return $json_doc if($json_doc);
}

sub sm_get_title_of_epicLink($) {
	my ($epic_link) = @_;
	my $title = "";
	if($epic_link) {
		my $request = "key = $epic_link";
		my @results = sm_jql($request);
		if( scalar @results > 0 ) {
			foreach my $THIS_sub_JIRA (@results) {
				next if($THIS_sub_JIRA->{'fields'}->{'summary'} =~ /\(Non\s+Jira\)/i);
				$title = $THIS_sub_JIRA->{'fields'}->{'customfield_15141'};
				last; # no need to loop
			}
		}
	}
	return $title if($title);
}

sub sm_get_parent_title_of_epicLink($) {
	my ($jira) = @_;
	my $label;
	my $request = "key = $jira";
	my @results = sm_jql($request);
	foreach my $THIS_sub_JIRA (@results) {
		if($THIS_sub_JIRA->{'fields'}->{'customfield_15140'}) {
			$label = sm_get_title_of_epicLink($THIS_sub_JIRA->{'fields'}->{'customfield_15140'}) ;
			last;
		}
	}
	return $label if($label);
}

sub sm_start_script() {
	print <<START_SCRIPT;

start of $0

START_SCRIPT
}

sub sm_end_script() {
	print <<END_SCRIPT;

end of $0

END_SCRIPT
	exit 0;
}


##############################################################################
##############################################################################
##############################################################################
1;
