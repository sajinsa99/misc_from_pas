package XProcessLogRE;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
use Exporter;
$VERSION = 1.00;
@ISA = qw(Exporter);
@EXPORT = qw(%patterns);

%XProcessLogRE::patterns = (
    # applies to all languages - no general exceptions
    'all_special' => [
        [qr/\b\d+\s(?:failed|errors?)\b/i                         , qr/\b0+\s(?:failed|errors?)\b|\*EXTRA File|error.h|^Win32\\SINGLE_SETUP - 1 error\(s\)/i, undef],
        [qr/^Invalid solution configuration\b/                    , undef, undef],
    ],
    # applies to all languages - with general exceptions
    'all_general' => [
        # An error                                                , Except this               , End of description, Email notification array, optional condition for sending notification  
        [qr/\bdoes not exist\b/i                                  , qr/\[javac\] \[JLin\] .+\$\{compiler\.bootclasspath\}\" does not exist and will be ignored\.$|\bdoes not exist, re|Will create one\.|\[uptodate\]|info \w+ classpath entry|SASSERTMSG|\bdoes not exist, creating it now\.|\[delete\] Directory does not exist:|\[INFO\]|\[warn\]|println|<description>The document does not exist.<\/description>/i, undef],
        [qr/\berror : .* failed\./i                               , undef, undef,	],
        [qr/Exception in thread/i                                , undef, undef, 	],
        [qr/^Project.+failed to open.make/i                       , undef, undef,],
        [qr/^[a-z.]+: error \w+:\s/i                              , undef, undef, 	],
        [qr/^\[idcard2wix\].*: Error:/i                           , undef, undef, 	],
        [qr/^\s*error before\b/i                                  , undef, undef,	],
        [qr/^\s*error\s?:\s/i                                     , qr/error : -500|error : -501|EXTRA File/, undef,],
        [qr/The system cannot find the file specified\./i         , undef, undef,],
        [qr/^Access denied/i                                      , undef, undef,],
        [qr/\|Exception./i                                        , undef, undef,	],
        [qr/OutOfMemoryError/i                                    , qr/OutOfMemoryError\.class/i, undef,['DL_522F903BFD84A01F490040AE@exchange.sap.corp']],
        [qr/^java.io.IOException: There is not enough space on the disk/i, undef, undef, ['DL_522F903BFD84A01F490040AE@exchange.sap.corp']], # DL PI HANA Plat PRODUCTION Build Tools France <DL_525E8385DF15DB3110000BE4@exchange.sap.corp>
        [qr/problems with insufficient memory/i                   , undef, undef,],
        [qr/Connection timed out/i                                , undef, undef,],
        [qr/Deep recursion on subroutine/i                        , undef, undef,],
        [qr/The network connection could not be found\./i         , undef, undef,],
        [qr/Failed/i                         					  , qr/Total    Copied   Skipped  Mismatch|ditamap\.failed/i, undef,['DL_522F903BFD84A01F490040AE@exchange.sap.corp']],
    ],
    # applies to default
    'default' => [
    ],
);

1; 
