#!/usr/bin/perl -w

use Date::Calc(qw(Today_and_Now Delta_DHMS Add_Delta_Days Add_Delta_DHMS Day_of_Week Week_of_Year));
use GD::Graph::mixed;
use Sys::Hostname;
use Time::Local;
use File::Copy;
use File::Path;
use File::Find;
use Net::SMTP;

use FindBin;
use lib ($FindBin::Bin);
$CURRENT_DIR = $FindBin::Bin;
system("p4 print -o $CURRENT_DIR/DAM.pm //internal/cis/1.0/REL/cgi-bin/DAM.pm");
our($DROP_DIR, $DAM_DIR);
require DAM;
DAM->import();

$ENV{SMTP_SERVER} ||= "mail.sap.corp";
$SMTPFROM = $SMTPTO = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
$SMTPTO = 'jean.maqueda@sap.com';
$NumberOfEmails = 0;
$HOST = hostname();
#$SIG{__DIE__} = sub { SendMail(@_); die(@_) };
#$SIG{__WARN__} = sub { SendMail(@_); warn(@_) };

##############
# Parameters #
##############

die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
$JobFile = "$CURRENT_DIR/documentation.txt";
@Today = localtime();
$Date = sprintf("%4d.%02d.%02d", $Today[5]+1900, $Today[4]+1, $Today[3]);
$TodayAt0h00 = timelocal(0, 0, 0, @Today[3..5]);
$TodayAt9h00 = timelocal(0, 0, 9, @Today[3..5]);
$TodayAt24h00 = timelocal(59, 59, 23, @Today[3..5]);
$LastWeekAgo = timelocal(@Today)-7*24*60*60;
$METEO_HREF = 'http://pard30011629a:3000';
# $Projects{$Project} = [$Title, $DocumentBase]
foreach my $Project (keys(%{$PROJECTS{documentation}})) { $Projects{$Project} = [@{${$PROJECTS{documentation}}{$Project}}] } 

########
# Main #
########

