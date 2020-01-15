#!/usr/bin/perl
#========================================================================================
# Module: XDepUploadDB.pm
# For   : Saturn RM dependency tool to interact with the Jupiter dependency tool db.
#
package XDepUploadDB;
use strict;
use warnings;

# cpan
use DBI;
use DBD::Oracle qw(:ora_types);    
use File::Basename;
use Cwd qw(abs_path);
use Data::Dump qw(dump);

#----our bits
my $Home;
BEGIN{$Home = abs_path(dirname(__FILE__));};
use lib ($Home);
use XLogging;
use XDepDB (
'$G_DPSR_Host',
'$G_DPSR_Port',
'$G_DPSR_Sid',
'$G_DPSR_User',
'$G_DPSR_Passwd',
'$G_DPSR_Commit_Limit',
'$G_DPSR_Mapping_Format',
'$G_DPSR_P4_Format',
'$G_DPSR_MAX_MSG_LENGTH',
'$G_DPSR_Param_Format',
'%G_DPSR_Params',
'$G_DPSR_Param_Section',
'$G_DPSR_Mapping_Section'
);

# public subs
sub fillDatabase($;$);
sub stpRemoveRun($);

# private subs
sub _conn();
sub _setDateTime($);
sub _uploadFail($$$;$);
sub _getRunId($$$$$$);
sub _stpPreUpload($);
sub _stpUpload($$$$$$$$$);
sub _stpEnd($$$);
sub _discon(;$);
sub _parseParams($$$);
sub _parseFile($);
sub _setDescription($$$);

