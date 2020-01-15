#!/usr/bin/perl -w

# base
use File::Basename;
use Sys::Hostname;
use Getopt::Long;
use File::Path;
use XML::DOM;

use FindBin;
use lib ($FindBin::Bin);
use Perforce;

##############
# Parameters #
##############

Usage() unless(@ARGV);
$Getopt::Long::ignorecase = 0;
GetOptions("help|?"=>\$Help, "deep=i"=>\$HistoryDeep, "adapt=s"=>\$OutAdapt, "jira=s"=>\$OutJira, "CWB=s"=>\$OutCWB, "comment=s"=>\$Comment, "from=s"=>\$FromContext, "to=s"=>\$ToContext, "outdat=s"=>\$OutDAT, , "outxml=s"=>\$OutXML, "xml!"=>\$XML, "dat!"=>\$DAT, "rev1=s"=>\$FileRevision1, "rev2=s"=>\$FileRevision2, "writable=s"=>\$Areas);
Usage() if($Help);
unless($FromContext || $ToContext || $FileRevision1 || $FileRevision2)  { print(STDERR "ERROR: -f.rom, -t.o, -rev1 or -rev2 options are mandatory.\n"); Usage() };
if($OutXML && defined($XML) && $XML==0) { print(STDERR "ERROR: -outx.ml and -nox.ml are exclusives.\n"); Usage() };
if($OutDAT && defined($DAT) && $DAT==0) { print(STDERR "ERROR: -outd.at and -nod.at are exclusives.\n"); Usage() };
$HistoryDeep = 4 unless(defined($HistoryDeep));
$Areas = '*' unless($Areas);
for my $Area (split(',', $Areas))
{
    if($Area =~ /^-(.+)$/) { push(@ROAreas, $1) }
    else { push(@RWAreas, $Area) }
}
$DAT = 1 if($OutDAT);
$XML = 1 if($OutXML);
$XML = 1 unless($DAT || $XML);

########
# Main #
########

