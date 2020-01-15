#!/usr/bin/perl -w

use Date::Calc(qw(Today_and_Now Delta_DHMS Add_Delta_Days));
use Sys::Hostname;
use Getopt::Long;
use File::Path;
use Win32::OLE;
use Net::SMTP;

use FindBin;
use lib ($FindBin::Bin);
$ENV{PW_DIR} ||= (($^O eq "MSWin32") ? '\\\\build-drops-wdf\dropzone\documentation\.pegasus' : '/net/build-drops-wdf/dropzone/documentation/.pegasus');
require  Perforce;

$ENV{SMTP_SERVER} ||= "mail.sap.corp";
$SMTPFROM = $SMTPTO = 'DL_522F903BFD84A01F490040AE@exchange.sap.corp';
$SMTPTO = 'jean.maqueda@sap.com';
$NumberOfEmails = 0;
$HOST = hostname();
#$SIG{__DIE__} = sub { SendMail(@_); die(@_) };
#$SIG{__WARN__} = sub { SendMail(@_); warn(@_) };
#$SIG{TERM} = $SIG{INT} = sub { SendMail("Caught a signal $!"); die("Caught a signal $!") };

##############
# Parameters #
##############

die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
GetOptions("help|?"=>\$Help, "directory=s"=>\@Directories, "project=s"=>\@Projects, "target=s"=>\@Targets);
Usage() if($Help);

@Targets = qw(src/cms win64_x64) unless(@Targets);
@JOBS = ('C:\Build\shared\jobs\documentation.txt');

########
# Main #
########

@Start = Today_and_Now();

$fso = Win32::OLE->new('Scripting.FileSystemObject');