# global vars
my $DBH   = undef;
my $RunID = undef;
#========================================================================================
#                                   public subs
#========================================================================================
# upload dependency mapping to db.
#
# Parameters:
# $file         : the file holds all the parameters and dependency mappings
# $restart_from : optional. It is used to restart from a particular line in $file.
#
# return:
#    0 - if failed
#    1 - otherwise
#
sub fillDatabase($;$){
    my($file, $restart_from) = @_;
 
    my $start        = time;
    my $line_counter = 0;
    my $commit_cnt   = 0;
    my $has          = 0;
    my $inserted_cnt = 0;
    my $dup_cnt      = 0;
    my $sth          = undef;
    my %params       = ();
    my $uploaded_cnt = 0;
    my $found_mapping_section = 0;
        
    unless($file && -f $file && !-z $file && open(MAPPING, "<$file")){
        xLogErr("fillDatabase: failed in accessing '$file'. SYS_ERR: $! $@");
        return 0;    	
    }
    if(defined $restart_from && ($restart_from !~ /^\d+$/ || $restart_from < 0)){
        xLogErr("fillDatabase: invalid restart value '$restart_from'");
        return 0;
    }
 
    # locate $project, $stream, $platform, $revision, $datetime 
    unless(_parseParams(\*MAPPING, \%params, \$line_counter)){
        xLogErr("fillDatabase: failed to locate all params(".(join(',', (keys %G_DPSR_Params))).")");
        dump(%params);
        close(MAPPING);
        return 0;	
    }

    if(! defined $DBH && ! _conn()){  
        xLogErr("fillDatabase: failed in _conn");
        return 0;
    }
    
    # TODO: here it knows the keys of params. Should be hidden away.
    unless($RunID && $RunID =~ /^\d+$/){
        $RunID = _getRunId($DBH, $params{stream}, $params{platform}, $params{revision}, $params{datetime}, $params{project});
        unless($RunID && $RunID =~ /^\d+$/){
            _discon("fillDatabase: failed in _getRunId");
            return 0;	
        }
        
        unless(_setDescription($DBH, $params{project}, $RunID)){
            _discon("fillDatabase: failed in _setDescription for runid '$RunID' and project '$params{project}'");
            return 0;	
        }
    }
        
    $sth = _stpPreUpload($DBH);
    unless($sth){
        _discon("fillDatabase: failed in _stpPreUpload");
        return 0;	
    }
 
    # locate mapping section
    while(<MAPPING>){
        chomp;
        $line_counter++;     
        if(m<$G_DPSR_Mapping_Section>){
            xLogInf1("fillDatabase: dependency mapping section is found at Line $line_counter.");
            $found_mapping_section = 1;
            last;	
        }
    }
    unless($found_mapping_section){
        xLogErr("fillDatabase: failed to locate dependency mapping section. Now at Line $line_counter");
        return 0;	
    }
      
    # Keep track of p4 src missing files
    my $p4Missing = $file.".p4Missing";
    unless(open(P4MISSING, ">>$p4Missing")){
        xLogErr("fillDatabase: failed to open $p4Missing to write. SYS_ERR: $! $@");
        return 0;
    }
    
    # processing mapping lines
    while(<MAPPING>){
    	chomp;
    	s!\\!\/!g;   
    	$line_counter++;
    	next if(/^\s*$/);
    	
    	# support restart from a particular line
    	if($restart_from && $line_counter < $restart_from){
            xLogInf1("fillDatabase: restart enabled, skipping Line $line_counter");
    	    next;	
    	}
    	
    	unless($_ =~ m<$G_DPSR_Mapping_Format>){
    	    _uploadFail($DBH, $RunID, \$sth, "fillDatabase: skipping unknown mapping line format at Line $line_counter:'$_'");
    	    close(MAPPING);
    	    return 0;
    	}
    	
    	my($src, $bin) = ($1, $2);
    	unless($src && $bin){
    	    _uploadFail($DBH, $RunID, \$sth, "fillDatabase: failed to locate src or bin from line $line_counter. Line $line_counter:'$_'");	
    	    close(MAPPING);
    	    return 0;
    	}
    	
        my($depot, $project, $stream, $area, $path) = ($src =~ m<$G_DPSR_P4_Format>);    	
    	unless($depot && $project && $stream && $area && $path){
            _uploadFail($DBH, $RunID, \$sth, "fillDatabase: rollback due to failure to parse src '$src' at Line $line_counter:'$_'");
            close(MAPPING);
    	    return 0;	
    	}
    
    	my($binname, $bindir) = _parseFile($bin);	 	    
    	my $rc = _stpUpload($sth, $RunID, $depot, $project, $stream, $area, $path, $bindir, $binname);
    	#if($rc == 0 || $rc == 1 || $rc == 4){
    	if($rc == 0 || $rc == 1){
    	    _uploadFail($DBH, $RunID, \$sth,"fillDatabase: rollback(rc=$rc) due to failure in uploading Line $line_counter:'$_'");
    	    close(MAPPING);	
    	    return 0;
    	}
    	
    	# p4 src not existing, keep track of them all
    	print P4MISSING "P4 src missing: $src\n" if($rc == 4);
    	
    	$uploaded_cnt++;
    	$inserted_cnt++ if($rc == 2);
    	$dup_cnt++      if($rc == 3);
    	if(0 == ($uploaded_cnt % $G_DPSR_Commit_Limit)){
    	    unless(_stpEnd($DBH, $RunID, 1)){
    	        _uploadFail($DBH, $RunID, \$sth,"fillDatabase: rollback due to failure in commit at Line $line_counter:'$_'");
    	        close(MAPPING);	
    	        return 0;
    	    }
    	    $commit_cnt++;
    	}
    }
    close(MAPPING);
    
    # close p4 src missing handle
    close(P4MISSING);
    
    if($uploaded_cnt != ($commit_cnt * $G_DPSR_Commit_Limit) && ! _stpEnd($DBH, $RunID, 1)){
        _uploadFail($DBH, $RunID, \$sth, "fillDatabase: failed to commit the reset records.") ;	
        return 0;
    }
    
    $sth = undef;
    unless(_discon()){
        xLogErr("fillDatabase: failed in _discon");
        return 0;	
    }
    
    xLogInf1("fillDatabase: total uploads=$uploaded_cnt, total insertion=$inserted_cnt, total dup=$dup_cnt, total time cost=".((time - $start)/60)." mins");
    return 1;
}
###============================================================================
# delete a run from db
# 
# Parameters:
#    $runid = a valid runid
#
# return:
#    0 - if failed
#    1 - otherwise
#
sub stpRemoveRun($){
    my ($runid) = @_;
    
    my $pause = 10;
    xLogWrn("Removing Run '$runid'.....pause for $pause secs");
    sleep($pause);
    
    my $stp = undef;
    my($rc, $msg) = (-1, undef);
    my $rt = undef;
    
    unless($runid =~ /^\d+$/){
        xLogErr("_stpRemoveRun:invalid runid");
        return 0;
    }
    if(! defined $DBH && ! _conn()){  
        xLogErr("stpRemoveRun: failed in _conn");
        return 0;
    }

    eval{$stp=$DBH->prepare(q{
            BEGIN
                PKG_IMPORT.stp_remove_run(:runid, 
                                          :status_code, 
                                          :status_message);
            END;
         });
    };
    unless($stp){
        _discon("_stpRemoveRun: error in preparing handle. DB_ERR:$DBI::errstr");
        return 0;
    }
    
    $stp->bind_param(":runid", $runid);
    $stp->bind_param_inout(":status_code",    \$rc,  1);
    $stp->bind_param_inout(":status_message", \$msg, $G_DPSR_MAX_MSG_LENGTH);
    
    eval{$rt = $stp->execute;};
    $stp = undef;
    unless($rt){
        _discon("_stpRemoveRun: error in execution. Error:".$stp->errstr);
        return 0;
    }
    if(0 ne $rc){
        _discon("_stpRemoveRun: error from stp MSG: $msg");
        return 0;
    }
    
    xLogInf1("_stpRemoveRun: success for runid '$runid'");
    return _discon();
}
###=====================================================================================
#                                     private subs
###============================================================================
# find params, return as soon as all the params are located.
#
# Comments starts with # at the begining of a line.
#
# return:
#    0 - if error
#    1 - other
#
sub _parseParams($$$){
    my($fh, $rh, $rLine_counter) = @_;
    
    my $total_params_filled   = 0;
    my $expected_total_params = scalar(keys %G_DPSR_Params);
    my $found_param_section   = 0;
    while(<$fh>){
    	chomp;	
    	$$rLine_counter++;
    	next if(/^\s*$|^\s*\#/);
    	
    	if(m<$G_DPSR_Mapping_Section>){
    	    xLogErr("_parseParams: passed param section and will not found all params. Line $$rLine_counter");
    	    return 0;
    	}
    	
    	# detect param section    	
    	if(! $found_param_section && $_ =~ m<$G_DPSR_Param_Section>){
    	    $found_param_section = 1;
    	    xLogInf1("_parseParams: located params section at Line $$rLine_counter");
    	    next;
    	}
    	unless($found_param_section){
    	    next;	
    	}
    	
    	# validate param and its value
    	unless(m<$G_DPSR_Param_Format> && defined $1 && defined $2){
    	    xLogWrn("_parseParams: skip line due to unknown param format at Line $$rLine_counter:'$_'");
    	    next;
    	}
    	my $param = lc($1);
    	my $value = $2;
    	unless(defined $G_DPSR_Params{$param}){
    	    xLogWrn("_parseParams: skip unknown param '$param' at Line $$rLine_counter:'$_'");
    	    next;	
    	}
    	
    	unless($value && $value =~ m<$G_DPSR_Params{$param}>){
    	    xLogWrn("_parseParams: skip invalid value for param '$param' at Line $$rLine_counter:'$_'");
    	    next;	
    	}
    	
    	defined $rh->{$param} ? xLogWrn("_parseParams: redefining param '$param' at Line $$rLine_counter") : 
    	                        $total_params_filled++;
    	$rh->{$param}=$value;
    	
    	# done
    	if($total_params_filled >= $expected_total_params){
            xLogInf1("_parseParams: successfully located all the params");
    	    return 1;
    	}
    } 
    
    xLogErr("_parseParams: failed to locate all the params and now hit on the last Line $$rLine_counter");
    return 0;
}
###=====================================================================================
# Set the project to Runs table
#
# return :
#   0 - if failed
#   1 - otherwise
sub _setDescription($$$){
    my ($dbh, $project, $runid) = @_;
    
    unless($dbh && $project && $project =~ m<\S+> && $runid && $runid =~ m<^\d+$>){
        xLogErr("_setDescription: invalid input args");
        return 0;	
    }
    
    my $sth = $dbh->prepare(qq{
        UPDATE dependency.Runs
        SET description = \'$project\'
        WHERE runid = $runid
    });
    
    unless($sth){
        xLogErr("_setDescription: failed to prepare. DB_ERR: $DBI::errstr");
        return 0;	
    }
    
    my $rc = undef;
    eval{ $rc = $sth->execute; };
    $sth = undef;
    unless(defined $rc){
        xLogErr("_setDescription: failed to exe. DB_ERR: $DBI::errstr");
        return 0;
    }
    
    if(0 == $rc || 1 != $rc){
        xLogErr("_setDescription: failed rc=$rc");
        return 0;	
    }
    
    xLogInf1("_setDescription: successfully set $project for runid $runid");
    return 1;
}
###=====================================================================================
# Also set datetime format
#
# return:
#    undef - if failed
#    dbh   - otherwise
#
sub _conn(){   
    $ENV{NLS_LANG} = "AMERICAN_AMERICA.AL32UTF8";
    
    eval{
        $DBH = DBI->connect("dbi:Oracle:host=$G_DPSR_Host;sid=$G_DPSR_Sid;port=$G_DPSR_Port;",
                           $G_DPSR_User, $G_DPSR_Passwd, { AutoCommit => 0 });
    };
   
    unless(defined $DBH){
        xLogErr("_conn: failed to make connection to DB. DB_ERR: $DBI::errstr");
        return 0;
    }
    
    # set datetime format
    unless(_setDateTime($DBH)){
        xLogErr("_conn: in _setDateTime");
        disconn($DBH);
        return 0;
    }

    return 1;
}
###============================================================================
# return:
#    0 - if failed
#    1 - otherwise
#
sub _setDateTime($){
    my ($dbh) = @_;
     
    # set datetime format
    my $rc = 0;
    eval{ $rc = $dbh->do("ALTER SESSION SET NLS_DATE_FORMAT='DY MON DD HH24:MI:SS YYYY'");};
    
    unless($rc){
        xLogErr("_setDateTime: failed to alter date format DB_ERR: $DBI::errstr");
        return 0;
    }
    
    return 1;
}
###=============================================================================
sub _uploadFail($$$;$){
    my($dbh, $runid, $rsth, $msg) = @_;
    $$rsth = undef;
    _stpEnd($dbh, $runid, 0);
    _discon($msg);	
}
###============================================================================
# return:
#    0 - if failed
#    runid - otherwise
#
sub _getRunId($$$$$$){
    my ($dbh, $stream, $platform, $revision, $datetime, $project) = @_;
    
    unless($dbh){
       xLogErr("_getRunId:invalid dbh");
       return 0;
    }
        
    my ($runid, $rc, $msg) = (0, -1, undef); 
    my $stp = undef;
    eval{ $stp= $dbh->prepare(q{
              BEGIN
                PKG_IMPORT.stp_imp_runs(:stream, 
                                        :platform, 
                                        :revision, 
                                        :datetime, 
                                        :project,
                                        :runid, 
                                        :status_code, 
                                        :status_message);
              END;
          });
    };
    
    unless($stp){
       xLogErr("_getRunId:error in preparing stp for _getRunId");
       return 0;
    }
    $revision = int($revision);
    $stp->bind_param(":stream",   $stream);
    $stp->bind_param(":platform", $platform);
    $stp->bind_param(":revision", $revision);
    $stp->bind_param(":datetime", $datetime);
    $stp->bind_param(":project",  $project);
    $stp->bind_param_inout(":runid",          \$runid, 1);
    $stp->bind_param_inout(":status_code",    \$rc,    1);
    $stp->bind_param_inout(":status_message", \$msg,   $G_DPSR_MAX_MSG_LENGTH);
    
    my $rt = undef;
    eval{$rt = $stp->execute;};
    unless($rt){
        xLogErr("_getRunId:error in execution. params[dbh($dbh), stream($stream), platform($platform), revision($revision), datetime($datetime), project($project)]. Error:".$stp->errstr);
        return 0;
    }
    unless($runid){
        xLogErr("_getRunId:Failed to get runid. params[dbh($dbh), stream($stream), platform($platform), revision($revision), datetime($datetime), project($project)]. Error:$msg");
        return 0;
    }
    
    return $runid;
}
###============================================================================
# return:
#    undef - if failed
#    handle - otherwise
#
sub _stpPreUpload($){
    my ($dbh) = @_;
    
    unless($dbh){
        xLogErr();
        return undef;
    }

    my $stp = undef;
    eval{ $stp = $dbh->prepare(q{
              BEGIN
                  PKG_IMPORT.stp_imp_src2bin(:runid,
                                             :b_filename,
                                             :b_dirname,
                                             :p_stream,
                                             :p_area,
                                             :p_project,
                                             :p_depot,
                                             :p_path,
                                             :status_code,
                                             :status_message);
              END;
           });
    };
    
    unless($stp){
        xLogErr("_stpPreUpload:error in prepare handle. DB_ERR:".$DBI::errstr);
        return undef;
    }
    
    return $stp;
}

###============================================================================
# return:
#    0 - if failed
#    1 - internal error
#    2 - insert
#    3 - update
#    4 - file id = 0, perforcedb error
sub _stpUpload($$$$$$$$$){  
    my ($stp, $runid, $depot, $project, $stream, $area, $path, $bindir, $binname) = @_;

    my ($rc, $msg) = (-1, undef);    
    $stp->bind_param(":runid",      $runid);
    $stp->bind_param(":b_filename", $binname);
    $stp->bind_param(":b_dirname",  $bindir);
    $stp->bind_param(":p_stream",   $stream);
    $stp->bind_param(":p_area",     $area);
    $stp->bind_param(":p_project",  $project);
    $stp->bind_param(":p_depot",    $depot);
    $stp->bind_param(":p_path",     $path);
    $stp->bind_param_inout(":status_code",    \$rc,  1);
    $stp->bind_param_inout(":status_message", \$msg, $G_DPSR_MAX_MSG_LENGTH);
    
    my $rt = undef;
    eval{ $rt = $stp->execute; };
    unless($rt){
        xLogErr("_stpUpload:error in execution. SYS_Error:".$stp->errstr);
        return 0;
    }
    
    my $src = "//$depot/$project/$stream/$area/$path";
    my $bin = $bindir . $binname;    
    if(0 ne $rc){
    	# stp: dup
        if(100 eq $rc){
            xLogInf1("_stpUpload Dup($rc): source($src) => bin($bin)");
            return 3;
        }
        
        # stp: file id == 0
        if(3 eq $rc){
            xLogErr("_stpUpload:Error($rc), file id = 0 src($src) bin($bin) from stp msg: $msg");
            return 4;	
        }
        
        # stp: fileid or binid generation error
        if(2 eq $rc){
            xLogErr("_stpUpload:Error($rc), id generation error from stp msg: $msg");
            return 1;
        }
        
        # stp: invalid parameters
        if( 1 eq $rc){
            xLogErr("_stpUpload:Error($rc), Invalid parameter from stp msg: $msg");
            return 1;	
        }
        
        xLogErr("_stpUpload:Unknown Error($rc) from stp msg:$msg");
        return 0;
    }
    
    # insert
    return 2;
}
###============================================================================
# $action = 1 - commit
# $action = 0 - rollback
#
# return:
#    0 - if failed
#    1 - otherwise
#
#
sub _stpEnd($$$){
    my ($dbh, $runid, $action) = @_;
    
    unless( (1 eq $action) || (0 eq $action)){
        xLogErr("_stpEnd:invalid action");
        return 0;
    }
    unless($runid =~ /^\d+$/){
        xLogErr("_stpEnd:invalid runid");
        return 0;
    }
    unless($dbh){
        xLogErr("_stpEnd:invalid dbh");
        return 0;
    }
    
    my $stp = undef;
    eval{$stp=$dbh->prepare(q{
            BEGIN
                PKG_IMPORT.stp_imp_src2bin_commitrollback(:runid,
                                                         :commit_rollback,
                                                         :status_code,
                                                         :status_message);
            END;
         });
    };    
    unless($stp){
        xLogErr("_stpEnd:Error in prepare handle. DB_ERR:".$DBI::errstr);
        return 0;
    }
    
    my $act = (1 eq $action) ? 'commit' : 'rollback';
    my ($rc, $msg) = (-1, undef);
    $stp->bind_param(":runid",           $runid);
    $stp->bind_param(":commit_rollback", $act);
    $stp->bind_param_inout(":status_code",    \$rc,  1);
    $stp->bind_param_inout(":status_message", \$msg, $G_DPSR_MAX_MSG_LENGTH);
   
    my $rt = undef;
    eval{$rt=$stp->execute;};
    unless($rt){
        xLogErr("_stpEnd:error in execution. runid($runid) action($action) act($act) Error:".$stp->errstr);
        return 0;
    }
    if(0 ne $rc){
        xLogErr("_:stpEnd:Error($rc) runid($runid) action($action) act($act) from stp msg:$msg");
        return 0;
    }
    
    return 1;
}
###============================================================================
# return:
#    0 - if failed
#    1 - otherwise
#
sub _discon(;$){
   my ($msg) = @_;
     
   if($msg){
       xLogErr("MSG when _discon: $msg");	
   }
   
   if(defined $DBI::errstr){
       my $err = "DB_ERR:";
       $err .= $DBI::errstr;
       xLogErr("ERR Message when _discon: $err");
   }
   my $rc = undef;
   eval{ $rc  = $DBH->disconnect; };
   $DBH = undef;
   unless(defined $rc){
       xLogErr("_discon: failed to disconnect, DB_ERR: $DBI::errstr") ;   
       return 0;
   }
   
   return 1;
}
###============================================================================
# return:
#    file name and path
#
sub _parseFile($){
    my ($file) = @_;
    $file =~ s!\\!\/!g;
    my ($name, $path, $ext) = fileparse($file,'\.[^\.]+$');
    $name .= $ext if(defined $ext);
    $path  =~ s!\\!\/!g;
    return ($name, $path);
}
###============================================================================

1;
