**free

//==============================================================================
// SCLOG      - Service log file location
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Service log location');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

/include 'SCLOG_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'SCDIRS_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

//==============================================================================
// SCLOG_dir
//==============================================================================

dcl-proc SCLOG_dir export;
  dcl-pi *n like(STMF_t);
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-s home like(STMF_t);

  if %len(%trim(def.log_dir)) > 0;
    return %trim(def.log_dir);
  endif;

  home = SCDIRS_home_dir();
  if %len(%trim(home)) = 0;
    // Nowhere better to put it than somewhere that certainly exists
    return '/tmp';
  endif;

  return %trim(home) + '/' + SCLOG_DIR_REL;

end-proc;

//==============================================================================
// SCLOG_new_path
//   A fresh, timestamped path for a service being started NOW
//==============================================================================

dcl-proc SCLOG_new_path export;
  dcl-pi *n like(STMF_t);
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-s stamp like(STMF_t);

  // %CHAR(..:*ISO) gives 'YYYY-MM-DD-HH.MM.SS.uuuuuu' - upstream's own
  // separators, MEASURED 19 September 2026 (docs/parity.md): truncating the
  // microseconds leaves exactly upstream's 19-character stamp. Computed
  // once per start and threaded through by the caller - calling this twice
  // for one start would name two different files for what is one instance.
  stamp = %subst(%char(%timestamp(): *ISO): 1: 19);

  return %trim(SCLOG_dir(def)) + '/' + stamp + '.' + %trim(def.short_name) +
         '.log';

end-proc;

//==============================================================================
// SCLOG_path
//   The MOST RECENT existing log for a service - '' if none
//
// Upstream timestamps the filename at start, so there is no longer one
// deterministic path to compute; a service started more than once has one
// file per start. MEASURED 19 September 2026: a stop then a fresh start left
// two files on disk, and upstream's own loginfo reported the newer one - the
// rule is "find the greatest matching name", not "track the running job".
//==============================================================================

dcl-proc SCLOG_path export;
  dcl-pi *n like(STMF_t);
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-s dir      like(STMF_t);
  dcl-s handle   pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);
  dcl-s suffix   like(STMF_t);
  dcl-s best     like(IFS_DIR_FILENAME_t) inz('');
  dcl-s want_len like(INTEGER_t);

  dir = SCLOG_dir(def);
  handle = IFS_opendir(dir);
  if handle = *null;
    return '';
  endif;

  // '<19-char timestamp>.<short_name>.log' - the suffix is matched EXACTLY
  // by length and content, not as a substring, so a service named 'svc'
  // cannot match a file that belongs to 'myservice_svc'.
  suffix = '.' + %trim(def.short_name) + '.log';
  want_len = 19 + %len(%trim(suffix));

  dow IFS_readdir(handle: filename);
    if %len(%trim(filename)) = want_len
       and %subst(filename: 20: %len(%trim(suffix))) = %trim(suffix);
      // The fixed-width ISO stamp sorts lexicographically by time, so the
      // greatest matching name is the most recently started instance.
      if filename > best;
        best = filename;
      endif;
    endif;
  enddo;

  IFS_closedir(handle);

  if best = '';
    return '';
  endif;

  return %trim(dir) + '/' + %trim(best);

end-proc;

//==============================================================================
// SCLOG_ensure_dir
//==============================================================================

dcl-proc SCLOG_ensure_dir export;
  dcl-pi *n like(BOOLEAN_t);
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-s dir  like(STMF_t);
  dcl-s part like(STMF_t);
  dcl-s i    like(INTEGER_t);

  dir = SCLOG_dir(def);
  if IFS_isa_directory(dir);
    return true;
  endif;

  // Create each level in turn: $HOME/.sc may not exist either, and IFS_crtdir
  // does not make intermediate directories.
  for i = 2 to %len(dir);
    if %subst(dir: i: 1) = '/';
      part = %subst(dir: 1: i - 1);
      if not IFS_isa_directory(part);
        IFS_crtdir(part);
      endif;
    endif;
  endfor;

  IFS_crtdir(dir);

  return IFS_isa_directory(dir);

end-proc;
