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
// SCLOG_path
//==============================================================================

dcl-proc SCLOG_path export;
  dcl-pi *n like(STMF_t);
    def likeds(SCDEF_t) const;
  end-pi;

  return %trim(SCLOG_dir(def)) + '/' + %trim(def.short_name) + '.log';

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