# Computing
if($FromContext)
{
    eval
    {
        my $CONTEXT = XML::DOM::Parser->new()->parsefile($FromContext);    
        for my $COMPONENT (@{$CONTEXT->getElementsByTagName('fetch')})
        {
            my($File, $Revision, $Authority) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute('revision'), $COMPONENT->getAttribute('authority'));
            ${$P4Diff2{$Authority}}{$File} = [$Revision, ""];
        }
        for my $GIT (@{$CONTEXT->getElementsByTagName('git')})
        {
            my($Repository, $Refspec, $Destination, $StartPoint) = ($GIT->getAttribute('repository'), $GIT->getAttribute('refspec'), $GIT->getAttribute('destination'), $GIT->getAttribute('startpoint'));
            $Destination =~ s/^.+?[\\\/]src[\\\/]/$ENV{SRC_DIR}\//;
            ${$GitDiff{$Repository}}{$Refspec} = [$Destination, $StartPoint, ''];
        }
        $CONTEXT->dispose();
    };
    if($@) { (my $Msg=$@); chomp($Msg); die("ERROR: $Msg in '$FromContext'") }
}
if($ToContext)
{
    eval
    {
        my $CONTEXT = XML::DOM::Parser->new()->parsefile($ToContext);    
        for my $COMPONENT (@{$CONTEXT->getElementsByTagName("fetch")})
        {
            my($File, $Revision, $Authority) = ($COMPONENT->getFirstChild()->getData(), $COMPONENT->getAttribute('revision'), $COMPONENT->getAttribute('authority'));
            if(exists(${$P4Diff2{$Authority}}{$File})) { ${${$P4Diff2{$Authority}}{$File}}[1] = $Revision }
            else { ${$P4Diff2{$Authority}}{$File} = ['', $Revision] }
        }
        for my $GIT (@{$CONTEXT->getElementsByTagName("git")})
        {
            my($Repository, $RefSpec, $Destination, $StartPoint) = ($GIT->getAttribute('repository'), $GIT->getAttribute('refspec'), $GIT->getAttribute('destination'), $GIT->getAttribute('startpoint'));
            $Destination =~ s/^.+?[\\\/]src[\\\/]/$ENV{SRC_DIR}\//;
            if(exists(${$GitDiff{$Repository}}{$RefSpec}))
            { ${${$GitDiff{$Repository}}{$RefSpec}}[2] = $StartPoint }
            else { ${$GitDiff{$Repository}}{$RefSpec} = [$Destination, '', $StartPoint] }
        }
        $CONTEXT->dispose();
    };
    if($@) { (my $Msg=$@); chomp($Msg); die("ERROR: $Msg in '$ToContext'") }
}
if($FileRevision1)
{
    my($File, $Revision) = $FileRevision1 =~ /^([^@#]+)(.*)$/;
    $P4Diff2{$File} = [$Revision, ""];
}
if($FileRevision2)
{
    my($File, $Revision) = $FileRevision2 =~ /^([^@#]+)(.*)$/;
    if(exists($P4Diff2{$File})) { ${$P4Diff2{$File}}[1] = $Revision }
    else { $P4Diff2{$File} = ["", $Revision] }
}

foreach my $Repository (keys(%GitDiff))
{
    my($Repo) = $Repository =~ /([^\\\/]+)\.git$/;
    foreach my $RefSpec (keys(%{$GitDiff{$Repository}}))
    {
        my($Destination, $Start, $Stop) = @{${$GitDiff{$Repository}}{$RefSpec}};
        chdir($Destination) or warn("ERROR: cannot chdir '$Destination': $!");
        my @Logs = split(/\n+/, `git log --name-only --format=format:"commit:%H|%an|%ad|%s" $Start...$Stop`);
        LINE: for(my $i=0; $i<@Logs; $i++)
        {
            if($Logs[$i] =~ /^commit:(.*?)\|(.*?)\|(.*?)\|(.*?)$/)
            { 
                my($Commit, $Author, $Date, $Description) = ($1,$2,$3,$4);
                my @Issues;
                while($Description =~ /\b([0-9a-z]+-\d+)\b/ig)
                {
                    my $task = $1;
                    push(@Issues, $task) ;
                    $Jiras{$task} = undef;
                }
                while($Description =~ /\b(\d{24})\b/ig)
                {
                    my $task = $1;
                    push(@Issues, $task) ;
                    push(@CWBs, [$task, $Commit]);
                }
                push(@GitCommits, [$Commit, $Author, $Date, $Description, [@Issues]]);
                for($i++,; $i<@Logs; $i++)
                {
                    redo LINE if($Logs[$i] =~ /^commit:/);
                    push(@GitFiles, ["$Logs[$i] ($Repo)", $Commit]);
                }
            }
        }
    }
}

$p4 = new Perforce;
for my $Authority (keys(%P4Diff2)) 
{
    $Authority ? $p4->SetOptions("-p \"$Authority\"") : $p4->SetOptions(''); 
    for my $File (keys(%{$P4Diff2{$Authority}}))
    {
        #next unless($File =~ /\/xcelsius.assets\//);   # ONLY FOR DEBUG
        if($File =~ /^\-/)
        {
            $File =~ s/^\-//;
            $File =~ s/\*/[^\/]*/g;      # *   Matches all characters except slashes within one directory.
            $File =~ s/\.\.\./\.\*/g;    # ... Matches all files under the current working directory and all subdirectories.
            push(@RevisionExcludes, $File);
            next;
        }
        my($FromRevision, $ToRevision) = @{${$P4Diff2{$Authority}}{$File}};
        next if($FromRevision eq $ToRevision);
        if ( $ToRevision eq "" )
        {
          print "INFO: The path \"$File\" is not present anymore in the latest context. Ignoring its content.\n";
          next;
        }

        $File =~ s/"//g;
        $File =~ s/^\+//;
        my $raDiff2 = $p4->diff2("-q", "$File$FromRevision", "$File$ToRevision");
        if( $p4->ErrorCount() )
        {
          if ( ${$p4->Errors()}[0] =~ /- no such file\(s\).$/ )
          {
            warn ("WARNING: Path not in perforce workspace will be ignored: ", @{$p4->Errors()});
            next;
          }
          elsif ( ${$p4->Errors()}[0] !~ /No file\(s\) to diff.$/
               && ${$p4->Errors()}[0] !~ /- no differing files.$/)
          {
            die("ERROR: cannot diff2 $File: ", @{$p4->Errors()});
          }
        }

        my($Area) = $File =~ /^\/\/[^\/]*\/([^\/]*)/;
        my $Import = grep({/\*/} @RWAreas) ? 0 : 1;
        if(grep({$_ eq $Area} @RWAreas)) { $Import = 0 }
        elsif(grep({$_ eq $Area} @ROAreas)) { $Import = 1 }
        %FileLogCmds = ();
        for my $Diff (@{$raDiff2})
        {
            chomp($Diff);
            my($File1, $File2) = $Diff =~ /^(.+)\s+-\s+((?:\/\/|<).+)$/;
            if($File2 =~ /<none>/i)
            {
                my($File, $Revision) = $File1 =~ /(\/\/[^#]+)#(\d+)/;
                push(@Revisions, [$File, $Revision, 'delete', '', 0, $Import, $Authority]);  
            }
            else
            {
                my($File, $LastRevision) = $File2 =~ /^([^#]+)#(\d+)/;
                my($FirstRevision) = $File1 =~ /#(\d+)/;
                $FirstRevision++;
                $FirstRevision    = $LastRevision if($FirstRevision > $LastRevision);
                #next unless($File=~/Charts.xlf/); # ONLY FOR DEBUG
                Changes($File, $FirstRevision, $LastRevision, 0, $Import, $Authority);
            }
        }
    }
}

# exclude any files that match RevisionExcludes
$RevisionExcludes = join("|", @RevisionExcludes);
$RevisionExcludesRE = qr/$RevisionExcludes/;
@Revisions = grep({ ${$_}[0] !~ /$RevisionExcludesRE/ } @Revisions) if(@RevisionExcludes);

foreach my $raRevision (@Revisions)
{
    my($Change, $History, $Import, $Authority) = @{$raRevision}[3,4,5,6];
    next if(!$Change || exists($Changes{$Change}));
    
    $Authority ? $p4->SetOptions("-p \"$Authority\"") : $p4->SetOptions(''); 
    my $raDescribe = $p4->describe('-s', $Change);
    warn("ERROR: cannot fetch change '$Change': ", @{$p4->Errors()}) if($p4->ErrorCount());
    my $rhChange;
    DESCRIBE: for(my $i=0; $i<@{$raDescribe}; $i++)
    {
        my $Line = ${$raDescribe}[$i];
        next if($Line=~/^\s*$/);
        if($Line=~/^Change.+?\s+by\s+(.+?)\@.+\s+on\s+(.+)$/)
        { 
            (${$rhChange}{User}, ${$rhChange}{Date}) = ($1, $2);
            for($i++; $i<@{$raDescribe}; $i++)
            {
                $Line = ${$raDescribe}[$i];
                next if($Line=~/^\s*$/);
                $Line =~ s/^\s+|\s+$//;
                last DESCRIBE if($Line=~/^Affected files/);
                next if($Line=~/By:\s/ or $Line=~/^Pending changeid:\s/);
                chomp($Line);
                push(@{${$rhChange}{Description}}, $Line);
            }
        }
    }
    if(${$rhChange}{User} =~ /^i\d+$/)
    {
        unless(exists($Users{${$rhChange}{User}}))
        {
            my $rhUser = $p4->FetchUser(${$rhChange}{User});
            warn("ERROR: cannot fetch user '${$rhChange}{User}': ", @{$p4->Errors()}) if($p4->ErrorCount());
            ${$rhUser}{'FullName'} =~ s/^\s*//;
            ${$rhUser}{'FullName'} =~ s/'/\\'/g;
            $Users{${$rhChange}{User}} = "${$rhUser}{'FullName'} (${$rhChange}{User})";
        } 
        ${$rhChange}{User} = $Users{${$rhChange}{User}};
    }

    my @Issues;
    for my $raDescription (${$rhChange}{Description})
    {
        for my $Line (@{$raDescription})
        {
            next unless($Line =~ /^\s*task/i);
            while($Line =~ /\b[a-z]*(\d{6,8})\b/ig)
            {
                my $task = sprintf("ADAPT%08d", $1);
                unless($task =~ /^ADAPT0{7}[01]$/)
                {
                    push(@Issues, $task) ;
                    $Adapts{$task} = undef unless($Import);
                }
            }
            while($Line =~ /\b([0-9a-z]+-\d+)\b/ig)
            {
                my $task = $1;
                push(@Issues, $task) ;
                $Jiras{$task} = undef unless($Import);
            }
            while($Line =~ /\b(\d{24})\b/ig)
            {
                my $task = $1;
                push(@Issues, $task) ;
                push(@CWBs, [$task, $Change]);
            }
        }
    }
    $Changes{$Change} = [${$rhChange}{User}, ${$rhChange}{Date}, [@Issues], join("\n", map(@{$_}, @{$rhChange}{Description})), $History, $Import];
}

# Output
if($DAT)
{
    if($OutDAT)
    {
        my($Path) = $OutDAT =~ /^(.*?)[\\\/][^\\\/]+$/;
        mkpath($Path) or die("ERROR: cannot mkpath '$Path': $!") if($Path && !-e $Path);
        open(OUT, ">$OutDAT") or die("ERROR: cannot open '$OutDAT': $!");
        select(OUT);
    }
    print("\@Revisions=(");
    for(@Revisions)
    {
        my($File, $Revision, $Action, $Change, $History, $Import) = @{$_};
        $File =~ s/'/\\'/g;
        print("['$File','$Revision','$Action','$Change','$History','$Import'],");
    }
    print(");");
    print("\@Changes=(");
    for my $Change (keys(%Changes))
    {
        my($User, $Date, $raAdapts, $Desc, $History, $Import) = @{$Changes{$Change}};
        $Desc =~ s/\\/\\\\/g;
        $Desc =~ s/'/\\'/g;
        print("['$Change','$User','$Date',[",join(',', map({"'$_'"} @{$raAdapts})),"],'$Desc','$History','$Import'],");
    }
    print(");");
    print("\@GitCommits=(");
    foreach(@GitCommits)
    {
        my($Commit, $Author, $Date, $Description, $raIssues) = @{$_};
        $Description =~ s/\\/\\\\/g;
        $Description =~ s/'/\\'/g;
        print("['$Commit','$Author','$Date',[",join(',', map({"'$_'"} @{$raIssues})),"],'$Description','0','0'],");
    }
    print(");");
    print("\@GitFiles=(");
    foreach(@GitFiles)
    {
        my($File, $Commit) = @{$_};
        print("['$File','$Commit'],");
    }
    print(");");
    print("\$Comment='$Comment';") if($Comment);
    close(OUT) if($OutDAT);
}

if($XML)
{
    if($OutXML)
    {
        my($Path) = $OutXML =~ /^(.*?)[\\\/][^\\\/]+$/;
        mkpath($Path) or die("ERROR: cannot mkpath '$Path': $!") if($Path && !-e $Path);
        open(OUT, ">$OutXML") or die("ERROR: cannot open '$OutXML': $!");
        select(OUT);
    }
    print("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    print("<files>\n");
    for(@Revisions)
    {
        my($File, $Revision, $Action, $Change, $History, $Import) = @{$_};
        print("\t<file revision=\"$Revision\" change=\"$Change\" action=\"$Action\" history=\"$History\" import=\"$Import\">$File</file>\n");
    }
    for my $Change (keys(%Changes))
    {
        my($User, $Time, $raAdapts, $Desc, $History, $Import) = @{$Changes{$Change}};
        $Desc =~ s/"/&quote;/g;
        print("\t<change user=\"$User\" time=\"$Time\" adapts=\"",join(',', @{$raAdapts}),"\" desc=\"$Desc\" history=\"$History\" import=\"$Import\">$Change</change>\n");
    }
    for(@GitCommits)
    {
        my($Commit, $Author, $Date, $Description) = @{$_};
        $Description =~ s/"/&quote;/g;
        print("\t<gitcommit author=\"$Author\" date=\"$Date\" description=\"$Description\">$Commit</gitcommit>\n");
    }
    for(@GitFiles)
    {
        my($File, $Commit) = @{$_};
        print("\t<gitfile commit=\"$Commit\">$File</gitfile>\n");
    }
    print("</files>\n");
    close(OUT) if($OutXML);
}

if($OutAdapt)
{
    my($Path) = $OutAdapt =~ /^(.*?)[\\\/][^\\\/]+$/;
    mkpath($Path) or die("ERROR: cannot mkpath '$Path': $!") if($Path && !-e $Path);
    open(OUT, ">$OutAdapt") or die("ERROR: cannot open '$OutAdapt': $!");
    print(OUT join("\n", sort(keys(%Adapts))));
    close(OUT);    
}

if($OutJira)
{
    my($Path) = $OutJira =~ /^(.*?)[\\\/][^\\\/]+$/;
    mkpath($Path) or die("ERROR: cannot mkpath '$Path': $!") if($Path && !-e $Path);
    open(OUT, ">$OutJira") or die("ERROR: cannot open '$OutJira': $!");
    print(OUT join("\n", sort(keys(%Jiras))));
    close(OUT);    
}

if($OutCWB)
{
    my($Path) = $OutCWB =~ /^(.*?)[\\\/][^\\\/]+$/;
    mkpath($Path) or die("ERROR: cannot mkpath '$Path': $!") if($Path && !-e $Path);
    open(OUT, ">$OutCWB") or die("ERROR: cannot open '$OutCWB': $!");
    foreach my $raCWB (@CWBs)
    {
        print(OUT join(";", @{$raCWB}), "\n");
    }
    close(OUT);    
}

END { $p4->Final() if($p4) }

#############
# Functions #
#############

sub Changes
{
    my($DepotFile, $Revision1, $Revision2, $History, $Import, $Authority) = @_;

    return if(exists($FileLogCmds{"$DepotFile\#$Revision2"}));
    my @FileLogs = $p4->filelog("-m".($Revision2-$Revision1+1), "\"$DepotFile\#$Revision2\""); 
    die("ERROR: cannot filelog '$DepotFile\#$Revision2': ", @{$p4->Errors()}) if($p4->ErrorCount());
    $FileLogCmds{"$DepotFile\#$Revision2"} = undef;
    $Authority ? $p4->SetOptions("-p \"$Authority\"") : $p4->SetOptions(''); 
    
    my %FromFiles;
    foreach my $raFileLog (@FileLogs)
    {
        LINE: for(my $i=0; $i<@{$raFileLog}; $i++)
        {
            my $Line = ${$raFileLog}[$i];
            if(my($Revision, $ChangeNumber, $Action) = $Line =~ /^\.\.\.\s+#(\d+)\s+change\s+(\d+)\s+(.+)\s+on\s+/)
            {
                $Action =~ s/'/\\'/g;
                push(@Revisions, [$DepotFile, $Revision, $Action, $ChangeNumber, $History, $Import, $Authority]);
                for( $i++; $i<@{$raFileLog}; $i++)
                {
                    my $Line = ${$raFileLog}[$i];
                    redo LINE unless($Line =~ /^\.\.\.\s+\.\.\.\s+/);
                    my($IntegrateAction, $PartnerFile, $PartnerStartRevision, $PartnerStopRevision);
                    if(($IntegrateAction, $PartnerFile, $PartnerStartRevision, $PartnerStopRevision) = $Line =~ /^\.\.\.\s+\.\.\.\s+(.+)\s+(\/\/[^#]+)#(\d+),?#?(\d*)$/)
                    {
                        unless($PartnerStopRevision) { $PartnerStopRevision=$PartnerStartRevision }
                    }
                    else { warn("ERROR: cannot find integration action in '$Line' from '$DepotFile'") }
                    next unless($IntegrateAction =~ /from/i);
                    if(exists($FromFiles{$PartnerFile}))
                    {
                        ${$FromFiles{$PartnerFile}}[0] = $PartnerStartRevision if($PartnerStartRevision < ${$FromFiles{$PartnerFile}}[0]); 
                        ${$FromFiles{$PartnerFile}}[1] = $PartnerStopRevision if($PartnerStopRevision > ${$FromFiles{$PartnerFile}}[1]); 
                    }
                    else { $FromFiles{$PartnerFile}=[$PartnerStartRevision, $PartnerStopRevision] }
                }
            }
        }
    }

    foreach my $File (keys(%FromFiles))
    {
        my($Rev1, $Rev2) = @{$FromFiles{$File}};
        Changes($File, $Rev1, $Rev2, $History+1, $Import, $Authority) if(!$HistoryDeep || $History < $HistoryDeep);
    }
}

sub Usage
{
   print <<USAGE;
   Usage   : DiffContext.pl [options]
   Example : DiffContext.pl -h
             DiffContext.pl -f=CB2_PI_AR_core_3.context.xml -t=CB2_PI_AR_core_4.context.xml

   [options]
   -help|?      argument displays helpful information about builtin commands.
   -a.dapt      specifies the ADAPT output file.
   -j.ira       specifies the JIRA output file.
   -C.WB        specifies the CWB output file.
   -c.omment    specifies a free comment line (ex. -c=Main_PI_138,Main_PI_139)
   -de.ep       specifies a deep history, defaut is 4, no limit is 0
   -f.rom       specifies the 'from' context file.
   -t.o         specifies the 'to' context file.
   -rev1        specifies the revision1 (with perforce syntax)
   -rev2        specifies the revision2 (with perforce syntax)
   -outx.ml     specifies the XML output file, default is the standard output.
   -outd.at     specifies the DAT output file, default is the standard output.
   -da.t        specifies or not the dat format (Perl Dump), default is -nodat.
   -x.ml        specifies or not the xml format, default is -noxml.
   -w.ritable   specifies the writable areas (with comma separator), default is *.  -area excludes area.
USAGE

    exit;
}
