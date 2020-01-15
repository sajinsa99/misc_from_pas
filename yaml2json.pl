#!/usr/bin/env perl

# pyaml2json.pl
#     YAML <-> JSON converter by Perl

# Prerequisite installation (on CentOS 6.x)
# -----------------------------------------
#     # yum -y install perl
#     # curl -L https://cpanmin.us | perl - App::cpanminus
#     # cpanm JSON YAML::Tiny

# * Synopsis
#     pyaml2json.pl [--yaml2json|--y2j] [--json2yaml|--j2y] [filenames...]
# * Usage
#     $ cat utf8.yml | pyaml2json.pl --yaml2json
#     $ cat utf8.json | pyaml2json.pl --json2yaml
# * Notice
#     * Mangles standard input or contents of specified files by arguments.
#     * Input and output must be in UTF-8 only ;( Sorry.
#     * [Null] data in YAML is described by '~'.

use strict;
use warnings;
use diagnostics;

use utf8;
use Encode qw( decode encode );
use Scalar::Util qw(blessed reftype);
use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);
use JSON;
use YAML::Tiny;

my( $y2j, $j2y );
GetOptions(
    'yaml2json|y2j' => \$y2j,
    'json2yaml|j2y' => \$j2y,
);

my $str = do { local $/; <>; };

# yaml2json mode:
if ( $y2j || !$j2y ) {
    print
    JSON->new
    ->ascii->pretty
    ->encode( Load $str )
    ;
    exit;
}

# json2yaml mode:
my $hash = 
JSON->new
->utf8
->decode( $str )
;
stringifyObjects( $hash );
print encode( 'utf8', Dump( $hash ) );

sub stringifyObjects {
    for my $val (@_) {
        next unless my $ref = reftype $val;
        if (blessed $val) {
            $val = "$val";
        } elsif ($ref eq 'ARRAY') {
            stringifyObjects(@$val);
        } elsif ($ref eq 'HASH')  {
            stringifyObjects(values %$val);
        }
    }
}