@Start = Today_and_Now();
$NumberOfProjectsOnDemand = $NumberOfProjects = $NumberOfDITAProjects = $NumberOfNonDITAProjects = 0;
$NumberOfDocuments = $NumberOfExpectedDocuments = $NumberOfImpactedDocuments = 0;
$NumberOfDITAExpectedDocuments = $NumberOfDITAImpactedDocuments = 0;
$NumberOfNonDITAExpectedDocuments = $NumberOfNonDITAImpactedDocuments = 0;
$NumberOfModifiedProjects = $NumberOfDITAModifiedProjects = $NumberOfNonDITAModifiedProjects = 0;
$NumberOfProjectsOnTime = $NumberOfDITAProjectsOnTime = $NumberOfNonDITAProjectsOnTime = 0;
$NumberOfProjectsOnDay = $NumberOfDITAProjectsOnDay = $NumberOfNonDITAProjectsOnDay = 0;
$NumberOfNothingToDoProjects = $NumberOfNothingToDoProjectsOnTime = $NumberOfNothingToDoProjectsOnDay  = 0;
$NumberOfDITANothingToDoProjects = $NumberOfDITANothingToDoProjectsOnTime = $NumberOfDITANothingToDoProjectsOnDay  = 0;
$NumberOfNonDITANothingToDoProjects = $NumberOfNonDITANothingToDoProjectsOnTime = $NumberOfNonDITANothingToDoProjectsOnDay  = 0;
system("p4 print -o $JobFile //depot2/Main/Stable/Build/shared/jobs/documentation.txt");
open(JOB, $JobFile) or die("ERROR: cannot open '$JobFile': $!");
while(<JOB>)
{
    next unless(my($Host, $Project) = /^\[([^\.]+)\.\w+?\.(\w+)\./);
    next unless(exists($Projects{$Project}));
    my($BuildNumber, $NbOfExpectedDocuments, $NbOfImpactedDocuments, $TextMLServer) = (0, 0, 0, '');
    print("$Project\n");
    opendir(BUILD, "$DAM_DIR/$Project") or warn("ERROR: cannot open '$DAM_DIR/$Project': $!");
    while(defined($Build = readdir(BUILD)))
    {
        next unless(my($BuildNb) = $Build =~ /^${Project}_(\d{5})$/);
        my $OutputStatus = -e "$DAM_DIR/$Project/$Build/$Build=${DEFAULT_PLATFORM}_release_outputstatus_1.dat" ? "$DAM_DIR/$Project/$Build/$Build=${DEFAULT_PLATFORM}_release_outputstatus_1.dat" : "$DAM_DIR/$Project/$Build/$Build=${DEFAULT_PLATFORM}_debug_outputstatus_1.dat";
        if(open(DAT, $OutputStatus))
        {
            print("\t$Build\n");
            my %Status;
            eval <DAT>;
            close(DAT);
            if($Status{requester} eq 'buildondemand')
            {
                next unless($Status{start}>$LastWeekAgo);
                push(@OnDemandBuilds, [$Host, $Project, ${$Projects{$Project}}[0], $Status{textmlserver}, ${$Projects{$Project}}[1], $BuildNb, $Status{start}, $Status{stop}, $Status{NumberOfDocuments}]);
                $NumberOfProjectsOnDemand++;
                next;
            }
            ($NbOfImpactedDocuments, $NbOfExpectedDocuments) = split('/', $Status{impactedoutputs});
            $TextMLServer = $Status{textmlserver};
        } else { warn("ERROR: cannot open '$OutputStatus': $!") }
        $BuildNumber = $BuildNb if($BuildNb > $BuildNumber);
    }
    closedir(BUILD);
    next unless($BuildNumber);
    $NumberOfProjects++;
    $NumberOfExpectedDocuments += $NbOfExpectedDocuments;
    $NumberOfImpactedDocuments += $NbOfImpactedDocuments;
    if(${$Projects{$Project}}[1] eq 'dita') { $NumberOfDITAProjects++; $NumberOfDITAExpectedDocuments+=$NbOfExpectedDocuments; $NumberOfDITAImpactedDocuments+=$NbOfImpactedDocuments }
    else { $NumberOfNonDITAProjects++; $NumberOfNonDITAExpectedDocuments+=$NbOfExpectedDocuments; $NumberOfNonDITAImpactedDocuments+=$NbOfImpactedDocuments }

    my($Start, $Stop, $FetchStart, $FetchStop, $IsInProgress, $IsNothingToDo) = (0xFFFFFFFF, 0, 0, 0, 1, 0);
    my $BuildName = "${Project}_$BuildNumber";
    if(-f "$DAM_DIR/$Project/NothingToDo.dat")
    {
        my @NothingToDo;
        open(DAT, "$DAM_DIR/$Project/NothingToDo.dat") or warn("ERROR: cannot open '$DAM_DIR/$Project/NothingToDo.dat': $!");
        eval(<DAT>);
        close(DAT);
        if($NothingToDo[0]>=$TodayAt0h00)
        {
            $Start = $Stop = $NothingToDo[0];
            ($IsInProgress, $IsNothingToDo) = (0, 1);
            $NumberOfNothingToDoProjects++;
        }
    }
    unless($IsNothingToDo)
    {
        my $Infra = -e "$DAM_DIR/$Project/$BuildName/$BuildName=${DEFAULT_PLATFORM}_release_infra_1.dat" ? "$DAM_DIR/$Project/$BuildName/$BuildName=${DEFAULT_PLATFORM}_release_infra_1.dat" : "$DAM_DIR/$Project/$BuildName/$BuildName=${DEFAULT_PLATFORM}_debug_infra_1.dat";
        if(open(DAT, $Infra))
        {
            my @Errors;
            eval <DAT>;
            close(DAT);
            foreach(@Errors[1..$#Errors])
            {
                my($Errors, $Log, $Summary, $Area, $Strt, $Stp) = @{$_};
                $Start = $Strt if($Strt < $Start);
                $Stop = $Stp if($Stp > $Stop);
                ($FetchStart, $FetchStop) = ($Strt, $Stp) if($Area eq 'prefetch_step');
                $IsInProgress = 0 if($Area eq 'smoke_step');
            }                
        } else { warn("ERROR: cannot open '$Infra': $!") }
    }
    my $IsProjectOnTime = (($IsNothingToDo or !$IsInProgress) && $Start>=$TodayAt0h00 && $Stop<=$TodayAt9h00) ? 1 : 0;
    my $IsProjectOnDay = (($IsNothingToDo or !$IsInProgress) && $Start>=$TodayAt0h00 && $Stop<=$TodayAt24h00) ? 1 : 0;
    my $IsNothingToDoProjectOnTime = ($IsNothingToDo && $Start>=$TodayAt0h00) ? 1 : 0; # a ameliorer
    my $IsNothingToDoProjectOnDay = ($IsNothingToDo && $Start>=$TodayAt0h00) ? 1 : 0;
    $NumberOfProjectsOnTime++ if($IsProjectOnTime);
    $NumberOfProjectsOnDay++ if($IsProjectOnDay);
    $NumberOfNothingToDoProjectsOnTime++ if($IsNothingToDoProjectOnTime);
    $NumberOfNothingToDoProjectsOnDay++ if($IsNothingToDoProjectOnDay);
    if(${$Projects{$Project}}[1] eq 'dita') { $NumberOfDITAProjectsOnTime++ if($IsProjectOnTime); $NumberOfDITAProjectsOnDay++ if($IsProjectOnDay); $NumberOfDITANothingToDoProjects++ if($IsNothingToDo); $NumberOfDITANothingToDoProjectsOnTime++ if($IsNothingToDoProjectOnTime); $NumberOfDITANothingToDoProjectsOnDay++ if($IsNothingToDoProjectOnDay) }
    else { $NumberOfNonDITAProjects++; $NumberOfNonDITAProjectsOnTime++ if($IsProjectOnTime); $NumberOfNonDITAProjectsOnDay++ if($IsProjectOnDay); $NumberOfNonDITANothingToDoProjects++ if($IsNothingToDo);  $NumberOfNonDITANothingToDoProjectsOnTime++ if($IsNothingToDoProjectOnTime); $NumberOfNonDITANothingToDoProjectsOnDay++ if($IsNothingToDoProjectOnDay) }
    
    (my $BldNbr = $BuildNumber) =~ s/^0+//;
    $NbrOfDocuments = 0;
    #sub CountDocuments { return unless(-f $File::Find::name && $File::Find::name!~/\.chm$/); $NbrOfDocuments++ }
    #if(-e "$DROP_DIR/documentation/$Project/$BldNbr/packages") { find(\&CountDocuments, "$DROP_DIR/documentation/$Project/$BldNbr/packages"); $NumberOfDocuments += $NbrOfDocuments }
    my $LastManifestModificationDate = '';
    if(-e "$DAM_DIR/$Project/LastManifestModificationDate.txt")
    {
        open(TXT, "$DAM_DIR/$Project/LastManifestModificationDate.txt") or warn("ERROR: cannot open '$DAM_DIR/$Project/LastManifestModificationDate.txt': $!");
        ($LastManifestModificationDate) = <TXT> =~ /^(.{10})/;
        close(TXT);
        $LastManifestModificationDate =~ s/\//./g;
        if($LastManifestModificationDate eq $Date)
        {
            $NumberOfModifiedProjects++ ;
            if(${$Projects{$Project}}[1] eq 'dita') { $NumberOfDITAModifiedProjects++ }
            else { $NumberOfNonDITAModifiedProjects++ }
        }
    }
    push(@Projects, [$Host, $Project, ${$Projects{$Project}}[0], $TextMLServer, ${$Projects{$Project}}[1], $BuildNumber, $Start, $Stop, $IsNothingToDo, $IsInProgress, $IsProjectOnTime, $IsProjectOnDay, $NbOfExpectedDocuments, $NbrOfDocuments, $FetchStart, $FetchStop, $LastManifestModificationDate]);
    push(@{$XAxis{$Host}}, $Start, $Stop) if($Start && $Stop);

    opendir(LOGS, "$DAM_DIR/$Project/$BuildName/Host_1") or warn("ERROR: cannot open '$DAM_DIR/$Project/$BuildName/Host_1': $!");
    while(defined($Summary = readdir(LOGS)))
    {
        next unless($Summary =~ /_summary_build.txt/);
        open(SUMMARY, "$DAM_DIR/$Project/$BuildName/Host_1/$Summary") or warn("ERROR: cannot open '$DAM_DIR/$Project/$BuildName/Host_1/$Summary': $!");
        while(<SUMMARY>)
        {
            if(/\s\[(\w+?)\]\[\w+?\]/)
            {
                ${$ErrorStatistics{$1}}[0]++;  
                ${${$ErrorStatistics{$1}}[1]}{${$Projects{$Project}}[0]} = undef;
            }
        }
        close(SUMMARY); 
    }
    closedir(LOGS);
}
close(JOB);
printf("Phase1 took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3], scalar(localtime()));

@Start = Today_and_Now();
opendir(VIEW, "$DAM_DIR/JobViewer") or die("ERROR: cannot opendir '$DAM_DIR/JobViewer': $!");
while(defined(my $JobViewer = readdir(VIEW)))
{
    next unless(my($Dt)=$JobViewer=~/^JobViewer_((\d{4})\.(\d{2}).(\d{2}))\.htm/);
    push(@JobViewers, $JobViewer);
    next if($1 eq $Date or Day_of_Week($2, $3, $4)==6 or Day_of_Week($2, $3, $4)==7);
    
    open(JOB, "$DAM_DIR/JobViewer/$JobViewer") or warn("ERROR: cannot open '$DAM_DIR/JobViewer/$JobViewer': $!");
    while(<JOB>)
    {
        if(/Available.*?(\d+)\%/) { push(@Rates, [$Dt, $1]); last }
    }
    close(JOB);
}
closedir(VIEW);
push(@Rates, [$Date, int(($NumberOfDITAProjectsOnDay-$NumberOfDITANothingToDoProjectsOnDay)/($NumberOfDITAProjects-$NumberOfDITANothingToDoProjectsOnDay)*100)]);
@Rates = sort({${$a}[0] cmp ${$b}[0]} @Rates);
@data = ([map({${$_}[0]} @Rates)], [map({${$_}[1]} @Rates)]);
$Graph = GD::Graph::bars->new(1000,400) or die("ERROR: cannot new : ", GD::Graph::bars->error());
$Graph->set(x_label=>'Date', y_label=>'%', title=>'Build availability', x_labels_vertical=>1, dclrs=>['cyan'], text_space=>20, show_values=>1, values_vertical=>1, box_axis=>0) or warn("WARNING: cannot set:", $Graph->error());
$Image = $Graph->plot(\@data) or warn("ERROR: cannot plot : ", $Graph->error());
open(PNG, ">$DAM_DIR/JobViewer/success.png") or die("Cannot open file '$DAM_DIR/JobViewer/success.png': $!");
binmode PNG;
print PNG $Image->png();
close PNG;
foreach (@Rates)
{
    ${$_}[0] =~ /^(\d{4})\.(\d{2}).(\d{2})$/;
    ${$Averages{'W'.Week_of_Year($1,$2,$3)}}[0] += ${$_}[1];
    ${$Averages{'W'.Week_of_Year($1,$2,$3)}}[1]++;
}
@Weeks = sort(keys(%Averages));
@data = ([@Weeks], [map({sprintf("%.1f", ${$Averages{$_}}[0]/${$Averages{$_}}[1])} @Weeks)]);
$Graph = GD::Graph::bars->new(250,365) or die("ERROR: cannot new : ", GD::Graph::bars->error());
$Graph->set(x_label=>'Week', y_label=>'%', title=>'Availibility average', x_labels_vertical=>1, dclrs=>['cyan'], text_space=>20, show_values=>1, values_vertical=>1, box_axis=>0) or warn("WARNING: cannot set:", $Graph->error());
$Image = $Graph->plot(\@data) or warn("ERROR: cannot plot : ", $Graph->error());
open(PNG, ">$DAM_DIR/JobViewer/averages.png") or die("Cannot open file '$DAM_DIR/JobViewer/averages.png': $!");
binmode PNG;
print PNG $Image->png();
close PNG;
printf("Phase2 took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3], scalar(localtime()));

@Start = Today_and_Now();
map({my $Host=$_; @{$XAxis{$Host}}=sort(@{$XAxis{$Host}}); @{$YAxis{$Host}}[0..$#{$XAxis{$Host}}]=(0)x@{$XAxis{$Host}}} keys(%XAxis));
foreach my $raProject (sort({${$a}[6] cmp ${$b}[6]} @Projects))
{
    my($Host, $ProjectId, $ProjectName, $TextMLServer, $DocumentBase, $BuildNumber, $Start, $Stop, $IsNothingToDo, $IsInProgress, $IsProjectOnTime, $IsProjectOnDay, $NbOfExpectedDocuments, $NbrOfDocuments, $FetchStart, $FetchStop) = @{$raProject};
    my $i;
    for($i=0; $i<@{$XAxis{$Host}} && $Start>${$XAxis{$Host}}[$i]; $i++) {}
    for(; $i<@{$XAxis{$Host}} && $Stop>=${$XAxis{$Host}}[$i]; $i++) { ${$YAxis{$Host}}[$i]++ }
    @{$Hosts{$Host}} = (0xFFFFFFFF, 0) unless(exists($Hosts{$Host}));
    ${$Hosts{$Host}}[0] = $Start if($Start>$TodayAt0h00 && $Start<${$Hosts{$Host}}[0]);
    ${$Hosts{$Host}}[1] = $Stop if($Stop>$TodayAt0h00 && $Stop>${$Hosts{$Host}}[1]);
    push(@{${$Hosts{$Host}}[2]}, [$ProjectId, $ProjectName, $TextMLServer, $DocumentBase, $BuildNumber, $Start, $Stop, $IsNothingToDo, $IsInProgress, $IsProjectOnDay, $FetchStart, $FetchStop]);
}
printf("Phase3 took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3], scalar(localtime()));

@Start = Today_and_Now();
mkpath("$DAM_DIR/JobViewer") or die("ERROR: cannot mkpath '$DAM_DIR/JobViewer': $!") unless(-e "$DAM_DIR/JobViewer");
foreach my $Host (keys(%XAxis))
{
    my $BeginTime = ${$XAxis{$Host}}[0];
    my @X = map({$_-$BeginTime} @{$XAxis{$Host}}); 
    my @data = (\@X, \@{$YAxis{$Host}});

    my $mygraph = GD::Graph::mixed->new(500, 220);
    $mygraph->set(y_min_value=>0, y_max_value=>6, y_tick_number=>2, y_label=>'Number of Projects',
    #    #y_number_format => \&y_format, 
        x_min_value => ${$data[0]}[0],
        x_max_value => ${$data[0]}[-1],
        x_number_format => \&HHMMSS, 
    #    x_ticks => 1,
        x_tick_number => 10,
    #    #zero_axis => 1,
        long_ticks => 1,
        types => ['lines'],
    ) or warn $mygraph->error;
    $myimage = $mygraph->plot(\@data) or die $mygraph->error;
    open(PNG, ">$DAM_DIR/JobViewer/load_${Host}_$Date.png") or die("Cannot open file '$DAM_DIR/JobViewer/load_${Host}_$Date.png': $!");
    binmode PNG;
    print PNG $myimage->png;
    close PNG;
}
printf("Phase4 took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3], scalar(localtime()));

@Start = Today_and_Now();
open(IN, "$DAM_DIR/JobViewer/JobViewer.csv") or warn("ERROR: cannot open '$DAM_DIR/JobViewer/JobViewer.csv': $!");
open(OUT, ">$TEMP_DIR/JobViewer_$$.csv") or warn("ERROR: cannot open '$TEMP_DIR/JobViewer_$$.csv': $!");
$IsDateFound = 0;
while(<IN>)
{
    my $Line = $_;
    if(($Line=~/^(\d{4}\.\d{2}\.\d{2})/) && ($1 eq $Date)) { printf(OUT "%s;%d;%d;%d;%d;%d\n", $Date, ($NumberOfDITAProjectsOnDay/$NumberOfDITAProjects)*100, ($NumberOfDITAProjectsOnTime/$NumberOfDITAProjects)*100, $NumberOfProjects, $NumberOfDocuments, $NumberOfExpectedDocuments); $IsDateFound=1  }
    else { print OUT $Line }
}
printf(OUT "%s;%d;%d;%d;%d;%d\n", $Date, ($NumberOfDITAProjectsOnDay/$NumberOfDITAProjects)*100, ($NumberOfDITAProjectsOnTime/$NumberOfDITAProjects)*100, $NumberOfProjects, $NumberOfDocuments, $NumberOfExpectedDocuments) unless($IsDateFound);
close(OUT);
close(IN);
rename("$TEMP_DIR/JobViewer_$$.csv", "$DAM_DIR/JobViewer/JobViewer.csv");   
printf("Phase5 took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3], scalar(localtime()));

@Start = Today_and_Now();
open(HTM , ">$DAM_DIR/JobViewer/JobViewer.htm") or die("ERROR: cannot open '$DAM_DIR/JobViewer/JobViewer.htm': $!");
print(HTM "\n<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n");
print(HTM "<html>\n");
print(HTM "\t<head>\n");
print(HTM "\t\t<meta http-equiv=\"content-type\" content=\"text/html; charset=UTF-8\"/>\n");
print(HTM "\t\t<title>Job Viewer</title>\n");
print(HTM "\t\t<script language=javascript>\n");
print(HTM "\t\t\tfunction select(elem)\n");
print(HTM "\t\t\t{\n");
print(HTM "\t\t\t\tcurNavBarElem.className	= 'wbar';\n");
print(HTM "\t\t\t\telem.className = 'bbar';\n");
print(HTM "\t\t\t\tcurNavBarElem =	elem;\n");
print(HTM "\t\t\t\tdocument.all['dailyP'].style.display = 'none';\n");
print(HTM "\t\t\t\tdocument.all['dailyO'].style.display = 'none';\n");
print(HTM "\t\t\t\tdocument.all['ondemand'].style.display = 'none';\n");
print(HTM "\t\t\t\tdocument.all['history'].style.display = 'none';\n");
print(HTM "\t\t\t\tdocument.all['error'].style.display = 'none';\n");
print(HTM "\t\t\t\tdocument.all['machine'].style.display = 'none';\n");
print(HTM "\t\t\t\tdocument.all[elem.getAttribute('tab')].style.display = '';\n");
print(HTM "\t\t\t}\n");
print(HTM "\t\t\tfunction selectDate(date)\n");
print(HTM "\t\t\t{\n");
print(HTM "\t\t\t\twindow.open('$DAM_HREF/dam/JobViewer/'+date.options[date.selectedIndex].value, '_blank');\n");
print(HTM "\t\t\t\tdate.selectedIndex=0;\n");
print(HTM "\t\t\t}\n");
print(HTM "\t\t</script>\n");
print(HTM "\t\t<style type='text/css'>\n");
print(HTM "\t\t\tbody { background:white }\n");
print(HTM "\t\t\t.whiteTitle {font-size:10.0pt;color:black;background:white;font-weight:bold;text-align:left;padding-left:0.3cm;padding-right:0.3cm}\n");
print(HTM "\t\t\t.greyTitle {font-size:10.0pt;color:black;background:#D9D9D9;font-weight:bold;text-align:left;padding-left:0.3cm;padding-right:0.3cm}\n");
print(HTM "\t\t\t.whiteCell {font-size:10.0pt;text-align:left;padding-left:0.3cm;padding-right:0.3cm}\n");
print(HTM "\t\t\t.whiteRedCell {font-size:10.0pt;color:red;text-align:left;padding-left:0.3cm;padding-right:0.3cm}\n");
print(HTM "\t\t\t.greenCell {font-size:10.0pt;background:#92D050;text-align:center;padding-left:0.3cm;padding-right:0.3cm}\n");
print(HTM "\t\t\t.redCell {font-size:10.0pt;background:red;text-align:center;padding-left:0.3cm;padding-right:0.3cm}\n");
print(HTM "\t\t\t.orangeCell {font-size:10.0pt;background:orange;text-align:center;padding-left:0.3cm;padding-right:0.3cm}\n");
print(HTM "\t\t\t.bbar {font-size:10.0pt;background-color:#3366cc;color:white;text-align:center;padding-left:0.3cm;padding-right:0.3cm;font-weight:bold;font-size:x-small;cursor:pointer}\n");
print(HTM "\t\t\t.wbar {font-size:10.0pt;background-color:#cfcfcf;color:blue;text-align:center;padding-left:0.3cm;padding-right:0.3cm;font-size:x-small;cursor:pointer}\n");
print(HTM "\t\t.b0010 {text-align:left;border-bottom:solid black 1px;color:black;padding-left:0.1cm;padding-right:0.1cm}\n");
print(HTM "\t\t</style>\n");
print(HTM "\t</head>\n");
print(HTM "\t<body>\n");

print(HTM "\t\tJob Viewer:&nbsp;&nbsp;&nbsp;<select onchange='selectDate(this)'>\n");
@JobViewers = reverse(sort(@JobViewers));
for(my $i=0; $i<@JobViewers; $i++)
{
    my($Year, $Month, $Day) = $JobViewers[$i] =~ /^JobViewer_(\d{4})\.(\d{2}).(\d{2})\.htm$/;
    print(HTM "\t\t\t<option value='$JobViewers[$i]'", $i?'':' selected', ">$Day\/$Month\/$Year</option>\n");
}
print(HTM "\t\t<\/select></br></br>\n");

print(HTM "\t\t<table id='navbar' border='0' cellpadding='0' cellspacing='0'>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t\t<td class='bbar' tab='dailyP' nowrap onclick=select(this)>daily build (production)</td>\n");
print(HTM "\t\t\t\t<td width=1 bgcolor='#808080'><img	width=1	height=1 alt=''></td>\n");
print(HTM "\t\t\t\t<td width=1 bgcolor='white'><img width=1 height=1	alt=''></td>\n");
print(HTM "\t\t\t\t<td class='wbar' tab='dailyO' nowrap onclick=select(this)>daily build (others)</td>\n");
print(HTM "\t\t\t\t<td width=1 bgcolor='#808080'><img	width=1	height=1 alt=''></td>\n");
print(HTM "\t\t\t\t<td width=1 bgcolor='white'><img width=1 height=1	alt=''></td>\n");
print(HTM "\t\t\t\t<td class='wbar' tab='ondemand' nowrap onclick=select(this)>build on demand</td>\n");
print(HTM "\t\t\t\t<td width='1' bgcolor='#808080'><img width='1' height='1' alt=''></td>\n");
print(HTM "\t\t\t\t<td width='1' bgcolor='white'><img width='1' height='1' alt=''></td>\n");
print(HTM "\t\t\t\t<td class='wbar' tab='history' nowrap onclick=select(this)>history</td>\n");
print(HTM "\t\t\t\t<td width='1' bgcolor='#808080'><img width='1' height='1' alt=''></td>\n");
print(HTM "\t\t\t\t<td width='1' bgcolor='white'><img width='1' height='1' alt=''></td>\n");
print(HTM "\t\t\t\t<td class='wbar' tab='error' nowrap onclick=select(this)>error</td>\n");
print(HTM "\t\t\t\t<td width='1' bgcolor='#808080'><img width='1' height='1' alt=''></td>\n");
print(HTM "\t\t\t\t<td width='1' bgcolor='white'><img width='1' height='1' alt=''></td>\n");
print(HTM "\t\t\t\t<td class='wbar' tab='machine' nowrap onclick=select(this)>machine</td>\n");
print(HTM "\t\t\t\t<td width='1' bgcolor='#808080'><img width='1' height='1' alt=''></td>\n");
print(HTM "\t\t\t\t<td width='1' bgcolor='white'><img width='1' height='1' alt=''></td>\n");
print(HTM "\t\t\t</tr>\n");
print(HTM "\t\t</table>\n");
print(HTM "\t\t<table width='100%' cellpadding='0' cellspacing='0' border='0'>\n");
print(HTM "\t\t\t<tr><td style='background-color:#3366CC' nowrap>&nbsp;</td></tr>\n");
print(HTM "\t\t</table><br>\n");

print(HTM "\t\t<div id='dailyP' style=\"display:'none'\">\n");
print(HTM "\t\t\t<table border='0' cellspacing='0'>\n");
print(HTM "\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t<td>Report generated at ", FormatDate(timelocal(@Today[0..5])), " (refreshed every hour)</td>\n");
print(HTM "\t\t\t\t\t<td rowspan='6'>", '&nbsp;'x40, "<img src='$DAM_HREF/dam/JobViewer/success.png' alt='success' title='success'/>", '&nbsp;'x3, "<img src='$DAM_HREF/dam/JobViewer/averages.png' alt='averages' title='averages' align='top'/></td>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t<tr>\n");
printf(HTM "\t\t\t\t\t<td>Available dita builds during the day: %3.0d%%</td>\n", ($NumberOfDITAProjectsOnDay-$NumberOfDITANothingToDoProjectsOnDay)/($NumberOfDITAProjects-$NumberOfDITANothingToDoProjectsOnDay)*100);
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t<tr>\n");
printf(HTM "\t\t\t\t\t<td>Success rate of dita builds: %3.0d%% (Build available before 09:00)</td>\n", ($NumberOfDITAProjectsOnTime-$NumberOfDITANothingToDoOnTime)/($NumberOfDITAProjects-$NumberOfDITANothingToDoOnTime)*100);
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t<td>Number of dita projects: $NumberOfDITAProjects</td>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t<td>Number of dita projects impacted by source changes: $NumberOfDITAModifiedProjects</td>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t<td>Number of expected dita documents: $NumberOfDITAExpectedDocuments</td>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t</table>\n");
print(HTM "\t\t\t<table border='0' cellspacing='0'>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Build Machine</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Project ID</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Project Name</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>TextML</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Doc Base</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Revision</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Status</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Last start date/time</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Last stop date/time</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Duration</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Fetch</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Last modification</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Activities</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Number of Expected Documents</td>\n");
print(HTM "\t\t\t</tr>\n");
foreach my $raProject (sort({${$a}[9] cmp ${$b}[9] or ${$a}[6] cmp ${$b}[6]} @Projects))
{
    my($Host, $ProjectId, $ProjectName, $TextMLServer, $DocumentBase, $BuildNumber, $Start, $Stop, $IsNothingToDo, $IsInProgress, $IsProjectOnTime, $IsProjectOnDay, $NbOfExpectedDocuments, $NbrOfDocuments, $FetchStart, $FetchStop, $LastManifestModificationDate) = @{$raProject};
    next unless($DocumentBase eq 'dita');
    print(HTM "\t\t\t<tr>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$Host</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$ProjectId</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'><a href='$DAM_HREF/cgi-bin/DAM.pl?phio=$ProjectId&streams=$ProjectName&tag=${ProjectId}_$BuildNumber'>$ProjectName</a></td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$TextMLServer</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$DocumentBase&nbsp;&nbsp;<a href='$METEO_HREF/project/$ProjectId/results'>h</a></td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$BuildNumber</td>\n");
    print(HTM "\t\t\t\t<td class='", $IsInProgress?'orangeCell':($IsProjectOnDay?'greenCell':($IsNothingToDo?'whiteCell':'redCell')), "'>", $IsInProgress?'in progress':($IsProjectOnDay?'completed':($IsNothingToDo?'nothing to do':'not started')), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", FormatDate($Start), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", FormatDate($Stop), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", HHMMSS($Stop-$Start), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", HHMMSS($FetchStop-$FetchStart), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$LastManifestModificationDate</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", (-f "$DAM_DIR/$ProjectId/${ProjectId}_$BuildNumber/Activities.htm") ? "<a href='$DAM_HREF/dam/$ProjectId/${ProjectId}_$BuildNumber/Activities.htm'>Activities</a>":((-f "$DAM_DIR/$ProjectId/${ProjectId}_$BuildNumber/Activities.txt") ? "<a href='$DAM_HREF/dam/$ProjectId/${ProjectId}_$BuildNumber/Activities.txt'>Activities</a>":"&nbsp"), "</td>\n");
    print(HTM "\t\t\t\t<td class=", $NbrOfDocuments==$NbOfExpectedDocuments?'whiteCell':'whiteCell', ">$NbOfExpectedDocuments</td>\n");
    print(HTM "\t\t\t</tr>\n");
}
print(HTM "\t\t</table>\n");
print(HTM "\t</div>\n");

print(HTM "\t\t<div id='dailyO' style=\"display:'none'\">\n");
print(HTM "\t\t\t<table border='0' cellspacing='0'>\n");
print(HTM "\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t<td>Report generated at ", FormatDate(timelocal(@Today[0..5])), " (refreshed every hour)</td>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t<tr>\n");
printf(HTM "\t\t\t\t\t<td>Available non dita builds during the day: %3.0d%%</td>\n", ($NumberOfNonDITAProjectsOnDay/$NumberOfNonDITAProjects)*100);
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t<tr>\n");
printf(HTM "\t\t\t\t\t<td>Success rate of non dita builds: %3.0d%% (Build available before 09:00)</td>\n", ($NumberOfNonDITAProjectsOnTime/$NumberOfNonDITAProjects)*100);
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t<td>Number of non dita projects: $NumberOfNonDITAProjects</td>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t<td>Number of non dita projects impacted by source changes: $NumberOfNonDITAModifiedProjects</td>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t<td>Number of expected non dita documents: $NumberOfNonDITAExpectedDocuments</td>\n");
print(HTM "\t\t\t\t</tr>\n");
print(HTM "\t\t\t</table>\n");
print(HTM "\t\t\t<table border='0' cellspacing='0'>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Build Machine</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Project ID</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Project Name</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>TextML</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Doc Base</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Revision</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Status</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Last start date/time</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Last stop date/time</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Duration</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Fetch</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Last modification</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Activities</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Number of Expected Documents</td>\n");
print(HTM "\t\t\t</tr></br>\n");
foreach my $raProject (sort({${$a}[9] cmp ${$b}[9] or ${$a}[6] cmp ${$b}[6]} @Projects))
{
    my($Host, $ProjectId, $ProjectName, $TextMLServer, $DocumentBase, $BuildNumber, $Start, $Stop, $IsNothingToDo, $IsInProgress, $IsProjectOnTime, $IsProjectOnDay, $NbOfExpectedDocuments, $NbrOfDocuments, $FetchStart, $FetchStop, $LastManifestModificationDate) = @{$raProject};
    next unless($DocumentBase ne 'dita');
    print(HTM "\t\t\t<tr>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$Host</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$ProjectId</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'><a href='$DAM_HREF/cgi-bin/DAM.pl?phio=$ProjectId&streams=$ProjectName&tag=${ProjectId}_$BuildNumber'>$ProjectName</a></td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$TextMLServer</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$DocumentBase&nbsp;&nbsp;<a href='$METEO_HREF/project/$ProjectId/results'>h</a></td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$BuildNumber</td>\n");
    print(HTM "\t\t\t\t<td class='", $IsInProgress?'orangeCell':($IsProjectOnDay?'greenCell':($IsNothingToDo?'whiteCell':'redCell')), "'>", $IsInProgress?'in progress':($IsProjectOnDay?'completed':($IsNothingToDo?'nothing to do':'not started')), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", FormatDate($Start), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", FormatDate($Stop), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", HHMMSS($Stop-$Start), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", HHMMSS($FetchStop-$FetchStart), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$LastManifestModificationDate</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>",(-f "$DAM_DIR/$ProjectId/${ProjectId}_$BuildNumber/Activities.txt") ? "<a href='$DAM_HREF/dam/$ProjectId/${ProjectId}_$BuildNumber/Activities.txt'>Activities</a>":"&nbsp","</td>\n");
    print(HTM "\t\t\t\t<td class=", $NbrOfDocuments==$NbOfExpectedDocuments?'whiteCell':'whiteCell', ">$NbOfExpectedDocuments</td>\n");
    print(HTM "\t\t\t</tr>\n");
}
print(HTM "\t\t</table>\n");
print(HTM "\t</div>\n");

print(HTM "\t\t<div id='ondemand' style=\"display:'none'\">\n");
print(HTM "\t\t\tReport generated at ", FormatDate(timelocal(@Today[0..5])), "<br><br>\n");
print(HTM "\t\t\t$NumberOfProjectsOnDemand builds on demand the last week<br><br>\n");
print(HTM "\t\t\t<table border='0' cellspacing='0'>\n");
print(HTM "\t\t\t<tr>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Build Machine</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Project ID</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Project Name</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>TextML</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Doc Base</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Revision</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Last start date/time</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Last stop date/time</td>\n");
print(HTM "\t\t\t\t<td class='greyTitle'>Duration</td>\n");
print(HTM "\t\t\t</tr>\n");
foreach my $raProject (sort({${$b}[6] cmp ${$a}[6]} @OnDemandBuilds))
{
    my($Host, $ProjectId, $ProjectName, $TextMLServer, $DocumentBase, $BuildNumber, $Start, $Stop, $NbrOfDocuments) = @{$raProject};
    print(HTM "\t\t\t<tr>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$Host</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$ProjectId</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'><a href='$DAM_HREF/cgi-bin/DAM.pl?phio=$ProjectId&streams=$ProjectName&tag=${ProjectId}_$BuildNumber'>$ProjectName</a></td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$TextMLServer</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$DocumentBase</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>$BuildNumber</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", FormatDate($Start), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", FormatDate($Stop), "</td>\n");
    print(HTM "\t\t\t\t<td class='whiteCell'>", HHMMSS($Stop-$Start), "</td>\n");
    print(HTM "\t\t\t</tr>\n");
}
print(HTM "\t\t</table>\n");
print(HTM "\t</div>\n");

print(HTM "\t\t<div id='history' style=\"display:'none'\">\n");
print(HTM "\t\t\tReport generated at ", FormatDate(timelocal(@Today[0..5])), "<br><br>\n");
print(HTM "\t\t\t<a href='$DAM_HREF/dam/JobViewer/JobViewer.csv'>CSV File</a><br><br>\n");
print(HTM "\t\t\t<table border='0' cellspacing='0'>\n");
print(HTM "\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t<td class='greyTitle'>Date</td>\n");
print(HTM "\t\t\t\t\t<td class='greyTitle'>Available during the day</td>\n");
print(HTM "\t\t\t\t\t<td class='greyTitle'>Available before 9h00</td>\n");
print(HTM "\t\t\t\t\t<td class='greyTitle'>Number of projects</td>\n");
print(HTM "\t\t\t\t\t<td class='greyTitle'>Number of expected documents</td>\n");
print(HTM "\t\t\t\t</tr>\n");
open(IN, "$DAM_DIR/JobViewer/JobViewer.csv") or warn("ERROR: cannot open '$DAM_DIR/JobViewer/JobViewer.csv': $!");
while(<IN>)
{
    next unless(/^\d{4}\.\d{2}\.\d{2}/);
    my($Date, $PercentOfDITAProjectsOnDay, $PercentOfDITAProjectsOnTime, $NumberOfProjects, $NumberOfDocuments, $NumberOfExpectedDocuments) = split(/\s*;\s*/, $_);
    print(HTM "\t\t\t\t<tr>\n");
    print(HTM "\t\t\t\t\t<td class='whiteCell'>$Date</td>\n");
    print(HTM "\t\t\t\t\t<td class='whiteCell'>$PercentOfDITAProjectsOnDay%</td>\n");
    print(HTM "\t\t\t\t\t<td class='whiteCell'>$PercentOfDITAProjectsOnTime%</td>\n");
    print(HTM "\t\t\t\t\t<td class='whiteCell'>$NumberOfProjects</td>\n");
    print(HTM "\t\t\t\t\t<td class='whiteCell'>$NumberOfExpectedDocuments</td>\n");
    print(HTM "\t\t\t\t</tr>\n");
}
close(IN);
print(HTM "\t\t\t</table></br>\n");
print(HTM "\t</div>\n");

print(HTM "\t\t<div id='error' style=\"display:'none'\">\n");
print(HTM "\t\t\tReport generated at ", FormatDate(timelocal(@Today[0..5])), "<br><br>\n");
print(HTM "\t\t\t<table border='0' cellspacing='0'>\n");
print(HTM "\t\t\t\t<tr>\n");
print(HTM "\t\t\t\t\t<td class='greyTitle'>Error Id</td>\n");
print(HTM "\t\t\t\t\t<td class='greyTitle'>Number of Errors</td>\n");
print(HTM "\t\t\t\t\t<td class='greyTitle'>List of projects</td>\n");
print(HTM "\t\t\t\t</tr>\n");
$FistLine = 1;
foreach my $ErrorId (sort({${$ErrorStatistics{$b}}[0] <=> ${$ErrorStatistics{$a}}[0]} keys(%ErrorStatistics)))
{
    my($NumberOfErrors, $rhProjects) = @{$ErrorStatistics{$ErrorId}};
    print(HTM "\t\t\t\t<tr>\n");
    print(HTM "\t\t\t\t\t<td class='b0010'><a href='https://uacp2.hana.ondemand.com/viewer/#/DRAFT/94c67e56655c4dac925f5f732e338ced/Latest/en-US/SAPDITAmessages.html#SAPDITAmessages__$ErrorId'>$ErrorId</a></td>\n");
    print(HTM "\t\t\t\t\t<td class='b0010'>$NumberOfErrors</td>\n");
    print(HTM "\t\t\t\t\t<td class='b0010'>", join(', ', sort(keys(%{$rhProjects}))), "</td>\n");
    print(HTM "\t\t\t\t</tr>\n");
    $FistLine = 0;
}
print(HTM "\t\t\t</table></br>\n");
print(HTM "\t</div>\n");

print(HTM "\t\t<div id='machine' style=\"display:'none'\">\n");
print(HTM "\t\t\tReport generated at ", FormatDate(timelocal(@Today[0..5])), "<br><br>\n");
foreach my $Host (sort(keys(%Hosts)))
{
    my($Start, $Stop, $raProjects) = @{$Hosts{$Host}};
    print(HTM "\t\t\t<table border='0' cellspacing='0'>\n");
    print(HTM "\t\t\t\t<tr>\n");
    print(HTM "\t\t\t\t\t<td style='background-color:#BDD3EF;padding-left:0.3cm;padding-right:0.3cm' colspan='7'>$Host -- ", scalar(@{$raProjects}), ' projects -- ', FormatDate($Start), " -- ", FormatDate($Stop) , " -- ", HHMMSS($Stop-$Start), '&nbsp;'x10, "<a href='#' onclick=\"javascript:window.open('http://$Host:8082/?mode=STATS')\"><b>STAT</b></a>", '&nbsp;'x10, "<a href='#' onclick=\"javascript:window.open('http://$Host:8082/?mode=INFO')\"><b>INFO</b></a></td>\n");
    print(HTM "\t\t\t\t</tr>\n");
    print(HTM "\t\t\t\t<tr>\n");
    print(HTM "\t\t\t\t\t<td class='whiteTitle'>Project Name</td>\n");
    print(HTM "\t\t\t\t\t<td class='whiteTitle'>TextML</td>\n");
    print(HTM "\t\t\t\t\t<td class='whiteTitle'>Doc Base</td>\n");
    print(HTM "\t\t\t\t\t<td class='whiteTitle'>Last start date/time</td>\n");
    print(HTM "\t\t\t\t\t<td class='whiteTitle'>Last stop date/time</td>\n");
    print(HTM "\t\t\t\t\t<td class='whiteTitle'>Duration</td>\n");
    print(HTM "\t\t\t\t\t<td class='whiteTitle'>Fetch</td>\n");
    print(HTM "\t\t\t\t\t<td class='whiteTitle'>In progress</td>\n");
    print(HTM "\t\t\t\t\t<td rowspan='", scalar(@{$raProjects}),"'><img src='$DAM_HREF/dam/JobViewer/load_${Host}_$Date.png' alt='toto' title='load $Host'/></td>\n");
    print(HTM "\t\t\t\t</tr>\n");
    foreach (@{$raProjects})
    {
        my($ProjectId, $ProjectName, $TextMLServer, $DocumentBase, $BuildNumber, $Start, $Stop, $IsNothingToDo, $IsInProgress, $IsProjectOnDay, $FetchStart, $FetchStop) = @{$_};
        print(HTM "\t\t\t\t<tr>\n");
        print(HTM "\t\t\t\t\t<td class='whiteCell'><a href='$DAM_HREF/cgi-bin/DAM.pl?phio=$ProjectId&streams=$ProjectName&tag=${ProjectId}_$BuildNumber'>$ProjectName</a></td>\n");
        print(HTM "\t\t\t\t\t<td class='whiteCell'>$TextMLServer</td>\n");
        print(HTM "\t\t\t\t\t<td class='whiteCell'>$DocumentBase&nbsp;&nbsp;<a href='$METEO_HREF/project/$ProjectId/results'>h</a></td>\n");
        print(HTM "\t\t\t\t\t<td class='whiteCell'>", FormatDate($Start), "</td>\n");
        print(HTM "\t\t\t\t\t<td class='whiteCell'>", FormatDate($Stop), "</td>\n");
        print(HTM "\t\t\t\t\t<td class='whiteCell'>", HHMMSS($Stop-$Start), "</td>\n");
        print(HTM "\t\t\t\t\t<td class='whiteCell'>", HHMMSS($FetchStop-$FetchStart), "</td>\n");
        print(HTM "\t\t\t\t\t<td class='", $IsInProgress?'orangeCell':($IsProjectOnDay?'greenCell':($IsNothingToDo?'whiteCell':'redCell')), "'>", $IsInProgress?'in progress':($IsProjectOnDay?'completed':($IsNothingToDo?'nothing to do':'not started')), "</td>\n");
        print(HTM "\t\t\t\t</tr>\n");
    }    
    print(HTM "\t\t\t</table></br>\n");
}
print(HTM "\t</div>\n");

print(HTM "\t<script language='javascript'>\n");
print(HTM "\t\tvar curNavBarElem = document.all.navbar.rows[0].cells[0];\n");
print(HTM "\t\tselect(curNavBarElem)\n");
print(HTM "\t</script>\n");
print(HTM "\t</body>\n");
print(HTM "</html>\n");
close(HTM);

copy("$DAM_DIR/JobViewer/JobViewer.htm", "$DAM_DIR/JobViewer/JobViewer_$Date.htm") or die("ERROR: cannot copy '$DAM_DIR/JobViewer/JobViewer.htm': $!");
#SendMail() if($NumberOfDITAProjectsOnTime/$NumberOfDITAProjects<1 && timelocal(@Today)>$TodayAt9h00 && timelocal(@Today)<$TodayAt10h00 && !-f "$DAM_DIR/JobViewer/Mail_$Date.htm");
printf("Phase6 took %u h %02u mn %02u s at %s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3], scalar(localtime()));

#############
# Functions #
#############

sub HHMMSS
{
    my($Difference) = @_;
    my $s = $Difference % 60;
    $Difference = ($Difference - $s)/60;
    my $m = $Difference % 60;
    $h = ($Difference - $m)/60;
    return sprintf("%02uh%02u", $h, $m);
}

sub FormatDate
{
    my($Time) = @_;
    my($ss, $mn, $hh, $dd, $mm, $yy, $wd, $yd, $isdst) = localtime($Time);
    return sprintf("%04u/%02u/%02u %02u:%02u", $yy+1900, $mm+1, $dd, $hh, $mn);
}

sub SendMail
{
    my @Messages = @_;

    return if($NumberOfEmails);
    $NumberOfEmails++;
    
    open(HTML, ">$TEMP_DIR/Mail$$.htm") or die("ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $!");
    print(HTML "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n");
    print(HTML "<html>\n");
    print(HTML "\t<head>\n");
    print(HTML "\t</head>\n");
    print(HTML "\t<body>\n");
    print(HTML "*****This email has been sent from an unmonitored automatic mailbox.*****<br/><br/>\n");
    print(HTML "Hi everyone,<br/><br/>\n");
    print(HTML "&nbsp;"x5, "We have the following error(s) in $0 on $HOST:<br/>\n");
    foreach (@Messages)
    {
        print(HTML "&nbsp;"x5, "$_<br/>\n");
    }
    print(HTML "<br/>Best regards\n");
    print(HTML "\t</body>\n");
    print(HTML "</html>\n");
    close(HTML);

    my $smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60) or warn("ERROR: SMTP connection impossible: $!");
    $smtp->mail($SMTPFROM);
    $smtp->to(split('\s*;\s*', $SMTPTO));
    $smtp->data();
    $smtp->datasend("To: $SMTPTO\n");
    my($Script) = $0 =~ /([^\/\\]+)$/; 
    $smtp->datasend("Subject: [$Script] Errors on $HOST\n");
    $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
    open(HTML, "$TEMP_DIR/Mail$$.htm") or warn("ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $!");
    while(<HTML>) { $smtp->datasend($_) } 
    close(HTML);
    $smtp->dataend();
    $smtp->quit();

    unlink("$TEMP_DIR/Mail$$.htm") or warn("ERROR: cannot unlink '$TEMP_DIR/Mail$$.htm': $!");
}
