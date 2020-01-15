#!/usr/bin/perl -w

use Getopt::Long;
use File::Path;
use JSON;

##############
# Parameters #
##############

die("ERROR: SRC_DIR environment variable must be set") unless($ENV{SRC_DIR});

Usage() unless(@ARGV);
GetOptions("help|?"=>\$Help, "area=s@"=>\@Areas, "dag=s"=>\$DAGFile);
Usage() if($Help);
die("ERROR: the DAG file name parameter is mandatory") unless($DAGFile);

########
# Main #
########

open(DAG, $DAGFile) or die("ERROR: cannot open '$DAGFile': $!");
{ local $/; $rhDAG = from_json(<DAG>) }
close(DAG);

# %Depends{id} = [$rhParents, SCM, branch, gav, IsCloned]
foreach my $rhNodes (@{${$rhDAG}{nodes}}) { @{$Depends{${$rhNodes}{id}}}[0..4] = (undef, ${${$rhNodes}{value}}{scm}, ${${$rhNodes}{value}}{branch}, ${${$rhNodes}{value}}{gav}, 0) }	
foreach my $rhLinks (@{${$rhDAG}{links}}) { ${${$Depends{${$rhLinks}{v}}}[0]}{${$rhLinks}{u}} = undef }
@Areas = keys(%Depends) unless(@Areas); 

foreach my $Child (@Areas)
{
	my %Parents;
	Parents(1, \%Parents, $Child);
	foreach my $Parent (keys(%Parents))
	{
		GitClone($Parent) unless(${$Depends{$Parent}}[4]);
	}
	GitClone($Child) unless(${$Depends{$Child}}[4])
}

#############
# Functions #
#############

sub GitClone
{
	my($Id) = @_;
	my($Repository, $RefSpec, $GAV) = @{$Depends{$Id}}[1..3];
	my($Destination) = (split(':', $GAV))[1];

	rmtree("$ENV{SRC_DIR}/$Destination") or warn("ERROR: cannot rmtree '$ENV{SRC_DIR}/$Destination': $!") if(-e "$ENV{SRC_DIR}/$Destination");
	mkpath("$ENV{SRC_DIR}/$Destination") or warn("ERROR: cannot mkpath '$ENV{SRC_DIR}/$Destination': $!");
	chdir("$ENV{SRC_DIR}/$Destination") or warn("ERROR: cannot chdir '$ENV{SRC_DIR}/$Destination': $!");
	system("git init");
	system("git fetch $Repository $RefSpec");
	system("git checkout FETCH_HEAD");
	${$Depends{$Id}}[4] = 1;
}

sub Parents
{
	my($Deep, $rhParents, $Child) = @_;
	return unless(${$Depends{$Child}}[0]);
	
	foreach my $Parent (keys(%{${$Depends{$Child}}[0]}))
	{
		${$rhParents}{$Parent} = undef;
		Parents($Deep+1, $rhParents, $Parent);
	}
}

sub Usage
{
   print <<USAGE;
   Usage   : CloneFromDAG.pl -d -a
   Example : CloneFromDAG.pl -h
             CloneFromDAG.pl -d=arimul_dag.json -a=arimul-versions

	-help|?      argument displays helpful information about builtin commands.
	-a.rea       specifies the node name.
    -d.ag        specifies the configuration file.
USAGE
    exit;
}
