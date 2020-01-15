use strict;
use warnings;
use diagnostics;
use Perl::Critic;
use Carp qw(cluck confess);


my $file = shift;
my $critic = Perl::Critic->new();
my @violations = $critic->critique($file);
print "\n";
print "perl file : $file\n";
print "========\n";
print @violations;
print "========\n";
print "\n";
exit 0;