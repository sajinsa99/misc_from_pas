#!/softs/perl/latest/bin/perl

##############################################################################
##############################################################################
##### declare uses
# ensure quality
#use strict;
use warnings;
use diagnostics;
use Carp qw(cluck confess); # to use instead of (warn die)

# for the script itself
use Sort::Versions;
use Data::Dumper;
use JSON;
use JSON::MaybeXS ();
use File::Path;


# opt/parameters
use Getopt::Long;

# personal uses
use sm_queries;



##############################################################################
##############################################################################
##### declare vars
use vars qw(
	$this_date
	$this_sprint
	$this_sprint_begin
	$this_sprint_end
);



##############################################################################
##############################################################################
##### declare subs
sub sm_queries($$$);
sub sm_write_json_file($$);
sub sm_display_list_issues_found($);
sub sm_clean_json_file($);



##############################################################################
##############################################################################
##### get options/parameters
$Getopt::Long::ignorecase = 0;
GetOptions(
	"prj=s"      =>\$param_project,
	"site=s"     =>\$param_site,
	"X"          =>\$opt_debug,
	"fl"         =>\$opt_force_login,
	"member=s"   =>\$param_member,
	"jira=s"     =>\$param_this_jira,
	"request=s"  =>\$param_request,
);



##############################################################################
##############################################################################
##### inits
$param_project ||= $ENV{SM_PROJECT} || "DTXMAKE";
$CouchDB_DB      = lc $param_project;
$param_site    ||= $ENV{SM_SITE}    || "LVL";



sm_inits();
$jira_Project_Members = ($param_member) ? $param_member : $jira_Project_Members ;



##############################################################################
##############################################################################
##### MAIN
sm_start_script();

sm_display_main_info();

if($param_this_jira) {
	$param_this_jira = uc $param_this_jira;
	my @list_jiras   = split ',' , $param_this_jira ;
	print "\n\tGet  Jira json file(s)\n";
	print   "\t======================\n";
	foreach my $this_jira (@list_jiras) {
		print "wget $this_jira\n";
		sm_wget_json_jira($this_jira);
		if( -e "$OUTPUT_SM_DIR/$param_project/$param_site/issues/$this_jira") {
			print "$param_this_jira downloaded, see $OUTPUT_SM_DIR/$param_project/$param_site/issues/$this_jira\n";
		}
	}
	print "\n";
	sm_end_script();
}

if($param_request) {
	my $queries_hRef = sm_get_available_queries($param_request);
	foreach my $this_query_hRef (  @{$queries_hRef->{projects}} ) {
		if($this_query_hRef->{project} =~ /$param_project/i) {
			foreach my $query (@{$this_query_hRef->{queries}}) {
				if($query->{label} =~ /$param_request/i) {
					if( (defined $query->{per_sprint}) && ($query->{per_sprint} eq "true") ) {
						my $flag = 0;
						foreach my $sprint_found ( sort { versioncmp($b, $a) } keys %jira_Sprints ) {
							$flag = 1 if($flag == 0 && ($sprint_found eq $Current_Sprint));
							next if($flag == 0);
							sm_queries($query->{title},$query->{label},$sprint_found);
							last if($sprint_found eq $From_Sprint);
						}
					} else {
						sm_queries($query->{title},$query->{label},$Current_Sprint);
					}
					last;
				}
			}
			last;
		}
	}
	exit;
}


sm_end_script();



##############################################################################
##############################################################################
##### functions
sub sm_queries($$$) {
	my ($this_title,$this_item,$self_sprint) = @_;
	print "in sm_queries\n" if($opt_debug);
	print "\n\t$this_title ($self_sprint)\n\n";
	my $queries_hRef   = sm_get_queries("queries",$this_item);
	$this_date         = $Local_Year . "-" . $display_Local_Month . "-" .$display_Local_Day ;
	$this_sprint       = $self_sprint;
	$this_sprint_begin = $jira_Sprints{$this_sprint}{begin} ;
	$this_sprint_end   = $jira_Sprints{$this_sprint}{end}   ;
	foreach my $this_query_hRef (  @{$queries_hRef->{$this_item}} ) {
		my $jql = $this_query_hRef->{jql} ;
		while($jql =~ /\$\{(.*?)\}/g) {
			my $Name = $1;
			$jql =~ s/\$\{$Name\}/${$Name}/ if(defined(${$Name}));
		}
		print "\t$this_query_hRef->{title}\n";
		my @results = sm_jql($jql);
		if( $results[0] > 0 ) {
			sm_display_list_issues_found(\@results) if($opt_debug);
			my $json_file_name = "${this_item}_$this_query_hRef->{label}" . "_$this_sprint";
			if( $this_item =~ /^$this_query_hRef->{label}$/i ) { # no need to have eg news_news
				sm_write_json_file("${this_sprint}_$this_item",\@results);
			} else {
				sm_write_json_file("${this_sprint}_${this_item}_$this_query_hRef->{label}",\@results);
			}
		} else {
			print "WARNING : no result for query: [$jql]\n";
			if( $this_item =~ /^$this_query_hRef->{label}$/i ) { # no need to have eg news_news
				sm_clean_json_file("${this_sprint}_$this_item");
			} else {
				sm_clean_json_file("${this_sprint}_${this_item}_$this_query_hRef->{label}");
			}
		}
	}
}

sub sm_write_json_file($$) {
	my ($filename,$this_jiras_list) = @_;
	my $data;
	my $nb_elem = 0 ;
	foreach my $this_jira (@$this_jiras_list) {
		$data->{jiras}[$nb_elem]{key} = $this_jira->{key};
		$nb_elem++;
	}
	my $json = JSON::MaybeXS->new(utf8 => 1, pretty => 1);
	my $data_json = $json->encode($data);
	my $fh;
	if ( ! -e "$OUTPUT_SM_DIR/$param_project/$param_site/status") {
		mkpath "$OUTPUT_SM_DIR/$param_project/$param_site/status" ;
	}
	my $data_json_file = "$OUTPUT_SM_DIR/$param_project/$param_site/status/$filename";
	if($param_member) {
		$data_json_file .= "_$param_member";
	}
	$data_json_file .= ".json";
	unlink $data_json_file if ( -e "$data_json_file" ) ;
	if(open   $fh , ">", "$data_json_file") {
		print $fh $data_json;
		close $fh;
	}
	my @list_jira = ();
	foreach my $this_jira (@$this_jiras_list) {
		push @list_jira , $this_jira->{key};
	}
	sm_wget_all_jira(\@list_jira,$filename);
	#foreach my $this_jira (@$this_jiras_list) {
	#	my $jira_key = $this_jira->{key};
	#	unless ( -e "$OUTPUT_SM_DIR/$param_project/$param_site/issues/$jira_key.downloading") { # if no download ongoing by another run
	#		sm_wget_json_jira($jira_key);
	#	}
	#}
	print "$data_json_file created\n";
}

sub sm_clean_json_file($) {
	my ($filename) = @_;
	my $data_json_file = "$OUTPUT_SM_DIR/$param_project/$param_site/status/$filename.json";
	print "clean $data_json_file\n";
	system "rm -f \"$data_json_file\"";
}

sub sm_display_list_issues_found($) {
	my ($this_jiras_list) = @_;
	print "\n";
	my $nb_elem = 1;
	foreach my $this_jira (@$this_jiras_list) {
		print "$nb_elem |$this_jira->{key} | $this_jira->{'fields'}->{'summary'} | https://sapjira.wdf.sap.corp/browse/$this_jira->{key}\n";
		$nb_elem++;
	}
	print "\n";
}
