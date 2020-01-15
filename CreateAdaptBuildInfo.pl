#!/usr/bin/perl

#create a BuildInfo object in perforce and associate a list of FR and DevTask with the build
#parameter : build_name, stream, fich_in, fich_out
#the fich_in contains the list of Fr and DevTask (one each line)
#the fich_out is the log file

#Use LWP::Simple ;
use LWP;
require HTTP::Request;

# set home variable
our $Home = $^O eq 'MSWin32' ? $ENV{SYSTEMDRIVE} : $ENV{HOME};

# pragmas
use strict;
use warnings;

#my ( $BuildName , $Stream , $ListeId ) = @ARGV ; ;
my ( $BuildName , $Stream , $fich_in , $fich_out ) = @ARGV ;

#print "b= $BuildName ,
my $result ;
if ( $BuildName and $Stream  )
{
     my $BuildToBeCreated = 1 ;
     if ( open IN , "<$fich_in" )
     {
     	my %liste_id ;
     	my $ind = 0 ;
        while ( <IN> )
        {
              /^\s*(ADAPT\d*)/ ;
              if ( $1 )
              {
                 $liste_id{$1} = "ok" ;
                 $ind ++ ;
                 if ( $ind >= 30 ) # a modifier
                 {
                 	my $ListeId = join ',' , sort keys %liste_id ;

                        $BuildToBeCreated = 0 ;
                        $result .= AddFrToBuildInfo($BuildName,$Stream,$ListeId) . "\n";
                        #my $res_fr_check = `$WGET --proxy=off -q -O- http://rmcqapps.product.businessobjects.com/Internal_Applications/ReleaseManagement/BuildInfo/CreationBuildInfo.asp?build_name=$BuildName&liste_id=$ListeId&stream=$Stream`;
                        #die "problem reaching cqweb.rd.crystald.net : $res_fr_check\n" unless $res_fr_check =~ /^build name/ ;
                        #$result .= "$res_fr_check\n" ;
                        $ind = 0 ;
                        undef %liste_id ;
                 }
              }
        }
        #inscrire les derniers 
        if ( %liste_id )
        {
                my $ListeId = join ',' , sort keys %liste_id ;
                $BuildToBeCreated = 0 ;
                $result .= AddFrToBuildInfo($BuildName,$Stream,$ListeId) . "\n";
                #my $res_fr_check = `$WGET --proxy=off -q -O- http://rmcqapps.product.businessobjects.com/Internal_Applications/ReleaseManagement/BuildInfo/CreationBuildInfo.asp?build_name=$BuildName&liste_id=$ListeId&stream=$Stream`;
                #die "problem reaching cqweb.rd.crystald.net : $res_fr_check\n" unless $res_fr_check =~ /^build name/ ;
                #$result .= "$res_fr_check\n" ;
                $ind = 0 ;
                undef %liste_id ;
        }
     }
     if ( $BuildToBeCreated )
     {
     	 #BuildInfo creation without FR
     	 $result .= "Build creation withour FR : " . AddFrToBuildInfo($BuildName,$Stream) ;
         #my $res_fr_check = `$WGET --proxy=off -q -O- http://rmcqapps.product.businessobjects.com/Internal_Applications/ReleaseManagement/BuildInfo/CreationBuildInfo.asp?build_name=$BuildName&stream=$Stream`;
         #die "problem reaching cqweb.rd.crystald.net : $res_fr_check\n" unless $res_fr_check =~ /^build name/ ;
         #$result .= "Build creation withour FR : $res_fr_check" ;
     }
}
else
{
    $result .= "You must provide the Build Name and the stream to create the BuildInfo in ADAPT \n" ;
    $result .= "Usage : CreateAdaptBuildInfo.pl BuildName Stream Fich_in Fich_out\n\n" ;
    die $result ;
}

my @result = split(/<BR>/, $result);
map {
    s/^(.* not found)/ERROR: $1/i;
} @result;
$result = join("\n", @result);
if (defined $fich_out and open OUT  , ">$fich_out" )
{
   print OUT "CreateAdaptBuildInfo.pl\n" ;
   print OUT "------------------------\n" ;
   print OUT "BuidlName = $BuildName\n" ;
   print OUT "Stream    = $Stream\n" ;
   print OUT "Fich_in   = $fich_in\n" ;
   print OUT "Fich_out  = $fich_out\n" ;
   print OUT "------------------------\n\n" ;
   print OUT "$result\n" ;
   close OUT ;
}
else
{
   print "CreateAdaptBuildInfo.pl\n" ;
   print "------------------------\n" ;
   print "BuidlName = $BuildName\n" ;
   print "Stream    = $Stream\n" ;
   print "Fich_in   = $fich_in\n" ;
   #print "Fich_out  = $fich_out\n" ;
   print "------------------------\n\n" ;
   print "$result\n" ;
}

sub AddFrToBuildInfo_old
{
  my ($build,$stream ,$listeFr) = @_ ;
  my $url = "http://rmcqapps.product.businessobjects.com/Internal_Applications/ReleaseManagement/BuildInfo/CreationBuildInfo.asp?build_name=$build&stream=$stream" ;
  $url .= "&liste_id=$listeFr" if  $listeFr ;
  print "Appel de $url\n" ;
  return get($url) ;
  #my $res_fr_check = `$WGET --proxy=off -q -O- $url`;
  #die "problem reaching cqweb.rd.crystald.net : $res_fr_check\n" unless $res_fr_check =~ /^build name/ ;
  #return "$res_fr_check\n" ;

}

sub AddFrToBuildInfo
{
  my ($build,$stream ,$listeFr) = @_ ;
  my $url = "http://vanpgapps11.pgdev.sap.corp:1080/Internal_Applications/ReleaseManagement/BuildInfo/CreationBuildInfo.asp?build_name=$build&stream=$stream" ;
  $url .= "&liste_id=$listeFr" if  $listeFr ;
  print "Appel de $url\n" ;

  my $request = HTTP::Request->new(GET => $url);
  my $ua = LWP::UserAgent->new;

  my $response = $ua->request($request);

  if ($response->is_success)
  {
     return $response->content;
  }
  else
  {
     return "Error : " . $response->error_as_HTML;
  }
}