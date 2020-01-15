use Date::Calc(qw(Today_and_Now Delta_DHMS Add_Delta_Days));
use Getopt::Long;
use File::Find;
use File::Path;
use XML::DOM;

use FindBin;
use lib ($FindBin::Bin);
use Perforce;

$MAXIMUM_COMMAND_LENGTH = 7700;

##############
# Parameters #
##############

GetOptions("help|?"=>\$Help, "client=s"=>\$Client, "force!"=>\$Force, "rmdironly!"=>\$RmDirOnly, "area=s@"=>\@Areas, "xml=s"=>\$XMLContext);
Usage() if($Help);
unless($Client or $XMLContext)  { print(STDERR "ERROR: -c.lient or x.ml option is mandatory.\n"); Usage() }
$RmDirOnly ||= $ENV{"RM_DIR_ONLY"};
@Areas{@Areas} = undef if(@Areas);

if($Client) { $Clients{$Client} = undef }
else
{
    my $CONTEXT = XML::DOM::Parser->new()->parsefile($XMLContext);
    for my $COMPONENT (@{$CONTEXT->getElementsByTagName("fetch")})
    {
        my($Workspace, $P4Port) = ($COMPONENT->getAttribute("workspace"), $COMPONENT->getAttribute("authority"));
        my($Client) = $Workspace =~ /^\/\/(.+?)\//;
        $Clients{$Client} = $P4Port;
    }
    $CONTEXT->dispose();
}

########
# Main #
########

($ss, $mn, $hh, $dd, $mo, $yy) = (localtime)[0..5];
printf("P4Clean starts at %04d/%02d/%02d %02d:%02d:%02d\n", $yy+1900, $mo+1, $dd, $hh, $mn, $ss);

$p4 = new Perforce;

