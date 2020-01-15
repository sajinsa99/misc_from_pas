#!/usr/bin/perl -w
use Getopt::Long;
use Tie::IxHash;
use Net::SMTP;
use XML::DOM;
use FindBin qw($Bin);

my ( $context_file , $application_name , $application_version ) = @ARGV ;

my $legal_file = "$Bin\\legal.xml" ;

usage() unless ($context_file and $application_name  and $application_version ) ;
my %tp_lic ;

if($legal_file)
{
  my $LEGAL_CONTEXT = XML::DOM::Parser->new()->parsefile($legal_file);

  foreach my $tp  ( @{$LEGAL_CONTEXT->getElementsByTagName("Tp")} )
  {
    foreach my $lic  ( @{$tp->getElementsByTagName("Licence")} )
    {
          if (  $lic->getAttribute("app_name") eq $application_name && $lic->getAttribute("app_version") eq $application_version )
          {
            $tp_lic->{$tp->getAttribute("name")}->{$tp->getAttribute("version")} = $lic->getAttribute("lic_name") ;
          }
    }
  }
  print "\nCheck license for context $context_file \n          and for application $application_name , $application_version \n\n" ;

}

my $CONTEXT = XML::DOM::Parser->new()->parsefile($context_file);
      my $lic_granted = "";
      my $lic_internal = "";

      for my $COMPONENT (@{$CONTEXT->getElementsByTagName("fetch")})
      {
         my $tp2check = $COMPONENT->getFirstChild()->getData();
         if ( $tp2check =~ /^\/\/tp\/([^\/]*)\/([^\/]*)\// )
         {
           #print $tp2check , ":" , $1 , "," , $2 , "\n" ;
           if ( $tp_lic->{$1}->{$2} )
           {
             if ( $tp_lic->{$1}->{$2} eq "Internal Licence" )
             {
                   $lic_internal .= "      WARNING: " . $tp2check . ": \t" . $tp_lic->{$1}->{$2}. "\n"  ;
             }
             else
             {
                   $lic_granted .= "      " . $tp2check . ": \t" . $tp_lic->{$1}->{$2}. "\n"  ;
             }
             #print "      " , $tp2check , ":" , $tp_lic->{$1}->{$2}, "\n" ;
           }
           elsif ($tp2check =~ /^\/\/tp\/tp\.sap\./ )
           {
             $lic_granted .= "      " . $tp2check . ":  \tLic SAP\n" ;
             #print "      " , $tp2check , ":  Lic SAP\n" ;
           }
           else
           {
             print "      ERROR: " , $tp2check , ":  \tNO LIC\n" ;
           }
         }
      }
      
      print "\n\n$lic_internal\n\n$lic_granted\n";

sub usage
{
   print <<USAGE;
   Usage   : CheckLegalTp4Build.pl context_file legal_application_name legal_application_verion
   
   for example to check the tp of the build cons of program aurora 4.1 :
     CheckLegalTp4Build.pl aurora41_cons_00795.context.xml "Business Intelligence platform" "4.1 (BI Aurora 4.1) (formerly BI Aurora 4.2)"
USAGE
   exit;
}