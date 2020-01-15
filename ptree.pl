#!/usr/bin/perl

use Sys::Hostname;

#written by jboidot

$rootpid = shift;
$rootpid = 1 unless (defined $rootpid );
$depth=0;

$ENV{OBJECT_MODEL} = $OBJECT_MODEL 
                   = $Model ? "64"
                   : ($ENV{OBJECT_MODEL} || "32"
                   ); 
    if($^O eq "MSWin32") { $PLATFORM = $OBJECT_MODEL==64 ? "win64_x64"       : "win32_x86"      }
elsif($^O eq "solaris")  { $PLATFORM = $OBJECT_MODEL==64 ? "solaris_sparcv9" : "solaris_sparc"  }
elsif($^O eq "aix")      { $PLATFORM = $OBJECT_MODEL==64 ? "aix_rs6000_64"   : "aix_rs6000"     }
elsif($^O eq "hpux")     { $PLATFORM = $OBJECT_MODEL==64 ? "hpux_ia64"       : "hpux_pa-risc"   }
elsif($^O eq "linux")    { $PLATFORM = $OBJECT_MODEL==64 ? "linux_x64"       : "linux_x86"      }
elsif($^O eq "darwin")   { $PLATFORM = $OBJECT_MODEL==64 ? "mac_x64"         : "mac_x86"        }

my $HOST = hostname();
my $HERE = $ENV{HERE} || `pwd`;
chomp($HERE);
my $currentUser="";
my $tmpID=`id`;
chomp($tmpID);
($currentUser) = $tmpID =~ /\((.+?)\)/ ;
chomp($currentUser);
my $currentDate = `date`;
chomp($currentDate);

print "\n   $PLATFORM - $HOST - $currentUser - \"$currentDate\"\n\n";
print "pwd: $HERE\n\n";

@inlines = `ps -ef`;
foreach $curline (@inlines) {
    chomp $curline;
    $curline =~ s/^\s+//;
    ($user, $pid, $ppid, $dum, $pstart, $ptty, $ptime, $command)
    = split(/\s+/, $curline, 8);
    $command{$pid}=$command;
    $parent{$pid}=$ppid;
    $childs{$ppid}{$pid}=1;
}

pptree( $rootpid );
cptree( $rootpid );
print "\n";
exit;

##############################################################################
sub pptree {
    my $ref = shift;
    if( defined $parent{$ref} ) {
        if( $parent{$ref} > 1 ){
            pptree( $parent{$ref} );
            print "  " x $depth;
            print "$parent{$ref}  $command{$parent{$ref}}\n";
            $depth++;
        }
    }
}

sub cptree {
    my $ref = shift;
    print "  " x $depth;
    print "$ref  $command{$ref}\n";
    $depth++;
    foreach $pid ( sort {$a <=> $b} keys %{$childs{$ref}}) {
        cptree( $pid );
    }
    $depth--;
}
