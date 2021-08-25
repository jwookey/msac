%  MSAC_SAC - Run SAC commands.
%
%  MSAC toolkit function.
%
%  [result,...] = msac_sac(cmd,...) ;
%
%  Wrapper for matlab to run SAC through temporary macros (and optionally 
%  files). Warning: any error in the sac command(s) will silently abort SAC's
%  execution (as SAC is unreachably waiting for input in the background).
%  In this circumstance the script will wait for the timeout period to expire,
%  then fail with an error. 
%
%  Usage:
%
%  [result] = msac_sac(cmd)
%     The contents of command are placed in a temporary SAC macro, and SAC is
%     executed to run it. The (text) results are returned as a string. cmd can
%     be either a string or cell array of strings. Interactive or graphical 
%     operations are not possible (though plotting to disk via the sgf device
%     is). Any files generated (such as SGF plot files) by the commands sent are 
%     copied to the current directory.
%
%  [result] = msac_sac(cmd,tr)
%     The SAC trace(s) in the tr array are added for reading by the macro.
%     They are written to temporary files, and read in by SAC before the other
%     commands in the macro are processed.
%
%  [result,tr_out] = msac_sac(cmd,tr)
%     The SAC trace(s) in the tr array are also written back to temporary
%     storage and re-read back into the tr_out array, after the commands in 
%     cmd are executed.
%
%  Examples:
%
%  [~,tr_filt] = msac_sac('bp bu co 0.05 0.2 n 2 p 2',tr)
%     The trace(s) in tr are filtered using SAC's butterworth filter
%     algorith, and returned in tr_filt.
%
%  [~] = msac_sac('bg sgf; p1',tr)
%     The trace(s) in tr are plotted using SAC's p1 command to a SGF file
%     called f001.sgf.
%
%  [~,tr2]=msac_sac('funcgen seismogram',msac_new([0 1],0.1))
%     Creates a new seismogram with SAC's funcgen command. The msac_new
%     argument is required to provide a dummy trace.
%

%-------------------------------------------------------------------------------
%
%  This software is distributed under the term of the BSD free software license.
%
%  Copyright:
%     (c) 2003-2021, James Wookey
%
%  All rights reserved.
%
%   * Redistribution and use in source and binary forms, with or without
%     modification, are permitted provided that the following conditions are
%     met:
%        
%   * Redistributions of source code must retain the above copyright notice,
%     this list of conditions and the following disclaimer.
%        
%   * Redistributions in binary form must reproduce the above copyright
%     notice, this list of conditions and the following disclaimer in the
%     documentation and/or other materials provided with the distribution.
%     
%   * Neither the name of the copyright holder nor the names of its
%     contributors may be used to endorse or promote products derived from
%     this software without specific prior written permission.
%
%
%   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
%   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
%   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
%   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
%   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
%   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
%   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
%   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%
%-------------------------------------------------------------------------------

function [sac_result,varargout] = msac_sac(cmd,varargin) 
% check settings
if nargout>1 && nargin<=1
   error('MSAC_SAC: Output traces requested with no specified input traces') ;
end

%% options
sac_command = '/usr/local/sac/bin/sac' ;
opdir_root = '/tmp/' ; % root for temporary storage.
timeout = seconds(5) ; % time to wait for SAC to finish.

%% Configure, create, and go to the temporary directory
opdir = [opdir_root 'msac.' char(java.util.UUID.randomUUID) '/'] ;

[ierror,result] = system(['mkdir -p ' opdir]) ;
if ierror
   error(['MSAC_SAC: MKDIR: Failed with result: ',result]) ;
end

origdir = cd() ;
cd(opdir) ;

%% Write input data to disk, and generate a filename list

if nargin>=2
   tr = varargin{1} ;
   % generate a set of filenames
   ntr = length(tr) ;
   fname = cell(1,ntr) ;
   for i=1:ntr
      fname{i} = sprintf('s%4.4d',i) ;
   end
   % write the traces
   msac_mwrite(fname,tr) ;
   fname_list = '';
   for i=1:ntr
      fname_list = [fname_list sprintf('%s ',fname{i})] ;
   end
end

%% Construct the macro
fid = fopen(['run-macro'],'wt') ;

% first, read any data specified as input
if nargin>=2
   fprintf(fid,'r %s\n',fname_list) ;
end

% add the command(s) to the macro
if isstr(cmd)
   fprintf(fid,'%s\n',cmd) ;
elseif iscell(cmd)
   for i=1:length(cmd)
      fprintf(fid,'%s\n',cmd{i}) ;
   end
else
   error('MSAC_SAC: Bad format for command.') ;
end

% add an output line to the macro
if nargout>=2
   % add a write line to the SAC macro
   fprintf(fid,'w %s\n',fname_list) ;
end

% add the finalise commands to the macro
fprintf(fid,'sc touch sac_complete\n') ; % this outputs a file to allow MATLAB
                                         % to detect that SAC has completed
                                         % successfully
fprintf(fid,'quit\n') ;
fclose(fid) ;

%% Run SAC (in the background) with the macro, and catch the result
[ierror,sac_result] = system([sac_command ' run-macro &']) ;
if ierror
   error(['MSAC_SAC: Run SAC: Failed with result: ',result]) ;
end

% wait for a specified timeout
sac_complete = 0 ;
wait_until = datetime('now') + timeout;
while datetime('now') < wait_until
   if isfile('sac_complete')
      sac_complete = 1 ;
      break
   end
end

% check to see if SAC finished successfully.
if ~sac_complete
   cd(origdir) ;
   error('MSAC_SAC: Run SAC: SAC did not complete within specified timeout.') ;
end

%% Collect any results
if nargout>=2
   % read in the processed files
   tr_out = msac_mread(fname_list) ;
   varargout{1} = tr_out ;
end

%% Clean up

% remove macro
[ierror,result] = system('rm -f run-macro sac_complete') ;
if ierror
   error(['MSAC_SAC: CLEANUP: Failed with result: ',result]) ;
end

% remove any SAC files
if nargin>=2
   [ierror,result] = system(['rm -f ' fname_list]) ;
   if ierror
      error(['MSAC_SAC: CLEANUP: Failed with result: ',result]) ;
   end
end

% copy anything left over to the original directory (this might be plots, etc).
[ierror,result] = system(['cp -f * ' origdir]) ;
%if ierror
%   error(['MSAC_SAC: CLEANUP: Failed with result: ',result]) ;
%end

% return to the original directory
cd(origdir);

% finally, clean up the temporary directory
[ierror,result] = system(['rm -rf ' opdir]) ;
if ierror
   error(['MSAC_SAC: CLEANUP: Failed with result: ',result]) ;
end

return
% end of MSAC_SAC.M