$NumberOfUpdate = $NumberOfRemove = 0;
foreach my $Client (keys(%Clients))
{
    my $P4Port = $Clients{$Client};
    $p4->SetOptions("-c \"$Client\"".($P4Port ? " -p \"$P4Port\"" : ""));
    $rhClient = $p4->FetchClient($Client);
    die("ERROR: cannot fetch client: ", @{$p4->Errors()}) if($p4->ErrorCount());
    ($Root) = ${$rhClient}{Root} =~ /^\s*(.+)$/;

    my $raDirs = $p4->dirs("-H", "//$Client/*");
    if($p4->ErrorCount())
    {
        die("ERROR: cannot dirs '//$Client/*': ", @{$p4->Errors()}) unless(${$p4->Errors()}[0]=~/file\(s\) not on client/);
        exit;
    }
    die("ERROR: p4 dirs result not found") unless(@{$raDirs});
    chomp(@{$raDirs});
    @{$raDirs} = grep({ s/\\/\//g; /^\/\/[^\/]+\/([^\/]+)/; exists($Areas{$1}) } @{$raDirs}) if(@Areas);
    foreach my $Dir (@{$raDirs})
    {
        $p4->sync("$Dir/...#have");
        die("ERROR: cannot sync '$Dir/...': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date\.$/);
    }

    my(@FilesToSync, %P4Opened, @Files);
    if($Force)
    {
        foreach my $Dir (@{$raDirs})
        {
            chomp($Dir);
            $Dir =~ s/^\/\/.+?\//$Root\//;
            $P4Dirs{$Dir} = undef;
        }
    }
    
    unless($RmDirOnly)
    {
        # @Files contains the list of file revisions that have been most recently synced
        my %DirInError;
        foreach my $Dir (@{$raDirs})
        {
            print("p4 have $Dir/...   ");
            my @TempFiles = map({s/\\/\//g; /^\/\/[^\/]+\/([^\/]+)\/.+#\d+\s+-\s+(.+)$/; [$1, $2]} @{$p4->Have("$Dir/...")});
            if($p4->ErrorCount()) { warn("ERROR: cannot have '$Dir/...': ", @{$p4->Errors()}); $DirInError{$Dir}=undef; next }
            print("$#TempFiles\n");
            if($#TempFiles < 0)
            {
                print("p4 have $Dir/...   ");
                @TempFiles = map({s/\\/\//g; /^\/\/[^\/]+\/([^\/]+)\/.+#\d+\s+-\s+(.+)$/; [$1, $2]} @{$p4->Have("$Dir/...")});
                if($p4->ErrorCount()) { warn("ERROR: cannot have '$Dir/...': ", @{$p4->Errors()}); $DirInError{$Dir}=undef; next }
                print("$#TempFiles again...\n");
            }
            push(@Files, @TempFiles);
        }
        print("p4 have=$#Files\n");
        die("ERROR: p4 have result not found") unless(@Files);
        @Files = grep({ exists($Areas{${$_}[0]}) } @Files) if(@Areas);
        @Files = map({ ${$_}[1] } @Files);
            
        ## opened files treatment: revert ##
        @Opened = @{$p4->opened()};
        die("ERROR: cannot opened : ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/file\(s\) not opened on this client.$/i);
        if($Force)
        {
            foreach my $File (@Opened)
            {
                chomp($File);
                $File =~ s/\#\d+.+$//;
                $p4->revert("\"$File\"");
                die("ERROR: cannot revert ${$rhFile}{depotFile}: ", @{$p4->Errors()}) if($p4->ErrorCount());
            }
        }
        else
        {
            foreach my $File (@Opened)
            {
                chomp($File);
                $File =~ s/\#\d+.+$//;
                $raFStat = $p4->fstat("-m 1", "\"$File\"");
                die("ERROR: cannot fstat $File: ", @{$p4->Errors()}) if($p4->ErrorCount());
                foreach my $FStat (@{$raFStat})
                {
                    last if(($File) = $FStat =~ /clientFile\s(.+)$/);
                }
                $File =~ s/\\/\//g;
                $P4Opened{$File} = undef;
            }
        }
        
        ## deleted or hijacked(-w) files treatment: sync -f #have ##
        foreach my $File (@Files)
        {
            if(!-e $File || (-w $File && $Force))
            {
                $NumberOfUpdate++;
                $File =~ s/\%/\%25/g;
                $File =~ s/\@/\%40/g;
                $File =~ s/\#/\%23/g;
                $File =~ s/\*/\%2A/g;
                #if(!-e $File) { print("(deleted) p4 sync -f \"$File#have\"\n") }
                #else { my($Type)=${$p4->files("\"$File\"")}[0]=~ /\((.+)\)$/; print("(hijacked $Type) p4 sync -f \"$File#have\"\n") }
	            warn("WARNING: update ", (-e $File)?"writable":"missing", " $File");
                push(@FilesToSync, "\"$File#have\"");
            }
        }
        $FirstIndex = $CommandLength = 0;
        for(my $i=0; $i<@FilesToSync; $i++)
        {
            if($i == $#FilesToSync)
            {
                $p4->sync("-f", @FilesToSync[$FirstIndex..$i]);
                die("ERROR: cannot sync '$File': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date\.$/);
            }
            elsif($CommandLength+length($FilesToSync[$i]) > $MAXIMUM_COMMAND_LENGTH)
            {
                $p4->sync("-f", @FilesToSync[$FirstIndex..$i-1]);
                die("ERROR: cannot sync '$File': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date\.$/);
                $FirstIndex    = $i;
                $CommandLength = 0;
            }
            $CommandLength += length($FilesToSync[$i]);
        }
        
        ## added files treatment: unlink ##
        @P4Have{@Files} = ();
        my $rsRemove = sub
        {
            if(-d) { $NumberOfRemove++ if(rmdir($File::Find::name)) }
            else
            {
                (my $File = $File::Find::name) =~ s/\\/\//g;
                return if(exists($P4Have{$File}) or exists($P4Opened{$File}));
                $NumberOfRemove++;
	            warn("WARNING: unlink $File");
                unlink($File) or warn("ERROR: cannot unlink '$File': $!") if(-e $File);
            }
        };
        my $raDirs = $p4->dirs("-H", "//$Client/*");
        die("ERROR: cannot dirs ${$rhFile}{depotFile}: ", @{$p4->Errors()}) if($p4->ErrorCount());
        foreach my $Dir (@{$raDirs})
        {
            chomp($Dir);
            $Dir =~ /^\/\/[^\/]+\/([^\/]+)/;
            next unless(!@Areas || exists($Areas{$1}));
            $Dir =~ s/^\/\/.+?\//$Root\//;
            $P4Dirs{$Dir} = undef;
            next if(exists($DirInError{$Dir}));
            finddepth($rsRemove, $Dir) if(-e $Dir);
        }
    }
}

if($Force && %P4Dirs && !@Areas)
{
    if(opendir(DIR, $Root))
    {
        while(defined(my $Dir = readdir(DIR)))
        {
            next if($Dir =~ /^\.\.?$/);
            $Dir = "$Root/$Dir";
            next unless(-d $Dir);
            next if(exists($P4Dirs{$Dir}));
            next if(-e "$Dir/.git");
            next if(-e "$Dir/content");
            next if($Dir =~ /[\\\/]O2O_metadata$/);
            $NumberOfRemove++;
            warn("WARNING: rmtree $Dir");
            $Dir = Win32::GetShortPathName($Dir) if($^O eq "MSWin32");
            rmtree($Dir) or warn("ERROR: cannot rmtree '$Root/$Dir': $!");
        }
        closedir(DIR);
    } else { warn("ERROR: cannot opendir '$Root': $!") }
}

print("$NumberOfRemove file(s) or dir(s) removed, $NumberOfUpdate file(s) updated\n");

END { $p4->Final() if($p4) }

($ss, $mn, $hh, $dd, $mo, $yy) = (localtime)[0..5];
printf("P4Clean ends at %04d/%02d/%02d %02d:%02d:%02d", $yy+1900, $mo+1, $dd, $hh, $mn, $ss);

#############
# Functions #
#############

sub Usage
{
   print <<USAGE;
   Usage   : P4Clean.pl [option]+
   Example : P4Clean.pl -h
             P4Clean.pl -c=Main_PI_lvwin014

   [option]
   -help|?     argument displays helpful information about builtin commands.
   -a.rea      clean only the specified areas.
   -c.lient    specifies the client name.
   -f.orce     force the clean for opened and hijacked files (-f.orce) or not (-nof.orce), default is -noforce.
   -r.mdironly remove obsolete folders only (-r.mdironly) or not (-nor.mdironly), default is \$ENV{"RM_DIR_ONLY"} (unset=not only).
   -x.ml       specifies context xml file.
USAGE
    exit;
}
