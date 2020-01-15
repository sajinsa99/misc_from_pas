#!/usr/bin/perl -w

use File::Find;
use Data::UUID;
use Net::SMTP;
use XML::DOM;

##############
# Parameters #
##############

die("ERROR: BUILD_NAME environment variable must be set") unless($BUILD_NAME=$ENV{BUILD_NAME});
die("ERROR: BUILD_CONFIG environment variable must be set") unless($BUILD_CONFIG=$ENV{BUILD_CONFIG});
die("ERROR: OUTPUT_DIR environment variable must be set") unless($OUTPUT_DIR=$ENV{OUTPUT_DIR});
die("ERROR: HOSTNAME environment variable must be set") unless($HOSTNAME=$ENV{HOSTNAME});
die("ERROR: PLATFORM environment variable must be set") unless($PLATFORM=$ENV{PLATFORM});
die("ERROR: OBJECT_MODEL environment variable must be set") unless($OBJECT_MODEL=$ENV{OBJECT_MODEL});
die("ERROR: build_number environment variable must be set") unless($BuildNumber=$ENV{build_number});
die("ERROR: TEMP environment variable must be set") unless($TEMP_DIR=$ENV{TEMP});
$ENV{SMTP_SERVER} ||= "mail.sap.corp";
$SMTPFROM = 'SAP_BIT_HotFixes_Requests@exchange.sap.corp';
#$SMTPTO = 'jean.maqueda@sap.com;louis.lecaroz@sap.com';
$SMTPTO = 'jean.maqueda@sap.com';

########
# Main #
########

open(DAT, "$OUTPUT_DIR/obj/ImpactedAreas.dat") or warn("ERROR: cannot open '$OUTPUT_DIR/obj/ImpactedAreas.dat': $!");
eval <DAT>;
close(DAT);
open(DAT, "$OUTPUT_DIR/obj/Users.dat") or warn("ERROR: cannot open '$OUTPUT_DIR/obj/Users.dat': $!");
eval <DAT>; 
close(DAT);

open(TXT, "$OUTPUT_DIR/obj/BuildDateEPOCH.txt") or die("ERROR: cannot open '$OUTPUT_DIR/obj/BuildDateEPOCH.txt': $!");
$BUILD_DATE_EPOCH = <TXT>;
chomp($BUILD_DATE_EPOCH);
close(TXT);

foreach my $Area (keys(%AreasToCompile))
{
    unless(-d "$OUTPUT_DIR/deploymentunits/$Area") { warn("ERROR: '$OUTPUT_DIR/deploymentunits/$Area' not found'"); next }
    opendir(DU, "$OUTPUT_DIR/deploymentunits/$Area") or warn("ERROR: cannot opendir '$OUTPUT_DIR/deploymentunits/$Area': $!");
    while(defined(my $DU = readdir(DU)))
    {
        next unless(-f "$OUTPUT_DIR/deploymentunits/$Area/$DU/assemblylist.xml");
        my $ASSEMBLY = XML::DOM::Parser->new()->parsefile("$OUTPUT_DIR/deploymentunits/$Area/$DU/assemblylist.xml");
        for my $SOURCEDIR (@{$ASSEMBLY->getElementsByTagName('sourcedir')})
        {
            (my $SrcDir = $SOURCEDIR->getAttribute('id')) =~ s/\\/\//g;
            for my $FILE (@{$SOURCEDIR->getElementsByTagName('file')})
            {
                (my $Name = $FILE->getAttribute('name')) =~ s/\\/\//g;
                ${$DUs{"\u$SrcDir/$Name"}}{$DU} = undef;
            }
        }
        $ASSEMBLY->dispose();
    }   
    closedir(DU);
}

open(TXT, ">$OUTPUT_DIR/obj/ImpactedBinaries.txt") or die("ERROR: cannot open '$OUTPUT_DIR/obj/ImpactedBinaries.txt': $!");
foreach my $Area (keys(%AreasToCompile))
{
    unless(-d "$OUTPUT_DIR/bin/$Area") { warn("ERROR: '$OUTPUT_DIR/bin/$Area' not found'"); next }
    find(\&ImpactedBinary, "$OUTPUT_DIR/bin/$Area");
}
close(TXT);

