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
        [qr/\b\d+\s(?:failed|errors?)\b/i                         , qr/\b0+\s(?:failed|errors?)\b|error.h|^Win32\\SINGLE_SETUP - 1 error\(s\)|nohup.out/i, undef],
        [qr/^Invalid solution configuration\b/                    , undef, undef],
    ],
    # applies to all languages - with general exceptions
    'all_general' => [
        # An error                                                , Except this               , End of description
        [qr/error:/i                               								, qr/cannot copy .+\/\.|RETRY LIMIT EXCEEDED/, undef],
        [qr/Command failed:/i                               			, qr/-u sdbmake -P make4MaxDB/, undef],
        [qr/not made/i                               							, undef, undef],
        [qr/dependency errors/i                               		, undef, undef],
        [qr/TARGETS FAILED/i                               				, undef, undef],
        [qr/FAILED /i                               							, qr/Failed to undeploy delivery unit|Skipped  Mismatch    FAILED|GERRIT_CHANGE_SUBJECT/, undef, undef],
				[qr/Error while/i                               					, undef, undef],
				[qr/Connection refused/i                               		, undef, undef],
				[qr/ Error \d+ /i                                         , qr/install\-data\-local|Failed to undeploy delivery unit|nohup.out/, undef],	
				[qr/\bno rule to make target\b/i                          , qr/clean/i, undef],
        [qr/\bno such file\b/i                                    , qr/(?:libtoolT|install|rm|chmod|python_runtime\/support\/Python\/python26.so|\/.' to)/, undef],
        [qr/AOM_AREA.+PROC/																				, undef, undef],
        [qr/installer not found, exiting/													, undef, undef],
        [qr/Installation failed/																	, undef, undef],      
    ],
    # applies to default
    'default' => [
    ],
);

1; 
