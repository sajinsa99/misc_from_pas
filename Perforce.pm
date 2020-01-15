#!/usr/bin/perl -w

package Perforce;

use vars qw($AUTOLOAD);
use Carp;

use FindBin;
$CURRENT_DIR = $FindBin::Bin;

die("ERROR: TEMP environment variable must be set") unless($TEMPDIR=$ENV{TEMP});
$TEMPDIR =~ s/[\\\/]\d+$//;
$TICKET_TIMEOUT = $ENV{TICKET_TIMEOUT} || 11*60*60;
$PW_DIR = $ENV{PW_DIR} || (($^O eq "MSWin32") ? '\\\\build-drops-wdf\dropzone\aurora_dev\.xiamen' : '/net/build-drops-wdf/dropzone/aurora_dev/.xiamen');
$PWFILE = $ENV{PWFILE} || (($^O eq "MSWin32") ? "$PW_DIR\\.PW" : "$PW_DIR/.PW");
$NUMBER_OF_ATTEMPTS = $ENV{P4_ATTEMPS} || 5;

#%P4Hosts{P4HOST} = [PASS, EXPIRATION LOGIN DATE, GLOBALOPTIONS, TICKET]
$P4Options = '';
unless(exists($ENV{DISABLE_PERFORCE_PASSWORD_FILE}) && $ENV{DISABLE_PERFORCE_PASSWORD_FILE}=~/^(yes|true|on)$/i)
{
    if(-e $PWFILE)
    {
        if(open(PW, $PWFILE))
        {
            while(<PW>)
            {
                s/^\s*//;
                s/\s*$//;
                my($P4Host, $Attributes) = /^\s*(.+?)\s*=\s*(.+?)\s*$/;
                $P4Hosts{$P4Host} = [$Attributes, undef, $P4Options, undef];
                if($Attributes=~/{\s*(.+)}/)
                {
                    foreach my $Option (split(/\s*;\s*/, $1))
                    {
                        my($Key, $Value) = $Option =~ /^\s*(.+?)\s*=>\s*(.+?)\s*$/;
                        if($Key =~ /globalOptions/i) { $Value=~s/'//g; ${$P4Hosts{$P4Host}}[2] = "$P4Options $Value" }
                        elsif($Key =~ /login/i) { ${$P4Hosts{$P4Host}}[0] = $Value }
                    }
                }
                if(${$P4Hosts{$P4Host}}[0]=~/^\s*\*+\s*$/)
                {
                    ${$P4Hosts{$P4Host}}[0] = `$CURRENT_DIR/prodpassaccess/bin/prodpassaccess --credentials-file $PWFILE.properties --master-file $PW_DIR/.master.xml get $P4Host password`; chomp(${$P4Hosts{$P4Host}}[0]);
                }
            }
            close(PW);
        }
    }
} elsif($ENV{P4PORT} && $ENV{P4PASSWD}) { $P4Hosts{$ENV{P4PORT}} = [$ENV{P4PASSWD}, undef, $P4Options, undef] }
$| = 1;

sub new
{
    my $path_split_char = ":";
    my $extension = "";
    if ($^O eq "MSWin32") {
      $extension = ".exe";
        $path_split_char = ";";
   }

    my $p4_exists = 0;
    for my $path (split $path_split_char, $ENV{PATH}) {
        if ($path ne "" && -x "$path/p4$extension") {
            $p4_exists = 1;
         last;
      }

    }

    if(!$p4_exists) {
      return;
   }
    my($pkg) = @_;
    bless {"Input"=>undef, "Prefix"=>"", "Errors"=>[]}, $pkg;
}

sub Logon
{
    my($pkg) = @_;

    "a" =~ /a/;
    my($P4Host) = ($pkg->{Prefix}=~/-p\s*([^\s]+)/, $1) || $ENV{P4PORT} || (`p4 set P4PORT` =~ /=(.+)\s+\(set\)$/, $1);
    $P4Host =~ s/^"|"$//g;
    my($Password) = ${$P4Hosts{$P4Host}}[0] || $ENV{P4PASSWD} || (`p4 set P4PASSWD` =~ /=(.+)\s+\(set\)$/, $1);
    open(P4, "| p4 $pkg->{Prefix} login 2>$TEMPDIR/p4_error_file.$$.txt") or die("ERROR: cannot execute 'login': $!");
    print(P4 $Password);
    close(P4);
    @{$pkg->{Errors}} = ();
    open(P4ERROR, "$TEMPDIR/p4_error_file.$$.txt") or die("ERROR: cannot open '$TEMPDIR/p4_error_file.$$.txt': $!");
    while(<P4ERROR>) { push(@{$pkg->{Errors}}, $_) }
    close(P4ERROR);
    unlink("$TEMPDIR/p4_error_file.$$.txt") or die("ERROR: cannot unlink '$TEMPDIR/p4_error_file.$$.txt': $!") if(-e "$TEMPDIR/p4_error_file.$$.txt");
}

sub SetClient
{
    my($pkg, $Client) = @_;
    $pkg->{Prefix} = "-c \"$Client\"";
}

sub SetPassword
{
    my($pkg, $Password) = @_;

	my $P4Host;
	if(($P4Host)=$pkg->{Prefix}=~/-p\s*([^\s]+)/) {}
	elsif($P4Host||=$ENV{P4PORT}) {}
	else { ($P4Host) = `p4 set P4PORT` =~ /=(.+)\s+\(set\)$/ }
	$P4Host =~ s/^"//;
	$P4Host =~ s/"$//;
	${$P4Hosts{$P4Host}}[0] = $Password;
	${$P4Hosts{$P4Host}}[1] = undef;
}

sub SetOptions
{
    my($pkg, $Options) = @_;
    $pkg->{Prefix} = $Options;
}

sub Errors
{
    my $pkg = shift;
    return return $pkg->{'Errors'};
}

sub ErrorCount
{
    my $pkg = shift;
    return scalar(@{$pkg->{'Errors'}});
}

sub Init { ${$_}[0]->{Prefix}='toto'; return 1 }
sub Final { }
sub ParseForms { }

sub AUTOLOAD
{
    my $pkg = shift;

    return if $AUTOLOAD =~ /::DESTROY$/;
    (my $cmd = $AUTOLOAD ) =~ s/.*:://;
    $cmd = lc $cmd;

    $GlobalOptions = $P4Options;
    if(%P4Hosts)
    {
        my $P4Host;
        if(($P4Host)=$pkg->{Prefix}=~/-p\s*([^\s]+)/) {}
        elsif($P4Host||=$ENV{P4PORT}) {}
        else { ($P4Host) = `p4 set P4PORT` =~ /=(.+)\s+\(set\)$/ }
        $P4Host =~ s/^"//;
        $P4Host =~ s/"$//;
        if($P4Host && exists($P4Hosts{$P4Host}))
        {
            my($Password, $TimeOut, $P4Opt, $Ticket) = @{$P4Hosts{$P4Host}};
            if(!$TimeOut or time()>$TimeOut)
            {
                for(my $i=1; $i<=$NUMBER_OF_ATTEMPTS; $i++)
                {
                    open(P4, "| p4 $GlobalOptions $pkg->{Prefix} login -p >$TEMPDIR/ticket.$$  2>$TEMPDIR/p4_error_file.$$.txt") or die("ERROR: cannot execute 'login': $!");
                    print(P4 ${$P4Hosts{$P4Host}}[0]);
                    close(P4);

                    @{$pkg->{Errors}} = ();
                    open(P4ERROR, "$TEMPDIR/p4_error_file.$$.txt") or die("ERROR: cannot open '$TEMPDIR/p4_error_file.$$.txt': $!");
                    while(<P4ERROR>) { push(@{$pkg->{Errors}}, $_) }
                    close(P4ERROR);

                    open(P4TICKET, "$TEMPDIR/ticket.$$") or die("ERROR: cannot open '$TEMPDIR/ticket.$$': $!");
                    <P4TICKET>;
                    $Ticket = ${$P4Hosts{$P4Host}}[3] = $1 if(<P4TICKET> =~ /^(\w+)$/i);
                    close(P4TICKET);
                    unlink("$TEMPDIR/ticket.$$") or warn("WARNING: cannot unlink '$TEMPDIR/ticket.$$': $!");

                    unless($pkg->ErrorCount()) { ${$P4Hosts{$P4Host}}[1] = time()+ $TICKET_TIMEOUT; last }
                    chomp(${$pkg->{Errors}}[-1]);
                    carp("ERROR: cannot execute 'login' ($i/$NUMBER_OF_ATTEMPTS attempts) at ", __FILE__, " line ", __LINE__, ": ", @{$pkg->Errors()},": $!");
                    return undef if($i==$NUMBER_OF_ATTEMPTS);
                    sleep(24);
                }
            }
            $GlobalOptions = "$P4Opt -P $Ticket";
        }
    }

    if($cmd =~ /^save(\w+)/i)
    {
        die("Save$1 requires an argument!") unless(scalar( @_ ));
        $pkg->{Input} = shift;
        return $pkg->PERFORCE("$1 -i @_");
    }
    elsif($cmd =~ /^fetch(\w+)/i) { return $pkg->PERFORCE("$1 -o @_") }
    return $pkg->PERFORCE("$cmd @_");
}

sub PERFORCE
{
    my($pkg, $Command) = @_;

    # input #
    if($pkg->{Input})
    {
        if(ref($pkg->{Input}) eq "HASH")
        {
            open(OUT, ">$TEMPDIR/p4_input_file.$$.txt") or die("ERROR: cannot open '$TEMPDIR/p4_input_file.$$.txt': $!");
            foreach my $Key (sort(keys(%{$pkg->{Input}})))
            {
                my $Value = ${$pkg->{Input}}{$Key};
                if(ref($Value) eq "ARRAY")
                {
                    print(OUT "$Key:\n");
                    foreach(@{$Value}) { print(OUT "\t$_\n") }
                } else { print(OUT "$Key: $Value\n") }
            }
            close(OUT);
            $Command .= " < $TEMPDIR/p4_input_file.$$.txt";
        }
        $pkg->{Input} = undef;
    }
    $Command .= " 2>$TEMPDIR/p4_error_file.$$.txt";

    # A ameliorer...
    my @Results;
    for(my $i=1; $i<=$NUMBER_OF_ATTEMPTS; $i++)
    {
        @Results = ();
        open(P4, "p4 $GlobalOptions $pkg->{Prefix} $Command |") or die("ERROR: cannot execute '$Command': $!");
        while(<P4>) { push(@Results, $_) }
        close(P4);

        @{$pkg->{Errors}} = ();
        open(P4ERROR, "$TEMPDIR/p4_error_file.$$.txt") or die("ERROR: cannot open '$TEMPDIR/p4_error_file.$$.txt': $!");
        while(<P4ERROR>) { push(@{$pkg->{Errors}}, $_) }
        close(P4ERROR);
        chomp(${$pkg->{Errors}}[-1]) if($pkg->ErrorCount());
        my $ErrorLines = join(' ', @{$pkg->{'Errors'}});
        last unless($pkg->ErrorCount() && ($ErrorLines=~/TCP connect to.+failed\./ || $ErrorLines=~/Fatal client error/ || $ErrorLines=~/TCP receive failed/));
        carp("ERROR: cannot execute '$Command' ($i/$NUMBER_OF_ATTEMPTS attempts) at ", __FILE__, " line ", __LINE__, " : ", @{$pkg->Errors()},": $!");
        sleep(24);
    }

    unlink("$TEMPDIR/p4_input_file.$$.txt") or die("ERROR: cannot unlink '$TEMPDIR/p4_input_file.$$.txt': $!") if(-e "$TEMPDIR/p4_input_file.$$.txt");
    unlink("$TEMPDIR/p4_error_file.$$.txt") or die("ERROR: cannot unlink '$TEMPDIR/p4_error_file.$$.txt': $!") if(-e "$TEMPDIR/p4_error_file.$$.txt");
    ##############

    # A ameliorer aussi
    my %Results;
    if($Command=~/\s-o\s/ || $Command=~/^info/ || $Command=~/^fetch/)
    {
        RESULT: for(my $i=0; $i<@Results; $i++)
        {
            my $Result = $Results[$i];
            next if($Result=~/^#/ || $Result=~/^\s*$/);
            my($Key, $Value) = $Result =~ /^([^:]+):(.*)/;
            next unless($Key);
            if($Value && $Value=~/\S/) { $Results{$Key}=$Value }
            else
            {
                for($i++; $i<@Results; $i++)
                {
                    my $Result = $Results[$i];
                    redo RESULT unless($Result =~ /^\s+(.*?)\s*$/);
                    push(@{$Results{$Key}}, $1);
                }
            }
        }
    }
    ####################

    return keys(%Results) ? \%Results : \@Results;
}

1;