map({ @Changes{keys(%{$Users{$_}}) } = (undef)} keys(%Users));
$ug = Data::UUID->new();
map( {SendMail($_)} keys(%Users));

#############
# Functions #
#############

sub ImpactedBinary
{
    return unless(-f $File::Find::name);
    my $mtime = (stat($File::Find::name))[9];
    (my $File = $File::Find::name) =~ s/\\/\//g;
    #return unless($mtime >= $BUILD_DATE_EPOCH and exists($DUs{"\u$File"}));
    return unless($mtime >= $BUILD_DATE_EPOCH);
    print(TXT "$File::Find::name\n");
}

sub SendMail
{
    my($User) = @_;
    my $RequestID = $ug->to_string($ug->create());

    open(MAIL, ">$TEMP_DIR/Mail$$.txt") or warn("ERROR: cannot open '$TEMP_DIR/Mail$$.txt': $!");
    print(MAIL "; Please complete the following list of impacted binaries files to be installed in the [Impacted binaries] section without quoting, for the following context:\n\n");
    print(MAIL "[Request information]\n");
    print(MAIL "Build name=$BUILD_NAME\n");
    print(MAIL "Build version=$BuildNumber\n");
    print(MAIL "Build platform=$PLATFORM\n");
    print(MAIL "Build model=$OBJECT_MODEL\n");
    print(MAIL "Build configuration file=$BUILD_CONFIG\n");
    print(MAIL "Build hostname=$HOSTNAME\n");
    print(MAIL "Build responsible=arun02.singh\@sap.com\n");
    print(MAIL "Changelists=", join(', ', keys(%Changes)),"\n");
    print(MAIL "Owned changelists by current user=", join(', ', keys(%{$Users{$User}})), "\n");
    print(MAIL "Request-id=$RequestID\n\n");
    print(MAIL "[Impacted binaries]\n");
    my $REChangedAreas = join('|', grep({$AreasToCompile{$_}} keys(%AreasToCompile)));
    (my $output_dir = $OUTPUT_DIR) =~ s/\\/\//g;
    open(TXT, "$OUTPUT_DIR/obj/ImpactedBinaries.txt") or die("ERROR: cannot open '$OUTPUT_DIR/obj/ImpactedBinaries.txt': $!");
    while(<TXT>)
    {
        next unless(/$REChangedAreas/);
        chomp;
        (my $Binary = $_) =~ s/\\/\//g;
        $Binary =~ s/$output_dir\///;
        print(MAIL "$Binary\n");
    }
    close(TXT);
    print(MAIL "\n[Impacted clients binaries]\n");
    open(TXT, "$OUTPUT_DIR/obj/ImpactedBinaries.txt") or die("ERROR: cannot open '$OUTPUT_DIR/obj/ImpactedBinaries.txt': $!");
    while(<TXT>)
    {
        next if(/$REChangedAreas/);
        chomp;
        (my $Binary = $_) =~ s/\\/\//g;
        $Binary =~ s/$output_dir\///;
        print(MAIL "$Binary\n");
    }
    close(TXT);
    close(MAIL);

    my $smtp = Net::SMTP->new($ENV{SMTP_SERVER}, Timeout=>60) or warn("ERROR: SMTP connection impossible: $!");
    $smtp->mail($SMTPFROM);
    my $smptto = join(';', $User, $SMTPTO);
    #$smptto = $SMTPTO;   # FOR DEBUG
    $smtp->to(split('\s*;\s*', $smptto));
    $smtp->data();
    $smtp->datasend("To: $smptto\n");
    $smtp->datasend("Subject: [IMPORTANT] Hot Fix request '$RequestID'; please answer !\n");
    $smtp->datasend("content-type: text/plain; charset: iso-8859-1; name=Mail.txt\n");
    $smtp->datasend("Priority: Urgent\n");
    open(TXT, "$TEMP_DIR/Mail$$.txt") or warn ("ERROR: cannot open '$TEMP_DIR/Mail$$.txt': $!");
    while(<TXT>) { print; $smtp->datasend($_) } 
    close(TXT);
    $smtp->dataend();
    $smtp->quit();

    unlink("$TEMP_DIR/Mail$$.txt") or warn("ERROR: cannot unlink '$TEMP_DIR/Mail$$.txt': $!");
}