if(@Projects)
{
    foreach my $PathName (@Projects)
    {
        my($Directory, $Project) = $PathName =~ /^(.+)[\\\/](.+)$/;
        my($FromPath, $ToPath) = ("$Directory\\$Project", "$Directory\\todelete\\$$\\$Project");
        map({CleanDir("$FromPath/$_", "$ToPath/$_") if(-d "$FromPath/$_")} @Targets);
        if(opendir(OUTPUT, "$FromPath\\src"))
        {
            while(defined(my $Output = readdir(OUTPUT)))
            {
                next unless(-d "$FromPath\\src\\$Output" && $Output=~/^..\-..\_.{16}$/);
                CleanDir("$FromPath\\src\\$Output", "$ToPath\\src\\$Output");
            }
            close(OUTPUT);
        }
    }
}
if(@Directories)
{
    $p4 = new Perforce;
    foreach my $Job (@JOBS)
    {
        $p4->sync('-f', $Job);
        warn("ERROR: cannot p4 sync '$Job': ", @{$p4->Errors()}) if($p4->ErrorCount() && ${$p4->Errors()}[0]!~/up-to-date.$/);
    
        open(TXT, $Job) or die("ERROR: cannot open '$Job': $!");
        while(<TXT>)
        {
            if(my($Host, $PhIO) = /\[([^.]+)\.[^.]+.([^.]+)\./)
            { 
                next unless($Host =~ /^$HOST$/i);
                $Projects{$PhIO} = undef;
            }
        }
        close(TXT);
    }
    
    foreach my $Directory (@Directories)
    {
        unless(opendir(PROJECT, "$Directory\\"))
        {
            warn("ERROR: cannot opendir '$Directory': $!");
            SendMail("ERROR: cannot opendir '$Directory': $!");
            next;
        }
        while(defined(my $Project = readdir(PROJECT)))
        {
            next unless(-d "$Directory\\$Project" && $Project=~/^[a-z0-9]{3}\d{13}$/i);
            if(exists($Projects{$Project}))
            {
                my($FromPath, $ToPath) = ("$Directory\\$Project", "$Directory\\todelete\\$$\\$Project");
                map({CleanDir("$FromPath/$_", "$ToPath/$_") if(-d "$FromPath/$_")} @Targets);
                if(opendir(OUTPUT, "$FromPath\\src"))
                {
                    while(defined(my $Output = readdir(OUTPUT)))
                    {
                        next unless(-d "$FromPath\\src\\$Output" && $Output=~/^..\-..\_.{16}$/);
                        CleanDir("$FromPath\\src\\$Output", "$ToPath\\src\\$Output");
                    }
                    close(OUTPUT);
                }
            }
            else { CleanDir("$Directory\\$Project", "$Directory\\todelete\\$$\\$Project") }
        }
        closedir(PROJECT);
    }
    
    my $raClients = $p4->clients("-E *_$HOST");
    die("ERROR: cannot 'p4 clients -E *_$HOST' : ", @{$p4->Errors()}) if($p4->ErrorCount());
    foreach (@{$raClients})
    {
        if((my($Client)=/^Client\s+(([a-z0-9]{3}\d{13})_$HOST)/i) && !exists($Projects{$2}))
        {
            my $raChanges = $p4->changes("-c $Client -s pending");
            warn("ERROR: cannot 'p4 changes -c $Client -s pending' : ", @{$p4->Errors()}) if($p4->ErrorCount());
            foreach (@{$raChanges})
            {
                my($Change) = /^Change\s+(\d+)/;
                $p4->SetOptions("-c $Client");
                $p4->change("-d $Change");
                warn("ERROR: cannot 'p4 change -d $Change' : ", @{$p4->Errors()}) if($p4->ErrorCount());
            }            
            print("p4 client -d $Client\n");
            $p4->SetOptions('');
            $p4->client("-d $Client");
            warn("ERROR: cannot 'p4 client -d $Client' : ", @{$p4->Errors()}) if($p4->ErrorCount());
        }
    }
}
printf("Clean took %u h %02u mn %02u s\n", (Delta_DHMS(@Start, Today_and_Now()))[1..3]);

END { $p4->Final() if($p4) } 

#############
# Functions #
#############

sub CleanDir
{
    my($SrcDir, $DstDir) = @_;
    
    my($ToPath) = $DstDir =~ /^(.*)[\\\/][^\\\/]+$/;
    mkpath($ToPath) or warn("ERROR: cannot mkpath '$ToPath': $!") unless(-d $ToPath); 
    rename($SrcDir, $DstDir) or warn("ERROR: cannot rename '$SrcDir': $!") if(-d $SrcDir);
    if(-d $SrcDir)
    {
        $fso->DeleteFolder($SrcDir, 1);
        warn("ERROR: can't delete folder '$SrcDir': ", Win32::OLE->LastError()) if(Win32::OLE->LastError());
    }
    if(-d $SrcDir)
    { 
        unless(rmtree($SrcDir))
        {
            warn("ERROR: cannot rmtree '$SrcDir': $!");
            SendMail("ERROR: cannot rmtree '$SrcDir': $!");
        }
    }
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
    $smtp->datasend("Subject: [$0] Errors on $HOST\n");
    $smtp->datasend("content-type: text/html; charset: iso-8859-1; name=Mail.htm\n");
    open(HTML, "$TEMP_DIR/Mail$$.htm") or warn("ERROR: cannot open '$TEMP_DIR/Mail$$.htm': $!");
    while(<HTML>) { $smtp->datasend($_) } 
    close(HTML);
    $smtp->dataend();
    $smtp->quit();

    unlink("$TEMP_DIR/Mail$$.htm") or warn("ERROR: cannot unlink '$TEMP_DIR/Mail$$.htm': $!");
}

sub Usage
{
   print <<USAGE;
   Usage   : $CleanProjects.pl -d -p
   Example : $CleanProjects.pl -h
             $CleanProjects.pl -d=C:

   [option]
   -help|?      argument displays helpful information about builtin commands.
   -d.irectory  specifies one or more directory names.
   -p.roject    specifies one or more project directory names.
   -t.arget     specifies one or more sub directory names. Default is src/cms and win64_x64
USAGE
    exit;
}
